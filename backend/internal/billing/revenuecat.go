package billing

import (
	"context"
	"crypto/subtle"
	"encoding/json"
	"errors"
	"fmt"
	"log"
	"strings"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
)

var (
	ErrUnauthorizedWebhook = errors.New("UNAUTHORIZED_WEBHOOK: Invalid or missing authorization token")
	ErrMalformedEvent      = errors.New("MALFORMED_EVENT: Missing required event attributes")
)

// RevenueCatEvent represents the event payload sent by RevenueCat webhooks.
type RevenueCatEvent struct {
	ID                        string   `json:"id"`
	Type                      string   `json:"type"`
	AppUserID                 string   `json:"app_user_id"`
	OriginalAppUserID         string   `json:"original_app_user_id"`
	Aliases                   []string `json:"aliases"`
	ProductID                 string   `json:"product_id"`
	EntitlementID             string   `json:"entitlement_id"`
	EntitlementIDs            []string `json:"entitlement_ids"`
	PurchasedAtMs             int64    `json:"purchased_at_ms"`
	ExpirationAtMs            int64    `json:"expiration_at_ms"`
	Store                     string   `json:"store"`
	Environment               string   `json:"environment"`
	PeriodType                string   `json:"period_type"`
	OriginalTransactionID     string   `json:"original_transaction_id"`
	TransactionID             string   `json:"transaction_id"`
	Currency                  string   `json:"currency"`
	PriceInPurchasedCurrency  float64  `json:"price_in_purchased_currency"`
}

type RevenueCatWebhookPayload struct {
	APIVersion string          `json:"api_version"`
	Event      RevenueCatEvent `json:"event"`
}

// ClientSyncRequest is sent by the mobile app after purchase/restore to synchronize state immediately.
type ClientSyncRequest struct {
	OriginalTransactionID string     `json:"original_transaction_id"`
	ProductID             string     `json:"product_id"`
	EntitlementID         string     `json:"entitlement_id"`
	IsActive              bool       `json:"is_active"`
	ExpirationDate        *time.Time `json:"expiration_date"`
	Store                 string     `json:"store"`
}

// RevenueCatHandler manages webhook processing and subscription synchronization.
type RevenueCatHandler struct {
	pool       *pgxpool.Pool
	authToken  string
	packageName string
}

func NewRevenueCatHandler(pool *pgxpool.Pool, authToken, packageName string) *RevenueCatHandler {
	if packageName == "" {
		packageName = "com.aichat.app.mobile"
	}
	return &RevenueCatHandler{
		pool:        pool,
		authToken:   strings.TrimSpace(authToken),
		packageName: packageName,
	}
}

// VerifyAuthorization verifies the incoming webhook Authorization header using constant-time comparison.
func (h *RevenueCatHandler) VerifyAuthorization(authHeader string) bool {
	if h.authToken == "" {
		log.Println("[WARN] [RevenueCat] REVENUECAT_WEBHOOK_AUTH_TOKEN is not configured; rejecting webhook request (fail-closed)")
		return false
	}

	token := strings.TrimPrefix(authHeader, "Bearer ")
	token = strings.TrimSpace(token)
	return subtle.ConstantTimeCompare([]byte(token), []byte(h.authToken)) == 1
}

// ProcessWebhook processes a RevenueCat webhook event idempotently.
func (h *RevenueCatHandler) ProcessWebhook(ctx context.Context, rawBody []byte, authHeader string) error {
	if !h.VerifyAuthorization(authHeader) {
		return ErrUnauthorizedWebhook
	}

	var payload RevenueCatWebhookPayload
	if err := json.Unmarshal(rawBody, &payload); err != nil {
		return fmt.Errorf("failed to parse RevenueCat webhook JSON: %w", err)
	}

	ev := payload.Event
	if ev.ID == "" || ev.Type == "" {
		return ErrMalformedEvent
	}

	// 1. Idempotency check using webhook_events table
	res, err := h.pool.Exec(ctx, `
		INSERT INTO webhook_events (event_id, event_name, payload)
		VALUES ($1, $2, $3)
		ON CONFLICT (event_id) DO NOTHING
	`, ev.ID, ev.Type, rawBody)
	if err != nil {
		return fmt.Errorf("failed to record webhook idempotency: %w", err)
	}

	if res.RowsAffected() == 0 {
		log.Printf("[INFO] [RevenueCat] Duplicate webhook event %s (%s) ignored", ev.ID, ev.Type)
		return nil
	}

	log.Printf("[INFO] [RevenueCat] Processing webhook event: %s, ID: %s, User: %s, Product: %s",
		ev.Type, ev.ID, ev.AppUserID, ev.ProductID)

	// 2. Resolve User ID
	userID := h.resolveUserID(ctx, &ev)
	if userID == "" {
		log.Printf("[WARN] [RevenueCat] Could not resolve application user_id for app_user_id=%s, original=%s",
			ev.AppUserID, ev.OriginalAppUserID)
		return nil
	}

	// 3. Process according to event type
	switch ev.Type {
	case "INITIAL_PURCHASE", "RENEWAL", "PRODUCT_CHANGE", "UNCANCELLATION":
		return h.handleActiveSubscription(ctx, userID, &ev)

	case "CANCELLATION":
		return h.handleCancellation(ctx, userID, &ev)

	case "EXPIRATION":
		return h.handleExpiration(ctx, userID, &ev)

	case "BILLING_ISSUE":
		return h.handleBillingIssue(ctx, userID, &ev)

	default:
		log.Printf("[INFO] [RevenueCat] Unhandled event type: %s (recorded for audit)", ev.Type)
		return nil
	}
}

