package generations

import "time"

// Generation represents an AI streaming generation job.
type Generation struct {
	ID                 string     `json:"id"`
	ConversationID     string     `json:"conversation_id"`
	UserID             string     `json:"user_id"`
	AssistantMessageID *string    `json:"assistant_message_id,omitempty"`
	Status             string     `json:"status"`
	Provider           string     `json:"provider"`
	Model              string     `json:"model"`
	PromptTokens       int        `json:"prompt_tokens"`
	CompletionTokens   int        `json:"completion_tokens"`
	TotalTokens        int        `json:"total_tokens"`
	ErrorCode          *string    `json:"error_code,omitempty"`
	ErrorMessage       *string    `json:"error_message,omitempty"`
	CreatedAt          time.Time  `json:"created_at"`
	CompletedAt        *time.Time `json:"completed_at,omitempty"`
	CancelledAt        *time.Time `json:"cancelled_at,omitempty"`
}

// GenerateRequest payload when user initiates chat generation.
type GenerateRequest struct {
	Message string   `json:"message"`
	ModelID string   `json:"model_id,omitempty"`
	FileIDs []string `json:"file_ids,omitempty"`
}
