package tests

import (
	"encoding/json"
	"fmt"
	"net"
	"net/http"
	"strings"
	"time"
)

// StartMockLLMServer starts a deterministic mock OpenAI/OpenRouter SSE server.
func StartMockLLMServer(port int) (string, func()) {
	mux := http.NewServeMux()

	mux.HandleFunc("/chat/completions", func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost {
			http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
			return
		}

		var req struct {
			Model    string `json:"model"`
			Stream   bool   `json:"stream"`
			Messages []struct {
				Role    string `json:"role"`
				Content string `json:"content"`
			} `json:"messages"`
		}

		_ = json.NewDecoder(r.Body).Decode(&req)

		if !req.Stream {
			w.Header().Set("Content-Type", "application/json")
			_ = json.NewEncoder(w).Encode(map[string]any{
				"id":     "mock-chatcmpl-123",
				"object": "chat.completion",
				"model":  req.Model,
				"choices": []any{
					map[string]any{
						"message": map[string]string{
							"role":    "assistant",
							"content": "Mock completion non-streaming response.",
						},
						"finish_reason": "stop",
					},
				},
				"usage": map[string]int{
					"prompt_tokens":     15,
					"completion_tokens": 10,
					"total_tokens":      25,
				},
			})
			return
		}

		flusher, ok := w.(http.Flusher)
		if !ok {
			http.Error(w, "Streaming unsupported", http.StatusInternalServerError)
			return
		}

		w.Header().Set("Content-Type", "text/event-stream; charset=utf-8")
		w.Header().Set("Cache-Control", "no-cache, no-transform")
		w.Header().Set("Connection", "keep-alive")

		tokens := []string{
			"Salom", "!", " Bu", " sinov", " uchun", " mock", " AI", " javobi", ".",
			" Tizim", " yuklama", " va", " bekor", " qilish", " testlaridan", " muvaffaqiyatli", " o'tmoqda", ".",
		}

		ctx := r.Context()
		for i, tok := range tokens {
			select {
			case <-ctx.Done():
				return // Client disconnected or cancelled
			default:
			}

			chunk := map[string]any{
				"id":     "mock-chunk-id",
				"object": "chat.completion.chunk",
				"model":  req.Model,
				"choices": []any{
					map[string]any{
						"index": 0,
						"delta": map[string]string{
							"content": tok,
						},
						"finish_reason": nil,
					},
				},
			}
			chunkBytes, _ := json.Marshal(chunk)
			_, _ = fmt.Fprintf(w, "data: %s\n\n", string(chunkBytes))
			flusher.Flush()

			// Delay between chunks simulating token generation
			time.Sleep(15 * time.Millisecond)

			if i == len(tokens)-1 {
				finalChunk := map[string]any{
					"id":     "mock-chunk-id",
					"object": "chat.completion.chunk",
					"choices": []any{
						map[string]any{
							"index":         0,
							"delta":         map[string]string{},
							"finish_reason": "stop",
						},
					},
				}
				finalBytes, _ := json.Marshal(finalChunk)
				_, _ = fmt.Fprintf(w, "data: %s\n\n", string(finalBytes))
				_, _ = fmt.Fprintf(w, "data: [DONE]\n\n")
				flusher.Flush()
			}
		}
	})

	listener, err := net.Listen("tcp", fmt.Sprintf("127.0.0.1:%d", port))
	if err != nil {
		// fallback to random port
		listener, err = net.Listen("tcp", "127.0.0.1:0")
		if err != nil {
			panic(err)
		}
	}

	actualAddr := listener.Addr().String()
	if !strings.HasPrefix(actualAddr, "http") {
		actualAddr = "http://" + actualAddr
	}

	server := &http.Server{Handler: mux}
	go func() {
		_ = server.Serve(listener)
	}()

	teardown := func() {
		_ = server.Close()
	}

	return actualAddr, teardown
}
