package handlers

import (
	"net/http"

	apphttp "ai-chat-backend/internal/http"
	"ai-chat-backend/internal/middleware"
	"ai-chat-backend/internal/plans"
)

type PlansHandler struct {
	service *plans.Service
}

func NewPlansHandler(service *plans.Service) *PlansHandler {
	return &PlansHandler{service: service}
}

// ListPlans handles GET /api/v1/plans.
func (h *PlansHandler) ListPlans(w http.ResponseWriter, r *http.Request) {
	list, err := h.service.ListPlans(r.Context())
	if err != nil {
		apphttp.WriteError(w, r, http.StatusInternalServerError, "PLANS_FETCH_FAILED", err.Error())
		return
	}
	apphttp.WriteJSON(w, http.StatusOK, list)
}

// GetMyEntitlements handles GET /api/v1/me/entitlements.
func (h *PlansHandler) GetMyEntitlements(w http.ResponseWriter, r *http.Request) {
	userID, ok := middleware.GetUserID(r.Context())
	if !ok {
		apphttp.WriteError(w, r, http.StatusUnauthorized, "UNAUTHORIZED", "Avtorizatsiya talab qilinadi")
		return
	}

	ent, err := h.service.ResolveUserEntitlement(r.Context(), userID)
	if err != nil {
		apphttp.WriteError(w, r, http.StatusInternalServerError, "ENTITLEMENT_ERROR", err.Error())
		return
	}
	apphttp.WriteJSON(w, http.StatusOK, ent)
}

// GetMyUsage handles GET /api/v1/me/usage.
func (h *PlansHandler) GetMyUsage(w http.ResponseWriter, r *http.Request) {
	userID, ok := middleware.GetUserID(r.Context())
	if !ok {
		apphttp.WriteError(w, r, http.StatusUnauthorized, "UNAUTHORIZED", "Avtorizatsiya talab qilinadi")
		return
	}

	usage, err := h.service.GetUserUsage(r.Context(), userID)
	if err != nil {
		apphttp.WriteError(w, r, http.StatusInternalServerError, "USAGE_ERROR", err.Error())
		return
	}
	apphttp.WriteJSON(w, http.StatusOK, usage)
}
