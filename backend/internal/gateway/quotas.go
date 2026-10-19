package gateway

import (
	"context"
	"errors"
	"fmt"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

// QuotaError represents a detailed, structured rate-limit or quota rejection.
type QuotaError struct {
	Code     string    `json:"code"`
	Window   string    `json:"window"` // "hourly", "daily", "weekly", "concurrency"
	Limit    int       `json:"limit"`
	Used     int       `json:"used"`
	ResetsAt time.Time `json:"resets_at"`
	Message  string    `json:"message"`
}

func (e *QuotaError) Error() string {
	return fmt.Sprintf("[%s] %s: limit=%d, used=%d, resets_at=%s",
		e.Code, e.Message, e.Limit, e.Used, e.ResetsAt.UTC().Format(time.RFC3339))
}

var (
	ErrQuotaExceeded           = errors.New("PLAN_LIMIT_EXCEEDED: So'rovlar limitingiz tugadi.")
	ErrConcurrencyLimitReached = errors.New("CONCURRENCY_LIMIT_REACHED: Bir vaqtning o'zida bir nechta so'rov yuborish limiti oshib ketdi. Avvalgi xabar yakunlanishini kuting.")
)

type QuotaLimits struct {
	HourlyLimit int
	DailyLimit  int
	WeeklyLimit int
	MaxStreams  int
}

type QuotaService struct {
	pool *pgxpool.Pool
}

func NewQuotaService(pool *pgxpool.Pool) *QuotaService {
	return &QuotaService{pool: pool}
}

// ReserveQuota atomically verifies hourly, daily, weekly, and concurrency limits and reserves a ledger slot.
func (q *QuotaService) ReserveQuota(
	ctx context.Context,
	userID, convID, genID, modelID, planID string,
	limits QuotaLimits,
) (string, error) {
	if q.pool == nil {
		return "mock-ledger-slot-id", nil
	}

	tx, err := q.pool.Begin(ctx)
	if err != nil {
		return "", fmt.Errorf("failed to begin quota transaction: %w", err)
	}
	defer tx.Rollback(ctx)

	// Acquire transactional advisory lock on hashtext(userID) to serialize concurrent reservation requests
	_, err = tx.Exec(ctx, `SELECT pg_advisory_xact_lock(hashtext($1))`, userID)
	if err != nil {
		return "", fmt.Errorf("failed to acquire quota advisory lock: %w", err)
	}

	// 1. Check active concurrent generations (clean up any stale generations older than 3 minutes first)
	_, _ = tx.Exec(ctx, `
		UPDATE generations
		SET status = 'failed', error_code = 'TIMEOUT', error_message = 'Generatsiya vaqti tugadi', completed_at = CURRENT_TIMESTAMP
		WHERE user_id = $1 AND status = 'running' AND created_at < CURRENT_TIMESTAMP - INTERVAL '3 minutes'
	`, userID)

	if limits.MaxStreams > 0 {
		var activeCount int
		err := tx.QueryRow(ctx, `
			SELECT COUNT(*)
			FROM generations
			WHERE user_id = $1 AND status = 'running' AND created_at >= CURRENT_TIMESTAMP - INTERVAL '3 minutes'
		`, userID).Scan(&activeCount)
		if err == nil && activeCount >= limits.MaxStreams {
			return "", &QuotaError{
				Code:     "CONCURRENCY_LIMIT_REACHED",
				Window:   "concurrency",
				Limit:    limits.MaxStreams,
				Used:     activeCount,
				ResetsAt: time.Now().Add(10 * time.Second),
				Message:  "Bir vaqtning o'zida bir nechta so'rov yuborish limiti oshib ketdi. Avvalgi xabar yakunlanishini kuting.",
			}
		}
	}

	// 2. Query usage counts across all 3 windows
	var hourlyCount, dailyCount, weeklyCount int
	err = tx.QueryRow(ctx, `
		SELECT 
			COUNT(*) FILTER (WHERE created_at >= CURRENT_TIMESTAMP - INTERVAL '1 hour'),
			COUNT(*) FILTER (WHERE created_at >= date_trunc('day', CURRENT_TIMESTAMP)),
			COUNT(*) FILTER (WHERE created_at >= date_trunc('week', CURRENT_TIMESTAMP))
		FROM usage_ledger
		WHERE user_id = $1 AND status IN ('reserved', 'settled')
	`, userID).Scan(&hourlyCount, &dailyCount, &weeklyCount)
	if err != nil && !errors.Is(err, pgx.ErrNoRows) {
		return "", fmt.Errorf("failed to check usage ledger: %w", err)
	}

	now := time.Now().UTC()

	// Check Hourly Window
	if limits.HourlyLimit > 0 && hourlyCount >= limits.HourlyLimit {
		resetsAt := now.Add(time.Hour).Truncate(time.Minute)
		return "", &QuotaError{
			Code:     "HOURLY_LIMIT_EXCEEDED",
			Window:   "hourly",
			Limit:    limits.HourlyLimit,
			Used:     hourlyCount,
			ResetsAt: resetsAt,
			Message:  fmt.Sprintf("Soatlik so'rovlar limitingiz (%d ta) tugadi. Iltimos, keyingi soat boshini kuting yoki Pro/Ultra tarifiga o'ting.", limits.HourlyLimit),
		}
	}

	// Check Daily Window
	if limits.DailyLimit > 0 && dailyCount >= limits.DailyLimit {
		// Tomorrow 00:00 UTC
		tomorrow := time.Date(now.Year(), now.Month(), now.Day()+1, 0, 0, 0, 0, time.UTC)
		return "", &QuotaError{
			Code:     "DAILY_LIMIT_EXCEEDED",
			Window:   "daily",
			Limit:    limits.DailyLimit,
			Used:     dailyCount,
			ResetsAt: tomorrow,
			Message:  fmt.Sprintf("Kunlik so'rovlar limitingiz (%d ta) tugadi. Iltimos, ertaga kuting yoki Pro/Ultra tarifiga o'ting.", limits.DailyLimit),
		}
	}

	// Check Weekly Window
	if limits.WeeklyLimit > 0 && weeklyCount >= limits.WeeklyLimit {
		// Next Monday 00:00 UTC
		daysUntilMonday := (8 - int(now.Weekday())) % 7
		if daysUntilMonday == 0 {
			daysUntilMonday = 7
		}
		nextWeek := time.Date(now.Year(), now.Month(), now.Day()+daysUntilMonday, 0, 0, 0, 0, time.UTC)
		return "", &QuotaError{
			Code:     "WEEKLY_LIMIT_EXCEEDED",
			Window:   "weekly",
			Limit:    limits.WeeklyLimit,
			Used:     weeklyCount,
			ResetsAt: nextWeek,
			Message:  fmt.Sprintf("Haftalik so'rovlar limitingiz (%d ta) tugadi. Iltimos, keyingi haftani kuting yoki Ultra tarifiga o'ting.", limits.WeeklyLimit),
		}
	}

	var genUUID any
	if genID != "" {
		genUUID = genID
	}

	var convUUID any
	if convID != "" {
		convUUID = convID
	}

	// 3. Insert reservation slot atomically
	var ledgerID string
	err = tx.QueryRow(ctx, `
		INSERT INTO usage_ledger (id, user_id, conversation_id, generation_id, model_id, plan_id, status)
		VALUES (gen_random_uuid(), $1, $2, $3, $4, $5, 'reserved')
		RETURNING id
	`, userID, convUUID, genUUID, modelID, planID).Scan(&ledgerID)

	if err != nil {
		return "", fmt.Errorf("quota reservation insert failed: %w", err)
	}

	if err := tx.Commit(ctx); err != nil {
		return "", fmt.Errorf("failed to commit quota reservation: %w", err)
	}

	return ledgerID, nil
}

// SettleUsage finalizes the token counts and calculated cost when a generation completes.
func (q *QuotaService) SettleUsage(
	ctx context.Context,
	ledgerID string,
	inTokens, outTokens int,
	inPricePerM, outPricePerM float64,
	costMultiplier float64,
) error {
	if q.pool == nil {
		return nil
	}

	mult := costMultiplier
	if mult <= 0 {
		mult = 1.0
	}

	inCost := ((float64(inTokens) * inPricePerM) / 1000000.0) * mult
	outCost := ((float64(outTokens) * outPricePerM) / 1000000.0) * mult
	totalCost := inCost + outCost

	_, err := q.pool.Exec(ctx, `
		UPDATE usage_ledger
		SET input_tokens = $1, output_tokens = $2, actual_cost_usd = $3, 
		    status = 'settled', updated_at = CURRENT_TIMESTAMP
		WHERE id = $4
	`, inTokens, outTokens, totalCost, ledgerID)
	return err
}

// ReleaseReservation updates the ledger record to 'released' or 'failed' if generation did not produce output.
func (q *QuotaService) ReleaseReservation(ctx context.Context, ledgerID string, status string) error {
	if q.pool == nil {
		return nil
	}

	_, err := q.pool.Exec(ctx, `
		UPDATE usage_ledger
		SET status = $1, updated_at = CURRENT_TIMESTAMP
		WHERE id = $2
	`, status, ledgerID)
	return err
}
