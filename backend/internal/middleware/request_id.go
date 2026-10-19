package middleware

import (
	"context"
	"net/http"

	apphttp "ai-chat-backend/internal/http"
	"github.com/google/uuid"
)

// RequestID middleware adds an X-Request-ID to context and header.
func RequestID(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		reqID := r.Header.Get("X-Request-ID")
		if reqID == "" {
			reqID = uuid.New().String()
		}
		w.Header().Set("X-Request-ID", reqID)
		ctx := context.WithValue(r.Context(), apphttp.RequestIDKey, reqID)
		next.ServeHTTP(w, r.WithContext(ctx))
	})
}
