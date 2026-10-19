package http

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestWriteJSON(t *testing.T) {
	rr := httptest.NewRecorder()
	WriteJSON(rr, http.StatusOK, map[string]string{"foo": "bar"})

	if rr.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", rr.Code)
	}

	var resp SuccessResponse
	if err := json.Unmarshal(rr.Body.Bytes(), &resp); err != nil {
		t.Fatalf("failed to decode response: %v", err)
	}

	dataMap, ok := resp.Data.(map[string]any)
	if !ok || dataMap["foo"] != "bar" {
		t.Fatalf("unexpected data: %v", resp.Data)
	}
}

func TestWriteError(t *testing.T) {
	rr := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodGet, "/err", nil)
	ctx := context.WithValue(req.Context(), RequestIDKey, "test-req-id-999")
	req = req.WithContext(ctx)

	WriteError(rr, req, http.StatusBadRequest, "INVALID_INPUT", "Invalid message input")

	if rr.Code != http.StatusBadRequest {
		t.Fatalf("expected 400, got %d", rr.Code)
	}

	var errResp ErrorResponse
	if err := json.Unmarshal(rr.Body.Bytes(), &errResp); err != nil {
		t.Fatalf("failed to decode error response: %v", err)
	}

	if errResp.Error.Code != "INVALID_INPUT" {
		t.Errorf("expected code INVALID_INPUT, got %s", errResp.Error.Code)
	}
	if errResp.Error.RequestID != "test-req-id-999" {
		t.Errorf("expected request_id test-req-id-999, got %s", errResp.Error.RequestID)
	}
}