// SyncFromClient allows the authenticated mobile app to proactively sync its active entitlement.
// SyncFromClient allows the mobile app to report entitlement state, but enforces server-side authority.
func (h *RevenueCatHandler) SyncFromClient(ctx context.Context, userID string, req ClientSyncRequest) error {
	if userID == "" {
		return errors.New("userID is required")
	}
	if h.pool == nil {
		return nil
	}

	// SEC-01: Verify server-side authority. Check if an active subscription verified by webhook already exists.
	var hasVerifiedActiveSub bool
	err := h.pool.QueryRow(ctx, `
		SELECT EXISTS (
			SELECT 1 FROM subscriptions 
			WHERE user_id = $1::uuid AND status = 'active' AND (ends_at IS NULL OR ends_at > CURRENT_TIMESTAMP)
		)
	`, userID).Scan(&hasVerifiedActiveSub)
	if err != nil {
		return fmt.Errorf("failed to verify existing subscription: %w", err)
	}

	planID := "free"
	status := "pending_verification"

	if hasVerifiedActiveSub {
		// Server already confirmed via webhook
		planID = "pro"
		status = "active"
	} else if !req.IsActive {
		status = "expired"
		planID = "free"
	} else {
		// Client claimed active, but no server webhook verification has arrived yet.
		// Retain free tier until authoritative webhook arrives, recording client sync attempt.
		log.Printf("[INFO] [RevenueCat] Client sync requested active for user %s, waiting for webhook confirmation", userID)
		planID = "free"
		status = "pending_verification"
	}

	origID := req.OriginalTransactionID
	if origID == "" {
		origID = "rc_sync_" + userID
	}

	store := req.Store
	if store == "" {
		store = "play_store"
	}

	portalURL := fmt.Sprintf("https://play.google.com/store/account/subscriptions?package=%s", h.packageName)

	_, err = h.pool.Exec(ctx, `
		INSERT INTO subscriptions (
			user_id, provider, original_transaction_id, revenuecat_app_user_id,
			product_id, store, plan_id, status, ends_at, customer_portal_url, updated_at
		) VALUES (
			$1::uuid, 'revenuecat', $2, $3, $4, $5, $6, $7, $8, $9, CURRENT_TIMESTAMP
		)
		ON CONFLICT (original_transaction_id) WHERE original_transaction_id IS NOT NULL DO UPDATE SET
			status = EXCLUDED.status,
			ends_at = EXCLUDED.ends_at,
			product_id = EXCLUDED.product_id,
			store = EXCLUDED.store,
			customer_portal_url = EXCLUDED.customer_portal_url,
			updated_at = CURRENT_TIMESTAMP
	`, userID, origID, userID, req.ProductID, store, planID, status, req.ExpirationDate, portalURL)
	if err != nil {
		return fmt.Errorf("failed to upsert synced subscription: %w", err)
	}

	// Update user's direct plan_id only if verified
	if planID == "pro" {
		_, err = h.pool.Exec(ctx, `UPDATE users SET plan_id = 'pro', updated_at = CURRENT_TIMESTAMP WHERE id = $1::uuid`, userID)
		return err
	}
	return nil
}

