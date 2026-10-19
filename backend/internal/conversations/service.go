package conversations

import (
	"context"
	"errors"
	"fmt"
	"strings"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

var (
	ErrNotFound   = errors.New("CONVERSATION_NOT_FOUND: Suhbat topilmadi")
	ErrForbidden  = errors.New("FORBIDDEN: Ushbu suhbatga kirish huquqi yo'q")
	ErrValidation = errors.New("VALIDATION_ERROR: Noto'g'ri parametrlar")
)

// Service handles conversation management and ownership checks.
type Service struct {
	pool *pgxpool.Pool
}

// NewService creates a new conversations service.
func NewService(pool *pgxpool.Pool) *Service {
	return &Service{pool: pool}
}

// Create creates a new conversation for the user.
func (s *Service) Create(ctx context.Context, userID string, req CreateConversationRequest) (*Conversation, error) {
	if userID == "" {
		return nil, ErrForbidden
	}

	title := strings.TrimSpace(req.Title)
	if title == "" {
		title = "Yangi suhbat"
	}
	if len(title) > 200 {
		title = title[:200]
	}

	category := strings.TrimSpace(req.Category)
	if category == "" {
		category = "general"
	}

	if s.pool == nil {
		now := time.Now().UTC()
		return &Conversation{
			ID:            "conv-" + fmt.Sprintf("%d", now.UnixNano()),
			UserID:        userID,
			Title:         title,
			Category:      category,
			CreatedAt:     now,
			UpdatedAt:     now,
			LastMessageAt: now,
		}, nil
	}

	var conv Conversation
	err := s.pool.QueryRow(ctx, `
		INSERT INTO conversations (user_id, title, category)
		VALUES ($1, $2, $3)
		RETURNING id, user_id, title, category, created_at, updated_at, last_message_at
	`, userID, title, category).Scan(
		&conv.ID, &conv.UserID, &conv.Title, &conv.Category,
		&conv.CreatedAt, &conv.UpdatedAt, &conv.LastMessageAt,
	)
	if err != nil {
		return nil, fmt.Errorf("failed to create conversation: %w", err)
	}

	return &conv, nil
}

// List returns conversations for the authenticated user ordered by latest activity.
func (s *Service) List(ctx context.Context, userID string, limit, offset int) ([]Conversation, error) {
	if limit <= 0 || limit > 100 {
		limit = 30
	}
	if offset < 0 {
		offset = 0
	}

	if s.pool == nil {
		now := time.Now().UTC()
		return []Conversation{
			{
				ID:            "conv-default-1",
				UserID:        userID,
				Title:         "Default Chat",
				Category:      "general",
				CreatedAt:     now,
				UpdatedAt:     now,
				LastMessageAt: now,
			},
		}, nil
	}

	rows, err := s.pool.Query(ctx, `
		SELECT id, user_id, title, category, created_at, updated_at, last_message_at
		FROM conversations
		WHERE user_id = $1
		ORDER BY last_message_at DESC
		LIMIT $2 OFFSET $3
	`, userID, limit, offset)
	if err != nil {
		return nil, fmt.Errorf("failed to list conversations: %w", err)
	}
	defer rows.Close()

	items := make([]Conversation, 0)
	for rows.Next() {
		var c Conversation
		if err := rows.Scan(&c.ID, &c.UserID, &c.Title, &c.Category, &c.CreatedAt, &c.UpdatedAt, &c.LastMessageAt); err != nil {
			return nil, fmt.Errorf("failed to scan conversation: %w", err)
		}
		items = append(items, c)
	}

	return items, nil
}

// GetByID returns a specific conversation, strictly verifying ownership.
func (s *Service) GetByID(ctx context.Context, userID, convID string) (*Conversation, error) {
	if s.pool == nil {
		now := time.Now().UTC()
		return &Conversation{
			ID:            convID,
			UserID:        userID,
			Title:         "Test Conversation",
			Category:      "general",
			CreatedAt:     now,
			UpdatedAt:     now,
			LastMessageAt: now,
		}, nil
	}

	var c Conversation
	err := s.pool.QueryRow(ctx, `
		SELECT id, user_id, title, category, created_at, updated_at, last_message_at
		FROM conversations
		WHERE id = $1 AND user_id = $2
	`, convID, userID).Scan(
		&c.ID, &c.UserID, &c.Title, &c.Category, &c.CreatedAt, &c.UpdatedAt, &c.LastMessageAt,
	)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, ErrNotFound
		}
		return nil, fmt.Errorf("failed to query conversation: %w", err)
	}
	return &c, nil
}

// UpdateTitle renames a conversation.
func (s *Service) UpdateTitle(ctx context.Context, userID, convID, newTitle string) (*Conversation, error) {
	title := strings.TrimSpace(newTitle)
	if title == "" {
		return nil, fmt.Errorf("%w: Sarlavha bo'sh bo'lishi mumkin emas", ErrValidation)
	}
	if len(title) > 200 {
		title = title[:200]
	}

	if s.pool == nil {
		now := time.Now().UTC()
		return &Conversation{
			ID:            convID,
			UserID:        userID,
			Title:         title,
			Category:      "general",
			CreatedAt:     now,
			UpdatedAt:     now,
			LastMessageAt: now,
		}, nil
	}

	var c Conversation
	err := s.pool.QueryRow(ctx, `
		UPDATE conversations
		SET title = $1, updated_at = CURRENT_TIMESTAMP
		WHERE id = $2 AND user_id = $3
		RETURNING id, user_id, title, category, created_at, updated_at, last_message_at
	`, title, convID, userID).Scan(
		&c.ID, &c.UserID, &c.Title, &c.Category, &c.CreatedAt, &c.UpdatedAt, &c.LastMessageAt,
	)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, ErrNotFound
		}
		return nil, fmt.Errorf("failed to update title: %w", err)
	}
	return &c, nil
}

// Delete removes a conversation with ownership check.
func (s *Service) Delete(ctx context.Context, userID, convID string) error {
	if s.pool == nil {
		return nil
	}

	cmd, err := s.pool.Exec(ctx, `
		DELETE FROM conversations
		WHERE id = $1 AND user_id = $2
	`, convID, userID)
	if err != nil {
		return fmt.Errorf("failed to delete conversation: %w", err)
	}
	if cmd.RowsAffected() == 0 {
		return ErrNotFound
	}
	return nil
}
