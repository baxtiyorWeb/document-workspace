package middleware

import (
	"net/http"
	"net/http/httptest"
	"testing"
	"time"
)

func TestIPRateLimiter_ThrottlesExcessiveRequests(t *testing.T) {
	limiter := NewIPRateLimiter(3, 100*time.Millisecond)

	dummyHandler := limiter.Limit(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
	}))

	for i := 0; i < 3; i++ {
		req := httptest.NewRequest("POST", "/test", nil)
		req.RemoteAddr = "192.168.1.100:12345"
		w := httptest.NewRecorder()
		dummyHandler.ServeHTTP(w, req)
		if w.Code != http.StatusOK {
			t.Fatalf("request %d expected 200 OK, got %d", i+1, w.Code)
		}
	}

	// 4th request should be throttled
	req := httptest.NewRequest("POST", "/test", nil)
	req.RemoteAddr = "192.168.1.100:12345"
	w := httptest.NewRecorder()
	dummyHandler.ServeHTTP(w, req)
	if w.Code != http.StatusTooManyRequests {
		t.Fatalf("expected 429 Too Many Requests, got %d", w.Code)
	}

	// Wait for window to expire
	time.Sleep(120 * time.Millisecond)

	// Should be allowed again
	req2 := httptest.NewRequest("POST", "/test", nil)
	req2.RemoteAddr = "192.168.1.100:12345"
	w2 := httptest.NewRecorder()
	dummyHandler.ServeHTTP(w2, req2)
	if w2.Code != http.StatusOK {
		t.Fatalf("expected 200 OK after window reset, got %d", w2.Code)
	}
}
