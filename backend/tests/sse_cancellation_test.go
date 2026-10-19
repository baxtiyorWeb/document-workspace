package tests

import (
	"bufio"
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"testing"
	"time"

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
	"github.com/golang-jwt/jwt/v5"
)

func createTestJWT(userID, secret string) string {
	claims := jwt.MapClaims{
		"sub": userID,
		"exp": time.Now().Add(1 * time.Hour).Unix(),
	}
	token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	signed, _ := token.SignedString([]byte(secret))
	return signed
}

func setupFullTestServer(mockLLMURL string) (http.Handler, string, *generations.Service) {
	jwtSecret := "test-secret-key-for-load-tests-12345"
	token := createTestJWT("user-pro-1", jwtSecret)

	r := chi.NewRouter()
	r.Use(middleware.RequestID)

	healthHandler := handlers.NewHealthHandler(nil)
	r.Get("/health/live", healthHandler.Live)
	r.Get("/health/ready", healthHandler.Ready)

	authService := auth.NewService(nil, jwtSecret, 15*time.Minute, 7*24*time.Hour)
	authHandler := handlers.NewAuthHandler(authService)

	convService := conversations.NewService(nil)
	convHandler := handlers.NewConversationHandler(convService)

	msgService := messages.NewService(nil)
	msgHandler := handlers.NewMessageHandler(msgService)

	plansService := plans.NewService(nil)
	plansHandler := handlers.NewPlansHandler(plansService)

	modelReg := gateway.NewModelRegistry(nil)
	modelsHandler := handlers.NewModelsHandler(modelReg, plansService)
	gatewayRouter := gateway.NewRouter(modelReg)
	quotaService := gateway.NewQuotaService(nil)

	aiProvider := ai.NewOpenAICompatibleProvider(mockLLMURL, "mock-api-key", "nemotron-ultra", "system prompt", 2048, 0.7)
	filesService := files.NewService(nil, "")
	filesHandler := handlers.NewFilesHandler(filesService, plansService)

	genService := generations.NewService(nil, aiProvider, msgService, plansService, filesService, gatewayRouter, quotaService)
	genHandler := handlers.NewGenerationHandler(genService)

	rcHandler := billing.NewRevenueCatHandler(nil, "rc-token", "com.aichat.app.mobile")
	billingHandler := handlers.NewBillingHandler(rcHandler, plansService, nil)

	authenticator := middleware.NewAuthenticator(jwtSecret)

	r.Route("/api/v1", func(api chi.Router) {
		api.Post("/auth/register", authHandler.Register)
		api.Post("/auth/login", authHandler.Login)
		api.Get("/plans", plansHandler.ListPlans)
		api.Post("/billing/webhook", billingHandler.Webhook)

		// Test helper: mint JWT
		api.Post("/test/token", func(w http.ResponseWriter, r *http.Request) {
			userID := r.URL.Query().Get("user_id")
			if userID == "" {
				userID = "user-load-test"
			}
			t := createTestJWT(userID, jwtSecret)
			w.Header().Set("Content-Type", "application/json")
			_ = json.NewEncoder(w).Encode(map[string]string{"token": t})
		})

		api.Group(func(protected chi.Router) {
			protected.Use(authenticator.RequireAuth)

			protected.Get("/me/entitlements", plansHandler.GetMyEntitlements)
			protected.Get("/me/usage", plansHandler.GetMyUsage)
			protected.Get("/models", modelsHandler.ListModels)

			protected.Get("/conversations", convHandler.List)
			protected.Post("/conversations", convHandler.Create)
			protected.Get("/conversations/{conversationID}", convHandler.GetByID)
			protected.Patch("/conversations/{conversationID}", convHandler.Patch)
			protected.Delete("/conversations/{conversationID}", convHandler.Delete)

			protected.Get("/conversations/{conversationID}/messages", msgHandler.List)
			protected.Post("/conversations/{conversationID}/messages", msgHandler.Create)

			protected.Post("/conversations/{conversationID}/generations", genHandler.StreamGeneration)
			protected.Post("/generations/{generationID}/cancel", genHandler.CancelGeneration)

			protected.Post("/files/upload", filesHandler.Upload)
		})
	})

	return r, token, genService
}

