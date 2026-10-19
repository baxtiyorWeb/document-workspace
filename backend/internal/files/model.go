package files

import (
	"time"
)

type FileType string

const (
	FileTypePDF   FileType = "pdf"
	FileTypeDOCX  FileType = "docx"
	FileTypeXLSX  FileType = "xlsx"
	FileTypePPTX  FileType = "pptx"
	FileTypeImage FileType = "image"
	FileTypeText  FileType = "text"
	FileTypeAudio FileType = "audio"
	FileTypeVideo FileType = "video"
	FileTypeOther FileType = "other"
)

// File represents a stored file asset with extracted metadata.
type File struct {
	ID             string         `json:"id"`
	UserID         string         `json:"user_id"`
	ConversationID *string        `json:"conversation_id,omitempty"`
	Filename       string         `json:"filename"`
	FileType       FileType       `json:"file_type"`
	MimeType       string         `json:"mime_type"`
	FileSizeBytes  int64          `json:"file_size_bytes"`
	SHA256Hash     string         `json:"sha256_hash"`
	StoragePath    string         `json:"-"` // Not exposed directly to client
	ExtractedText  *string        `json:"extracted_text,omitempty"`
	ChunkCount     int            `json:"chunk_count"`
	Metadata       map[string]any `json:"metadata"`
	DownloadURL    string         `json:"download_url,omitempty"`
	CreatedAt      time.Time      `json:"created_at"`
}

// FileChunk represents a structured text chunk for RAG.
type FileChunk struct {
	ID           string    `json:"id"`
	FileID       string    `json:"file_id"`
	ChunkIndex   int       `json:"chunk_index"`
	PageNumber   *int      `json:"page_number,omitempty"`
	SectionTitle *string   `json:"section_title,omitempty"`
	Content      string    `json:"content"`
	TokenCount   int       `json:"token_count"`
	CreatedAt    time.Time `json:"created_at"`
}

// MediaJob represents an asynchronous video/audio processing job.
type MediaJob struct {
	ID              string     `json:"id"`
	UserID          string     `json:"user_id"`
	FileID          string     `json:"file_id"`
	Status          string     `json:"status"` // queued, processing, completed, failed
	JobType         string     `json:"job_type"`
	ProgressPercent int        `json:"progress_percent"`
	ResultText      *string    `json:"result_text,omitempty"`
	ErrorMessage    *string    `json:"error_message,omitempty"`
	StartedAt       *time.Time `json:"started_at,omitempty"`
	CompletedAt     *time.Time `json:"completed_at,omitempty"`
	CreatedAt       time.Time  `json:"created_at"`
}

// RetrievalResult is returned during RAG retrieval.
type RetrievalResult struct {
	FileID       string `json:"file_id"`
	Filename     string `json:"filename"`
	PageNumber   int    `json:"page_number,omitempty"`
	SectionTitle string `json:"section_title,omitempty"`
	Snippet      string `json:"snippet"`
	Relevance    float64 `json:"relevance"`
}
