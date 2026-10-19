package handlers

import (
	"encoding/json"
	"errors"
	"net/http"

	"ai-chat-backend/internal/generations"
	apphttp "ai-chat-backend/internal/http"
	"ai-chat-backend/internal/middleware"
	"github.com/go-chi/chi/v5"
)

type GenerationHandler struct {
	service *generations.Service
}

func NewGenerationHandler(service *generations.Service) *GenerationHandler {
	return &GenerationHandler{service: service}
}

// StreamGeneration handles the streaming AI generation endpoint (SSE).
func (h *GenerationHandler) StreamGeneration(w http.ResponseWriter, r *http.Request) {
	userID, ok := middleware.GetUserID(r.Context())
	if !ok {
		apphttp.WriteError(w, r, http.StatusUnauthorized, "UNAUTHORIZED", "Avtorizatsiya talab qilinadi")
		return
	}

	convID := chi.URLParam(r, "conversationID")
	var req generations.GenerateRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		apphttp.WriteError(w, r, http.StatusBadRequest, "MALFORMED_JSON", "Noto'g'ri so'rov formati")
		return
	}

	if req.Message == "" {
		apphttp.WriteError(w, r, http.StatusBadRequest, "EMPTY_MESSAGE", "Xabar matni bo'sh bo'lishi mumkin emas")
		return
	}

	h.service.ExecuteStream(w, r, userID, convID, req.Message, req.ModelID, req.FileIDs)
}

// CancelGeneration triggers cancellation for an in-flight generation.
func (h *GenerationHandler) CancelGeneration(w http.ResponseWriter, r *http.Request) {
	userID, ok := middleware.GetUserID(r.Context())
	if !ok {
		apphttp.WriteError(w, r, http.StatusUnauthorized, "UNAUTHORIZED", "Avtorizatsiya talab qilinadi")
		return
	}

	genID := chi.URLParam(r, "generationID")
	err := h.service.CancelGeneration(r.Context(), userID, genID)
	if err != nil {
		if errors.Is(err, generations.ErrGenerationNotFound) {
			apphttp.WriteError(w, r, http.StatusNotFound, "NOT_FOUND", "Generatsiya topilmadi")
			return
		}
		if errors.Is(err, generations.ErrAlreadyFinished) {
			apphttp.WriteError(w, r, http.StatusConflict, "ALREADY_FINISHED", "Generatsiya allaqachon yakunlangan")
			return
		}
		apphttp.WriteError(w, r, http.StatusInternalServerError, "INTERNAL_ERROR", "Generatsiyani bekor qilishda xatolik yuz berdi")
		return
	}

	apphttp.WriteJSON(w, http.StatusOK, map[string]string{
		"message":       "Generatsiya muvaffaqiyatli bekor qilindi",
		"generation_id": genID,
	})
}
