package plans

import (
	"context"
	"errors"
	"fmt"
	"strings"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

var (
	ErrPlanNotFound = errors.New("PLAN_NOT_FOUND: Ko'rsatilgan tarif rejasi topilmadi")
)

type Service struct {
	pool *pgxpool.Pool
}

func NewService(pool *pgxpool.Pool) *Service {
	return &Service{pool: pool}
}

// ListPlans returns all active plans.
func (s *Service) ListPlans(ctx context.Context) ([]Plan, error) {
	if s.pool == nil {
		return []Plan{
			{
				ID: "free", Name: "Bepul (Free)", Description: "Bepul boshlang'ich reja",
				HourlyRequests: 15, DailyRequests: 40, WeeklyRequests: 200, MonthlyTokens: 500000,
				MaxInputTokens: 4000, MaxOutputTokens: 1024, MaxActiveStreams: 1,
				MaxFileSizeBytes: 10485760, MaxFilesPerRequest: 2,
				AllowsVision: true, AllowsDocumentRAG: true, AllowsMedia: false,
				AllowedModels: []string{"nemotron-ultra", "cohere-code", "gpt-4o-mini"},
				PriceUSDCents: 0, IsActive: true,
			},
			{
				ID: "pro", Name: "Pro Obuna ($9.99/oy)", Description: "Ilg'or modellar va hujjatlar tahlili",
				HourlyRequests: 60, DailyRequests: 400, WeeklyRequests: 2000, MonthlyTokens: 10000000,
				MaxInputTokens: 32000, MaxOutputTokens: 4096, MaxActiveStreams: 3,
				MaxFileSizeBytes: 52428800, MaxFilesPerRequest: 5,
				AllowsVision: true, AllowsDocumentRAG: true, AllowsMedia: true,
				AllowedModels: []string{"nemotron-ultra", "cohere-code", "gpt-4o-mini", "gpt-4o", "claude-3-5-sonnet", "deepseek-r1", "llama-70b"},
				PriceUSDCents: 999, IsActive: true,
			},
			{
				ID: "ultra", Name: "Ultra Obuna ($24.99/oy)", Description: "To'liq multimodal va cheksiz imkoniyatlar",
				HourlyRequests: 180, DailyRequests: 1200, WeeklyRequests: 6000, MonthlyTokens: 30000000,
				MaxInputTokens: 128000, MaxOutputTokens: 8192, MaxActiveStreams: 6,
				MaxFileSizeBytes: 209715200, MaxFilesPerRequest: 10,
				AllowsVision: true, AllowsDocumentRAG: true, AllowsMedia: true,
				AllowedModels: []string{"nemotron-ultra", "cohere-code", "gpt-4o-mini", "gpt-4o", "claude-3-5-sonnet", "deepseek-r1", "llama-70b", "gemini-1-5-pro"},
				PriceUSDCents: 2499, IsActive: true,
			},
		}, nil
	}

	rows, err := s.pool.Query(ctx, `
		SELECT id, name, description, 
		       COALESCE(hourly_requests, 15), daily_requests, COALESCE(weekly_requests, 200), monthly_tokens, 
		       max_input_tokens, max_output_tokens, max_active_streams, 
		       COALESCE(max_file_size_bytes, 10485760), COALESCE(max_files_per_request, 2),
		       COALESCE(allows_vision, TRUE), COALESCE(allows_document_rag, TRUE), COALESCE(allows_media, FALSE),
		       allowed_models, price_usd_cents, is_active, created_at, updated_at
		FROM plans
		WHERE is_active = TRUE
		ORDER BY price_usd_cents ASC
	`)
	if err != nil {
		return nil, fmt.Errorf("failed to query plans: %w", err)
	}
	defer rows.Close()

	var list []Plan
	for rows.Next() {
		var p Plan
		if err := rows.Scan(
			&p.ID, &p.Name, &p.Description,
			&p.HourlyRequests, &p.DailyRequests, &p.WeeklyRequests, &p.MonthlyTokens,
			&p.MaxInputTokens, &p.MaxOutputTokens, &p.MaxActiveStreams,
			&p.MaxFileSizeBytes, &p.MaxFilesPerRequest,
			&p.AllowsVision, &p.AllowsDocumentRAG, &p.AllowsMedia,
			&p.AllowedModels, &p.PriceUSDCents, &p.IsActive, &p.CreatedAt, &p.UpdatedAt,
		); err != nil {
			return nil, fmt.Errorf("failed to scan plan: %w", err)
		}
		list = append(list, p)
	}
	return list, nil
}

// GetPlan retrieves a single plan by its ID.
func (s *Service) GetPlan(ctx context.Context, planID string) (*Plan, error) {
	if s.pool == nil {
		plans, _ := s.ListPlans(ctx)
		for _, p := range plans {
			if p.ID == planID {
				return &p, nil
			}
		}
		if planID == "" || planID == "free" {
			if len(plans) > 0 {
				return &plans[0], nil
			}
		}
		return nil, ErrPlanNotFound
	}

	var p Plan
	err := s.pool.QueryRow(ctx, `
		SELECT id, name, description, 
		       COALESCE(hourly_requests, 15), daily_requests, COALESCE(weekly_requests, 200), monthly_tokens, 
		       max_input_tokens, max_output_tokens, max_active_streams, 
		       COALESCE(max_file_size_bytes, 10485760), COALESCE(max_files_per_request, 2),
		       COALESCE(allows_vision, TRUE), COALESCE(allows_document_rag, TRUE), COALESCE(allows_media, FALSE),
		       allowed_models, price_usd_cents, is_active, created_at, updated_at
		FROM plans
		WHERE id = $1
	`, planID).Scan(
		&p.ID, &p.Name, &p.Description,
		&p.HourlyRequests, &p.DailyRequests, &p.WeeklyRequests, &p.MonthlyTokens,
		&p.MaxInputTokens, &p.MaxOutputTokens, &p.MaxActiveStreams,
		&p.MaxFileSizeBytes, &p.MaxFilesPerRequest,
		&p.AllowsVision, &p.AllowsDocumentRAG, &p.AllowsMedia,
		&p.AllowedModels, &p.PriceUSDCents, &p.IsActive, &p.CreatedAt, &p.UpdatedAt,
	)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, ErrPlanNotFound
		}
		return nil, fmt.Errorf("failed to fetch plan: %w", err)
	}
	return &p, nil
}

