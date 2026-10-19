package plans

import "time"

// Plan represents an available system tier (Free, Pro, Ultra).
type Plan struct {
	ID                 string    `json:"id"`
	Name               string    `json:"name"`
	Description        string    `json:"description"`
	HourlyRequests     int       `json:"hourly_requests"`
	DailyRequests      int       `json:"daily_requests"`
	WeeklyRequests     int       `json:"weekly_requests"`
	MonthlyTokens      int64     `json:"monthly_tokens"`
	MaxInputTokens     int       `json:"max_input_tokens"`
	MaxOutputTokens    int       `json:"max_output_tokens"`
	MaxActiveStreams   int       `json:"max_active_streams"`
	MaxFileSizeBytes   int64     `json:"max_file_size_bytes"`
	MaxFilesPerRequest int       `json:"max_files_per_request"`
	AllowsVision       bool      `json:"allows_vision"`
	AllowsDocumentRAG  bool      `json:"allows_document_rag"`
	AllowsMedia        bool      `json:"allows_media"`
	AllowedModels      []string  `json:"allowed_models"`
	PriceUSDCents      int       `json:"price_usd_cents"`
	IsActive           bool      `json:"is_active"`
	CreatedAt          time.Time `json:"created_at"`
	UpdatedAt          time.Time `json:"updated_at"`
}

// UserEntitlement represents the resolved, authoritative capabilities for a user.
type UserEntitlement struct {
	UserID                  string     `json:"user_id"`
	PlanID                  string     `json:"plan_id"`
	PlanName                string     `json:"plan_name"`
	IsPro                   bool       `json:"is_pro"`
	IsUltra                 bool       `json:"is_ultra"`
	HourlyRequestsLimit     int        `json:"hourly_requests_limit"`
	HourlyRequestsRemaining int        `json:"hourly_requests_remaining"`
	DailyRequestsLimit      int        `json:"daily_requests_limit"`
	DailyRequestsRemaining  int        `json:"daily_requests_remaining"`
	WeeklyRequestsLimit     int        `json:"weekly_requests_limit"`
	WeeklyRequestsRemaining int        `json:"weekly_requests_remaining"`
	MaxInputTokens          int        `json:"max_input_tokens"`
	MaxOutputTokens         int        `json:"max_output_tokens"`
	MaxActiveStreams        int        `json:"max_active_streams"`
	MaxFileSizeBytes        int64      `json:"max_file_size_bytes"`
	MaxFilesPerRequest      int        `json:"max_files_per_request"`
	AllowsVision            bool       `json:"allows_vision"`
	AllowsDocumentRAG       bool       `json:"allows_document_rag"`
	AllowsMedia             bool       `json:"allows_media"`
	AllowedModels           []string   `json:"allowed_models"`
	SubscriptionStatus      *string    `json:"subscription_status,omitempty"`
	RenewsAt                *time.Time `json:"renews_at,omitempty"`
	EndsAt                  *time.Time `json:"ends_at,omitempty"`
	CustomerPortalURL       *string    `json:"customer_portal_url,omitempty"`
}

// UsageSummary holds recent usage statistics across all windows for the user.
type UsageSummary struct {
	UserID                  string  `json:"user_id"`
	PlanID                  string  `json:"plan_id"`
	HourlyRequestsCount     int     `json:"hourly_requests_count"`
	HourlyRequestsLimit     int     `json:"hourly_requests_limit"`
	TodayRequestsCount      int     `json:"today_requests_count"`
	DailyRequestsLimit      int     `json:"daily_requests_limit"`
	WeeklyRequestsCount     int     `json:"weekly_requests_count"`
	WeeklyRequestsLimit     int     `json:"weekly_requests_limit"`
	MonthTotalTokens        int64   `json:"month_total_tokens"`
	MonthEstimatedCost      float64 `json:"month_estimated_cost_usd"`
	RemainingTodaySlots     int     `json:"remaining_today_slots"`
	RemainingHourlySlots    int     `json:"remaining_hourly_slots"`
	RemainingWeeklySlots    int     `json:"remaining_weekly_slots"`
}
