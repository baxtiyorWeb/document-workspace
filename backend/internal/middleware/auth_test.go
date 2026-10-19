package middleware

import (
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/golang-jwt/jwt/v5"
)

func TestAuthMiddleware_ValidToken(t *testing.T) {
	secret := "test-secret-key-123456"
	auth := NewAuthenticator(secret)

	// Create valid token
	claims := jwt.MapClaims{
		"sub":   "user-123",
		"email": "test@example.com",
		"exp":   time.Now().Add(10 * time.Minute).Unix(),
	}
	token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	signed, err := token.SignedString([]byte(secret))
	if err != nil {
		t.Fatalf("failed to sign token: %v", err)
	}

	handlerCalled := false
	testHandler := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		handlerCalled = true
		userID, ok := GetUserID(r.Context())
		if !ok || userID != "user-123" {
			t.Errorf("expected user_id user-123, got: %v", userID)
		}
		email := GetUserEmail(r.Context())
		if email != "test@example.com" {
			t.Errorf("expected email test@example.com, got: %v", email)
		}
		w.WriteHeader(http.StatusOK)
	})

	req := httptest.NewRequest(http.MethodGet, "/test", nil)
	req.Header.Set("Authorization", "Bearer "+signed)
	rr := httptest.NewRecorder()

	auth.RequireAuth(testHandler).ServeHTTP(rr, req)

	if !handlerCalled {
		t.Fatal("expected handler to be called")
	}
	if rr.Code != http.StatusOK {
		t.Errorf("expected 200 OK, got: %d", rr.Code)
	}
}

func TestAuthMiddleware_MissingHeader(t *testing.T) {
	auth := NewAuthenticator("secret")
	testHandler := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {})

	req := httptest.NewRequest(http.MethodGet, "/test", nil)
	rr := httptest.NewRecorder()

	auth.RequireAuth(testHandler).ServeHTTP(rr, req)

	if rr.Code != http.StatusUnauthorized {
		t.Errorf("expected 401 Unauthorized, got: %d", rr.Code)
	}
}

func TestAuthMiddleware_ExpiredToken(t *testing.T) {
	secret := "test-secret"
	auth := NewAuthenticator(secret)

	// Create expired token
	claims := jwt.MapClaims{
		"sub":   "user-123",
		"email": "test@example.com",
		"exp":   time.Now().Add(-10 * time.Minute).Unix(),
	}
	token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	signed, _ := token.SignedString([]byte(secret))

	testHandler := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {})
	req := httptest.NewRequest(http.MethodGet, "/test", nil)
	req.Header.Set("Authorization", "Bearer "+signed)
	rr := httptest.NewRecorder()

	auth.RequireAuth(testHandler).ServeHTTP(rr, req)

	if rr.Code != http.StatusUnauthorized {
		t.Errorf("expected 401 Unauthorized for expired token, got: %d", rr.Code)
	}
}
