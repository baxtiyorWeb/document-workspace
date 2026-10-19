package conversations

import "time"

// Conversation represents a chat session.
type Conversation struct {
	ID            string    `json:"id"`
	UserID        string    `json:"user_id"`
	Title         string    `json:"title"`
	Category      string    `json:"category"`
	CreatedAt     time.Time `json:"created_at"`
	UpdatedAt     time.Time `json:"updated_at"`
	LastMessageAt time.Time `json:"last_message_at"`
}

// CreateConversationRequest payload.
type CreateConversationRequest struct {
	Title    string `json:"title,omitempty"`
	Category string `json:"category,omitempty"`
}

// UpdateConversationRequest payload.
type UpdateConversationRequest struct {
	Title string `json:"title"`
}
