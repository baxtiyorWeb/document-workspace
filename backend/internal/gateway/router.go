package gateway

import (
	"context"
	"errors"
	"fmt"

	"ai-chat-backend/internal/plans"
)

var (
	ErrNoEligibleModel = errors.New("NO_ELIGIBLE_MODEL: Tanlangan model sizning rejangiz uchun mavjud emas")
)

type ModelGetter interface {
	GetModel(ctx context.Context, modelID string) (*Model, error)
}

type Router struct {
	registry ModelGetter
}

func NewRouter(registry ModelGetter) *Router {
	return &Router{registry: registry}
}

// SelectAndAuthorize resolves the model and ensures the user's plan permits using it.
func (r *Router) SelectAndAuthorize(ctx context.Context, requestedModelID string, ent *plans.UserEntitlement) (*Model, error) {
	return r.RouteMultimodal(ctx, requestedModelID, ent, false)
}

// RouteMultimodal resolves the model, automatically routing to vision-capable models if images/multimodal content is provided.
func (r *Router) RouteMultimodal(ctx context.Context, requestedModelID string, ent *plans.UserEntitlement, hasImages bool) (*Model, error) {
	targetModelID := requestedModelID
	if targetModelID == "" {
		if ent.IsUltra {
			targetModelID = "gpt-4o"
		} else if ent.IsPro {
			targetModelID = "gpt-4o"
		} else {
			targetModelID = "nemotron-ultra"
		}
	}

	model, err := r.registry.GetModel(ctx, targetModelID)
	if err != nil {
		return nil, err
	}

	// If images are attached but model is not vision-capable, route to suitable vision model
	if hasImages && !model.IsFreeTier && targetModelID != "gpt-4o" && targetModelID != "gpt-4o-mini" && targetModelID != "claude-3-5-sonnet" {
		visionCandidate := "gpt-4o-mini"
		if ent.IsPro || ent.IsUltra {
			visionCandidate = "gpt-4o"
		}
		if vm, err := r.registry.GetModel(ctx, visionCandidate); err == nil && vm.IsEnabled {
			model = vm
		}
	}

	if !model.IsEnabled {
		return nil, ErrModelDisabled
	}

	// Verify plan authorization
	isAllowed := false
	for _, p := range model.AllowedPlans {
		if p == ent.PlanID || (ent.IsPro && p == "free") || (ent.IsUltra && (p == "free" || p == "pro" || p == "ultra")) {
			isAllowed = true
			break
		}
	}

	if !isAllowed {
		return nil, ErrPlanNotAuthorized
	}

	return model, nil
}

// GetFallbackModel returns an eligible, healthy fallback model permitted for this user's plan.
func (r *Router) GetFallbackModel(ctx context.Context, ent *plans.UserEntitlement, failedModelID string) (*Model, error) {
	candidates := []string{"gpt-4o-mini", "cohere-code", "nemotron-ultra"}
	for _, cID := range candidates {
		if cID == failedModelID {
			continue
		}
		m, err := r.registry.GetModel(ctx, cID)
		if err == nil && m.IsEnabled {
			return m, nil
		}
	}
	return nil, fmt.Errorf("no fallback model available")
}
