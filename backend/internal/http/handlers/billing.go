package handlers

import (
	"encoding/json"
	"io"
	"net/http"

	"ai-chat-backend/internal/billing"
	apphttp "ai-chat-backend/internal/http"
	"ai-chat-backend/internal/middleware"
	"ai-chat-backend/internal/plans"
	"github.com/jackc/pgx/v5/pgxpool"
)

type BillingHandler struct {
	rcHandler    *billing.RevenueCatHandler
	plansService *plans.Service
	pool         *pgxpool.Pool
}

func NewBillingHandler(
	rcHandler *billing.RevenueCatHandler,
	plansService *plans.Service,
	pool *pgxpool.Pool,
) *BillingHandler {
	return &BillingHandler{
		rcHandler:    rcHandler,
		plansService: plansService,
		pool:         pool,
	}
}

// Webhook processes raw RevenueCat webhook notifications with Bearer token authentication.
func (h *BillingHandler) Webhook(w http.ResponseWriter, r *http.Request) {
	authHeader := r.Header.Get("Authorization")

	// Read raw body for JSON decoding and audit logging
	rawBody, err := io.ReadAll(io.LimitReader(r.Body, 1024*1024)) // 1MB limit
	if err != nil {
		apphttp.WriteError(w, r, http.StatusBadRequest, "BODY_READ_FAILED", "So'rov tanasini o'qishda xatolik")
		return
	}

	if err := h.rcHandler.ProcessWebhook(r.Context(), rawBody, authHeader); err != nil {
		if err == billing.ErrUnauthorizedWebhook {
			apphttp.WriteError(w, r, http.StatusUnauthorized, "UNAUTHORIZED", "RevenueCat webhook avtorizatsiyasi yaroqsiz")
			return
		}
		if err == billing.ErrMalformedEvent {
			apphttp.WriteError(w, r, http.StatusBadRequest, "MALFORMED_EVENT", "RevenueCat voqea parametrlari yetishmaydi")
			return
		}
		apphttp.WriteError(w, r, http.StatusInternalServerError, "WEBHOOK_PROCESS_FAILED", err.Error())
		return
	}

	w.WriteHeader(http.StatusOK)
	_, _ = w.Write([]byte(`{"received":true}`))
}

// Sync allows the authenticated mobile application to immediately synchronize its active subscription after purchase/restore.
func (h *BillingHandler) Sync(w http.ResponseWriter, r *http.Request) {
	userID, ok := middleware.GetUserID(r.Context())
	if !ok {
		apphttp.WriteError(w, r, http.StatusUnauthorized, "UNAUTHORIZED", "Avtorizatsiya talab qilinadi")
		return
	}

	var req billing.ClientSyncRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		apphttp.WriteError(w, r, http.StatusBadRequest, "MALFORMED_JSON", "Noto'g'ri JSON formati")
		return
	}

	if err := h.rcHandler.SyncFromClient(r.Context(), userID, req); err != nil {
		apphttp.WriteError(w, r, http.StatusInternalServerError, "SYNC_FAILED", err.Error())
		return
	}

	// Return authoritatively updated entitlement
	ent, err := h.plansService.ResolveUserEntitlement(r.Context(), userID)
	if err != nil {
		apphttp.WriteError(w, r, http.StatusInternalServerError, "ENTITLEMENT_ERROR", err.Error())
		return
	}

	apphttp.WriteJSON(w, http.StatusOK, ent)
}

// GetStatus returns the current authenticated user's subscription and entitlements.
func (h *BillingHandler) GetStatus(w http.ResponseWriter, r *http.Request) {
	userID, ok := middleware.GetUserID(r.Context())
	if !ok {
		apphttp.WriteError(w, r, http.StatusUnauthorized, "UNAUTHORIZED", "Avtorizatsiya talab qilinadi")
		return
	}

	ent, err := h.plansService.ResolveUserEntitlement(r.Context(), userID)
	if err != nil {
		apphttp.WriteError(w, r, http.StatusInternalServerError, "ENTITLEMENT_ERROR", err.Error())
		return
	}

	apphttp.WriteJSON(w, http.StatusOK, ent)
}
