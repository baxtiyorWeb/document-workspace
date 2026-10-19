package gateway_test

import (
	"context"
	"testing"

	"ai-chat-backend/internal/gateway"
	"ai-chat-backend/internal/plans"
)

type mockModelRegistry struct {
	models map[string]*gateway.Model
}

func (m *mockModelRegistry) GetModel(ctx context.Context, modelID string) (*gateway.Model, error) {
	if model, exists := m.models[modelID]; exists {
		return model, nil
	}
	return nil, gateway.ErrModelNotFound
}

func TestRouter_SelectAndAuthorize(t *testing.T) {
	mockReg := &mockModelRegistry{
		models: map[string]*gateway.Model{
			"nemotron-ultra": {
				ID:           "nemotron-ultra",
				Name:         "Nvidia Nemotron 550B",
				IsEnabled:    true,
				AllowedPlans: []string{"free", "pro"},
				IsFreeTier:   true,
			},
			"gpt-4o": {
				ID:           "gpt-4o",
				Name:         "GPT-4o Omni",
				IsEnabled:    true,
				AllowedPlans: []string{"pro"},
				IsFreeTier:   false,
			},
			"claude-3-opus": {
				ID:           "claude-3-opus",
				Name:         "Claude 3 Opus",
				IsEnabled:    false, // disabled
				AllowedPlans: []string{"pro"},
			},
		},
	}

	router := gateway.NewRouter(mockReg)
	ctx := context.Background()

	freeEntitlement := &plans.UserEntitlement{
		PlanID: "free",
		IsPro:  false,
	}

	proEntitlement := &plans.UserEntitlement{
		PlanID: "pro",
		IsPro:  true,
	}

	// 1. Attack Scenario: Free user requests Pro-only model directly -> MUST BE REJECTED
	_, err := router.SelectAndAuthorize(ctx, "gpt-4o", freeEntitlement)
	if err != gateway.ErrPlanNotAuthorized {
		t.Fatalf("Expected ErrPlanNotAuthorized for free user requesting gpt-4o, got %v", err)
	}

	// 2. Free user requests Free model -> MUST SUCCEED
	model, err := router.SelectAndAuthorize(ctx, "nemotron-ultra", freeEntitlement)
	if err != nil {
		t.Fatalf("Expected success for free user requesting nemotron-ultra, got %v", err)
	}
	if model.ID != "nemotron-ultra" {
		t.Errorf("Expected model nemotron-ultra, got %s", model.ID)
	}

	// 3. Pro user requests Pro model -> MUST SUCCEED
	proModel, err := router.SelectAndAuthorize(ctx, "gpt-4o", proEntitlement)
	if err != nil {
		t.Fatalf("Expected success for pro user requesting gpt-4o, got %v", err)
	}
	if proModel.ID != "gpt-4o" {
		t.Errorf("Expected model gpt-4o, got %s", proModel.ID)
	}

	// 4. Pro user requests Free model -> MUST SUCCEED (Pro includes Free)
	proFreeModel, err := router.SelectAndAuthorize(ctx, "nemotron-ultra", proEntitlement)
	if err != nil {
		t.Fatalf("Expected success for pro user requesting free model, got %v", err)
	}
	if proFreeModel.ID != "nemotron-ultra" {
		t.Errorf("Expected model nemotron-ultra, got %s", proFreeModel.ID)
	}

	// 5. User requests disabled model -> MUST BE REJECTED WITH ErrModelDisabled
	_, err = router.SelectAndAuthorize(ctx, "claude-3-opus", proEntitlement)
	if err != gateway.ErrModelDisabled {
		t.Fatalf("Expected ErrModelDisabled, got %v", err)
	}

	// 6. User requests unknown / invented model ID -> MUST BE REJECTED WITH ErrModelNotFound
	_, err = router.SelectAndAuthorize(ctx, "unreal-fake-model-id", proEntitlement)
	if err != gateway.ErrModelNotFound {
		t.Fatalf("Expected ErrModelNotFound, got %v", err)
	}
}
