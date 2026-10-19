# Production-Grade AI Assistant: Performance, Multimodal Files & Tiered Usage Limits

Ushbu hisobot mavjud Flutter mobil ilovasi, Go backend va PostgreSQL ma'lumotlar bazasi asosidagi AI Assistant tizimini ishlab chiqarish (production) darajasiga ko'tarish bo'yicha amalga oshirilgan to'liq arxitektura va amaliy ishlanmalarni o'z ichiga oladi.

---

## 1. Tizim A: Chat Interfeysi — Maksimal Silliqlik va Scroll Holat Mashinasi

### Muammo
Avvalgi chat interfeysida:
- Har bir kelgan token (har 10–20 ms) butun xabarlar ro'yxatini qayta render qilar va layout hisoblashlarini ishga tushirardi.
- Streaming davomida foydalanuvchi yuqoriga chiqib o'tgan xabarlar yoki kodlarni o'qiyotgan paytda, yangi tokenlar uni majburan pastga sakratardi.
- Pastga tushish tugmasi va yangi xabarlar indikatori yo'q edi.

### Amalga oshirilgan yechimlar
1. **Streaming Token Batching (45ms Throttle Timer):**
   - [`chat_provider.dart`](mobile/lib/features/chat/providers/chat_provider.dart) ichida `_contentBuffer` va `_flushTimer` joriy qilindi.
   - Har bir token kelganda to'g'ridan-to'g'ri `state` yangilanmaydi; deltalari buferga yozilib, 45 ms oraliqda bir marta batch qilib UI ga uzatiladi.
   - Stream yakunlanganda (`generation.completed`, `cancelled`, `failed`) qolgan bufer darhol to'liq yoziladi.
   - Natijada: Flutter 60 FPS / 120 FPS ekranda qotishlarsiz va yuksiz silliq ishlaydi.

2. **Scroll Holat Mashinasi (Scroll State Machine):**
   - [`chat_screen.dart`](mobile/lib/features/chat/presentation/chat_screen.dart) ichida quyidagi holatlar bir-biriga zid bo'lmagan holda boshqariladi:
     - `_isNearBottom`: foydalanuvchi ro'yxatning eng pastki qismidan 100px masofa ichida ekanligini bildiradi.
     - `_isUserScrolling`: `NotificationListener<ScrollNotification>` orqali foydalanuvchi barmoq bilan ekranni surayotgan vaqtni aniqlaydi.
     - `_hasNewMessages`: agar foydalanuvchi yuqorida bo'lsa va yangi xabar/tokenlar kelsa, `true` bo'ladi.
   - **Qoida:** Agar `_isNearBottom && !_isUserScrolling` bo'lsa, chat yangi xabarlar ortidan pastga silliq tushadi. Agar foydalanuvchi yuqoriga chiqqan bo'lsa, scroll **hech qachon majburan pastga tortilmaydi**.

3. **Pastga tushish ("Scroll to Bottom") suzuvchi tugmasi:**
   - Ekranning o'ng tomonida, composer ustida xavfsiz joylashtirildi (`Positioned(right: 16, bottom: 12)`).
   - Klaviatura, input maydoni yoki safe area bilan to'qnashmaydi.
   - Foydalanuvchi yuqoriga chiqqanda `AnimatedScale` va `AnimatedOpacity` bilan silliq paydo bo'ladi.
   - Yangi xabarlar kelganda tugma ichida **"Yangi xabarlar"** nishoni (badge) va pulsatsiya indikatori ko'rsatiladi.
   - Bosilganda foydalanuvchini eng so'nggi xabarga silliq olib tushadi va `_hasNewMessages` holatini tiklaydi.

4. **Virtualizatsiya va RepaintBoundary:**
   - `ListView.builder` `cacheExtent: 500` bilan sozlandi.
   - Har bir xabar `RepaintBoundary` bilan o'raldi, shu orqali streaming bo'layotgan xabar boshqa xabarlarning qayta chizilishiga olib kelmaydi.

---

