package generations

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"strings"
	"sync"
	"time"

	"ai-chat-backend/internal/ai"
	"ai-chat-backend/internal/files"
	"ai-chat-backend/internal/gateway"
	"ai-chat-backend/internal/messages"
	"ai-chat-backend/internal/plans"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

var (
	ErrGenerationNotFound = errors.New("GENERATION_NOT_FOUND: Generatsiya topilmadi")
	ErrAlreadyFinished    = errors.New("ALREADY_FINISHED: Generatsiya allaqachon yakunlangan")
)

// Service coordinates generation lifecycle, streaming, authorization, and cancellation.
type Service struct {
	pool         *pgxpool.Pool
	baseProvider *ai.OpenAICompatibleProvider
	msgService   *messages.Service
	plansService *plans.Service
	filesService *files.Service
	router       *gateway.Router
	quotaService *gateway.QuotaService

	mu        sync.RWMutex
	cancels   map[string]context.CancelFunc
	completed map[string]time.Time
}

// NewService creates a new generations service with AI Gateway, files, and Quota enforcement.
func NewService(
	pool *pgxpool.Pool,
	baseProvider *ai.OpenAICompatibleProvider,
	msgService *messages.Service,
	plansService *plans.Service,
	filesService *files.Service,
	router *gateway.Router,
	quotaService *gateway.QuotaService,
) *Service {
	return &Service{
		pool:         pool,
		baseProvider: baseProvider,
		msgService:   msgService,
		plansService: plansService,
		filesService: filesService,
		router:       router,
		quotaService: quotaService,
		cancels:      make(map[string]context.CancelFunc),
		completed:    make(map[string]time.Time),
	}
}

func (s *Service) registerCancel(genID string, cancel context.CancelFunc) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.cancels[genID] = cancel
}

func (s *Service) unregisterCancel(genID string) {
	s.mu.Lock()
	defer s.mu.Unlock()
	delete(s.cancels, genID)
	now := time.Now()
	s.completed[genID] = now
	// Bounded cleanup: prevent unbounded memory leak by pruning old entries
	if len(s.completed) > 500 {
		cutoff := now.Add(-10 * time.Minute)
		for id, t := range s.completed {
			if t.Before(cutoff) || len(s.completed) > 400 {
				delete(s.completed, id)
			}
		}
	}
}

// CancelGeneration triggers cancellation for an active generation.
func (s *Service) CancelGeneration(ctx context.Context, userID, genID string) error {
	s.mu.RLock()
	cancel, found := s.cancels[genID]
	_, wasCompleted := s.completed[genID]
	s.mu.RUnlock()

	if s.pool == nil {
		if found && cancel != nil {
			cancel()
			return nil
		}
		if wasCompleted {
			return ErrAlreadyFinished
		}
		return ErrGenerationNotFound
	}

	var currentStatus string
	err := s.pool.QueryRow(ctx, `
		SELECT status FROM generations WHERE id = $1 AND user_id = $2
	`, genID, userID).Scan(&currentStatus)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return ErrGenerationNotFound
		}
		return fmt.Errorf("failed to check generation: %w", err)
	}

	if currentStatus != "running" && currentStatus != "pending" {
		return ErrAlreadyFinished
	}

	if found && cancel != nil {
		cancel()
	}

	_, err = s.pool.Exec(ctx, `
		UPDATE generations
		SET status = 'cancelled', cancelled_at = CURRENT_TIMESTAMP
		WHERE id = $1 AND user_id = $2
	`, genID, userID)
	return err
}

