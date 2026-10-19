package middleware

import (
	"context"
	"net/http"
	"strings"

	apphttp "ai-chat-backend/internal/http"
	"github.com/golang-jwt/jwt/v5"
)

type userContextKey string

const (
	UserIDKey    userContextKey = "user_id"
	UserEmailKey userContextKey = "user_email"
)

// Authenticator validates Bearer JWT tokens and sets user identity in context.
type Authenticator struct {
	jwtSecret string
}

// NewAuthenticator creates a new Authenticator.
func NewAuthenticator(jwtSecret string) *Authenticator {
	return &Authenticator{jwtSecret: jwtSecret}
}

// RequireAuth middleware verifies the JWT token.
func (a *Authenticator) RequireAuth(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		authHeader := r.Header.Get("Authorization")
		if authHeader == "" || !strings.HasPrefix(strings.ToLower(authHeader), "bearer ") {
			apphttp.WriteError(w, r, http.StatusUnauthorized, "UNAUTHORIZED", "Missing or invalid Authorization header")
			return
		}

		tokenString := strings.TrimSpace(authHeader[7:])
		token, err := jwt.Parse(tokenString, func(t *jwt.Token) (interface{}, error) {
			if _, ok := t.Method.(*jwt.SigningMethodHMAC); !ok {
				return nil, jwt.ErrSignatureInvalid
			}
			return []byte(a.jwtSecret), nil
		})

		if err != nil || !token.Valid {
			apphttp.WriteError(w, r, http.StatusUnauthorized, "INVALID_TOKEN", "Authentication token is invalid or expired")
			return
		}

		claims, ok := token.Claims.(jwt.MapClaims)
		if !ok {
			apphttp.WriteError(w, r, http.StatusUnauthorized, "INVALID_CLAIMS", "Malformed token claims")
			return
		}

		userID, okID := claims["sub"].(string)
		email, _ := claims["email"].(string)

		if !okID || userID == "" {
			apphttp.WriteError(w, r, http.StatusUnauthorized, "INVALID_USER_ID", "Token missing subject identifier")
			return
		}

		ctx := context.WithValue(r.Context(), UserIDKey, userID)
		ctx = context.WithValue(ctx, UserEmailKey, email)
		next.ServeHTTP(w, r.WithContext(ctx))
	})
}

// GetUserID retrieves the user ID from the request context.
func GetUserID(ctx context.Context) (string, bool) {
	val, ok := ctx.Value(UserIDKey).(string)
	return val, ok && val != ""
}

// GetUserEmail retrieves the user email from the request context.
func GetUserEmail(ctx context.Context) string {
	val, _ := ctx.Value(UserEmailKey).(string)
	return val
}
