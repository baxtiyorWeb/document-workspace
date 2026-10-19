package gateway

import (
	"context"
	"errors"
	"fmt"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

var (
	ErrModelNotFound     = errors.New("MODEL_NOT_FOUND: Ko'rsatilgan AI model topilmadi")
	ErrModelDisabled     = errors.New("MODEL_DISABLED: Ushbu model hozirda o'chirilgan")
	ErrPlanNotAuthorized = errors.New("MODEL_NOT_PERMITTED_ON_PLAN: Ushbu model sizning tarif rejangizda mavjud emas. Iltimos, Pro tarifiga o'ting.")
)

// Model represents the database model entity (including internal provider routing info).
type Model struct {
	ID                       string    `json:"id"`
	Name                     string    `json:"name"`
	Description              string    `json:"description"`
	Provider                 string    `json:"provider"`
	ProviderModelID          string    `json:"provider_model_id"`
	IsEnabled                bool      `json:"is_enabled"`
	AllowedPlans             []string  `json:"allowed_plans"`
	MaxContextTokens         int       `json:"max_context_tokens"`
	MaxOutputTokens          int       `json:"max_output_tokens"`
	InputPricePerMillionUSD  float64   `json:"input_price_per_million_usd"`
	OutputPricePerMillionUSD float64   `json:"output_price_per_million_usd"`
	IsFreeTier               bool      `json:"is_free_tier"`
	IsReasoning              bool      `json:"is_reasoning"`
	CreatedAt                time.Time `json:"created_at"`
}

// PublicModelDTO is the safe representation sent to mobile clients (no provider secrets).
type PublicModelDTO struct {
	ID               string   `json:"id"`
	Name             string   `json:"name"`
	Description      string   `json:"description"`
	AllowedPlans     []string `json:"allowed_plans"`
	MaxContextTokens int      `json:"max_context_tokens"`
	MaxOutputTokens  int      `json:"max_output_tokens"`
	IsFreeTier       bool     `json:"is_free_tier"`
	IsReasoning      bool     `json:"is_reasoning"`
	IsProOnly        bool     `json:"is_pro_only"`
}

type ModelRegistry struct {
	pool *pgxpool.Pool
}

func NewModelRegistry(pool *pgxpool.Pool) *ModelRegistry {
	return &ModelRegistry{pool: pool}
}

// ListPublicModels returns only enabled models with safe metadata.
func (r *ModelRegistry) ListPublicModels(ctx context.Context, userPlanID string) ([]PublicModelDTO, error) {
	if r.pool == nil {
		return []PublicModelDTO{
			{
				ID:               "nemotron-ultra",
				Name:             "Nvidia Nemotron 550B",
				Description:      "Tezkor va kuchli bepul model",
				AllowedPlans:     []string{"free", "pro", "ultra"},
				MaxContextTokens: 8192,
				MaxOutputTokens:  2048,
				IsFreeTier:       true,
				IsReasoning:      false,
				IsProOnly:        false,
			},
			{
				ID:               "gpt-4o-mini",
				Name:             "GPT-4o Mini",
				Description:      "Aqlli va tejamkor model",
				AllowedPlans:     []string{"free", "pro", "ultra"},
				MaxContextTokens: 16384,
				MaxOutputTokens:  2048,
				IsFreeTier:       true,
				IsReasoning:      false,
				IsProOnly:        false,
			},
			{
				ID:               "gpt-4o",
				Name:             "GPT-4o Omni",
				Description:      "Eng yuqori aniqlikdagi flagman model",
				AllowedPlans:     []string{"pro", "ultra"},
				MaxContextTokens: 32000,
				MaxOutputTokens:  4096,
				IsFreeTier:       false,
				IsReasoning:      false,
				IsProOnly:        true,
			},
		}, nil
	}

	rows, err := r.pool.Query(ctx, `
		SELECT id, name, description, allowed_plans, max_context_tokens, 
		       max_output_tokens, is_free_tier, is_reasoning
		FROM models
		WHERE is_enabled = TRUE
		ORDER BY is_free_tier DESC, name ASC
	`)
	if err != nil {
		return nil, fmt.Errorf("failed to query models: %w", err)
	}
	defer rows.Close()

	var list []PublicModelDTO
	for rows.Next() {
		var m PublicModelDTO
		if err := rows.Scan(
			&m.ID, &m.Name, &m.Description, &m.AllowedPlans,
			&m.MaxContextTokens, &m.MaxOutputTokens, &m.IsFreeTier, &m.IsReasoning,
		); err != nil {
			return nil, fmt.Errorf("failed to scan model: %w", err)
		}

		isProOnly := true
		for _, p := range m.AllowedPlans {
			if p == "free" {
				isProOnly = false
				break
			}
		}
		m.IsProOnly = isProOnly

		list = append(list, m)
	}
	return list, nil
}

// GetModel retrieves the internal model representation.
func (r *ModelRegistry) GetModel(ctx context.Context, modelID string) (*Model, error) {
	if r.pool == nil {
		defaults := map[string]*Model{
			"nemotron-ultra": {
				ID:              "nemotron-ultra",
				Name:            "Nvidia Nemotron 550B",
				Provider:        "openrouter",
				ProviderModelID: "nvidia/nemotron-3-ultra-550b-a55b:free",
				IsEnabled:       true,
				AllowedPlans:    []string{"free", "pro", "ultra"},
				MaxContextTokens: 8192,
				MaxOutputTokens:  2048,
				IsFreeTier:      true,
			},
			"gpt-4o-mini": {
				ID:              "gpt-4o-mini",
				Name:            "GPT-4o Mini",
				Provider:        "openrouter",
				ProviderModelID: "openai/gpt-4o-mini",
				IsEnabled:       true,
				AllowedPlans:    []string{"free", "pro", "ultra"},
				MaxContextTokens: 16384,
				MaxOutputTokens:  2048,
				IsFreeTier:      true,
			},
			"gpt-4o": {
				ID:              "gpt-4o",
				Name:            "GPT-4o Omni",
				Provider:        "openrouter",
				ProviderModelID: "openai/gpt-4o",
				IsEnabled:       true,
				AllowedPlans:    []string{"pro", "ultra"},
				MaxContextTokens: 32000,
				MaxOutputTokens:  4096,
				IsFreeTier:      false,
			},
		}
		if m, ok := defaults[modelID]; ok {
			return m, nil
		}
		return nil, ErrModelNotFound
	}

	var m Model
	err := r.pool.QueryRow(ctx, `
		SELECT id, name, description, provider, provider_model_id, is_enabled,
		       allowed_plans, max_context_tokens, max_output_tokens,
		       input_price_per_million_usd, output_price_per_million_usd,
		       is_free_tier, is_reasoning, created_at
		FROM models
		WHERE id = $1
	`, modelID).Scan(
		&m.ID, &m.Name, &m.Description, &m.Provider, &m.ProviderModelID, &m.IsEnabled,
		&m.AllowedPlans, &m.MaxContextTokens, &m.MaxOutputTokens,
		&m.InputPricePerMillionUSD, &m.OutputPricePerMillionUSD,
		&m.IsFreeTier, &m.IsReasoning, &m.CreatedAt,
	)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, ErrModelNotFound
		}
		return nil, fmt.Errorf("failed to fetch model: %w", err)
	}
	return &m, nil
}
