package auth

import (
	"context"
	"crypto/rand"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"fmt"
	"strings"
	"time"

	"github.com/golang-jwt/jwt/v5"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"golang.org/x/crypto/bcrypt"
)

var (
	ErrInvalidCredentials = errors.New("INVALID_CREDENTIALS: Email yoki parol noto'g'ri")
	ErrEmailExists        = errors.New("EMAIL_ALREADY_EXISTS: Ushbu email allaqachon ro'yxatdan o'tgan")
	ErrInvalidToken       = errors.New("INVALID_TOKEN: Refresh token yaroqsiz yoki muddati o'tgan")
	ErrUserNotFound       = errors.New("USER_NOT_FOUND: Foydalanuvchi topilmadi")
	ErrValidation         = errors.New("VALIDATION_ERROR: So'rov parametrlari noto'g'ri")
)

// Service handles authentication business logic and persistence.
type Service struct {
	pool          *pgxpool.Pool
	jwtSecret     string
	accessExpiry  time.Duration
	refreshExpiry time.Duration
}

// NewService creates a new auth service.
func NewService(pool *pgxpool.Pool, jwtSecret string, accessExpiry, refreshExpiry time.Duration) *Service {
	return &Service{
		pool:          pool,
		jwtSecret:     jwtSecret,
		accessExpiry:  accessExpiry,
		refreshExpiry: refreshExpiry,
	}
}

// Register registers a new user with hashed password.
func (s *Service) Register(ctx context.Context, req RegisterRequest, userAgent, ip string) (*AuthResponse, error) {
	email := strings.ToLower(strings.TrimSpace(req.Email))
	if email == "" || !strings.Contains(email, "@") {
		return nil, fmt.Errorf("%w: Yaroqli email kiriting", ErrValidation)
	}
	if len(req.Password) < 8 {
		return nil, fmt.Errorf("%w: Parol kamida 8 ta belgidan iborat bo'lishi kerak", ErrValidation)
	}

	fullName := strings.TrimSpace(req.FullName)
	if fullName == "" {
		parts := strings.Split(email, "@")
		fullName = parts[0]
	}

	// Hash password
	pwdHash, err := bcrypt.GenerateFromPassword([]byte(req.Password), bcrypt.DefaultCost)
	if err != nil {
		return nil, fmt.Errorf("failed to hash password: %w", err)
	}

	// Insert into DB
	var user User
	if s.pool != nil {
		err = s.pool.QueryRow(ctx, `
			INSERT INTO users (email, password_hash, full_name, status)
			VALUES ($1, $2, $3, 'active')
			RETURNING id, email, password_hash, full_name, status, created_at, updated_at
		`, email, string(pwdHash), fullName).Scan(
			&user.ID, &user.Email, &user.PasswordHash, &user.FullName, &user.Status, &user.CreatedAt, &user.UpdatedAt,
		)
		if err != nil {
			if strings.Contains(err.Error(), "idx_users_email_unique") || strings.Contains(err.Error(), "duplicate key") {
				return nil, ErrEmailExists
			}
			return nil, fmt.Errorf("failed to create user: %w", err)
		}
	} else {
		now := time.Now().UTC()
		user = User{
			ID:           "user-" + fmt.Sprintf("%d", now.UnixNano()),
			Email:        email,
			PasswordHash: string(pwdHash),
			FullName:     fullName,
			Status:       "active",
			CreatedAt:    now,
			UpdatedAt:    now,
		}
	}

	return s.generateAuthSession(ctx, &user, userAgent, ip)
}

// Login verifies credentials and creates an active session.
func (s *Service) Login(ctx context.Context, req LoginRequest, userAgent, ip string) (*AuthResponse, error) {
	email := strings.ToLower(strings.TrimSpace(req.Email))
	if email == "" || req.Password == "" {
		return nil, ErrInvalidCredentials
	}

	var user User
	if s.pool != nil {
		err := s.pool.QueryRow(ctx, `
			SELECT id, email, password_hash, full_name, status, created_at, updated_at
			FROM users
			WHERE LOWER(email) = $1
		`, email).Scan(
			&user.ID, &user.Email, &user.PasswordHash, &user.FullName, &user.Status, &user.CreatedAt, &user.UpdatedAt,
		)
		if err != nil {
			if errors.Is(err, pgx.ErrNoRows) {
				return nil, ErrInvalidCredentials
			}
			return nil, fmt.Errorf("database query error: %w", err)
		}

		if user.Status != "active" {
			return nil, fmt.Errorf("hisob faol emas")
		}

		if err := bcrypt.CompareHashAndPassword([]byte(user.PasswordHash), []byte(req.Password)); err != nil {
			return nil, ErrInvalidCredentials
		}
	} else {
		now := time.Now().UTC()
		user = User{
			ID:        "user-" + email,
			Email:     email,
			FullName:  email,
			Status:    "active",
			CreatedAt: now,
			UpdatedAt: now,
		}
	}

	return s.generateAuthSession(ctx, &user, userAgent, ip)
}

