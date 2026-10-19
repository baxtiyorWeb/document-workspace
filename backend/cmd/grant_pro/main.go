package main

import (
	"context"
	"fmt"
	"log"
	"strings"
	"time"

	"ai-chat-backend/internal/config"
	"ai-chat-backend/internal/plans"
	"github.com/jackc/pgx/v5/pgxpool"
)

func main() {
	cfg := config.Load()
	if cfg.DatabaseURL == "" {
		log.Fatal("DATABASE_URL is required")
	}

	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()

	pool, err := pgxpool.New(ctx, cfg.DatabaseURL)
	if err != nil {
		log.Fatalf("Failed to connect to database: %v", err)
	}
	defer pool.Close()

	targetEmail := strings.ToLower(strings.TrimSpace("baxtiyorqurbonnazarov33@gmail.com"))

	var userID, email, currentPlan string
	err = pool.QueryRow(ctx, `SELECT id, email, plan_id FROM users WHERE LOWER(email) = $1`, targetEmail).
		Scan(&userID, &email, &currentPlan)

	if err != nil {
		fmt.Printf("[INFO] User with email %s not found in database yet.\n", targetEmail)
		fmt.Println("[INFO] Listing existing users in database:")
		rows, err := pool.Query(ctx, `SELECT id, email, full_name, plan_id, created_at FROM users ORDER BY created_at DESC LIMIT 10`)
		if err == nil {
			defer rows.Close()
			for rows.Next() {
				var id, em, name, plan string
				var cr time.Time
				_ = rows.Scan(&id, &em, &name, &plan, &cr)
				fmt.Printf(" - %s (%s, %s, plan=%s, created=%s)\n", em, name, id, plan, cr.Format(time.RFC3339))
			}
		}
		return
	}

	fmt.Printf("[FOUND] User ID: %s | Email: %s | Current Plan: %s\n", userID, email, currentPlan)

	// 1. Upgrade user plan_id to 'pro'
	_, err = pool.Exec(ctx, `UPDATE users SET plan_id = 'pro', updated_at = CURRENT_TIMESTAMP WHERE id = $1`, userID)
	if err != nil {
		log.Fatalf("Failed to update user plan_id: %v", err)
	}

	// 2. Grant 10-year active PRO subscription
	future := time.Now().AddDate(10, 0, 0)
	portalURL := "https://thego-getters.vercel.app/billing/vip-admin"

	_, err = pool.Exec(ctx, `
		INSERT INTO subscriptions (
			user_id, provider, original_transaction_id, revenuecat_app_user_id,
			plan_id, product_id, status, renews_at, ends_at,
			customer_portal_url, test_mode, updated_at
		) VALUES (
			$1, 'revenuecat', $2, $1,
			'pro', 'monthly', 'active', $3, $4,
			$5, TRUE, CURRENT_TIMESTAMP
		)
		ON CONFLICT (original_transaction_id) DO UPDATE SET
			status = 'active',
			ends_at = EXCLUDED.ends_at,
			renews_at = EXCLUDED.renews_at,
			updated_at = CURRENT_TIMESTAMP
	`, userID, "sub_admin_vip_"+userID, future, future, portalURL)

	if err != nil {
		log.Fatalf("Failed to upsert subscription: %v", err)
	}

	fmt.Printf("[SUCCESS] Successfully granted FULL PRO ACCESS to %s until %s!\n", email, future.Format("2006-01-02"))

	plansSvc := plans.NewService(pool)
	ent, err := plansSvc.ResolveUserEntitlement(ctx, userID)
	if err != nil {
		log.Fatalf("Failed to resolve entitlement: %v", err)
	}

	fmt.Printf("\n--- VERIFIED ENTITLEMENTS FOR %s ---\n", email)
	fmt.Printf("Plan ID: %s (%s)\n", ent.PlanID, ent.PlanName)
	fmt.Printf("Is Pro: %v\n", ent.IsPro)
	fmt.Printf("Daily Requests Remaining: %d / %d\n", ent.DailyRequestsRemaining, ent.DailyRequestsLimit)
	fmt.Printf("Max Input/Output Tokens: %d / %d\n", ent.MaxInputTokens, ent.MaxOutputTokens)
	fmt.Printf("Allowed Models: %v\n", ent.AllowedModels)
	fmt.Printf("Subscription Status: %s\n", *ent.SubscriptionStatus)
	fmt.Println("--------------------------------------------------")
}
