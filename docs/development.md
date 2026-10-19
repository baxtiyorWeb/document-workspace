# Mahalliy Dasturlash va Ishga Tushirish Yo'riqnomasi (Local Development Guide)

Ushbu yo'riqnoma **The Go-getters AI Chat** loyihasini o'rnatish, ma'lumotlar bazasini sozlash va ilovalarni ishga tushirish qadamlarini tushuntiradi.

---

## 1. Talablar (Prerequisites)

- **Go**: 1.22+ (o'rnatilgan versiya: `1.27.0`)
- **Flutter**: 3.24+ (o'rnatilgan versiya: `3.47.6`, Dart `3.13.5`)
- **PostgreSQL**: Neon serverless hisobi yoki mahalliy PostgreSQL 14+
- **Git**

---

## 2. Ma'lumotlar Bazasini Sozlash (Neon PostgreSQL)

### 2.1 Neon dan ulanish havolasini olish:
1. [neon.tech](https://neon.tech) saytiga kiring va yangi loyiha (Project) oching.
2. Dashboard dan `Connection String` ni nusxalang:
   ```
   postgresql://[foydalanuvchi]:[parol]@[endpoint].neon.tech/[baza_nomi]?sslmode=require
   ```

### 2.2 database.sql ni import qilish:
1. Neon konsolidagi **SQL Editor** bo'limini oching.
2. Loyiha ildizidagi `database.sql` fayli tarkibini to'liq nusxalab, SQL Editor ga tashlang.
3. **Run** tugmasini bosing. Barcha jadvallar, indekslar va triggerlar yaratiladi.

*(Eslatma: Go backend serveri ham ishga tushganda `DATABASE_URL` mavjud bo'lsa, avtomatik ravishda migratsiyani tekshiradi va qo'llaydi).*

---

## 3. Go Backend ni Sozlash va Ishga Tushirish

### 3.1 Muhit faylini yaratish:
`backend/` papkasida `.env` faylini yarating (`.env.example` dan nusxa olib):

```bash
cd backend
copy .env.example .env
```

`.env` faylini ochib, qiymatlarni kiriting:
```ini
PORT=8080
DATABASE_URL=postgresql://[user]:[password]@[endpoint].neon.tech/[dbname]?sslmode=require
JWT_SECRET=maxfiy-32-baytlik-kalit-bu-yerda
AI_PROVIDER_BASE_URL=https://api.openai.com/v1
AI_API_KEY=sizning-haqiqiy-ai-kalitingiz
AI_MODEL=gpt-4o-mini
```

*(AI provayderi sifatida OpenAI, Groq, OpenRouter yoki lokal Ollama dan foydalanishingiz mumkin. Agar `AI_API_KEY` kiritilmasa, backend soxta javob qaytarmaydi, balki toza `AI_PROVIDER_NOT_CONFIGURED` xatoligini ko'rsatadi).*

### 3.2 Testlarni ishga tushirish:
```bash
go test -v ./...
```

### 3.3 Backend serverni ishga tushirish:
```bash
go run ./cmd/api
```
Server `http://localhost:8080` manzilida ishlay boshlaydi.

---

## 4. Flutter Mobil Ilovasini Ishga Tushirish

### 4.1 Bog'liqliklarni yuklash:
```bash
cd mobile
flutter pub get
```

### 4.2 Testlarni va statik tahlilni tekshirish:
```bash
flutter test
flutter analyze
```

### 4.3 Ilovani ishga tushirish:

- **Chrome / Web brauzerda:**
  ```bash
  flutter run -d chrome
  ```

- **Android emulyatorida:**
  ```bash
  flutter run -d android
  ```
  *(Android emulyatori `localhost` o'rniga `http://10.0.2.2:8080` manzilidan foydalanadi. Ilova bu manzilni avtomatik taniydi yoki Sozlamalar (Settings) ekranidan istalgan vaqt o'zgartirishingiz mumkin).*

- **Haqiqiy jismoniy telefonda:**
  Kompyuteringizning lokal Wi-Fi IP manzilini (masalan: `http://192.168.1.100:8080`) ilovaning **Sozlamalar (Settings) -> API Base URL** maydoniga kiriting.

---

## 5. Yangi Serverga Ko'chirish (Server Migration)

Loyiha hech qanday xususiy yoki vendor-lock extensionlarga bog'lanmagan.
Boshqa serverga (masalan: Supabase, AWS RDS, Docker yoki VPS) ko'chirish uchun:
1. Yangi PostgreSQL da `database.sql` skriptini ishga tushiring.
2. Backend `.env` faylidagi `DATABASE_URL` parametrini yangi server manziliga yo'naltiring.
3. Backendni qayta ishga tushiring.
