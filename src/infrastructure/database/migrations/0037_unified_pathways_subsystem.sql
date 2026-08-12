-- Migration 0037: Unified Pathways Subsystem (Stage 1 Foundation)
-- Complies with [PD-001] (Offline Storage & Outbox) and Canonical Fellows & LEAD Architecture

-- 1. Seed Canonical Pathway Definitions in pathways table
INSERT OR IGNORE INTO pathways (pathway_key, name, description, total_milestones, is_active)
VALUES ('fellows', 'Fellows', 'Four-year ministry formation fellowship pathway', 4, 1);

INSERT OR IGNORE INTO pathways (pathway_key, name, description, total_milestones, is_active)
VALUES ('lead', 'LEAD', 'Four-year leadership development track', 4, 1);

-- 2. Create Annual Program Years Table
CREATE TABLE IF NOT EXISTS pathway_program_years (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    uuid TEXT UNIQUE NOT NULL,
    pathway_id INTEGER NOT NULL,
    academic_year TEXT NOT NULL,
    display_name TEXT NOT NULL,
    start_date TEXT,
    end_date TEXT,
    status TEXT NOT NULL DEFAULT 'active',
    notes TEXT,
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at TEXT NOT NULL DEFAULT (datetime('now')),
    FOREIGN KEY(pathway_id) REFERENCES pathways(id) ON DELETE CASCADE,
    UNIQUE(pathway_id, academic_year)
);

-- 3. Extend person_pathways with modern columns if not present
-- Note: ALTER TABLE in SQLite adds columns one by one safely
ALTER TABLE person_pathways ADD COLUMN uuid TEXT;
ALTER TABLE person_pathways ADD COLUMN current_track TEXT NOT NULL DEFAULT 'standard';
ALTER TABLE person_pathways ADD COLUMN current_standing TEXT NOT NULL DEFAULT 'year_1';
ALTER TABLE person_pathways ADD COLUMN enrollment_status TEXT NOT NULL DEFAULT 'active';
ALTER TABLE person_pathways ADD COLUMN assigned_mentor_person_id INTEGER REFERENCES people(id) ON DELETE SET NULL;
ALTER TABLE person_pathways ADD COLUMN general_notes TEXT;
ALTER TABLE person_pathways ADD COLUMN updated_at TEXT;

-- Backfill missing UUIDs and updated_at for pre-existing person_pathways rows
UPDATE person_pathways SET uuid = 'pp_legacy_' || id WHERE uuid IS NULL OR uuid = '';
UPDATE person_pathways SET updated_at = datetime('now') WHERE updated_at IS NULL OR updated_at = '';

-- 4. Create Person Pathway Program Years (Annual Participant Standing & Track Records)
CREATE TABLE IF NOT EXISTS person_pathway_program_years (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    uuid TEXT UNIQUE NOT NULL,
    person_pathway_id INTEGER NOT NULL,
    pathway_program_year_id INTEGER NOT NULL,
    standing_for_that_year TEXT NOT NULL DEFAULT 'year_1',
    track_for_that_year TEXT NOT NULL DEFAULT 'standard',
    participation_status TEXT NOT NULL DEFAULT 'active',
    mentor_person_id INTEGER REFERENCES people(id) ON DELETE SET NULL,
    annual_plan_notes TEXT,
    catch_up_plan TEXT,
    started_at TEXT NOT NULL DEFAULT (datetime('now')),
    completed_at TEXT,
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at TEXT NOT NULL DEFAULT (datetime('now')),
    FOREIGN KEY(person_pathway_id) REFERENCES person_pathways(id) ON DELETE CASCADE,
    FOREIGN KEY(pathway_program_year_id) REFERENCES pathway_program_years(id) ON DELETE CASCADE,
    UNIQUE(person_pathway_id, pathway_program_year_id)
);

