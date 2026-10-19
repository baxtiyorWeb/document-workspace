package middleware

import (
	"log"
	"net/http"
	"time"

	apphttp "ai-chat-backend/internal/http"
)

type responseWriterWrapper struct {
	http.ResponseWriter
	statusCode int
}

func (rw *responseWriterWrapper) WriteHeader(code int) {
	rw.statusCode = code
	rw.ResponseWriter.WriteHeader(code)
}

func (rw *responseWriterWrapper) Flush() {
	if flusher, ok := rw.ResponseWriter.(http.Flusher); ok {
		flusher.Flush()
	}
}

func (rw *responseWriterWrapper) Unwrap() http.ResponseWriter {
	return rw.ResponseWriter
}

// Logger logs each incoming request with method, path, status, and duration.
func Logger(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		wrapper := &responseWriterWrapper{ResponseWriter: w, statusCode: http.StatusOK}
		next.ServeHTTP(wrapper, r)

		reqID := ""
		if id, ok := r.Context().Value(apphttp.RequestIDKey).(string); ok {
			reqID = id
		}

		duration := time.Since(start)
		log.Printf("[%s] %s %s -> %d (%s) req_id=%s",
			r.Method, r.URL.Path, r.RemoteAddr, wrapper.statusCode, duration, reqID)
	})
}