// ResolveUserEntitlement authoritatively determines the user's plan and remaining limits.
func (s *Service) ResolveUserEntitlement(ctx context.Context, userID string) (*UserEntitlement, error) {
	if s.pool == nil {
		effectivePlanID := "free"
		if strings.Contains(strings.ToLower(userID), "pro") {
			effectivePlanID = "pro"
		} else if strings.Contains(strings.ToLower(userID), "ultra") {
			effectivePlanID = "ultra"
		}
		plan, _ := s.GetPlan(ctx, effectivePlanID)
		if plan == nil {
			plan = &Plan{
				ID: "free", Name: "Bepul (Free)",
				HourlyRequests: 15, DailyRequests: 40, WeeklyRequests: 200,
				MaxInputTokens: 4000, MaxOutputTokens: 1024, MaxActiveStreams: 1,
				MaxFileSizeBytes: 10485760, MaxFilesPerRequest: 2,
				AllowsVision: true, AllowsDocumentRAG: true, AllowsMedia: false,
				AllowedModels: []string{"nemotron-ultra", "cohere-code", "gpt-4o-mini"},
			}
		}
		isPro := plan.ID == "pro" || plan.ID == "ultra"
		isUltra := plan.ID == "ultra"
		return &UserEntitlement{
			UserID:                  userID,
			PlanID:                  plan.ID,
			PlanName:                plan.Name,
			IsPro:                   isPro,
			IsUltra:                 isUltra,
			HourlyRequestsLimit:     plan.HourlyRequests,
			HourlyRequestsRemaining: plan.HourlyRequests,
			DailyRequestsLimit:      plan.DailyRequests,
			DailyRequestsRemaining:  plan.DailyRequests,
			WeeklyRequestsLimit:     plan.WeeklyRequests,
			WeeklyRequestsRemaining: plan.WeeklyRequests,
			MaxInputTokens:          plan.MaxInputTokens,
			MaxOutputTokens:         plan.MaxOutputTokens,
			MaxActiveStreams:        plan.MaxActiveStreams,
			MaxFileSizeBytes:        plan.MaxFileSizeBytes,
			MaxFilesPerRequest:      plan.MaxFilesPerRequest,
			AllowsVision:            plan.AllowsVision,
			AllowsDocumentRAG:       plan.AllowsDocumentRAG,
			AllowsMedia:             plan.AllowsMedia,
			AllowedModels:           plan.AllowedModels,
		}, nil
	}

	// 1. Check for active subscription first
	var subStatus *string
	var renewsAt, endsAt *time.Time
	var portalURL *string
	var subPlanID string

	err := s.pool.QueryRow(ctx, `
		SELECT status, renews_at, ends_at, customer_portal_url, plan_id
		FROM subscriptions
		WHERE user_id = $1 
		  AND status IN ('active', 'on_trial', 'paused')
		  AND (ends_at IS NULL OR ends_at > CURRENT_TIMESTAMP)
		ORDER BY created_at DESC
		LIMIT 1
	`, userID).Scan(&subStatus, &renewsAt, &endsAt, &portalURL, &subPlanID)

	effectivePlanID := "free"
	if err == nil && subStatus != nil {
		effectivePlanID = subPlanID
	} else {
		// Fallback check user's direct plan_id in users table
		_ = s.pool.QueryRow(ctx, `SELECT plan_id FROM users WHERE id = $1`, userID).Scan(&effectivePlanID)
		if effectivePlanID == "" {
			effectivePlanID = "free"
		}
	}

	plan, err := s.GetPlan(ctx, effectivePlanID)
	if err != nil {
		// Fallback to free if plan record missing
		plan, _ = s.GetPlan(ctx, "free")
		if plan == nil {
			plan = &Plan{
				ID: "free", Name: "Bepul (Free)",
				HourlyRequests: 15, DailyRequests: 40, WeeklyRequests: 200,
				MaxInputTokens: 4000, MaxOutputTokens: 1024, MaxActiveStreams: 1,
				MaxFileSizeBytes: 10485760, MaxFilesPerRequest: 2,
				AllowsVision: true, AllowsDocumentRAG: true, AllowsMedia: false,
				AllowedModels: []string{"nemotron-ultra", "cohere-code", "gpt-4o-mini"},
			}
		}
	}

	// 2. Count used requests across Hourly, Daily, and Weekly windows
	var hourlyUsed, dailyUsed, weeklyUsed int
	_ = s.pool.QueryRow(ctx, `
		SELECT 
			COUNT(*) FILTER (WHERE created_at >= CURRENT_TIMESTAMP - INTERVAL '1 hour'),
			COUNT(*) FILTER (WHERE created_at >= date_trunc('day', CURRENT_TIMESTAMP)),
			COUNT(*) FILTER (WHERE created_at >= date_trunc('week', CURRENT_TIMESTAMP))
		FROM usage_ledger
		WHERE user_id = $1 AND status IN ('reserved', 'settled')
	`, userID).Scan(&hourlyUsed, &dailyUsed, &weeklyUsed)

	remainingHourly := plan.HourlyRequests - hourlyUsed
	if remainingHourly < 0 {
		remainingHourly = 0
	}

	remainingDaily := plan.DailyRequests - dailyUsed
	if remainingDaily < 0 {
		remainingDaily = 0
	}

	remainingWeekly := plan.WeeklyRequests - weeklyUsed
	if remainingWeekly < 0 {
		remainingWeekly = 0
	}

	isPro := plan.ID == "pro" || plan.ID == "ultra"
	isUltra := plan.ID == "ultra"

	return &UserEntitlement{
		UserID:                  userID,
		PlanID:                  plan.ID,
		PlanName:                plan.Name,
		IsPro:                   isPro,
		IsUltra:                 isUltra,
		HourlyRequestsLimit:     plan.HourlyRequests,
		HourlyRequestsRemaining: remainingHourly,
		DailyRequestsLimit:      plan.DailyRequests,
		DailyRequestsRemaining:  remainingDaily,
		WeeklyRequestsLimit:     plan.WeeklyRequests,
		WeeklyRequestsRemaining: remainingWeekly,
		MaxInputTokens:          plan.MaxInputTokens,
		MaxOutputTokens:         plan.MaxOutputTokens,
		MaxActiveStreams:        plan.MaxActiveStreams,
		MaxFileSizeBytes:        plan.MaxFileSizeBytes,
		MaxFilesPerRequest:      plan.MaxFilesPerRequest,
		AllowsVision:            plan.AllowsVision,
		AllowsDocumentRAG:       plan.AllowsDocumentRAG,
		AllowsMedia:             plan.AllowsMedia,
		AllowedModels:           plan.AllowedModels,
		SubscriptionStatus:      subStatus,
		RenewsAt:                renewsAt,
		EndsAt:                  endsAt,
		CustomerPortalURL:       portalURL,
	}, nil
}

