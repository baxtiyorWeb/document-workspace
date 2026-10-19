package ai

import (
	"bufio"
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"strings"
	"time"
)

var (
	ErrNotConfigured = errors.New("AI_PROVIDER_NOT_CONFIGURED: AI_API_KEY sozlanmagan. Iltimos, backend/.env faylida AI_API_KEY ni ko'rsating.")
	ErrUpstreamError = errors.New("AI_UPSTREAM_ERROR: AI provayderidan xatolik qaytdi")
)

// ChatMessage represents a prompt message in the chat sequence.
type ChatMessage struct {
	Role    string `json:"role"`
	Content string `json:"content"`
}

// StreamChunk delivers incremental delta tokens.
type StreamChunk struct {
	DeltaContent string
	IsDone       bool
	PromptTokens int
	CompTokens   int
}

// Provider represents the pluggable LLM interface.
type Provider interface {
	StreamChat(ctx context.Context, messages []ChatMessage) (<-chan StreamChunk, <-chan error)
}

// OpenAICompatibleProvider handles OpenAI, Groq, OpenRouter, DeepSeek, Ollama, etc.
type OpenAICompatibleProvider struct {
	baseURL      string
	apiKey       string
	model        string
	systemPrompt string
	maxTokens    int
	temperature  float64
	client       *http.Client
}

// NewOpenAICompatibleProvider creates a new provider instance.
func NewOpenAICompatibleProvider(baseURL, apiKey, model, systemPrompt string, maxTokens int, temperature float64) *OpenAICompatibleProvider {
	trimmedBase := strings.TrimRight(baseURL, "/")
	return &OpenAICompatibleProvider{
		baseURL:      trimmedBase,
		apiKey:       strings.TrimSpace(apiKey),
		model:        model,
		systemPrompt: systemPrompt,
		maxTokens:    maxTokens,
		temperature:  temperature,
		client: &http.Client{
			Timeout: 120 * time.Second,
		},
	}
}

// WithModel returns a copy of the provider targeting a specific model and token limit.
func (p *OpenAICompatibleProvider) WithModel(model string, maxTokens int) *OpenAICompatibleProvider {
	tokens := maxTokens
	if tokens <= 0 {
		tokens = p.maxTokens
	}
	return &OpenAICompatibleProvider{
		baseURL:      p.baseURL,
		apiKey:       p.apiKey,
		model:        model,
		systemPrompt: p.systemPrompt,
		maxTokens:    tokens,
		temperature:  p.temperature,
		client:       p.client,
	}
}

type openAIChatRequest struct {
	Model       string        `json:"model"`
	Messages    []ChatMessage `json:"messages"`
	Stream      bool          `json:"stream"`
	MaxTokens   int           `json:"max_tokens,omitempty"`
	Temperature float64       `json:"temperature,omitempty"`
}

type openAIStreamChoice struct {
	Delta struct {
		Content   string `json:"content"`
		Reasoning string `json:"reasoning,omitempty"`
	} `json:"delta"`
	FinishReason *string `json:"finish_reason"`
}

type openAIStreamResponse struct {
	Choices []openAIStreamChoice `json:"choices"`
	Usage   *struct {
		PromptTokens     int `json:"prompt_tokens"`
		CompletionTokens int `json:"completion_tokens"`
	} `json:"usage,omitempty"`
}

// StreamChat streams completion chunks through channels.
func (p *OpenAICompatibleProvider) StreamChat(ctx context.Context, messages []ChatMessage) (<-chan StreamChunk, <-chan error) {
	outCh := make(chan StreamChunk, 20)
	errCh := make(chan error, 1)

	if p.apiKey == "" {
		errCh <- ErrNotConfigured
		close(outCh)
		close(errCh)
		return outCh, errCh
	}

	allMessages := make([]ChatMessage, 0, len(messages)+1)
	if p.systemPrompt != "" {
		allMessages = append(allMessages, ChatMessage{
			Role:    "system",
			Content: p.systemPrompt,
		})
	}
	allMessages = append(allMessages, messages...)

	reqBody := openAIChatRequest{
		Model:       p.model,
		Messages:    allMessages,
		Stream:      true,
		MaxTokens:   p.maxTokens,
		Temperature: p.temperature,
	}

	jsonBytes, err := json.Marshal(reqBody)
	if err != nil {
		errCh <- fmt.Errorf("failed to encode request: %w", err)
		close(outCh)
		close(errCh)
		return outCh, errCh
	}

	go func() {
		defer close(outCh)
		defer close(errCh)

		endpoint := p.baseURL + "/chat/completions"
		httpReq, err := http.NewRequestWithContext(ctx, http.MethodPost, endpoint, bytes.NewReader(jsonBytes))
		if err != nil {
			errCh <- fmt.Errorf("failed to create http request: %w", err)
			return
		}

		httpReq.Header.Set("Content-Type", "application/json")
		httpReq.Header.Set("Authorization", "Bearer "+p.apiKey)
		httpReq.Header.Set("Accept", "text/event-stream")
		httpReq.Header.Set("HTTP-Referer", "https://thego-getters.vercel.app")
		httpReq.Header.Set("X-Title", "The Go-getters")

		resp, err := p.client.Do(httpReq)
		if err != nil {
			if errors.Is(ctx.Err(), context.Canceled) {
				return
			}
			errCh <- fmt.Errorf("%w: %v", ErrUpstreamError, err)
			return
		}
		defer resp.Body.Close()

		if resp.StatusCode != http.StatusOK {
			bodySnippet, _ := io.ReadAll(io.LimitReader(resp.Body, 2048))
			var upstreamErr struct {
				Error struct {
					Message string `json:"message"`
					Code    any    `json:"code"`
				} `json:"error"`
			}
			msg := string(bodySnippet)
			if err := json.Unmarshal(bodySnippet, &upstreamErr); err == nil && upstreamErr.Error.Message != "" {
				msg = upstreamErr.Error.Message
			}
			errCh <- fmt.Errorf("%w: status %d - %s", ErrUpstreamError, resp.StatusCode, msg)
			return
		}

		scanner := bufio.NewScanner(resp.Body)
		for scanner.Scan() {
			select {
			case <-ctx.Done():
				return
			default:
			}

			line := scanner.Text()
			line = strings.TrimSpace(line)
			if line == "" || strings.HasPrefix(line, ":") {
				continue
			}

			if !strings.HasPrefix(line, "data:") {
				continue
			}

			payload := strings.TrimSpace(strings.TrimPrefix(line, "data:"))
			if payload == "[DONE]" {
				outCh <- StreamChunk{IsDone: true}
				return
			}

			var streamResp openAIStreamResponse
			if err := json.Unmarshal([]byte(payload), &streamResp); err != nil {
				continue
			}

			if len(streamResp.Choices) > 0 {
				delta := streamResp.Choices[0].Delta.Content
				if delta != "" {
					outCh <- StreamChunk{DeltaContent: delta}
				}
			}
		}

		if err := scanner.Err(); err != nil && !errors.Is(err, io.EOF) && !errors.Is(ctx.Err(), context.Canceled) {
			errCh <- fmt.Errorf("stream read error: %w", err)
		}
	}()

	return outCh, errCh
}