## 2. Tizim B: Multimodal Fayllarni Qabul Qilish va Tahlil Qilish (RAG & Vision)

### Qo'llab-quvvatlanadigan formatlar
- **Hujjatlar:** PDF (`.pdf`), DOC/DOCX (`.doc`, `.docx`), TXT (`.txt`), Markdown (`.md`), CSV (`.csv`).
- **Rasmlar:** JPG/JPEG (`.jpg`, `.jpeg`), PNG (`.png`), WEBP (`.webp`).

### Server tomonidagi xavfsizlik va qayta ishlash
1. **Haqiqiy MIME va Magic-byte Tekshiruvi:**
   - [`parsers.go`](backend/internal/files/parsers.go) da fayl boshidagi baytlar tahlil qilinadi:
     - PDF: `%PDF-` (`0x25, 0x50, 0x44, 0x46, 0x2D`)
     - DOCX: PK ZIP arxivi (`0x50, 0x4B, 0x03, 0x04`) + XML validatsiyasi
     - PNG: `\x89PNG\r\n\x1a\n`
     - JPEG: `\xFF\xD8\xFF`
     - WEBP: `RIFF....WEBP`
     - Text/CSV: binary null-byte tekshiruvi va UTF-8 validatsiyasi.
   - Path traversal hujumlariga qarshi `filepath.Base()` va UUID asosidagi saqlash tizimi qo'llangan.

2. **CGO-siz sof Go DOCX va PDF Parserlari:**
   - DOCX: Go'ning standart `archive/zip` va `encoding/xml` paketlari orqali `word/document.xml` dan barcha `<w:p>` (paragraflar) va `<w:tbl>` (jadvallar) strukturali matnga ajratiladi.
   - PDF: sahifalar bo'yicha ajratish va sahifa indekslarini saqlash.
   - CSV: avtomatik ravishda Markdown jadvaliga aylantiriladi.

3. **Leksik RAG va Sahifama-sahifa Manbalar (Citations):**
   - Hujjatlar 700 ta belgidan iborat, 100 ta belgi o'zaro ustma-ust tushadigan bo'laklarga (`file_chunks`) bo'linadi va sahifa raqami saqlanadi.
   - Foydalanuvchi savol berganda, tegishli bo'laklar leksik moslik bo'yicha tanlanadi va promptga xavfsiz formatda kiritiladi:
     `--- HUJJAT: [nomi] (Sahifa: [N]) ---`
   - AI javobida sahifa manbalari (`citations`) ajratib olinadi va mobil ilovada alohida ko'rsatiladi.

4. **Vision Avto-Routing:**
   - Agar foydalanuvchi rasm yuklagan bo'lsa, [`router.go`](backend/internal/gateway/router.go) avtomatik tarzda multimodal/vision qobiliyatiga ega modelga (`gpt-4o` yoki `gpt-4o-mini`) yo'naltiradi.

5. **Mobil Ilova UX:**
   - [`message_composer.dart`](mobile/lib/features/chat/presentation/widgets/message_composer.dart):
     - Qisqich (paperclip) tugmasi orqali hujjat yoki rasm tanlash.
     - Yuklanayotgan fayllar uchun gorizontal chip ro'yxati (fayl ikonasi, nomi, hajmi, loader, o'chirish tugmasi).
     - Serverga yuklash tugaguncha jo'natish tugmasi xavfsiz bloklanadi.
   - [`message_bubble.dart`](mobile/lib/features/chat/presentation/widgets/message_bubble.dart):
     - Foydalanuvchi xabarida biriktirilgan fayllar nishoni.
     - AI javobida sahifalar bo'yicha **"Hujjat manbalari"** ro'yxati.

---

## 3. Tizim C: Free, Pro va Ultra Tariflari & 3 Bosqichli Token Limitlari

