package ai

import (
	"context"
	"errors"
	"testing"
)

func TestProvider_UnconfiguredReturnsError(t *testing.T) {
	// Must return ErrNotConfigured when API key is missing (Rule 2.3: No fake responses!)
	provider := NewOpenAICompatibleProvider("https://api.openai.com/v1", "", "gpt-4o-mini", "test", 100, 0.7)

	ctx := context.Background()
	_, errCh := provider.StreamChat(ctx, []ChatMessage{
		{Role: "user", Content: "Hello"},
	})

	err := <-errCh
	if err == nil {
		t.Fatal("expected error for unconfigured provider, got nil")
	}

	if !errors.Is(err, ErrNotConfigured) {
		t.Fatalf("expected ErrNotConfigured, got: %v", err)
	}
}
