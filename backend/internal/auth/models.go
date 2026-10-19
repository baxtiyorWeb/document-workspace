package auth

import "time"

// User represents an account in the database.
type User struct {
	ID           string    `json:"id"`
	Email        string    `json:"email"`
	PasswordHash string    `json:"-"`
	FullName     string    `json:"full_name"`
	Status       string    `json:"status"`
	CreatedAt    time.Time `json:"created_at"`
	UpdatedAt    time.Time `json:"updated_at"`
}

// UserPublic represents non-sensitive user profile data.
type UserPublic struct {
	ID        string    `json:"id"`
	Email     string    `json:"email"`
	FullName  string    `json:"full_name"`
	CreatedAt time.Time `json:"created_at"`
}

// RegisterRequest payload.
type RegisterRequest struct {
	Email    string `json:"email"`
	Password string `json:"password"`
	FullName string `json:"full_name"`
}

// LoginRequest payload.
type LoginRequest struct {
	Email    string `json:"email"`
	Password string `json:"password"`
}

// RefreshRequest payload.
type RefreshRequest struct {
	RefreshToken string `json:"refresh_token"`
}

// AuthResponse payload returned on successful register, login, or refresh.
type AuthResponse struct {
	User         UserPublic `json:"user"`
	AccessToken  string     `json:"access_token"`
	RefreshToken string     `json:"refresh_token"`
	ExpiresIn    int64      `json:"expires_in"` // seconds
}