// GetUserUsage returns the usage statistics across all windows for the current user.
func (s *Service) GetUserUsage(ctx context.Context, userID string) (*UsageSummary, error) {
	entitlement, err := s.ResolveUserEntitlement(ctx, userID)
	if err != nil {
		return nil, err
	}

	if s.pool == nil {
		return &UsageSummary{
			UserID:               userID,
			PlanID:               entitlement.PlanID,
			HourlyRequestsCount:  0,
			HourlyRequestsLimit:  entitlement.HourlyRequestsLimit,
			TodayRequestsCount:   0,
			DailyRequestsLimit:   entitlement.DailyRequestsLimit,
			WeeklyRequestsCount:  0,
			WeeklyRequestsLimit:  entitlement.WeeklyRequestsLimit,
			MonthTotalTokens:     0,
			MonthEstimatedCost:   0.0,
			RemainingHourlySlots: entitlement.HourlyRequestsLimit,
			RemainingTodaySlots:  entitlement.DailyRequestsLimit,
			RemainingWeeklySlots: entitlement.WeeklyRequestsLimit,
		}, nil
	}
	var hourlyCount, todayCount, weeklyCount int
	var monthTokens int64
	var monthCost float64

	_ = s.pool.QueryRow(ctx, `
		SELECT 
			COUNT(*) FILTER (WHERE created_at >= CURRENT_TIMESTAMP - INTERVAL '1 hour'),
			COUNT(*) FILTER (WHERE created_at >= date_trunc('day', CURRENT_TIMESTAMP)),
			COUNT(*) FILTER (WHERE created_at >= date_trunc('week', CURRENT_TIMESTAMP)),
			COALESCE(SUM(input_tokens + output_tokens) FILTER (WHERE created_at >= date_trunc('month', CURRENT_TIMESTAMP)), 0),
			COALESCE(SUM(actual_cost_usd) FILTER (WHERE created_at >= date_trunc('month', CURRENT_TIMESTAMP)), 0.0)
		FROM usage_ledger
		WHERE user_id = $1 AND status IN ('reserved', 'settled')
	`, userID).Scan(&hourlyCount, &todayCount, &weeklyCount, &monthTokens, &monthCost)

	remHourly := entitlement.HourlyRequestsLimit - hourlyCount
	if remHourly < 0 {
		remHourly = 0
	}
	remDaily := entitlement.DailyRequestsLimit - todayCount
	if remDaily < 0 {
		remDaily = 0
	}
	remWeekly := entitlement.WeeklyRequestsLimit - weeklyCount
	if remWeekly < 0 {
		remWeekly = 0
	}

	return &UsageSummary{
		UserID:               userID,
		PlanID:               entitlement.PlanID,
		HourlyRequestsCount:  hourlyCount,
		HourlyRequestsLimit:  entitlement.HourlyRequestsLimit,
		TodayRequestsCount:   todayCount,
		DailyRequestsLimit:   entitlement.DailyRequestsLimit,
		WeeklyRequestsCount:  weeklyCount,
		WeeklyRequestsLimit:  entitlement.WeeklyRequestsLimit,
		MonthTotalTokens:     monthTokens,
		MonthEstimatedCost:   monthCost,
		RemainingHourlySlots: remHourly,
		RemainingTodaySlots:  remDaily,
		RemainingWeeklySlots: remWeekly,
	}, nil
}
