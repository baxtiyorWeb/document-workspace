package middleware

import (
	"net"
	"net/http"
	"strings"
	"sync"
	"time"

	apphttp "ai-chat-backend/internal/http"
)

type clientRecord struct {
	tokens     int
	lastRefill time.Time
}

// IPRateLimiter provides thread-safe in-memory rate limiting per client IP.
type IPRateLimiter struct {
	mu      sync.Mutex
	clients map[string]*clientRecord
	limit   int
	window  time.Duration
}

// NewIPRateLimiter creates a new rate limiter with background cleanup.
func NewIPRateLimiter(limit int, window time.Duration) *IPRateLimiter {
	limiter := &IPRateLimiter{
		clients: make(map[string]*clientRecord),
		limit:   limit,
		window:  window,
	}
	go limiter.cleanupLoop(5 * time.Minute)
	return limiter
}

func (limiter *IPRateLimiter) cleanupLoop(interval time.Duration) {
	ticker := time.NewTicker(interval)
	for range ticker.C {
		limiter.mu.Lock()
		now := time.Now()
		for ip, rec := range limiter.clients {
			if now.Sub(rec.lastRefill) > limiter.window*2 {
				delete(limiter.clients, ip)
			}
		}
		limiter.mu.Unlock()
	}
}

// Limit returns a middleware that throttles excessive requests.
func (limiter *IPRateLimiter) Limit(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		ip := extractClientIP(r)
		limiter.mu.Lock()
		now := time.Now()
		rec, exists := limiter.clients[ip]
		if !exists {
			rec = &clientRecord{tokens: limiter.limit - 1, lastRefill: now}
			limiter.clients[ip] = rec
			limiter.mu.Unlock()
			next.ServeHTTP(w, r)
			return
		}

		elapsed := now.Sub(rec.lastRefill)
		if elapsed >= limiter.window {
			rec.tokens = limiter.limit - 1
			rec.lastRefill = now
			limiter.mu.Unlock()
			next.ServeHTTP(w, r)
			return
		}

		if rec.tokens <= 0 {
			limiter.mu.Unlock()
			w.Header().Set("Retry-After", "60")
			apphttp.WriteError(w, r, http.StatusTooManyRequests, "RATE_LIMIT_EXCEEDED", "Juda ko'p so'rov yuborildi. Iltimos, birozdan keyin qayta urinib ko'ring.")
			return
		}

		rec.tokens--
		limiter.mu.Unlock()
		next.ServeHTTP(w, r)
	})
}

func extractClientIP(r *http.Request) string {
	if xff := r.Header.Get("X-Forwarded-For"); xff != "" {
		parts := strings.Split(xff, ",")
		return strings.TrimSpace(parts[0])
	}
	if xrip := r.Header.Get("X-Real-IP"); xrip != "" {
		return strings.TrimSpace(xrip)
	}
	ip, _, err := net.SplitHostPort(r.RemoteAddr)
	if err == nil {
		return ip
	}
	return r.RemoteAddr
}