func (h *RevenueCatHandler) handleActiveSubscription(ctx context.Context, userID string, ev *RevenueCatEvent) error {
	status := "active"
	if strings.ToUpper(ev.PeriodType) == "TRIAL" {
		status = "on_trial"
	}

	var endsAt *time.Time
	if ev.ExpirationAtMs > 0 {
		t := time.UnixMilli(ev.ExpirationAtMs)
		endsAt = &t
	}

	var renewsAt *time.Time
	if ev.PurchasedAtMs > 0 {
		t := time.UnixMilli(ev.PurchasedAtMs)
		renewsAt = &t
	}

	origTransID := ev.OriginalTransactionID
	if origTransID == "" {
		origTransID = ev.TransactionID
	}
	if origTransID == "" {
		origTransID = "rc_" + ev.ID
	}

	portalURL := fmt.Sprintf("https://play.google.com/store/account/subscriptions?package=%s", h.packageName)
	testMode := strings.ToUpper(ev.Environment) == "SANDBOX"

	_, err := h.pool.Exec(ctx, `
		INSERT INTO subscriptions (
			user_id, provider, original_transaction_id, revenuecat_app_user_id,
			product_id, store, environment, plan_id, status, renews_at, ends_at,
			customer_portal_url, test_mode, updated_at
		) VALUES (
			$1::uuid, 'revenuecat', $2, $3, $4, $5, $6, 'pro', $7, $8, $9, $10, $11, CURRENT_TIMESTAMP
		)
		ON CONFLICT (original_transaction_id) WHERE original_transaction_id IS NOT NULL DO UPDATE SET
			status = EXCLUDED.status,
			renews_at = EXCLUDED.renews_at,
			ends_at = EXCLUDED.ends_at,
			product_id = EXCLUDED.product_id,
			environment = EXCLUDED.environment,
			customer_portal_url = COALESCE(EXCLUDED.customer_portal_url, subscriptions.customer_portal_url),
			updated_at = CURRENT_TIMESTAMP
	`, userID, origTransID, ev.AppUserID, ev.ProductID, ev.Store, ev.Environment,
		status, renewsAt, endsAt, portalURL, testMode)
	if err != nil {
		return fmt.Errorf("failed to upsert RevenueCat subscription: %w", err)
	}

	// Upgrade user to PRO
	_, err = h.pool.Exec(ctx, `UPDATE users SET plan_id = 'pro', updated_at = CURRENT_TIMESTAMP WHERE id = $1`, userID)
	log.Printf("[INFO] [RevenueCat] User %s granted PRO plan (status=%s, origID=%s)", userID, status, origTransID)
	return err
}

func (h *RevenueCatHandler) handleCancellation(ctx context.Context, userID string, ev *RevenueCatEvent) error {
	origTransID := ev.OriginalTransactionID
	if origTransID == "" {
		origTransID = ev.TransactionID
	}

	var endsAt *time.Time
	if ev.ExpirationAtMs > 0 {
		t := time.UnixMilli(ev.ExpirationAtMs)
		endsAt = &t
	}

	// In RevenueCat, cancellation means auto-renew is off, but Pro access remains active until ends_at!
	_, err := h.pool.Exec(ctx, `
		UPDATE subscriptions 
		SET status = 'cancelled', ends_at = COALESCE($1, ends_at), updated_at = CURRENT_TIMESTAMP
		WHERE original_transaction_id = $2 OR (user_id = $3 AND provider = 'revenuecat')
	`, endsAt, origTransID, userID)

	log.Printf("[INFO] [RevenueCat] Subscription %s cancelled for user %s (valid until %v)", origTransID, userID, endsAt)
	return err
}

func (h *RevenueCatHandler) handleExpiration(ctx context.Context, userID string, ev *RevenueCatEvent) error {
	origTransID := ev.OriginalTransactionID
	if origTransID == "" {
		origTransID = ev.TransactionID
	}

	_, err := h.pool.Exec(ctx, `
		UPDATE subscriptions 
		SET status = 'expired', updated_at = CURRENT_TIMESTAMP
		WHERE original_transaction_id = $1 OR (user_id = $2 AND provider = 'revenuecat')
	`, origTransID, userID)

	// Demote user to free plan
	_, _ = h.pool.Exec(ctx, `UPDATE users SET plan_id = 'free', updated_at = CURRENT_TIMESTAMP WHERE id = $1`, userID)
	log.Printf("[INFO] [RevenueCat] Subscription expired for user %s. Reverted to FREE plan", userID)
	return err
}

func (h *RevenueCatHandler) handleBillingIssue(ctx context.Context, userID string, ev *RevenueCatEvent) error {
	origTransID := ev.OriginalTransactionID
	if origTransID == "" {
		origTransID = ev.TransactionID
	}

	_, err := h.pool.Exec(ctx, `
		UPDATE subscriptions 
		SET status = 'past_due', updated_at = CURRENT_TIMESTAMP
		WHERE original_transaction_id = $1 OR (user_id = $2 AND provider = 'revenuecat')
	`, origTransID, userID)
	return err
}

func (h *RevenueCatHandler) resolveUserID(ctx context.Context, ev *RevenueCatEvent) string {
	candidates := []string{ev.AppUserID, ev.OriginalAppUserID}
	candidates = append(candidates, ev.Aliases...)

	for _, c := range candidates {
		trimmed := strings.TrimSpace(c)
		if trimmed == "" {
			continue
		}

		// 1. Direct match on users.id
		var uid string
		err := h.pool.QueryRow(ctx, `SELECT id FROM users WHERE id::text = $1`, trimmed).Scan(&uid)
		if err == nil && uid != "" {
			return uid
		}

		// 2. Match on users.email if app_user_id was passed as email
		err = h.pool.QueryRow(ctx, `SELECT id FROM users WHERE LOWER(email) = LOWER($1)`, trimmed).Scan(&uid)
		if err == nil && uid != "" {
			return uid
		}
	}

	// 3. Fallback: match by existing original_transaction_id
	origID := ev.OriginalTransactionID
	if origID != "" {
		var uid string
		err := h.pool.QueryRow(ctx, `
			SELECT user_id FROM subscriptions 
			WHERE original_transaction_id = $1
		`, origID).Scan(&uid)
		if err == nil && uid != "" {
			return uid
		}
	}

	return ""
}
