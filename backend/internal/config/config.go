package config

import (
	"log"
	"os"
	"strconv"
	"strings"
	"time"

	"github.com/joho/godotenv"
)

// Config holds all backend configuration.
type Config struct {
	Port             string
	DatabaseURL      string
	JWTSecret        string
	JWTAccessExpiry  time.Duration
	JWTRefreshExpiry time.Duration
	AIBaseURL        string
	AIAPIKey         string
	AIModel          string
	AISystemPrompt   string
	AIMaxTokens      int
	AITemperature    float64
	AllowedOrigins   string
	MaxRequestSizeMB int64

	// RevenueCat & Google Play Subscriptions
	RevenueCatWebhookAuthToken string
	RevenueCatAPIKey           string
	AndroidPackageName         string
}

// Load loads configuration from environment variables and an optional .env file.
func Load() *Config {
	_ = godotenv.Load() // optional local .env

	aiKey := getEnv("AI_API_KEY", "")
	if aiKey == "" {
		aiKey = getEnv("OPEN_ROUTER_KEY", "")
	}
	if aiKey == "" {
		aiKey = getEnv("OPENROUTER_API_KEY", "")
	}

	aiBaseURL := getEnv("AI_PROVIDER_BASE_URL", "")
	if aiBaseURL == "" {
		if strings.HasPrefix(aiKey, "sk-or-") {
			aiBaseURL = "https://openrouter.ai/api/v1"
		} else {
			aiBaseURL = "https://api.openai.com/v1"
		}
	}

	aiModel := getEnv("AI_MODEL", "")
	if aiModel == "" {
		if strings.Contains(aiBaseURL, "openrouter.ai") {
			aiModel = "nvidia/nemotron-3-ultra-550b-a55b:free"
		} else {
			aiModel = "gpt-4o-mini"
		}
	}

	cfg := &Config{
		Port:             getEnv("PORT", "8080"),
		DatabaseURL:      getEnv("DATABASE_URL", ""),
		JWTSecret:        getEnv("JWT_SECRET", "super-secret-jwt-key-replace-in-production-change-me"),
		JWTAccessExpiry:  getDurationEnv("JWT_ACCESS_EXPIRY", 15*time.Minute),
		JWTRefreshExpiry: getDurationEnv("JWT_REFRESH_EXPIRY", 7*24*time.Hour),
		AIBaseURL:        aiBaseURL,
		AIAPIKey:         aiKey,
		AIModel:          aiModel,
		AISystemPrompt:   getEnv("AI_SYSTEM_PROMPT", "You are an intelligent, helpful, and concise research assistant. Respond cleanly and use markdown for formatting."),
		AIMaxTokens:      getIntEnv("AI_MAX_TOKENS", 2048),
		AITemperature:    getFloatEnv("AI_TEMPERATURE", 0.7),
		AllowedOrigins:   getEnv("ALLOWED_ORIGINS", "*"),
		MaxRequestSizeMB: int64(getIntEnv("MAX_REQUEST_SIZE_MB", 5)),

		RevenueCatWebhookAuthToken: getEnv("REVENUECAT_WEBHOOK_AUTH_TOKEN", ""),
		RevenueCatAPIKey:           getEnv("REVENUECAT_API_KEY", ""),
		AndroidPackageName:         getEnv("ANDROID_PACKAGE_NAME", "com.aichat.app.mobile"),
	}

	if cfg.DatabaseURL == "" {
		log.Println("[WARN] DATABASE_URL is not set. Service will run in memory/dry-run mode for health checks, but DB operations require DATABASE_URL.")
	}

	return cfg
}

func getEnv(key, defaultVal string) string {
	if val, ok := os.LookupEnv(key); ok && val != "" {
		return val
	}
	return defaultVal
}

func getIntEnv(key string, defaultVal int) int {
	if val, ok := os.LookupEnv(key); ok {
		if i, err := strconv.Atoi(val); err == nil {
			return i
		}
	}
	return defaultVal
}

func getFloatEnv(key string, defaultVal float64) float64 {
	if val, ok := os.LookupEnv(key); ok {
		if f, err := strconv.ParseFloat(val, 64); err == nil {
			return f
		}
	}
	return defaultVal
}

func getDurationEnv(key string, defaultVal time.Duration) time.Duration {
	if val, ok := os.LookupEnv(key); ok {
		if d, err := time.ParseDuration(val); err == nil {
			return d
		}
	}
	return defaultVal
}

func getBoolEnv(key string, defaultVal bool) bool {
	if val, ok := os.LookupEnv(key); ok {
		low := strings.ToLower(strings.TrimSpace(val))
		return low == "true" || low == "1" || low == "yes"
	}
	return defaultVal
}
