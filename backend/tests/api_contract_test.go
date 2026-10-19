package tests

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	"ai-chat-backend/internal/ai"
	"ai-chat-backend/internal/auth"
	"ai-chat-backend/internal/billing"
	"ai-chat-backend/internal/conversations"
	"ai-chat-backend/internal/files"
	"ai-chat-backend/internal/gateway"
	"ai-chat-backend/internal/generations"
	"ai-chat-backend/internal/http/handlers"
	"ai-chat-backend/internal/messages"
	"ai-chat-backend/internal/middleware"
	"ai-chat-backend/internal/plans"

	"github.com/go-chi/chi/v5"
)

func setupTestRouter() http.Handler {
	r := chi.NewRouter()
	r.Use(middleware.RequestID)

	healthHandler := handlers.NewHealthHandler(nil)
	r.Get("/health/live", healthHandler.Live)
	r.Get("/health/ready", healthHandler.Ready)

	authService := auth.NewService(nil, "test-jwt-secret-key", 0, 0)
	authHandler := handlers.NewAuthHandler(authService)

	convService := conversations.NewService(nil)
	convHandler := handlers.NewConversationHandler(convService)

	msgService := messages.NewService(nil)
	msgHandler := handlers.NewMessageHandler(msgService)

	aiProvider := ai.NewOpenAICompatibleProvider("http://localhost:8080", "", "test", "", 100, 0.7)
	plansService := plans.NewService(nil)
	filesService := files.NewService(nil, "")
	gatewayRouter := gateway.NewRouter(nil)
	quotaService := gateway.NewQuotaService(nil)
	genService := generations.NewService(nil, aiProvider, msgService, plansService, filesService, gatewayRouter, quotaService)
	genHandler := handlers.NewGenerationHandler(genService)
	filesHandler := handlers.NewFilesHandler(filesService, plansService)

	plansHandler := handlers.NewPlansHandler(plansService)
	modelsHandler := handlers.NewModelsHandler(gateway.NewModelRegistry(nil), plansService)
	rcHandler := billing.NewRevenueCatHandler(nil, "test-rc-webhook-token", "com.aichat.app.mobile")
	billingHandler := handlers.NewBillingHandler(rcHandler, plansService, nil)

	authenticator := middleware.NewAuthenticator("test-jwt-secret-key")

	r.Route("/api/v1", func(api chi.Router) {
		api.Post("/auth/register", authHandler.Register)
		api.Post("/auth/login", authHandler.Login)
		api.Get("/plans", plansHandler.ListPlans)
		api.Post("/billing/webhook", billingHandler.Webhook)
		api.Post("/subscriptions/webhook", billingHandler.Webhook)

		api.Group(func(protected chi.Router) {
			protected.Use(authenticator.RequireAuth)
			protected.Get("/me/entitlements", plansHandler.GetMyEntitlements)
			protected.Get("/models", modelsHandler.ListModels)
			protected.Post("/billing/sync", billingHandler.Sync)
			protected.Get("/billing/status", billingHandler.GetStatus)
			protected.Get("/conversations", convHandler.List)
			protected.Post("/conversations", convHandler.Create)
			protected.Get("/conversations/{conversationID}/messages", msgHandler.List)
			protected.Post("/conversations/{conversationID}/generations", genHandler.StreamGeneration)
			protected.Post("/generations/{generationID}/cancel", genHandler.CancelGeneration)
			protected.Post("/files/upload", filesHandler.Upload)
			protected.Get("/files/{id}", filesHandler.GetMetadata)
			protected.Get("/files/{id}/download", filesHandler.Download)
			protected.Delete("/files/{id}", filesHandler.Delete)
		})
	})

	return r
}

func TestHealthLive(t *testing.T) {
	router := setupTestRouter()
	req := httptest.NewRequest(http.MethodGet, "/health/live", nil)
	rr := httptest.NewRecorder()

	router.ServeHTTP(rr, req)

	if rr.Code != http.StatusOK {
		t.Fatalf("expected 200 OK, got: %d", rr.Code)
	}

	var res map[string]any
	if err := json.Unmarshal(rr.Body.Bytes(), &res); err != nil {
		t.Fatalf("failed to decode response: %v", err)
	}
	data := res["data"].(map[string]any)
	if data["status"] != "live" {
		t.Fatalf("expected live, got: %v", data["status"])
	}
}

