package handlers

import (
	"encoding/json"
	"errors"
	"net/http"

	"ai-chat-backend/internal/auth"
	apphttp "ai-chat-backend/internal/http"
	"ai-chat-backend/internal/middleware"
)

type AuthHandler struct {
	authService *auth.Service
}

func NewAuthHandler(authService *auth.Service) *AuthHandler {
	return &AuthHandler{authService: authService}
}

func (h *AuthHandler) Register(w http.ResponseWriter, r *http.Request) {
	var req auth.RegisterRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		apphttp.WriteError(w, r, http.StatusBadRequest, "MALFORMED_JSON", "So'rov formati noto'g'ri")
		return
	}

	userAgent := r.UserAgent()
	ip := r.RemoteAddr

	resp, err := h.authService.Register(r.Context(), req, userAgent, ip)
	if err != nil {
		if errors.Is(err, auth.ErrEmailExists) {
			apphttp.WriteError(w, r, http.StatusConflict, "EMAIL_EXISTS", err.Error())
			return
		}
		if errors.Is(err, auth.ErrValidation) {
			apphttp.WriteError(w, r, http.StatusUnprocessableEntity, "VALIDATION_ERROR", err.Error())
			return
		}
		apphttp.WriteError(w, r, http.StatusInternalServerError, "INTERNAL_ERROR", "Ro'yxatdan o'tishda xatolik yuz berdi")
		return
	}

	apphttp.WriteJSON(w, http.StatusCreated, resp)
}

func (h *AuthHandler) Login(w http.ResponseWriter, r *http.Request) {
	var req auth.LoginRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		apphttp.WriteError(w, r, http.StatusBadRequest, "MALFORMED_JSON", "So'rov formati noto'g'ri")
		return
	}

	userAgent := r.UserAgent()
	ip := r.RemoteAddr

	resp, err := h.authService.Login(r.Context(), req, userAgent, ip)
	if err != nil {
		if errors.Is(err, auth.ErrInvalidCredentials) {
			apphttp.WriteError(w, r, http.StatusUnauthorized, "INVALID_CREDENTIALS", "Email yoki parol noto'g'ri")
			return
		}
		apphttp.WriteError(w, r, http.StatusInternalServerError, "INTERNAL_ERROR", "Tizimga kirishda xatolik yuz berdi")
		return
	}

	apphttp.WriteJSON(w, http.StatusOK, resp)
}

func (h *AuthHandler) Refresh(w http.ResponseWriter, r *http.Request) {
	var req auth.RefreshRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		apphttp.WriteError(w, r, http.StatusBadRequest, "MALFORMED_JSON", "So'rov formati noto'g'ri")
		return
	}

	userAgent := r.UserAgent()
	ip := r.RemoteAddr

	resp, err := h.authService.RefreshToken(r.Context(), req.RefreshToken, userAgent, ip)
	if err != nil {
		apphttp.WriteError(w, r, http.StatusUnauthorized, "INVALID_TOKEN", "Sessiya muddati tugagan yoki token noto'g'ri")
		return
	}

	apphttp.WriteJSON(w, http.StatusOK, resp)
}

func (h *AuthHandler) Logout(w http.ResponseWriter, r *http.Request) {
	var req auth.RefreshRequest
	_ = json.NewDecoder(r.Body).Decode(&req)

	if req.RefreshToken != "" {
		_ = h.authService.Logout(r.Context(), req.RefreshToken)
	}

	apphttp.WriteJSON(w, http.StatusOK, map[string]string{"message": "Muvaffaqiyatli chiqildi"})
}

func (h *AuthHandler) Me(w http.ResponseWriter, r *http.Request) {
	userID, ok := middleware.GetUserID(r.Context())
	if !ok {
		apphttp.WriteError(w, r, http.StatusUnauthorized, "UNAUTHORIZED", "Avtorizatsiyadan o'tilmagan")
		return
	}

	user, err := h.authService.GetUserByID(r.Context(), userID)
	if err != nil {
		apphttp.WriteError(w, r, http.StatusNotFound, "USER_NOT_FOUND", "Foydalanuvchi topilmadi")
		return
	}

	apphttp.WriteJSON(w, http.StatusOK, auth.UserPublic{
		ID:        user.ID,
		Email:     user.Email,
		FullName:  user.FullName,
		CreatedAt: user.CreatedAt,
	})
}

// DeleteAccount handles Google Play compliant account deletion.
func (h *AuthHandler) DeleteAccount(w http.ResponseWriter, r *http.Request) {
	userID, ok := middleware.GetUserID(r.Context())
	if !ok {
		apphttp.WriteError(w, r, http.StatusUnauthorized, "UNAUTHORIZED", "Avtorizatsiyadan o'tilmagan")
		return
	}

	if err := h.authService.DeleteUser(r.Context(), userID); err != nil {
		apphttp.WriteError(w, r, http.StatusInternalServerError, "DELETE_FAILED", "Hisobni o'chirishda xatolik yuz berdi")
		return
	}

	apphttp.WriteJSON(w, http.StatusOK, map[string]string{
		"message": "Hisob va unga tegishli barcha ma'lumotlar muvaffaqiyatli o'chirildi",
	})
}