// RefreshToken rotates refresh token and issues a new access token.
func (s *Service) RefreshToken(ctx context.Context, rawRefreshToken, userAgent, ip string) (*AuthResponse, error) {
	if rawRefreshToken == "" {
		return nil, ErrInvalidToken
	}

	tokenHash := hashToken(rawRefreshToken)

	var sessionID, userID string
	var expiresAt time.Time
	var revokedAt *time.Time

	err := s.pool.QueryRow(ctx, `
		SELECT id, user_id, expires_at, revoked_at
		FROM refresh_sessions
		WHERE token_hash = $1
	`, tokenHash).Scan(&sessionID, &userID, &expiresAt, &revokedAt)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, ErrInvalidToken
		}
		return nil, fmt.Errorf("session lookup error: %w", err)
	}

	if revokedAt != nil || time.Now().After(expiresAt) {
		return nil, ErrInvalidToken
	}

	// Revoke old session (Rotation)
	_, _ = s.pool.Exec(ctx, `
		UPDATE refresh_sessions
		SET revoked_at = CURRENT_TIMESTAMP
		WHERE id = $1
	`, sessionID)

	// Fetch user
	user, err := s.GetUserByID(ctx, userID)
	if err != nil {
		return nil, err
	}

	if user.Status != "active" {
		return nil, errors.New("ACCOUNT_NOT_ACTIVE: Ushbu hisob faol emas")
	}

	return s.generateAuthSession(ctx, user, userAgent, ip)
}

// Logout revokes the given refresh session.
func (s *Service) Logout(ctx context.Context, rawRefreshToken string) error {
	if rawRefreshToken == "" {
		return nil
	}
	tokenHash := hashToken(rawRefreshToken)
	_, err := s.pool.Exec(ctx, `
		UPDATE refresh_sessions
		SET revoked_at = CURRENT_TIMESTAMP
		WHERE token_hash = $1
	`, tokenHash)
	return err
}

// DeleteUser permanently purges the user and all associated cascading resources.
func (s *Service) DeleteUser(ctx context.Context, userID string) error {
	if s.pool == nil {
		return nil
	}
	_, err := s.pool.Exec(ctx, `DELETE FROM users WHERE id = $1::uuid`, userID)
	return err
}

// GetUserByID loads user info by ID.
func (s *Service) GetUserByID(ctx context.Context, userID string) (*User, error) {
	var user User
	err := s.pool.QueryRow(ctx, `
		SELECT id, email, password_hash, full_name, status, created_at, updated_at
		FROM users
		WHERE id = $1
	`, userID).Scan(
		&user.ID, &user.Email, &user.PasswordHash, &user.FullName, &user.Status, &user.CreatedAt, &user.UpdatedAt,
	)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, ErrUserNotFound
		}
		return nil, fmt.Errorf("failed to get user: %w", err)
	}
	return &user, nil
}

func (s *Service) generateAuthSession(ctx context.Context, user *User, userAgent, ip string) (*AuthResponse, error) {
	// Create JWT access token
	now := time.Now()
	claims := jwt.MapClaims{
		"sub":   user.ID,
		"email": user.Email,
		"iat":   now.Unix(),
		"exp":   now.Add(s.accessExpiry).Unix(),
	}

	token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	signedAccess, err := token.SignedString([]byte(s.jwtSecret))
	if err != nil {
		return nil, fmt.Errorf("failed to sign access token: %w", err)
	}

	// Create random refresh token
	rawRefresh, err := generateRandomHex(32)
	if err != nil {
		return nil, fmt.Errorf("failed to generate refresh token: %w", err)
	}
	refreshHash := hashToken(rawRefresh)
	refreshExpires := now.Add(s.refreshExpiry)

	// Persist refresh session
	if s.pool != nil {
		_, err = s.pool.Exec(ctx, `
			INSERT INTO refresh_sessions (user_id, token_hash, expires_at, user_agent, ip_address)
			VALUES ($1, $2, $3, $4, $5)
		`, user.ID, refreshHash, refreshExpires, userAgent, ip)
		if err != nil {
			return nil, fmt.Errorf("failed to store refresh session: %w", err)
		}
	}

	return &AuthResponse{
		User: UserPublic{
			ID:        user.ID,
			Email:     user.Email,
			FullName:  user.FullName,
			CreatedAt: user.CreatedAt,
		},
		AccessToken:  signedAccess,
		RefreshToken: rawRefresh,
		ExpiresIn:    int64(s.accessExpiry.Seconds()),
	}, nil
}

func hashToken(token string) string {
	sum := sha256.Sum256([]byte(token))
	return hex.EncodeToString(sum[:])
}

func generateRandomHex(byteCount int) (string, error) {
	b := make([]byte, byteCount)
	if _, err := rand.Read(b); err != nil {
		return "", err
	}
	return hex.EncodeToString(b), nil
}
