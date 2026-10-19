package handlers

import (
	"encoding/json"
	"errors"
	"net/http"
	"strconv"

	apphttp "ai-chat-backend/internal/http"
	"ai-chat-backend/internal/messages"
	"ai-chat-backend/internal/middleware"
	"github.com/go-chi/chi/v5"
)

type MessageHandler struct {
	service *messages.Service
}

func NewMessageHandler(service *messages.Service) *MessageHandler {
	return &MessageHandler{service: service}
}

func (h *MessageHandler) List(w http.ResponseWriter, r *http.Request) {
	userID, ok := middleware.GetUserID(r.Context())
	if !ok {
		apphttp.WriteError(w, r, http.StatusUnauthorized, "UNAUTHORIZED", "Avtorizatsiya talab qilinadi")
		return
	}

	convID := chi.URLParam(r, "conversationID")
	limit := 50
	if l := r.URL.Query().Get("limit"); l != "" {
		if val, err := strconv.Atoi(l); err == nil && val > 0 {
			limit = val
		}
	}

	msgs, err := h.service.ListMessages(r.Context(), userID, convID, limit)
	if err != nil {
		if errors.Is(err, messages.ErrConversationNotFound) {
			apphttp.WriteError(w, r, http.StatusNotFound, "NOT_FOUND", "Suhbat topilmadi")
			return
		}
		apphttp.WriteError(w, r, http.StatusInternalServerError, "INTERNAL_ERROR", "Xabarlarni yuklashda xatolik yuz berdi")
		return
	}

	apphttp.WriteJSON(w, http.StatusOK, msgs)
}

func (h *MessageHandler) Create(w http.ResponseWriter, r *http.Request) {
	userID, ok := middleware.GetUserID(r.Context())
	if !ok {
		apphttp.WriteError(w, r, http.StatusUnauthorized, "UNAUTHORIZED", "Avtorizatsiya talab qilinadi")
		return
	}

	convID := chi.URLParam(r, "conversationID")
	var req messages.CreateMessageRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		apphttp.WriteError(w, r, http.StatusBadRequest, "MALFORMED_JSON", "Noto'g'ri so'rov formati")
		return
	}

	msg, err := h.service.CreateUserMessage(r.Context(), userID, convID, req.Content)
	if err != nil {
		if errors.Is(err, messages.ErrConversationNotFound) {
			apphttp.WriteError(w, r, http.StatusNotFound, "NOT_FOUND", "Suhbat topilmadi")
			return
		}
		if errors.Is(err, messages.ErrEmptyContent) {
			apphttp.WriteError(w, r, http.StatusBadRequest, "EMPTY_CONTENT", err.Error())
			return
		}
		apphttp.WriteError(w, r, http.StatusInternalServerError, "INTERNAL_ERROR", "Xabarni saqlashda xatolik yuz berdi")
		return
	}

	apphttp.WriteJSON(w, http.StatusCreated, msg)
}

type ReportMessageRequest struct {
	Reason  string `json:"reason"`
	Comment string `json:"comment"`
}

// Report handles user flagging/reporting of inappropriate or illegal AI responses.
func (h *MessageHandler) Report(w http.ResponseWriter, r *http.Request) {
	userID, ok := middleware.GetUserID(r.Context())
	if !ok {
		apphttp.WriteError(w, r, http.StatusUnauthorized, "UNAUTHORIZED", "Avtorizatsiya talab qilinadi")
		return
	}

	msgID := chi.URLParam(r, "messageID")
	if msgID == "" {
		apphttp.WriteError(w, r, http.StatusBadRequest, "MISSING_MESSAGE_ID", "Xabar identifikatori kiritilmadi")
		return
	}

	var req ReportMessageRequest
	_ = json.NewDecoder(r.Body).Decode(&req)
	if req.Reason == "" {
		req.Reason = "inappropriate_content"
	}

	if err := h.service.ReportMessage(r.Context(), userID, msgID, req.Reason, req.Comment); err != nil {
		apphttp.WriteError(w, r, http.StatusInternalServerError, "INTERNAL_ERROR", "Shikoyatni saqlashda xatolik yuz berdi")
		return
	}

	apphttp.WriteJSON(w, http.StatusOK, map[string]string{
		"message": "Shikoyat qabul qilindi. Moderatsiya ko'rib chiqadi.",
	})
}
