-- Migration 0034: People Review Status Subsystem for Registrations Awaiting Review Queue
-- Complies with [PD-001] (Offline Storage) and [PD-008] (Warm & Welcoming Design System)

ALTER TABLE people ADD COLUMN review_status TEXT DEFAULT 'reviewed';
ALTER TABLE people ADD COLUMN reviewed_at TEXT;

CREATE INDEX IF NOT EXISTS idx_people_review_status ON people(review_status);
