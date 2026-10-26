# Task 02: Core Database Schema Migration

**Date:** October 2026\
**Status:** Completed ✅\
**Context:** [05-database-schema-and-neon-pg.md](../knowledge/05-database-schema-and-neon-pg.md) & [08-end-to-end-operational-walkthrough.md](../knowledge/08-end-to-end-operational-walkthrough.md)\
**Database:** Neon Serverless PostgreSQL (`ep-broad-scene-b5d1f68v-pooler`)

---

## 🎯 Goal

Define and migrate the core domain tables and enums into Neon Serverless PostgreSQL:

1. `lectures`: Lecture metadata, duration, language, and lifecycle states.
2. `audio_chunks`: 30-second chunk tracking for durable client uploads.
3. `transcripts`: Immutable full transcript records with provider metadata.
4. `transcript_segments`: Timestamp-aligned segments with `vector(1536)` HNSW indexes for semantic search / RAG.
5. `study_materials`: Versioned synthesized Cornell notes, key topics, and exam highlights.
6. `flashcards`: Spaced repetition (SM-2 SRS) flashcard decks with lecture millisecond references.
7. `quizzes`: Active recall multiple-choice questions with answer keys and timestamp references.
8. `processing_jobs`: Background worker state tracking (stitching, transcription, note generation).

---

## 📌 Applied Artifacts

1. **SQL Migration:** [`scripts/migrations/002_create_core_schema.sql`](../../scripts/migrations/002_create_core_schema.sql)
2. **Runner Script:** [`scripts/init_db.py`](../../scripts/init_db.py)

---

## 🔍 Verification Results

Ran migration via:

```bash
uv run --with "psycopg[binary]" python scripts/init_db.py
```

### Active Public Tables:

- `users` (Users and monthly recording quotas)
- `lectures` (Lecture sessions)
- `audio_chunks` (Client audio chunk sequence)
- `transcripts` (Raw transcript versions)
- `transcript_segments` (Segments + `vector(1536)` HNSW index)
- `study_materials` (Cornell markdown notes)
- `flashcards` (Spaced repetition cards)
- `quizzes` (Active recall questions)
- `processing_jobs` (Worker task tracking)

### Active Custom Enums:

- `lecture_status` (`draft`, `recording`, `uploaded`, `transcribing`, `generating_notes`, `completed`, `failed`)
- `chunk_status` (`pending`, `uploaded`, `stitched`, `failed`)
- `stt_provider` (`groq_whisper`, `sarvam_saaras`, `deepgram_nova3`, `openai_whisper`)
- `job_status` (`queued`, `running`, `completed`, `failed`)

---

## ⏭️ Next Task: Task 03 — FastAPI Backend Connected Shell

With the database schema fully established in Neon, the next task is to initialize `services/api`:

1. Scaffold FastAPI with async SQLAlchemy engine connecting to Neon.
2. Expose `GET /api/health` and `GET /api/health/db`.
3. Connect Next.js frontend to verify the end-to-end connection.