func TestUnauthenticatedAccessRejected(t *testing.T) {
	router := setupTestRouter()

	endpoints := []struct {
		method string
		path   string
	}{
		{http.MethodGet, "/api/v1/conversations"},
		{http.MethodPost, "/api/v1/conversations"},
		{http.MethodGet, "/api/v1/conversations/123/messages"},
		{http.MethodPost, "/api/v1/conversations/123/generations"},
		{http.MethodPost, "/api/v1/generations/123/cancel"},
		{http.MethodGet, "/api/v1/models"},
		{http.MethodGet, "/api/v1/me/entitlements"},
		{http.MethodPost, "/api/v1/billing/sync"},
		{http.MethodGet, "/api/v1/billing/status"},
	}

	for _, ep := range endpoints {
		req := httptest.NewRequest(ep.method, ep.path, nil)
		rr := httptest.NewRecorder()
		router.ServeHTTP(rr, req)

		if rr.Code != http.StatusUnauthorized {
			t.Errorf("expected 401 Unauthorized for %s %s, got: %d", ep.method, ep.path, rr.Code)
		}
	}
}

func TestWebhookEndpointSecurity(t *testing.T) {
	router := setupTestRouter()

	payload := []byte(`{"api_version":"1.0","event":{"id":"evt_123","type":"INITIAL_PURCHASE","app_user_id":"user1"}}`)

	// 1. Missing Authorization header must be rejected with 401
	req := httptest.NewRequest(http.MethodPost, "/api/v1/billing/webhook", bytes.NewReader(payload))
	req.Header.Set("Content-Type", "application/json")
	rr := httptest.NewRecorder()

	router.ServeHTTP(rr, req)
	if rr.Code != http.StatusUnauthorized {
		t.Fatalf("expected 401 for missing Authorization header, got %d", rr.Code)
	}

	// 2. Invalid Authorization token must be rejected with 401
	req2 := httptest.NewRequest(http.MethodPost, "/api/v1/billing/webhook", bytes.NewReader(payload))
	req2.Header.Set("Content-Type", "application/json")
	req2.Header.Set("Authorization", "Bearer invalid-wrong-token")
	rr2 := httptest.NewRecorder()

	router.ServeHTTP(rr2, req2)
	if rr2.Code != http.StatusUnauthorized {
		t.Fatalf("expected 401 for invalid Authorization token, got %d", rr2.Code)
	}
}

func TestPublicPlansEndpoint(t *testing.T) {
	router := setupTestRouter()

	req := httptest.NewRequest(http.MethodGet, "/api/v1/plans", nil)
	rr := httptest.NewRecorder()

	router.ServeHTTP(rr, req)
	if rr.Code != http.StatusOK {
		t.Fatalf("expected 200 OK for /api/v1/plans, got: %d", rr.Code)
	}

	var res map[string]any
	if err := json.Unmarshal(rr.Body.Bytes(), &res); err != nil {
		t.Fatalf("failed to decode plans response: %v", err)
	}
	plansList, ok := res["data"].([]any)
	if !ok || len(plansList) < 2 {
		t.Fatalf("expected at least 2 default plans (free and pro), got: %v", res)
	}
}

func TestRegisterValidation(t *testing.T) {
	router := setupTestRouter()

	// Invalid short password
	body, _ := json.Marshal(map[string]string{
		"email":    "user@example.com",
		"password": "123", // too short (< 8 chars)
	})
	req := httptest.NewRequest(http.MethodPost, "/api/v1/auth/register", bytes.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	rr := httptest.NewRecorder()

	router.ServeHTTP(rr, req)

	if rr.Code != http.StatusUnprocessableEntity {
		t.Fatalf("expected 422 for invalid short password, got: %d", rr.Code)
	}
}
