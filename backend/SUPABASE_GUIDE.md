# 🚀 Panduan Setup PostgreSQL & Supabase untuk FinGent

Backend FinGent menggunakan **PostgreSQL Murni (*No-ORM*)** dengan driver async berkecepatan tinggi (`asyncpg`) dan connection pooling standar industri. Skema database didesain 100% kompatibel dengan **Supabase**.

---

## Opsi 1: Menggunakan Supabase Cloud (Rekomendasi Produksi)

### Langkah 1: Buat Proyek di Supabase
1. Buka [https://supabase.com](https://supabase.com) dan buat proyek baru (misal: `fingent-db`).
2. Catat **Database Password** yang Anda buat.

### Langkah 2: Upload Skema Database ke Supabase
1. Di Dashboard Supabase, buka menu **SQL Editor** (ikon terminal di menu sebelah kiri).
2. Buat query baru, lalu salin dan tempel (*copy-paste*) seluruh isi file:
   [`backend/migrations/001_initial_schema.sql`](file:///Users/surya/Documents/2026/Institute/C3/StoxGentMVVM/backend/migrations/001_initial_schema.sql)
3. Klik tombol **Run**.
4. Semua tabel (`news_articles`, `user_watchlists`, `portfolio_holdings`, `portfolio_transactions`, `ai_chat_logs`) beserta index GIN akan langsung dibuat.

### Langkah 3: Hubungkan Backend ke Supabase
1. Di Supabase, buka **Project Settings** (ikon roda gigi) > **Database**.
2. Scroll ke bagian **Connection parameters** atau **Connection string**, pilih mode **URI**.
3. Buka file `backend/.env` Anda dan isi variabel `DATABASE_URL`:
   ```env
   DATABASE_URL=postgresql://postgres.[YOUR-PROJECT-REF]:[YOUR-PASSWORD]@aws-0-[REGION].pooler.supabase.com:6543/postgres?sslmode=require
   ```
   *(Ganti `[YOUR-PROJECT-REF]`, `[YOUR-PASSWORD]`, dan `[REGION]` sesuai kredensial Supabase Anda).*

---

## Opsi 2: Menggunakan Docker Lokal (Development Offline)

Jika Anda ingin menjalankan PostgreSQL secara lokal di Mac:

1. Buka aplikasi **Docker Desktop**.
2. Di terminal, jalankan:
   ```bash
   cd backend
   docker compose up -d
   ```
3. Docker akan otomatis menjalankan PostgreSQL 16 pada port `5432` dan menjalankan migrasi skema awal secara otomatis.

---

## Menjalankan Server Backend

1. Aktifkan virtual environment dan jalankan server:
   ```bash
   cd backend
   source venv/bin/activate
   uvicorn main:app --reload --host 0.0.0.0 --port 8000
   ```

2. Tes kesehatan server di browser atau curl:
   ```bash
   curl http://localhost:8000/
   ```

3. Endpoint yang tersedia:
   - **`GET /api/v1/news?ticker=MU`**: Mengambil berita saham grounded dari PostgreSQL.
   - **`POST /api/v1/news/sync`**: Memicu ingestion feed RSS (Yahoo Finance & CNBC) ke PostgreSQL.
   - **`GET /api/v1/watchlist`**: Melihat daftar saham favorit pengguna.
   - **`POST /api/v1/watchlist`**: Menambah saham ke favorit.
   - **`GET /api/v1/portfolio/holdings`**: Melihat kepemilikan portofolio.
   - **`POST /api/v1/portfolio/transactions`**: Mencatat transaksi beli/jual.
   - **`GET /api/v1/stocks/{ticker}`**: Real-time quote Yahoo Finance (IDX & US).
