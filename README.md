# The Go-getters — Professional AI Chat Mobile App & Go Backend

[![Go](https://img.shields.io/badge/Go-1.27-blue.svg)](https://golang.org)
[![Flutter](https://img.shields.io/badge/Flutter-3.47.6-02569B.svg)](https://flutter.dev)
[![PostgreSQL](https://img.shields.io/badge/PostgreSQL-Neon%20Ready-336791.svg)](https://neon.tech)
[![State](https://img.shields.io/badge/State-Riverpod-283593.svg)](https://riverpod.dev)

A production-oriented AI Chat mobile application and Go backend built with clean architecture, PostgreSQL persistence (Neon serverless ready), real Server-Sent Events (SSE) streaming, server-side configurable LLM provider integration, and authenticated conversation management.

Designed to match **The Go-getters** brand aesthetics (Dark & Light themes with Mint/Emerald accents) and modern mobile UI standards.

---

## Repository Structure

```
document-workspace/
├── mobile/                        # Flutter Mobile Application
│   ├── lib/
│   │   ├── app/                   # App root and navigation shell
│   │   ├── core/                  # Design tokens, theme, network, errors
│   │   │   ├── config/            # Platform-aware API configuration
│   │   │   ├── errors/            # Typed application exceptions
│   │   │   ├── network/           # ApiClient and SSEClient
│   │   │   ├── theme/             # Go-getters Dark and Light Theme tokens
│   │   │   └── utils/             # Date and time formatters
│   │   ├── features/
│   │   │   ├── auth/              # Login, Register, secure token storage
│   │   │   ├── conversations/     # History drawer, rename, delete
│   │   │   ├── explore/           # Category cards and pulsing hero bubble
│   │   │   ├── chat/              # Live SSE streaming, Markdown, Stop button
│   │   │   └── settings/          # Theme switcher, API Base URL, Logout
│   │   └── main.dart
│   ├── test/                      # Widget and Riverpod unit tests
│   └── pubspec.yaml
├── backend/                       # Go RESTful API Service
│   ├── cmd/api/main.go            # Entry point, router, graceful shutdown
│   ├── internal/
│   │   ├── config/                # Environment variable configuration
│   │   ├── persistence/           # pgxpool PostgreSQL driver & auto-migrator
│   │   ├── middleware/            # RequestID, Logger, Recoverer, JWT Auth
│   │   ├── auth/                  # Password hashing (bcrypt) & sessions
│   │   ├── conversations/         # Conversations CRUD & ownership
│   │   ├── messages/              # Messages persistence & auto-titling
│   │   ├── generations/           # SSE streaming & cancellation registry
│   │   ├── ai/                    # Pluggable OpenAI-compatible LLM adapter
│   │   └── http/                  # Handlers and structured JSON responses
│   ├── migrations/                # Versioned SQL migration files
│   ├── tests/                     # API contract and integration tests
│   ├── go.mod
│   └── .env.example
├── database.sql                   # Clean master schema for Neon / Postgres console
├── docs/
│   ├── architecture.md            # System architecture and data flow
│   ├── api.md                     # Complete REST & SSE API contract
│   └── development.md             # Local setup and deployment guide
├── .gitignore
└── README.md
```

---

## Core Capabilities

1. **Persistent History in PostgreSQL**:
   - Single clean `database.sql` file ready for Neon console or any Postgres instance.
   - Relational entities: `users`, `refresh_sessions`, `conversations`, `messages`, `generations`.
   - Automatic triggers for updating `last_message_at` and `updated_at`.
2. **Real-time SSE Streaming & True Cancellation**:
   - Streams AI completion tokens live via Server-Sent Events.
   - Stop button sends a cancellation request to the backend, aborting the active upstream LLM call and updating database state immediately.
3. **Authentication & Data Isolation**:
   - Password hashing with bcrypt.
   - Cryptographically random refresh token sessions stored as SHA-256 hashes.
   - Strict data ownership checks: users cannot view, edit, or delete another user's conversations or messages.
4. **Configurable AI Provider**:
   - Configurable at the backend level (`AI_PROVIDER_BASE_URL`, `AI_API_KEY`, `AI_MODEL`).
   - Compatible with OpenAI, Groq, OpenRouter, DeepSeek, or local Ollama.
   - If unconfigured, returns an actionable `AI_PROVIDER_NOT_CONFIGURED` error (zero fake responses).
5. **Modern The Go-getters Theme**:
   - Dark mode (`#0D1117` obsidian background, `#161B22` cards, mint green accents).
   - Light mode (`#F8FAFC` clean background, `#FFFFFF` cards).
   - Explore dashboard with 8 categorized prompts (Art, Booking, Code, Content, Entertainment, Translator, Health, Music).
   - Pulsing hero bubble: "Salom, [Name] 👋 / Suhbatni boshlash".
   - Markdown rendering with syntax highlighting and code copy buttons.

---

## Quick Start

### 1. Database Setup (Neon PostgreSQL)
1. Open [Neon Console](https://console.neon.tech) and copy your connection string.
2. In the Neon SQL Editor, execute the contents of [database.sql](file:///c:/Users/user/Desktop/document-workspace/database.sql).

### 2. Run Go Backend
```bash
cd backend
copy .env.example .env
# Fill DATABASE_URL and AI_API_KEY in .env
go run ./cmd/api
```

### 3. Run Flutter App
```bash
cd mobile
flutter pub get
flutter run -d chrome    # Or -d android
```

---

## Verification & Testing

### Go Tests:
```bash
cd backend
go test -v ./...
```
- `PASS: TestProvider_UnconfiguredReturnsError`
- `PASS: TestWriteJSON`
- `PASS: TestWriteError`
- `PASS: TestAuthMiddleware_ValidToken`
- `PASS: TestAuthMiddleware_MissingHeader`
- `PASS: TestAuthMiddleware_ExpiredToken`
- `PASS: TestHealthLive`
- `PASS: TestUnauthenticatedAccessRejected`
- `PASS: TestRegisterValidation`

### Flutter Tests & Static Analysis:
```bash
cd mobile
flutter analyze  # No issues found!
flutter test     # All 7 tests passed!
```
- `PASS: UserProfile json serialization and deserialization`
- `PASS: AuthState initial state and copyWith`
- `PASS: ChatMessage json deserialization and helper getters`
- `PASS: ChatMessage copyWith updates content and status`
- `PASS: ChatState default values`
- `PASS: ChatState copyWith updates fields correctly`
- `PASS: AiChatApp renders correctly and shows initial authentication/splash screen`

---

## License
MIT
"# document-workspace" 