// ExecuteStream orchestrates the generation lifecycle with strict plan enforcement, quota reservation, and real SSE output.
func (s *Service) ExecuteStream(w http.ResponseWriter, r *http.Request, userID, convID, userMessageContent, requestedModelID string, fileIDs []string) {
	flusher, ok := w.(http.Flusher)
	if !ok {
		http.Error(w, "Streaming unsupported", http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "text/event-stream; charset=utf-8")
	w.Header().Set("Cache-Control", "no-cache, no-transform")
	w.Header().Set("Connection", "keep-alive")
	w.Header().Set("X-Accel-Buffering", "no")

	// 1. Authoritative Entitlement Resolution
	ent, err := s.plansService.ResolveUserEntitlement(r.Context(), userID)
	if err != nil {
		writeSSE(w, flusher, "generation.failed", map[string]string{
			"code":    "ENTITLEMENT_RESOLUTION_FAILED",
			"message": "Foydalanuvchi huquqlarini tekshirishda xatolik yuz berdi",
		})
		return
	}

	// 1a. Emit initial pipeline status: Validating
	writeSSE(w, flusher, "pipeline.status", map[string]string{
		"stage":       "validating",
		"status_text": "Fayl tekshirilmoqda",
	})

	// 1a. Validate file count limit (maximum 5 files per message)
	if len(fileIDs) > 5 {
		writeSSE(w, flusher, "generation.failed", map[string]string{
			"code":    "FILE_COUNT_LIMIT_EXCEEDED",
			"message": "Bitta xabarga ko'pi bilan 5 ta fayl biriktirish mumkin",
		})
		return
	}

	// 1b. Process attached files (Image inspection & Document RAG retrieval)
	var hasImages bool
	var docContext string
	var citations []files.RetrievalResult

	if len(fileIDs) > 0 && s.filesService != nil {
		writeSSE(w, flusher, "pipeline.status", map[string]string{
			"stage":       "opening",
			"status_text": "Hujjat ochilmoqda",
		})

		var validUserFileIDs []string
		for _, fID := range fileIDs {
			f, err := s.filesService.GetFile(r.Context(), userID, fID)
			if err == nil && f != nil {
				validUserFileIDs = append(validUserFileIDs, fID)
				if f.FileType == files.FileTypeImage {
					hasImages = true
				}
			}
		}

		writeSSE(w, flusher, "pipeline.status", map[string]string{
			"stage":       "extracting",
			"status_text": "Sahifalar va jadvallar tahlil qilinmoqda",
		})

		writeSSE(w, flusher, "pipeline.status", map[string]string{
			"stage":       "retrieving",
			"status_text": "Kerakli ma'lumotlar qidirilmoqda",
		})

		if len(validUserFileIDs) > 0 {
			ctxStr, cList, err := s.filesService.RetrieveRelevantContext(r.Context(), userID, validUserFileIDs, userMessageContent)
			if err == nil && ctxStr != "" {
				docContext = ctxStr
				citations = cList
			}
		}
	}

	// 2. Gateway Router Model Selection & Plan Authorization (multimodal auto-routing)
	targetModel, err := s.router.RouteMultimodal(r.Context(), requestedModelID, ent, hasImages)
	if err != nil {
		code := "MODEL_ACCESS_DENIED"
		if errors.Is(err, gateway.ErrPlanNotAuthorized) {
			code = "MODEL_NOT_PERMITTED_ON_PLAN"
		}
		writeSSE(w, flusher, "generation.failed", map[string]string{
			"code":    code,
			"message": err.Error(),
		})
		return
	}

	// 3. Pre-reserve Quota & check tiered hourly/daily/weekly & concurrency limits atomically
	ledgerID, err := s.quotaService.ReserveQuota(
		r.Context(),
		userID,
		convID,
		"", // will update with genID once created
		targetModel.ID,
		ent.PlanID,
		gateway.QuotaLimits{
			HourlyLimit: ent.HourlyRequestsLimit,
			DailyLimit:  ent.DailyRequestsLimit,
			WeeklyLimit: ent.WeeklyRequestsLimit,
			MaxStreams:  ent.MaxActiveStreams,
		},
	)
	if err != nil {
		var qErr *gateway.QuotaError
		if errors.As(err, &qErr) {
			writeSSE(w, flusher, "generation.failed", map[string]any{
				"code":      qErr.Code,
				"window":    qErr.Window,
				"limit":     qErr.Limit,
				"used":      qErr.Used,
				"resets_at": qErr.ResetsAt.UTC().Format("2006-01-02T15:04:05Z07:00"),
				"message":   qErr.Message,
			})
			return
		}
		writeSSE(w, flusher, "generation.failed", map[string]string{
			"code":    "QUOTA_EXCEEDED",
			"message": err.Error(),
		})
		return
	}

	// 4. Persist user message with any attached file IDs
	userMsg, err := s.msgService.CreateUserMessageWithFiles(r.Context(), userID, convID, userMessageContent, fileIDs)
	if err != nil {
		_ = s.quotaService.ReleaseReservation(context.Background(), ledgerID, "failed")
		writeSSE(w, flusher, "generation.failed", map[string]string{
			"code":    "USER_MESSAGE_FAILED",
			"message": err.Error(),
		})
		return
	}

	// 5. Dynamic Token Budgeting & History Pruning (Prevents context/exceeded errors)
	outputTokens := targetModel.MaxOutputTokens
	if outputTokens <= 0 {
		outputTokens = 2048
	}
	if ent.MaxOutputTokens > 0 && outputTokens > ent.MaxOutputTokens {
		outputTokens = ent.MaxOutputTokens
	}

	maxContextTokens := targetModel.MaxContextTokens
	if maxContextTokens <= 0 {
		maxContextTokens = 8192
	}
	maxInputTokens := ent.MaxInputTokens
	if maxInputTokens <= 0 {
		maxInputTokens = 4000
	}

	availableInputBudget := maxContextTokens - outputTokens - 300
	if availableInputBudget > maxInputTokens && maxInputTokens > 0 {
		availableInputBudget = maxInputTokens
	}
	if availableInputBudget < 600 {
		availableInputBudget = 600
	}

	// RAG budget: up to 55% of available input budget
	ragBudgetTokens := availableInputBudget * 55 / 100
	if docContext != "" && (len(docContext)/4) > ragBudgetTokens {
		charLimit := ragBudgetTokens * 4
		if len(docContext) > charLimit {
			docContext = docContext[:charLimit] + "\n\n*(Hujjatning qolgan qismi kontekst chegarasiga moslab qisqartirildi)*"
		}
	}

	// Load conversation history for LLM context
	histList, err := s.msgService.ListMessages(r.Context(), userID, convID, 20)
	if err != nil {
		_ = s.quotaService.ReleaseReservation(context.Background(), ledgerID, "failed")
		writeSSE(w, flusher, "generation.failed", map[string]string{
			"code":    "HISTORY_FAILED",
			"message": err.Error(),
		})
		return
	}

	userMsgEstimatedTokens := len(userMessageContent)/4 + len(docContext)/4 + 50
	remainingForHistory := availableInputBudget - userMsgEstimatedTokens - 150
	if remainingForHistory < 200 {
		remainingForHistory = 200
	}

	var historyMessages []ai.ChatMessage
	historyTokensUsed := 0

	for i := len(histList) - 1; i >= 0; i-- {
		m := histList[i]
		if m.ID == userMsg.ID {
			continue
		}
		msgTokens := len(m.Content)/4 + 8
		if historyTokensUsed+msgTokens > remainingForHistory {
			break
		}
		historyTokensUsed += msgTokens
		historyMessages = append([]ai.ChatMessage{{
			Role:    m.Role,
			Content: m.Content,
		}}, historyMessages...)
	}

	aiMessages := make([]ai.ChatMessage, 0, len(historyMessages)+1)
	aiMessages = append(aiMessages, historyMessages...)

	currentUserContent := userMsg.Content
	if docContext != "" {
		currentUserContent = fmt.Sprintf("%s\n\n[Hujjatlar konteksti:\n%s\n\nKO'RSATMA: Iltimos, faqat yuqoridagi hujjat bo'limlaridagi faktlarga tayanib javob bering va manba sahifa raqamlarini (masalan, [Sahifa N]) ko'rsating. Agar hujjatda so'ralgan ma'lumot bo'lmasa, uni to'qimasdan ochiq ayting.]", userMsg.Content, docContext)
	}
	aiMessages = append(aiMessages, ai.ChatMessage{
		Role:    "user",
		Content: currentUserContent,
	})

	// 6. Create generation record in DB
	var genID string
	if s.pool != nil {
		err = s.pool.QueryRow(r.Context(), `
			INSERT INTO generations (conversation_id, user_id, status, provider, model)
			VALUES ($1, $2, 'running', $3, $4)
			RETURNING id
		`, convID, userID, targetModel.Provider, targetModel.ID).Scan(&genID)
		if err != nil {
			_ = s.quotaService.ReleaseReservation(context.Background(), ledgerID, "failed")
			writeSSE(w, flusher, "generation.failed", map[string]string{
				"code":    "GENERATION_INIT_FAILED",
				"message": err.Error(),
			})
			return
		}

		// Link generation_id in usage_ledger
		_, _ = s.pool.Exec(context.Background(), `UPDATE usage_ledger SET generation_id = $1 WHERE id = $2`, genID, ledgerID)
	} else {
		genID = fmt.Sprintf("gen-%d", time.Now().UnixNano())
	}

	// 7. Setup cancellable context
	streamCtx, cancel := context.WithCancel(r.Context())
	defer cancel()
	s.registerCancel(genID, cancel)
	defer s.unregisterCancel(genID)

	// Final status event before tokens
	writeSSE(w, flusher, "pipeline.status", map[string]string{
		"stage":       "generating",
		"status_text": "Javob tayyorlanmoqda",
	})

	// Send generation.started event
	writeSSE(w, flusher, "generation.started", map[string]any{
		"generation_id":   genID,
		"conversation_id": convID,
		"user_message_id": userMsg.ID,
		"model_id":        targetModel.ID,
		"model_name":      targetModel.Name,
	})

	// 8. Invoke Provider with Target Model Deployment
	activeProvider := s.baseProvider.WithModel(targetModel.ProviderModelID, outputTokens)
	chunkCh, errCh := activeProvider.StreamChat(streamCtx, aiMessages)

	var sb strings.Builder
	var streamErr error
	isCancelled := false

	for {
		select {
		case <-streamCtx.Done():
			isCancelled = true
			goto STREAM_END

		case err, ok := <-errCh:
			if ok && err != nil {
				if errors.Is(err, context.Canceled) || errors.Is(streamCtx.Err(), context.Canceled) {
					isCancelled = true
				} else {
					streamErr = err
				}
				goto STREAM_END
			}

		case chunk, ok := <-chunkCh:
			if !ok {
				goto STREAM_END
			}
			if chunk.IsDone {
				goto STREAM_END
			}
			if chunk.DeltaContent != "" {
				sb.WriteString(chunk.DeltaContent)
				writeSSE(w, flusher, "message.delta", map[string]string{
					"generation_id": genID,
					"text":          chunk.DeltaContent,
				})
			}
		}
	}

STREAM_END:
	fullAssistantContent := sb.String()

	if isCancelled {
		var asstMsgID *string
		if fullAssistantContent != "" {
			asstMsg, _ := s.msgService.CreateAssistantMessage(context.Background(), userID, convID, fullAssistantContent, "cancelled")
			if asstMsg != nil {
				asstMsgID = &asstMsg.ID
			}
		}

		if s.pool != nil {
			_, _ = s.pool.Exec(context.Background(), `
				UPDATE generations
				SET status = 'cancelled', assistant_message_id = $1, cancelled_at = CURRENT_TIMESTAMP
				WHERE id = $2
			`, asstMsgID, genID)
		}

		_ = s.quotaService.ReleaseReservation(context.Background(), ledgerID, "cancelled")

		writeSSE(w, flusher, "generation.cancelled", map[string]any{
			"generation_id": genID,
			"partial_text":  fullAssistantContent,
		})
		return
	}

	if streamErr != nil {
		errCode := "UPSTREAM_ERROR"
		errMsg := "AI provayderi bilan ulanishda vaqtincha xatolik yuz berdi. Iltimos, qayta urining."
		errStr := strings.ToLower(streamErr.Error())

		if errors.Is(streamErr, ai.ErrNotConfigured) {
			errCode = "AI_PROVIDER_NOT_CONFIGURED"
			errMsg = "AI provayder kaliti sozlanmagan"
		} else if strings.Contains(errStr, "context") || strings.Contains(errStr, "token") || strings.Contains(errStr, "too large") {
			errCode = "CONTEXT_LENGTH_EXCEEDED"
			errMsg = "Savol yoki hujjat hajmi model chegarasidan oshdi. Iltimos, yangi suhbat oching yoki qisqaroq qism bo'yicha savol bering."
		} else if strings.Contains(errStr, "429") || strings.Contains(errStr, "rate limit") {
			errCode = "RATE_LIMIT_EXCEEDED"
			errMsg = "AI provayderi tezlik chekloviga (Rate Limit) uchradi. Iltimos, bir necha soniyadan so'ng qayta urining."
		}

		if s.pool != nil {
			_, _ = s.pool.Exec(context.Background(), `
				UPDATE generations
				SET status = 'failed', error_code = $1, error_message = $2, completed_at = CURRENT_TIMESTAMP
				WHERE id = $3
			`, errCode, errMsg, genID)
		}

		_ = s.quotaService.ReleaseReservation(context.Background(), ledgerID, "failed")

		writeSSE(w, flusher, "generation.failed", map[string]string{
			"generation_id": genID,
			"code":          errCode,
			"message":       errMsg,
		})
		return
	}

	// 9. Persist completed assistant message
	asstMsg, err := s.msgService.CreateAssistantMessage(context.Background(), userID, convID, fullAssistantContent, "completed")
	if err != nil {
		_ = s.quotaService.ReleaseReservation(context.Background(), ledgerID, "failed")
		writeSSE(w, flusher, "generation.failed", map[string]string{
			"generation_id": genID,
			"code":          "PERSISTENCE_FAILED",
			"message":       "Javobni saqlashda xatolik yuz berdi",
		})
		return
	}

	// 10. Finalize generation record in DB
	if s.pool != nil {
		_, _ = s.pool.Exec(context.Background(), `
			UPDATE generations
			SET status = 'completed', assistant_message_id = $1, completed_at = CURRENT_TIMESTAMP
			WHERE id = $2
		`, asstMsg.ID, genID)
	}

	// Settle usage and accounting in usage_ledger
	promptTokensEst := len(userMessageContent)/4 + 20
	compTokensEst := len(fullAssistantContent)/4 + 1
	costMultiplier := 1.0
	if hasImages {
		costMultiplier = 1.5
	}
	_ = s.quotaService.SettleUsage(
		context.Background(),
		ledgerID,
		promptTokensEst,
		compTokensEst,
		targetModel.InputPricePerMillionUSD,
		targetModel.OutputPricePerMillionUSD,
		costMultiplier,
	)

	respData := map[string]any{
		"generation_id": genID,
		"message_id":    asstMsg.ID,
		"content":       fullAssistantContent,
		"model_id":      targetModel.ID,
	}
	if len(citations) > 0 {
		respData["citations"] = citations
	}
	writeSSE(w, flusher, "generation.completed", respData)
}

func writeSSE(w http.ResponseWriter, flusher http.Flusher, event string, data any) {
	bytesData, err := json.Marshal(data)
	if err != nil {
		return
	}
	_, _ = fmt.Fprintf(w, "event: %s\ndata: %s\n\n", event, string(bytesData))
	flusher.Flush()
}
