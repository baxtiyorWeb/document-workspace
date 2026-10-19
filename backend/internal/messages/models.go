package messages

import "time"

// Message represents a single chat bubble.
type Message struct {
	ID             string    `json:"id"`
	ConversationID string    `json:"conversation_id"`
	UserID         string    `json:"user_id"`
	Role           string    `json:"role"`
	Content        string    `json:"content"`
	Status         string    `json:"status"`
	AttachedFileIDs []string  `json:"attached_file_ids,omitempty"`
	CreatedAt      time.Time `json:"created_at"`
	UpdatedAt      time.Time `json:"updated_at"`
}

// CreateMessageRequest payload.
type CreateMessageRequest struct {
	Content string `json:"content"`
}
