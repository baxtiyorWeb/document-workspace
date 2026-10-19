package handlers

import (
	"net/http"

	"ai-chat-backend/internal/gateway"
	apphttp "ai-chat-backend/internal/http"
	"ai-chat-backend/internal/middleware"
	"ai-chat-backend/internal/plans"
)

type ModelsHandler struct {
	registry     *gateway.ModelRegistry
	plansService *plans.Service
}

func NewModelsHandler(registry *gateway.ModelRegistry, plansService *plans.Service) *ModelsHandler {
	return &ModelsHandler{
		registry:     registry,
		plansService: plansService,
	}
}

// ListModels handles GET /api/v1/models.
func (h *ModelsHandler) ListModels(w http.ResponseWriter, r *http.Request) {
	userPlanID := "free"
	if userID, ok := middleware.GetUserID(r.Context()); ok {
		ent, err := h.plansService.ResolveUserEntitlement(r.Context(), userID)
		if err == nil && ent != nil {
			userPlanID = ent.PlanID
		}
	}

	models, err := h.registry.ListPublicModels(r.Context(), userPlanID)
	if err != nil {
		apphttp.WriteError(w, r, http.StatusInternalServerError, "MODELS_FETCH_FAILED", err.Error())
		return
	}

	apphttp.WriteJSON(w, http.StatusOK, models)
}
