package http

import (
	"encoding/json"
	"net/http"
)

type contextKey string

const RequestIDKey contextKey = "request_id"

// SuccessResponse standard format
type SuccessResponse struct {
	Data any `json:"data"`
}

// ErrorDetail standard format
type ErrorDetail struct {
	Code      string `json:"code"`
	Message   string `json:"message"`
	RequestID string `json:"request_id,omitempty"`
}

// ErrorResponse standard format
type ErrorResponse struct {
	Error ErrorDetail `json:"error"`
}

// WriteJSON writes a status code and JSON-encoded data.
func WriteJSON(w http.ResponseWriter, status int, data any) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(SuccessResponse{Data: data})
}

// WriteError writes a structured JSON error response.
func WriteError(w http.ResponseWriter, r *http.Request, status int, code, message string) {
	requestID := ""
	if r != nil {
		if id, ok := r.Context().Value(RequestIDKey).(string); ok {
			requestID = id
		}
	}
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(ErrorResponse{
		Error: ErrorDetail{
			Code:      code,
			Message:   message,
			RequestID: requestID,
		},
	})
}
