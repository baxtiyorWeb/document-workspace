package handlers

import (
	"encoding/json"
	"errors"
	"net/http"
	"strconv"

	"ai-chat-backend/internal/conversations"
	apphttp "ai-chat-backend/internal/http"
	"ai-chat-backend/internal/middleware"
	"github.com/go-chi/chi/v5"
)

type ConversationHandler struct {
	service *conversations.Service
}

func NewConversationHandler(service *conversations.Service) *ConversationHandler {
	return &ConversationHandler{service: service}
}

func (h *ConversationHandler) List(w http.ResponseWriter, r *http.Request) {
	userID, ok := middleware.GetUserID(r.Context())
	if !ok {
		apphttp.WriteError(w, r, http.StatusUnauthorized, "UNAUTHORIZED", "Avtorizatsiya talab qilinadi")
		return
	}

	limit := 30
	offset := 0
	if l := r.URL.Query().Get("limit"); l != "" {
		if val, err := strconv.Atoi(l); err == nil && val > 0 {
			limit = val
		}
	}
	if o := r.URL.Query().Get("offset"); o != "" {
		if val, err := strconv.Atoi(o); err == nil && val >= 0 {
			offset = val
		}
	}

	items, err := h.service.List(r.Context(), userID, limit, offset)
	if err != nil {
		apphttp.WriteError(w, r, http.StatusInternalServerError, "INTERNAL_ERROR", "Suhbatlarni yuklashda xatolik yuz berdi")
		return
	}

	apphttp.WriteJSON(w, http.StatusOK, items)
}

func (h *ConversationHandler) Create(w http.ResponseWriter, r *http.Request) {
	userID, ok := middleware.GetUserID(r.Context())
	if !ok {
		apphttp.WriteError(w, r, http.StatusUnauthorized, "UNAUTHORIZED", "Avtorizatsiya talab qilinadi")
		return
	}

	var req conversations.CreateConversationRequest
	_ = json.NewDecoder(r.Body).Decode(&req)

	item, err := h.service.Create(r.Context(), userID, req)
	if err != nil {
		apphttp.WriteError(w, r, http.StatusInternalServerError, "INTERNAL_ERROR", "Suhbat yaratishda xatolik yuz berdi")
		return
	}

	apphttp.WriteJSON(w, http.StatusCreated, item)
}

func (h *ConversationHandler) GetByID(w http.ResponseWriter, r *http.Request) {
	userID, ok := middleware.GetUserID(r.Context())
	if !ok {
		apphttp.WriteError(w, r, http.StatusUnauthorized, "UNAUTHORIZED", "Avtorizatsiya talab qilinadi")
		return
	}

	convID := chi.URLParam(r, "conversationID")
	if convID == "" {
		apphttp.WriteError(w, r, http.StatusBadRequest, "BAD_REQUEST", "Suhbat ID si ko'rsatilmadi")
		return
	}

	item, err := h.service.GetByID(r.Context(), userID, convID)
	if err != nil {
		if errors.Is(err, conversations.ErrNotFound) {
			apphttp.WriteError(w, r, http.StatusNotFound, "NOT_FOUND", "Suhbat topilmadi")
			return
		}
		apphttp.WriteError(w, r, http.StatusInternalServerError, "INTERNAL_ERROR", "Xatolik yuz berdi")
		return
	}

	apphttp.WriteJSON(w, http.StatusOK, item)
}

func (h *ConversationHandler) Patch(w http.ResponseWriter, r *http.Request) {
	userID, ok := middleware.GetUserID(r.Context())
	if !ok {
		apphttp.WriteError(w, r, http.StatusUnauthorized, "UNAUTHORIZED", "Avtorizatsiya talab qilinadi")
		return
	}

	convID := chi.URLParam(r, "conversationID")
	var req conversations.UpdateConversationRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		apphttp.WriteError(w, r, http.StatusBadRequest, "MALFORMED_JSON", "Noto'g'ri so'rov formati")
		return
	}

	item, err := h.service.UpdateTitle(r.Context(), userID, convID, req.Title)
	if err != nil {
		if errors.Is(err, conversations.ErrNotFound) {
			apphttp.WriteError(w, r, http.StatusNotFound, "NOT_FOUND", "Suhbat topilmadi")
			return
		}
		if errors.Is(err, conversations.ErrValidation) {
			apphttp.WriteError(w, r, http.StatusUnprocessableEntity, "VALIDATION_ERROR", err.Error())
			return
		}
		apphttp.WriteError(w, r, http.StatusInternalServerError, "INTERNAL_ERROR", "Suhbat nomini o'zgartirishda xatolik yuz berdi")
		return
	}

	apphttp.WriteJSON(w, http.StatusOK, item)
}

func (h *ConversationHandler) Delete(w http.ResponseWriter, r *http.Request) {
	userID, ok := middleware.GetUserID(r.Context())
	if !ok {
		apphttp.WriteError(w, r, http.StatusUnauthorized, "UNAUTHORIZED", "Avtorizatsiya talab qilinadi")
		return
	}

	convID := chi.URLParam(r, "conversationID")
	err := h.service.Delete(r.Context(), userID, convID)
	if err != nil {
		if errors.Is(err, conversations.ErrNotFound) {
			apphttp.WriteError(w, r, http.StatusNotFound, "NOT_FOUND", "Suhbat topilmadi")
			return
		}
		apphttp.WriteError(w, r, http.StatusInternalServerError, "INTERNAL_ERROR", "Suhbatni o'chirishda xatolik yuz berdi")
		return
	}

	apphttp.WriteJSON(w, http.StatusOK, map[string]string{"message": "Suhbat o'chirildi"})
}
