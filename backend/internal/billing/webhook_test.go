package billing_test

import (
	"encoding/json"
	"testing"

	"ai-chat-backend/internal/billing"
)

func TestRevenueCatWebhookAuthorization(t *testing.T) {
	authToken := "test-revenuecat-webhook-secret-token-xyz"
	handler := billing.NewRevenueCatHandler(nil, authToken, "com.aichat.app.mobile")

	// 1. Valid Bearer token must pass
	if !handler.VerifyAuthorization("Bearer " + authToken) {
		t.Errorf("Expected valid Bearer token to pass verification")
	}

	// 2. Valid raw token must pass
	if !handler.VerifyAuthorization(authToken) {
		t.Errorf("Expected valid raw token to pass verification")
	}

	// 3. Invalid token must fail
	if handler.VerifyAuthorization("Bearer invalid-secret-token") {
		t.Errorf("Expected invalid token to fail verification")
	}

	// 4. Empty header must fail
	if handler.VerifyAuthorization("") {
		t.Errorf("Expected empty auth header to fail verification")
	}

	// 5. Handler with empty token must fail closed
	devHandler := billing.NewRevenueCatHandler(nil, "", "com.aichat.app.mobile")
	if devHandler.VerifyAuthorization("") {
		t.Errorf("Expected empty token handler to fail closed")
	}
	if devHandler.VerifyAuthorization("Bearer some-token") {
		t.Errorf("Expected empty token handler to fail closed even with Bearer token")
	}
}

func TestRevenueCatEventPayloadParsing(t *testing.T) {
	rawJSON := `{
		"api_version": "1.0",
		"event": {
			"id": "rc_evt_test_12345",
			"type": "INITIAL_PURCHASE",
			"app_user_id": "c1f7a049-51a7-47b2-bd72-359f4277da65",
			"original_app_user_id": "c1f7a049-51a7-47b2-bd72-359f4277da65",
			"product_id": "monthly",
			"entitlement_id": "cognidoc_ai_document_analyzer_and_chatbot_pro",
			"entitlement_ids": ["cognidoc_ai_document_analyzer_and_chatbot_pro"],
			"purchased_at_ms": 1729000000000,
			"expiration_at_ms": 1731678400000,
			"store": "PLAY_STORE",
			"environment": "SANDBOX",
			"original_transaction_id": "GPA.3391-2314-1123-99120",
			"currency": "USD",
			"price_in_purchased_currency": 9.99
		}
	}`

	var p billing.RevenueCatWebhookPayload
	if err := json.Unmarshal([]byte(rawJSON), &p); err != nil {
		t.Fatalf("Failed to unmarshal RevenueCat JSON: %v", err)
	}

	if p.Event.ID != "rc_evt_test_12345" {
		t.Errorf("Expected event ID rc_evt_test_12345, got %s", p.Event.ID)
	}
	if p.Event.Type != "INITIAL_PURCHASE" {
		t.Errorf("Expected event Type INITIAL_PURCHASE, got %s", p.Event.Type)
	}
	if p.Event.EntitlementID != "cognidoc_ai_document_analyzer_and_chatbot_pro" {
		t.Errorf("Expected entitlement ID cognidoc_ai_document_analyzer_and_chatbot_pro, got %s", p.Event.EntitlementID)
	}
	if p.Event.OriginalTransactionID != "GPA.3391-2314-1123-99120" {
		t.Errorf("Expected GPA.3391-2314-1123-99120, got %s", p.Event.OriginalTransactionID)
	}
}
