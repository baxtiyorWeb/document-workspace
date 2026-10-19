package handlers

import (
	"context"
	"net/http"
	"time"

	apphttp "ai-chat-backend/internal/http"
	"ai-chat-backend/internal/persistence"
)

type HealthHandler struct {
	db *persistence.DB
}

func NewHealthHandler(db *persistence.DB) *HealthHandler {
	return &HealthHandler{db: db}
}

// Live liveness probe.
func (h *HealthHandler) Live(w http.ResponseWriter, r *http.Request) {
	apphttp.WriteJSON(w, http.StatusOK, map[string]string{
		"status": "live",
		"time":   time.Now().UTC().Format(time.RFC3339),
	})
}

// Ready readiness probe checking DB connectivity.
func (h *HealthHandler) Ready(w http.ResponseWriter, r *http.Request) {
	if h.db == nil {
		apphttp.WriteError(w, r, http.StatusServiceUnavailable, "DB_NOT_CONFIGURED", "Database connection not initialized")
		return
	}

	ctx, cancel := context.WithTimeout(r.Context(), 7*time.Second)
	defer cancel()

	if err := h.db.Ping(ctx); err != nil {
		apphttp.WriteError(w, r, http.StatusServiceUnavailable, "DB_UNAVAILABLE", "Database ping failed: "+err.Error())
		return
	}

	apphttp.WriteJSON(w, http.StatusOK, map[string]string{
		"status":   "ready",
		"database": "connected",
		"time":     time.Now().UTC().Format(time.RFC3339),
	})
}
