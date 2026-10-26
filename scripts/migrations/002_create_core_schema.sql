-- Migration: 002_create_core_schema.sql
-- Description: Core tables for lectures, audio chunks, transcripts, segments, study materials, flashcards, quizzes, and background jobs.

-- 1. Create Enums safely
DO $$ BEGIN
    CREATE TYPE lecture_status AS ENUM (
        'draft',
        'recording',
        'uploaded',
        'transcribing',
        'generating_notes',
        'completed',
        'failed'
    );
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

DO $$ BEGIN
    CREATE TYPE chunk_status AS ENUM (
        'pending',
        'uploaded',
        'stitched',
        'failed'
    );
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

DO $$ BEGIN
    CREATE TYPE stt_provider AS ENUM (
        'groq_whisper',
        'sarvam_saaras',
        'deepgram_nova3',
        'openai_whisper'
    );
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

DO $$ BEGIN
    CREATE TYPE job_status AS ENUM (
        'queued',
        'running',
        'completed',
        'failed'
    );
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

-- 2. Lectures Table
CREATE TABLE IF NOT EXISTS lectures (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    title VARCHAR(255) NOT NULL,
    course_name VARCHAR(255),
    course_code VARCHAR(50),
    status lecture_status DEFAULT 'draft',
    duration_seconds INT DEFAULT 0,
    language_code VARCHAR(20) DEFAULT 'en', -- 'en', 'hi-en' (Hinglish), etc.
    master_audio_s3_key TEXT,
    audio_format VARCHAR(20) DEFAULT 'webm',
    audio_size_bytes BIGINT DEFAULT 0,
    is_favorite BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_lectures_user_id ON lectures(user_id);
CREATE INDEX IF NOT EXISTS idx_lectures_status ON lectures(status);
CREATE INDEX IF NOT EXISTS idx_lectures_created_at ON lectures(created_at DESC);

DROP TRIGGER IF EXISTS set_lectures_updated_at ON lectures;
CREATE TRIGGER set_lectures_updated_at
BEFORE UPDATE ON lectures
FOR EACH ROW
EXECUTE FUNCTION update_updated_at_column();

-- 3. Audio Chunks Table (Durable client uploads)
CREATE TABLE IF NOT EXISTS audio_chunks (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    lecture_id UUID NOT NULL REFERENCES lectures(id) ON DELETE CASCADE,
    sequence_number INT NOT NULL,
    s3_key TEXT NOT NULL,
    size_bytes BIGINT NOT NULL,
    duration_ms INT DEFAULT 30000,
    checksum_sha256 VARCHAR(64),
    status chunk_status DEFAULT 'pending',
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(lecture_id, sequence_number)
);

CREATE INDEX IF NOT EXISTS idx_audio_chunks_lecture_seq ON audio_chunks(lecture_id, sequence_number);

-- 4. Transcripts Table (Immutable source of truth & revision tracking)
CREATE TABLE IF NOT EXISTS transcripts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    lecture_id UUID NOT NULL REFERENCES lectures(id) ON DELETE CASCADE,
    version INT DEFAULT 1,
    provider stt_provider NOT NULL,
    raw_text TEXT NOT NULL,
    word_count INT DEFAULT 0,
    is_current BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_transcripts_lecture_current ON transcripts(lecture_id, is_current);

-- 5. Transcript Segments Table (Timestamp-linked playback & semantic search)
CREATE TABLE IF NOT EXISTS transcript_segments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    transcript_id UUID NOT NULL REFERENCES transcripts(id) ON DELETE CASCADE,
    sequence_order INT NOT NULL,
    start_time_ms INT NOT NULL,
    end_time_ms INT NOT NULL,
    speaker_label VARCHAR(50) DEFAULT 'Professor',
    text TEXT NOT NULL,
    confidence NUMERIC(4, 3), -- e.g., 0.985
    embedding vector(1536),    -- For semantic RAG search across lectures
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_segments_transcript_seq ON transcript_segments(transcript_id, sequence_order);
CREATE INDEX IF NOT EXISTS idx_segments_time ON transcript_segments(transcript_id, start_time_ms);
CREATE INDEX IF NOT EXISTS idx_segments_vector ON transcript_segments USING hnsw (embedding vector_cosine_ops);

-- 6. Study Materials Table (Versioned synthesized study outputs)
CREATE TABLE IF NOT EXISTS study_materials (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    lecture_id UUID NOT NULL REFERENCES lectures(id) ON DELETE CASCADE,
    transcript_id UUID NOT NULL REFERENCES transcripts(id) ON DELETE CASCADE,
    version INT DEFAULT 1,
    markdown_content TEXT NOT NULL, -- Rendered in TipTap/Novel editor
    executive_summary TEXT,
    key_topics JSONB DEFAULT '[]'::jsonb, -- e.g. ["Dynamic Programming", "Memoization"]
    exam_highlights JSONB DEFAULT '[]'::jsonb,
    is_current BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_study_materials_lecture ON study_materials(lecture_id, is_current);

-- 7. Flashcards Table (Anki & Spaced Repetition SRS)
CREATE TABLE IF NOT EXISTS flashcards (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    lecture_id UUID NOT NULL REFERENCES lectures(id) ON DELETE CASCADE,
    study_material_id UUID REFERENCES study_materials(id) ON DELETE CASCADE,
    front_text TEXT NOT NULL,
    back_text TEXT NOT NULL,
    timestamp_ref_ms INT, -- Links back to exact lecture millisecond
    ease_factor NUMERIC(3, 2) DEFAULT 2.50, -- SuperMemo-2 SRS algorithm
    interval_days INT DEFAULT 1,
    repetition_count INT DEFAULT 0,
    due_date TIMESTAMPTZ DEFAULT NOW(),
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_flashcards_due ON flashcards(lecture_id, due_date);

-- 8. Practice Quizzes Table (Active Recall & Exam Prep)
CREATE TABLE IF NOT EXISTS quizzes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    lecture_id UUID NOT NULL REFERENCES lectures(id) ON DELETE CASCADE,
    study_material_id UUID REFERENCES study_materials(id) ON DELETE CASCADE,
    question TEXT NOT NULL,
    options JSONB NOT NULL, -- e.g. {"A": "O(N)", "B": "O(N^2)", "C": "O(log N)", "D": "O(1)"}
    correct_option VARCHAR(5) NOT NULL, -- 'A', 'B', 'C', 'D'
    explanation TEXT NOT NULL,
    timestamp_ref_ms INT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_quizzes_lecture ON quizzes(lecture_id);

-- 9. Async Processing Jobs Table (Tracing & Observability)
CREATE TABLE IF NOT EXISTS processing_jobs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    lecture_id UUID NOT NULL REFERENCES lectures(id) ON DELETE CASCADE,
    job_type VARCHAR(50) NOT NULL, -- 'stitch_audio', 'transcribe', 'generate_notes'
    status job_status DEFAULT 'queued',
    attempt_count INT DEFAULT 0,
    max_attempts INT DEFAULT 3,
    error_message TEXT,
    started_at TIMESTAMPTZ,
    finished_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_processing_jobs_lecture ON processing_jobs(lecture_id, status);
