package main

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
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
	"ai-chat-backend/tests"

	"github.com/go-chi/chi/v5"
	chimiddleware "github.com/go-chi/chi/v5/middleware"
	"github.com/go-chi/cors"
	"github.com/golang-jwt/jwt/v5"
)

func createTestToken(userID, secret string) string {
	claims := jwt.MapClaims{
		"sub": userID,
		"exp": time.Now().Add(24 * time.Hour).Unix(),
	}
	t := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	s, _ := t.SignedString([]byte(secret))
	return s
}

func main() {
	// 1. Start dedicated mock LLM server
	mockLLMURL, mockTeardown := tests.StartMockLLMServer(8086)
	defer mockTeardown()
	log.Printf("[TEST_ENV] Mock LLM provider running at %s", mockLLMURL)

	jwtSecret := "super-secret-jwt-key-replace-in-production-change-me"

	// 2. Initialize In-Memory/Test Services
	authService := auth.NewService(nil, jwtSecret, 15*time.Minute, 7*24*time.Hour)
	convService := conversations.NewService(nil)
	msgService := messages.NewService(nil)
	plansService := plans.NewService(nil)

	modelReg := gateway.NewModelRegistry(nil)
	gatewayRouter := gateway.NewRouter(modelReg)
	quotaService := gateway.NewQuotaService(nil)

	aiProvider := ai.NewOpenAICompatibleProvider(mockLLMURL, "mock-api-key", "nemotron-ultra", "system prompt", 2048, 0.7)
	filesService := files.NewService(nil, "./storage/uploads")

	genService := generations.NewService(nil, aiProvider, msgService, plansService, filesService, gatewayRouter, quotaService)

	rcHandler := billing.NewRevenueCatHandler(nil, "super-secret-revenuecat-webhook-token", "com.aichat.app.mobile")
	billingHandler := handlers.NewBillingHandler(rcHandler, plansService, nil)

	authHandler := handlers.NewAuthHandler(authService)
	convHandler := handlers.NewConversationHandler(convService)
	msgHandler := handlers.NewMessageHandler(msgService)
	genHandler := handlers.NewGenerationHandler(genService)
	plansHandler := handlers.NewPlansHandler(plansService)
	modelsHandler := handlers.NewModelsHandler(modelReg, plansService)
	filesHandler := handlers.NewFilesHandler(filesService, plansService)
	healthHandler := handlers.NewHealthHandler(nil)

	authenticator := middleware.NewAuthenticator(jwtSecret)

	r := chi.NewRouter()
	r.Use(middleware.RequestID)
	r.Use(chimiddleware.Recoverer)
	r.Use(cors.Handler(cors.Options{
		AllowedOrigins: []string{"*"},
		AllowedMethods: []string{"GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"},
		AllowedHeaders: []string{"*"},
	}))

	// Health
	r.Get("/health/live", healthHandler.Live)
	r.Get("/health/ready", healthHandler.Ready)

	// API v1
	r.Route("/api/v1", func(api chi.Router) {
		api.Post("/auth/register", authHandler.Register)
		api.Post("/auth/login", authHandler.Login)
		api.Get("/plans", plansHandler.ListPlans)
		api.Post("/billing/webhook", billingHandler.Webhook)

		// Helper to instantly mint JWT tokens for k6 virtual users
		api.Post("/test/token", func(w http.ResponseWriter, r *http.Request) {
			userID := r.URL.Query().Get("user_id")
			if userID == "" {
				userID = "user-load-test"
			}
			t := createTestToken(userID, jwtSecret)
			w.Header().Set("Content-Type", "application/json")
			_ = json.NewEncoder(w).Encode(map[string]string{
				"token":   t,
				"user_id": userID,
			})
		})

		api.Group(func(protected chi.Router) {
			protected.Use(authenticator.RequireAuth)

			protected.Get("/me", authHandler.Me)
			protected.Delete("/me", authHandler.DeleteAccount)
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
			protected.Post("/messages/{messageID}/report", msgHandler.Report)

			protected.Post("/conversations/{conversationID}/generations", genHandler.StreamGeneration)
			protected.Post("/generations/{generationID}/cancel", genHandler.CancelGeneration)

			protected.Post("/files/upload", filesHandler.Upload)
		})
	})

	testPort := "8085"
	server := &http.Server{
		Addr:    ":" + testPort,
		Handler: r,
	}

	stopChan := make(chan os.Signal, 1)
	signal.Notify(stopChan, os.Interrupt, syscall.SIGTERM)

	go func() {
		log.Printf("[TEST_ENV] Dedicated Performance Test Server listening on http://127.0.0.1:%s", testPort)
		if err := server.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Fatalf("Test server failure: %v", err)
		}
	}()

	<-stopChan
	log.Println("[TEST_ENV] Stopping test server...")
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	_ = server.Shutdown(ctx)
	fmt.Println("Test server stopped")
}
