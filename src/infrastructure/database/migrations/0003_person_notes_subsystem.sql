-- Migration 0003: Person Notes Sub-system & Configurable Note Types (Story DIR-SPR1-006)
PRAGMA journal_mode = WAL;
PRAGMA foreign_keys = ON;

-- 1. Note Types Lookup Table (PD-006, PD-007)
CREATE TABLE IF NOT EXISTS note_types (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    type_uuid TEXT NOT NULL UNIQUE,
    name TEXT NOT NULL,
    description TEXT,
    display_order INTEGER NOT NULL DEFAULT 0,
    is_active INTEGER NOT NULL DEFAULT 1,
    is_system INTEGER NOT NULL DEFAULT 0,
    org_visible INTEGER NOT NULL DEFAULT 1,
    org_enabled INTEGER NOT NULL DEFAULT 1,
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_note_types_type_uuid ON note_types(type_uuid);
CREATE INDEX IF NOT EXISTS idx_note_types_active_org ON note_types(is_active, org_visible, org_enabled);

-- Seed System Default Note Types (PD-007)
INSERT OR IGNORE INTO note_types (type_uuid, name, description, display_order, is_active, is_system, org_visible, org_enabled)
VALUES
('nt_general', 'General Note', 'General operational and constituent notes', 10, 1, 1, 1, 1),
('nt_academic', 'Academic Note', 'Academic progress, study goals, and pathway notes', 20, 1, 1, 1, 1),
('nt_behavioral', 'Behavioral Note', 'Conduct, attendance, and center policy observations', 30, 1, 1, 1, 1),
('nt_pastoral', 'Pastoral Care Note', 'Discipleship, prayer requests, and care notes', 40, 1, 1, 1, 1);

-- 2. Person Notes Table
CREATE TABLE IF NOT EXISTS person_notes (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    note_uuid TEXT NOT NULL UNIQUE,
    person_id INTEGER NOT NULL REFERENCES people(id) ON DELETE CASCADE,
    person_uuid TEXT NOT NULL,
    note_type_uuid TEXT NOT NULL REFERENCES note_types(type_uuid),
    title TEXT,
    body TEXT NOT NULL,
    visibility TEXT NOT NULL DEFAULT 'standard_staff',
    is_pinned INTEGER NOT NULL DEFAULT 0,
    is_deleted INTEGER NOT NULL DEFAULT 0,
    author_uuid TEXT,
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_person_notes_person_uuid ON person_notes(person_uuid);
CREATE INDEX IF NOT EXISTS idx_person_notes_type_uuid ON person_notes(note_type_uuid);
CREATE INDEX IF NOT EXISTS idx_person_notes_created ON person_notes(created_at);

-- 3. Data Preservation Migration: Import legacy people.notes into person_notes
INSERT OR IGNORE INTO person_notes (note_uuid, person_id, person_uuid, note_type_uuid, title, body, created_at, updated_at)
SELECT
  'note_migrated_' || p.person_uuid,
  p.id,
  p.person_uuid,
  'nt_general',
  'General Note',
  p.notes,
  p.created_at,
  p.updated_at
FROM people p
WHERE p.notes IS NOT NULL AND TRIM(p.notes) != '';
