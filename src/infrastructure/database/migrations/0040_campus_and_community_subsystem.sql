-- Migration 0040: Campus & Community Subsystem, Institutions Master Table, and Academic History
PRAGMA foreign_keys = ON;

-- 1. Master Institutions Table
CREATE TABLE IF NOT EXISTS institutions (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    uuid TEXT NOT NULL UNIQUE,
    name TEXT NOT NULL UNIQUE,
    short_name TEXT,
    institution_type TEXT NOT NULL DEFAULT 'college_university', -- 'college_university', 'high_school', 'community', 'other'
    display_order INTEGER NOT NULL DEFAULT 0,
    is_active INTEGER NOT NULL DEFAULT 1,
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_institutions_uuid ON institutions(uuid);
CREATE INDEX IF NOT EXISTS idx_institutions_type ON institutions(institution_type);
CREATE INDEX IF NOT EXISTS idx_institutions_order ON institutions(display_order);

-- Seed Initial Master Institutions
INSERT OR IGNORE INTO institutions (uuid, name, short_name, institution_type, display_order, is_active) VALUES
('inst_anderson_univ', 'Anderson University', 'AU', 'college_university', 1, 1),
('inst_erskine_coll', 'Erskine College', 'Erskine', 'college_university', 2, 1),
('inst_clemson_univ', 'Clemson University', 'CU', 'college_university', 3, 1),
('inst_tricounty_tech', 'Tri-County Technical College', 'TCTC', 'college_university', 4, 1),
('inst_local_hs', 'Local High School', 'LHS', 'high_school', 5, 1),
('inst_community', 'Community', 'Community', 'community', 6, 1),
('inst_other', 'Other', 'Other', 'other', 7, 1);

-- 2. Expand People Table for Campus & Community Foreign Key & Attributes
ALTER TABLE people ADD COLUMN institution_id INTEGER REFERENCES institutions(id);
ALTER TABLE people ADD COLUMN institution_other_name TEXT;
ALTER TABLE people ADD COLUMN relationship TEXT;
ALTER TABLE people ADD COLUMN academic_year TEXT;
ALTER TABLE people ADD COLUMN major TEXT;
ALTER TABLE people ADD COLUMN residence TEXT;
ALTER TABLE people ADD COLUMN expected_grad_term TEXT;
ALTER TABLE people ADD COLUMN expected_grad_year INTEGER;
ALTER TABLE people ADD COLUMN advancement_review_deferred INTEGER DEFAULT 0;
ALTER TABLE people ADD COLUMN skip_next_advancement INTEGER DEFAULT 0;
ALTER TABLE people ADD COLUMN advancement_last_reviewed_at TEXT;

CREATE INDEX IF NOT EXISTS idx_people_institution_id ON people(institution_id);
CREATE INDEX IF NOT EXISTS idx_people_relationship ON people(relationship);
CREATE INDEX IF NOT EXISTS idx_people_academic_year ON people(academic_year);

-- Backfill academic_year from existing grade column
UPDATE people SET academic_year = grade WHERE academic_year IS NULL AND grade IS NOT NULL AND grade != '';

-- 3. Person Academic History Table (Historical Tracking & Auditing)
CREATE TABLE IF NOT EXISTS person_academic_history (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    uuid TEXT NOT NULL UNIQUE,
    person_id INTEGER NOT NULL REFERENCES people(id) ON DELETE CASCADE,
    institution_id INTEGER REFERENCES institutions(id),
    institution_other_name TEXT,
    relationship TEXT,
    academic_year TEXT,
    major TEXT,
    residence TEXT,
    expected_grad_term TEXT,
    expected_grad_year INTEGER,
    change_source TEXT NOT NULL DEFAULT 'Profile Update',
    changed_by TEXT NOT NULL DEFAULT 'System',
    changed_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_academic_history_person_id ON person_academic_history(person_id);
CREATE INDEX IF NOT EXISTS idx_academic_history_changed_at ON person_academic_history(changed_at);