-- 5. Create Pathway Program Requirements (Group Requirements)
CREATE TABLE IF NOT EXISTS pathway_program_requirements (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    uuid TEXT UNIQUE NOT NULL,
    pathway_program_year_id INTEGER NOT NULL,
    title TEXT NOT NULL,
    description TEXT,
    category TEXT NOT NULL DEFAULT 'other',
    required_or_optional TEXT NOT NULL DEFAULT 'required',
    applies_to_track TEXT NOT NULL DEFAULT 'all',
    applies_to_standing TEXT NOT NULL DEFAULT 'all',
    due_date TEXT,
    display_order INTEGER NOT NULL DEFAULT 1,
    status TEXT NOT NULL DEFAULT 'active',
    created_by TEXT,
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at TEXT NOT NULL DEFAULT (datetime('now')),
    FOREIGN KEY(pathway_program_year_id) REFERENCES pathway_program_years(id) ON DELETE CASCADE
);

-- 6. Create Person Pathway Requirements (Personal Requirement Assignments & Catch-Up Items)
CREATE TABLE IF NOT EXISTS person_pathway_requirements (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    uuid TEXT UNIQUE NOT NULL,
    person_pathway_program_year_id INTEGER NOT NULL,
    source_program_requirement_id INTEGER REFERENCES pathway_program_requirements(id) ON DELETE SET NULL,
    title TEXT NOT NULL,
    description TEXT,
    category TEXT NOT NULL DEFAULT 'other',
    required_or_optional TEXT NOT NULL DEFAULT 'required',
    assigned_date TEXT NOT NULL DEFAULT (datetime('now')),
    due_date TEXT,
    status TEXT NOT NULL DEFAULT 'assigned',
    completed_at TEXT,
    completion_notes TEXT,
    assigned_by TEXT,
    completed_by TEXT,
    assignment_source TEXT NOT NULL DEFAULT 'annual_program',
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at TEXT NOT NULL DEFAULT (datetime('now')),
    FOREIGN KEY(person_pathway_program_year_id) REFERENCES person_pathway_program_years(id) ON DELETE CASCADE
);

-- 7. Create Track History Audit Table
CREATE TABLE IF NOT EXISTS person_pathway_track_history (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    uuid TEXT UNIQUE NOT NULL,
    person_pathway_id INTEGER NOT NULL,
    previous_track TEXT NOT NULL,
    new_track TEXT NOT NULL,
    effective_at TEXT NOT NULL DEFAULT (datetime('now')),
    changed_by TEXT,
    reason TEXT,
    catch_up_plan TEXT,
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    FOREIGN KEY(person_pathway_id) REFERENCES person_pathways(id) ON DELETE CASCADE
);

-- 8. Create Standing History Audit Table
CREATE TABLE IF NOT EXISTS person_pathway_standing_history (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    uuid TEXT UNIQUE NOT NULL,
    person_pathway_id INTEGER NOT NULL,
    previous_standing TEXT NOT NULL,
    new_standing TEXT NOT NULL,
    effective_at TEXT NOT NULL DEFAULT (datetime('now')),
    changed_by TEXT,
    reason TEXT,
    catch_up_plan TEXT,
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    FOREIGN KEY(person_pathway_id) REFERENCES person_pathways(id) ON DELETE CASCADE
);

-- 9. Create Pathway Program Sessions Linking Table
CREATE TABLE IF NOT EXISTS pathway_program_sessions (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    pathway_program_year_id INTEGER NOT NULL,
    session_id INTEGER NOT NULL,
    attendance_expectation TEXT NOT NULL DEFAULT 'required',
    applies_to_track TEXT NOT NULL DEFAULT 'all',
    applies_to_standing TEXT NOT NULL DEFAULT 'all',
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    created_by TEXT,
    FOREIGN KEY(pathway_program_year_id) REFERENCES pathway_program_years(id) ON DELETE CASCADE,
    FOREIGN KEY(session_id) REFERENCES sessions(id) ON DELETE CASCADE,
    UNIQUE(pathway_program_year_id, session_id)
);