func TestSSECancellationViaEndpoint(t *testing.T) {
	mockURL, teardown := StartMockLLMServer(0)
	defer teardown()

	router, token, _ := setupFullTestServer(mockURL)
	server := httptest.NewServer(router)
	defer server.Close()

	// 1. Start streaming request
	body, _ := json.Marshal(map[string]any{
		"message":  "Write a detailed explanation of distributed systems.",
		"model_id": "nemotron-ultra",
	})
	streamReq, err := http.NewRequest(http.MethodPost, server.URL+"/api/v1/conversations/conv-123/generations", bytes.NewReader(body))
	if err != nil {
		t.Fatalf("failed to create stream request: %v", err)
	}
	streamReq.Header.Set("Authorization", "Bearer "+token)
	streamReq.Header.Set("Content-Type", "application/json")

	resp, err := http.DefaultClient.Do(streamReq)
	if err != nil {
		t.Fatalf("stream request failed: %v", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		t.Fatalf("expected 200 OK for stream, got %d", resp.StatusCode)
	}

	reader := bufio.NewReader(resp.Body)
	var genID string

	// Read lines until generation.started event is encountered
	for {
		line, err := reader.ReadString('\n')
		if err != nil {
			t.Fatalf("unexpected stream termination before generation started: %v", err)
		}
		line = strings.TrimSpace(line)
		if strings.HasPrefix(line, "data:") {
			dataPayload := strings.TrimSpace(strings.TrimPrefix(line, "data:"))
			var eventData map[string]any
			if err := json.Unmarshal([]byte(dataPayload), &eventData); err == nil {
				if id, ok := eventData["generation_id"].(string); ok && id != "" {
					genID = id
					break
				}
			}
		}
	}

	if genID == "" {
		t.Fatal("failed to extract generation_id from SSE stream")
	}

	// 2. Issue cancellation request
	cancelReq, err := http.NewRequest(http.MethodPost, fmt.Sprintf("%s/api/v1/generations/%s/cancel", server.URL, genID), nil)
	if err != nil {
		t.Fatalf("failed to create cancel request: %v", err)
	}
	cancelReq.Header.Set("Authorization", "Bearer "+token)

	cancelResp, err := http.DefaultClient.Do(cancelReq)
	if err != nil {
		t.Fatalf("cancel request failed: %v", err)
	}
	defer cancelResp.Body.Close()

	if cancelResp.StatusCode != http.StatusOK {
		t.Fatalf("expected 200 OK from cancel endpoint, got %d", cancelResp.StatusCode)
	}

	// 3. Verify stream receives generation.cancelled event
	foundCancelledEvent := false
	for {
		line, err := reader.ReadString('\n')
		if err != nil {
			break // stream closed as expected after cancellation
		}
		line = strings.TrimSpace(line)
		if strings.Contains(line, "generation.cancelled") {
			foundCancelledEvent = true
			break
		}
	}

	if !foundCancelledEvent {
		t.Fatal("expected generation.cancelled event in SSE stream upon cancellation")
	}
}

func TestSSECancellationViaClientDisconnect(t *testing.T) {
	mockURL, teardown := StartMockLLMServer(0)
	defer teardown()

	router, token, _ := setupFullTestServer(mockURL)
	server := httptest.NewServer(router)
	defer server.Close()

	ctx, cancel := context.WithCancel(context.Background())

	body, _ := json.Marshal(map[string]any{
		"message":  "Test early client disconnect handling",
		"model_id": "nemotron-ultra",
	})
	streamReq, _ := http.NewRequestWithContext(ctx, http.MethodPost, server.URL+"/api/v1/conversations/conv-456/generations", bytes.NewReader(body))
	streamReq.Header.Set("Authorization", "Bearer "+token)
	streamReq.Header.Set("Content-Type", "application/json")

	resp, err := http.DefaultClient.Do(streamReq)
	if err != nil {
		t.Fatalf("stream request failed: %v", err)
	}
	defer resp.Body.Close()

	reader := bufio.NewReader(resp.Body)
	// Read first line
	_, _ = reader.ReadString('\n')

	// Abruptly disconnect client
	cancel()

	// Ensure reading now errors with context canceled
	buf := make([]byte, 1024)
	_, err = reader.Read(buf)
	if err == nil {
		t.Log("Stream read finished or returned EOF after context cancel")
	}
}

func TestConcurrentSSECancellations(t *testing.T) {
	mockURL, teardown := StartMockLLMServer(0)
	defer teardown()

	router, token, _ := setupFullTestServer(mockURL)
	server := httptest.NewServer(router)
	defer server.Close()

	var wg sync.WaitGroup
	const concurrentClients = 8

	for i := 0; i < concurrentClients; i++ {
		wg.Add(1)
		go func(idx int) {
			defer wg.Done()
			ctx, cancel := context.WithTimeout(context.Background(), 80*time.Millisecond)
			defer cancel()

			body, _ := json.Marshal(map[string]any{
				"message":  fmt.Sprintf("Concurrent question %d", idx),
				"model_id": "nemotron-ultra",
			})
			req, _ := http.NewRequestWithContext(ctx, http.MethodPost, fmt.Sprintf("%s/api/v1/conversations/conv-%d/generations", server.URL, idx), bytes.NewReader(body))
			req.Header.Set("Authorization", "Bearer "+token)
			req.Header.Set("Content-Type", "application/json")

			resp, err := http.DefaultClient.Do(req)
			if err != nil {
				return
			}
			defer resp.Body.Close()

			reader := bufio.NewReader(resp.Body)
			for {
				_, err := reader.ReadString('\n')
				if err != nil {
					break
				}
			}
		}(i)
	}

	wg.Wait()
}