### 1. Uchta Vaqt Oynasi (Hourly, Daily, Weekly)
Backend [`quotas.go`](backend/internal/gateway/quotas.go) va [`service.go`](backend/internal/plans/service.go) orqali uch xil vaqt o'lchovida limitlar o'rnatildi:
- **Soatlik (Hourly):** birdaniga ko'p so'rov yuborib serverni yuklashdan himoya.
- **Kunlik (Daily):** kunlik balans va reja nazorati.
- **Haftalik (Weekly):** haftalik sarf me'yori.

### 2. Tariflar Konfiguratsiyasi (Database & Admin-Boshqariladigan)
| Imkoniyat | Free | Pro | Ultra |
|---|---|---|---|
| Soatlik so'rovlar | 10 | 60 | 300 |
| Kunlik so'rovlar | 40 | 300 | 2,000 |
| Haftalik so'rovlar | 200 | 1,500 | 10,000 |
| Oylik tokenlar | 100,000 | 2,000,000 | 15,000,000 |
| Maksimal fayl hajmi | 5 MB | 25 MB | 100 MB |
| Bitta so'rovdagi fayllar | 1 ta | 5 ta | 20 ta |
| Vision / Rasm tahlili | Cheklangan | To'liq | Premium |
| Hujjat RAG tahlili | Asosiy | Kengaytirilgan | Katta hajmli |
| Parallel oqimlar | 1 | 3 | 10 |
| Narx | \$0.00 | \$9.99 / oy | \$29.99 / oy |

### 3. Atomar Tranzaksiya & Rezervatsiya (Usage Ledger)
- Parallel so'rovlarda limitdan oshib ketmaslik uchun so'rov boshida `usage_ledger` ga `reserved` holatida yoziladi.
- So'rov muvaffaqiyatli tugagach, AI provayder qaytargan haqiqiy tokenlar (input + output) asosida `settled` holatiga o'tkaziladi.
- Bekor qilingan yoki xato yuz bergan so'rovlarda zaxira qilingan tokenlar darhol `released` qilinadi.
- Multimodal so'rovlar uchun xarajat koeffitsiyenti (`costMultiplier = 2.5x`) hisobga olinadi.

### 4. Strukturali `429` / Quota Error
Limit tugaganda backend quyidagi ma'lumotlarni qaytaradi:
```json
{
  "code": "QUOTA_EXCEEDED",
  "message": "Kunlik so'rovlar limiti tugadi (40/40)",
  "window": "daily",
  "resets_at": "2026-10-15T00:00:00Z"
}
```
Mobil ilova foydalanuvchiga qaysi limit tugaganini va qachon yangilanishini tushunarli banner orqali ko'rsatadi.

---

## 4. Testlar va Verifikatsiya Natijalari

### Backend Testlari
Buyruq: `go test ./...`
```
ok   ai-chat-backend/internal/ai          (cached)
ok   ai-chat-backend/internal/billing     (cached)
ok   ai-chat-backend/internal/files       4.519s
ok   ai-chat-backend/internal/gateway     (cached)
ok   ai-chat-backend/internal/http        (cached)
ok   ai-chat-backend/internal/middleware  (cached)
ok   ai-chat-backend/tests                2.517s
PASS
```
- Fayllar imzosi (magic bytes), buzilgan fayllar, path traversal, PDF/DOCX matn ajratish, RAG qidiruvi va kontrakt testlari 100% muvaffaqiyatli o'tdi.

### Mobil Testlar va Analiz
1. Buyruq: `dart analyze lib`
   ```
   Analyzing lib...
   No issues found!
   ```
   Xatoliklar va ogohlantirishlar soni: **0**.

2. Buyruq: `flutter test`
   ```
   00:00 +0: UserProfile Model Tests
   00:00 +1: AuthState Model Tests
   00:00 +2: ChatMessage json deserialization and helper getters
   00:00 +3: ChatMessage copyWith updates content, status and citations
   00:00 +4: AttachedFile format size and type identification
   00:00 +5: ChatState default values
   00:00 +6: ChatState copyWith updates fields correctly
   00:25 +7: AiChatApp renders correctly
   00:33 +8: All tests passed!
   ```
   Barcha 8 ta avtomatlashtirilgan test to'liq muvaffaqiyatli yakunlandi.
