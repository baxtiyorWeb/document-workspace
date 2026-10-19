package handlers

import (
	"encoding/json"
	"errors"
	"net/http"
	"os"

	"ai-chat-backend/internal/files"
	"ai-chat-backend/internal/middleware"
	"ai-chat-backend/internal/plans"
	"github.com/go-chi/chi/v5"
)

type FilesHandler struct {
	filesService *files.Service
	plansService *plans.Service
}

func NewFilesHandler(filesService *files.Service, plansService *plans.Service) *FilesHandler {
	return &FilesHandler{
		filesService: filesService,
		plansService: plansService,
	}
}

// Upload handles multipart file upload with plan limits and text extraction.
func (h *FilesHandler) Upload(w http.ResponseWriter, r *http.Request) {
	userID, ok := middleware.GetUserID(r.Context())
	if !ok || userID == "" {
		http.Error(w, `{"error":"UNAUTHORIZED"}`, http.StatusUnauthorized)
		return
	}

	ent, err := h.plansService.ResolveUserEntitlement(r.Context(), userID)
	if err != nil {
		http.Error(w, `{"error":"ENTITLEMENT_RESOLUTION_FAILED"}`, http.StatusInternalServerError)
		return
	}

	// Limit request body to prevent memory exhaustion (e.g. up to 210MB)
	maxAllowedBytes := int64(210 * 1024 * 1024)
	r.Body = http.MaxBytesReader(w, r.Body, maxAllowedBytes)

	if err := r.ParseMultipartForm(32 << 20); err != nil { // 32MB in RAM, rest to temp files
		http.Error(w, `{"error":"FILE_TOO_LARGE","message":"Fayl hajmi server qabul qilish chegarasidan oshdi"}`, http.StatusBadRequest)
		return
	}

	file, header, err := r.FormFile("file")
	if err != nil {
		http.Error(w, `{"error":"NO_FILE_PROVIDED","message":"Yuklash uchun fayl tanlanmadi"}`, http.StatusBadRequest)
		return
	}
	defer file.Close()

	var convIDPtr *string
	convID := r.FormValue("conversation_id")
	if convID != "" {
		convIDPtr = &convID
	}

	processedFile, err := h.filesService.ProcessUpload(
		r.Context(),
		userID,
		convIDPtr,
		header.Filename,
		file,
		header.Size,
		ent,
	)
	if err != nil {
		status := http.StatusBadRequest
		if errors.Is(err, files.ErrFileSizeLimit) || errors.Is(err, files.ErrFeatureDisabled) {
			status = http.StatusForbidden
		}
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(status)
		_ = json.NewEncoder(w).Encode(map[string]string{
			"error":   "UPLOAD_REJECTED",
			"message": err.Error(),
		})
		return
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusCreated)
	_ = json.NewEncoder(w).Encode(map[string]any{
		"id":              processedFile.ID,
		"file":            processedFile,
		"data":            processedFile,
		"user_id":         processedFile.UserID,
		"conversation_id": processedFile.ConversationID,
		"filename":        processedFile.Filename,
		"file_type":       processedFile.FileType,
		"mime_type":       processedFile.MimeType,
		"file_size_bytes": processedFile.FileSizeBytes,
		"sha256_hash":     processedFile.SHA256Hash,
		"chunk_count":     processedFile.ChunkCount,
		"metadata":        processedFile.Metadata,
		"download_url":    processedFile.DownloadURL,
		"created_at":      processedFile.CreatedAt,
	})
}

// GetMetadata returns file details.
func (h *FilesHandler) GetMetadata(w http.ResponseWriter, r *http.Request) {
	userID, ok := middleware.GetUserID(r.Context())
	if !ok {
		http.Error(w, `{"error":"UNAUTHORIZED"}`, http.StatusUnauthorized)
		return
	}
	fileID := chi.URLParam(r, "id")

	f, err := h.filesService.GetFile(r.Context(), userID, fileID)
	if err != nil {
		if errors.Is(err, files.ErrFileNotFound) {
			http.Error(w, `{"error":"NOT_FOUND"}`, http.StatusNotFound)
			return
		}
		http.Error(w, `{"error":"INTERNAL_ERROR"}`, http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(f)
}

// Download streams the file securely with sanitized headers.
func (h *FilesHandler) Download(w http.ResponseWriter, r *http.Request) {
	userID, ok := middleware.GetUserID(r.Context())
	if !ok {
		http.Error(w, `{"error":"UNAUTHORIZED"}`, http.StatusUnauthorized)
		return
	}
	fileID := chi.URLParam(r, "id")

	f, err := h.filesService.GetFile(r.Context(), userID, fileID)
	if err != nil {
		http.Error(w, `{"error":"NOT_FOUND"}`, http.StatusNotFound)
		return
	}

	diskFile, err := os.Open(f.StoragePath)
	if err != nil {
		http.Error(w, `{"error":"FILE_UNAVAILABLE"}`, http.StatusNotFound)
		return
	}
	defer diskFile.Close()

	w.Header().Set("Content-Type", f.MimeType)
	w.Header().Set("Content-Disposition", `attachment; filename="`+f.Filename+`"`)
	http.ServeContent(w, r, f.Filename, f.CreatedAt, diskFile)
}

// Delete removes a file.
func (h *FilesHandler) Delete(w http.ResponseWriter, r *http.Request) {
	userID, ok := middleware.GetUserID(r.Context())
	if !ok {
		http.Error(w, `{"error":"UNAUTHORIZED"}`, http.StatusUnauthorized)
		return
	}
	fileID := chi.URLParam(r, "id")

	if err := h.filesService.DeleteFile(r.Context(), userID, fileID); err != nil {
		http.Error(w, `{"error":"DELETE_FAILED"}`, http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(map[string]bool{"success": true})
}
