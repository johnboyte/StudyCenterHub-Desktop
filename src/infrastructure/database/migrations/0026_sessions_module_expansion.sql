-- Migration 0026: Sessions Module Architecture Expansion
-- Complies with [PD-001] (Offline Storage) and [PD-007] (Admin Configuration First)

-- 1. Session Types Configuration Table
CREATE TABLE IF NOT EXISTS session_types (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    type_key TEXT UNIQUE NOT NULL,
    name TEXT NOT NULL,
    description TEXT,
    display_order INTEGER NOT NULL DEFAULT 1,
    is_active INTEGER NOT NULL DEFAULT 1,
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

-- Seed Default Session Types
INSERT OR IGNORE INTO session_types (type_key, name, description, display_order) VALUES ('reservation', 'Reservation', 'Room or space reservation', 1);
INSERT OR IGNORE INTO session_types (type_key, name, description, display_order) VALUES ('bible_study', 'Bible Study & Fellowship', 'Spiritual growth and fellowship session', 2);
INSERT OR IGNORE INTO session_types (type_key, name, description, display_order) VALUES ('fellows', 'Real Life Fellows', 'Leadership and mentorship session', 3);
INSERT OR IGNORE INTO session_types (type_key, name, description, display_order) VALUES ('leadership', 'Leadership', 'Staff and leader planning session', 4);
INSERT OR IGNORE INTO session_types (type_key, name, description, display_order) VALUES ('special_event', 'Special Event', 'Center-wide special event or workshop', 5);
INSERT OR IGNORE INTO session_types (type_key, name, description, display_order) VALUES ('other', 'Other', 'General study or uncategorized session', 6);

-- 2. Session Locations Configuration Table
CREATE TABLE IF NOT EXISTS session_locations (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    location_key TEXT UNIQUE NOT NULL,
    name TEXT NOT NULL,
    capacity INTEGER,
    is_exclusive INTEGER NOT NULL DEFAULT 0,
    display_order INTEGER NOT NULL DEFAULT 1,
    is_active INTEGER NOT NULL DEFAULT 1,
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

-- Seed Default Locations (Capacity NULL by default to separate room bounds from session limit)
INSERT OR IGNORE INTO session_locations (location_key, name, is_exclusive, display_order) VALUES ('gathering_room', 'Gathering Room', 0, 1);
INSERT OR IGNORE INTO session_locations (location_key, name, is_exclusive, display_order) VALUES ('kitchen', 'Kitchen', 0, 2);
INSERT OR IGNORE INTO session_locations (location_key, name, is_exclusive, display_order) VALUES ('study_room_1', 'Study Room #1', 0, 3);
INSERT OR IGNORE INTO session_locations (location_key, name, is_exclusive, display_order) VALUES ('study_room_2', 'Study Room #2', 0, 4);
INSERT OR IGNORE INTO session_locations (location_key, name, is_exclusive, display_order) VALUES ('study_room_3', 'Study Room #3', 0, 5);
INSERT OR IGNORE INTO session_locations (location_key, name, is_exclusive, display_order) VALUES ('the_study', 'The Study', 0, 6);
INSERT OR IGNORE INTO session_locations (location_key, name, is_exclusive, display_order) VALUES ('back_porch', 'The Back Porch', 0, 7);
INSERT OR IGNORE INTO session_locations (location_key, name, is_exclusive, display_order) VALUES ('front_porch_1', 'The Front Porch Area #1', 0, 8);
INSERT OR IGNORE INTO session_locations (location_key, name, is_exclusive, display_order) VALUES ('front_porch_2', 'The Front Porch Area #2', 0, 9);
INSERT OR IGNORE INTO session_locations (location_key, name, is_exclusive, display_order) VALUES ('front_porch_3', 'The Front Porch Area #3', 0, 10);
INSERT OR IGNORE INTO session_locations (location_key, name, is_exclusive, display_order) VALUES ('whole_center', 'Whole Center', 1, 11);

-- 3. Session Multi-Location Junction Table
CREATE TABLE IF NOT EXISTS session_location_assignments (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    session_id INTEGER NOT NULL,
    location_id INTEGER NOT NULL,
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    FOREIGN KEY(session_id) REFERENCES sessions(id) ON DELETE CASCADE,
    FOREIGN KEY(location_id) REFERENCES session_locations(id) ON DELETE CASCADE,
    UNIQUE(session_id, location_id)
);
CREATE INDEX IF NOT EXISTS idx_sess_loc_assg_sess ON session_location_assignments(session_id);
CREATE INDEX IF NOT EXISTS idx_sess_loc_assg_loc ON session_location_assignments(location_id);

-- 4. Session Entity Expansion
ALTER TABLE sessions ADD COLUMN session_uuid TEXT;
ALTER TABLE sessions ADD COLUMN session_type_id INTEGER REFERENCES session_types(id);
ALTER TABLE sessions ADD COLUMN description TEXT;
ALTER TABLE sessions ADD COLUMN signup_required INTEGER NOT NULL DEFAULT 1;
ALTER TABLE sessions ADD COLUMN limit_signups INTEGER NOT NULL DEFAULT 1;
ALTER TABLE sessions ADD COLUMN leader_person_id INTEGER;
ALTER TABLE sessions ADD COLUMN term_override TEXT;
ALTER TABLE sessions ADD COLUMN type_override TEXT;
ALTER TABLE sessions ADD COLUMN notes TEXT;
ALTER TABLE sessions ADD COLUMN updated_at TEXT;

-- Generate session_uuid for pre-existing sessions missing a UUID
UPDATE sessions SET session_uuid = 'sess_' || hex(randomblob(4)) || '-' || hex(randomblob(2)) || '-' || hex(randomblob(2)) WHERE session_uuid IS NULL OR session_uuid = '';

-- Deterministic Backfill of session_type_id for Known Legacy Types
UPDATE sessions SET session_type_id = (SELECT id FROM session_types WHERE type_key = 'bible_study') WHERE session_type_id IS NULL AND (session_type = 'Bible Study' OR session_type = 'Bible Study & Fellowship');
UPDATE sessions SET session_type_id = (SELECT id FROM session_types WHERE type_key = 'fellows') WHERE session_type_id IS NULL AND session_type = 'Real Life Fellows';
UPDATE sessions SET session_type_id = (SELECT id FROM session_types WHERE type_key = 'leadership') WHERE session_type_id IS NULL AND session_type = 'Leadership';
UPDATE sessions SET session_type_id = (SELECT id FROM session_types WHERE type_key = 'reservation') WHERE session_type_id IS NULL AND session_type = 'Reservation';
UPDATE sessions SET session_type_id = (SELECT id FROM session_types WHERE type_key = 'special_event') WHERE session_type_id IS NULL AND session_type = 'Special Event';

-- For any UNMATCHED legacy Session Type string, create an inactive migrated session_types record to preserve exact text
INSERT OR IGNORE INTO session_types (type_key, name, description, display_order, is_active)
SELECT DISTINCT 
    'migrated_' || lower(replace(session_type, ' ', '_')), 
    session_type, 
    'Migrated Legacy Session Type', 
    99, 
    0 
FROM sessions 
WHERE session_type_id IS NULL AND session_type IS NOT NULL AND session_type != '' AND session_type != 'General Study' AND session_type != 'Other';

-- Link sessions with newly created migrated session types
UPDATE sessions SET session_type_id = (SELECT id FROM session_types WHERE session_types.name = sessions.session_type LIMIT 1) WHERE session_type_id IS NULL AND session_type IS NOT NULL;

-- Final Fallback for remaining NULLs to 'other'
UPDATE sessions SET session_type_id = (SELECT id FROM session_types WHERE type_key = 'other') WHERE session_type_id IS NULL;

CREATE UNIQUE INDEX IF NOT EXISTS idx_sessions_session_uuid ON sessions(session_uuid);
CREATE INDEX IF NOT EXISTS idx_sessions_type_id ON sessions(session_type_id);

-- Backfill session_location_assignments for known matching locations
INSERT OR IGNORE INTO session_location_assignments (session_id, location_id)
SELECT s.id, sl.id FROM sessions s JOIN session_locations sl ON sl.name = s.room_location OR sl.location_key = lower(replace(s.room_location, ' ', '_')) WHERE s.room_location IS NOT NULL AND s.room_location != '';

-- For any UNMATCHED legacy room_location text (e.g. 'Fellowship Hall'), create an inactive migrated location record so data is never lost
INSERT OR IGNORE INTO session_locations (location_key, name, is_exclusive, display_order, is_active)
SELECT DISTINCT 
    'migrated_' || lower(replace(s.room_location, ' ', '_')), 
    s.room_location, 
    0, 
    99, 
    0 
FROM sessions s
LEFT JOIN session_location_assignments sla ON sla.session_id = s.id
WHERE sla.id IS NULL AND s.room_location IS NOT NULL AND s.room_location != '';

-- Link sessions to newly created migrated location records
INSERT OR IGNORE INTO session_location_assignments (session_id, location_id)
SELECT s.id, sl.id FROM sessions s JOIN session_locations sl ON sl.name = s.room_location WHERE s.room_location IS NOT NULL AND s.room_location != '';

-- 5. Session Signups Expansion & Legacy Status Migration
ALTER TABLE session_signups ADD COLUMN position INTEGER NOT NULL DEFAULT 1;
ALTER TABLE session_signups ADD COLUMN promoted_at TEXT;
ALTER TABLE session_signups ADD COLUMN promoted_by TEXT;
ALTER TABLE session_signups ADD COLUMN auto_promoted INTEGER NOT NULL DEFAULT 0;
ALTER TABLE session_signups ADD COLUMN removed_at TEXT;
ALTER TABLE session_signups ADD COLUMN removed_by TEXT;
ALTER TABLE session_signups ADD COLUMN removal_reason TEXT;

-- Map legacy signup_status values to canonical statuses ('confirmed', 'waitlist', 'removed')
UPDATE session_signups SET signup_status = 'confirmed' WHERE signup_status = 'registered';
UPDATE session_signups SET signup_status = 'waitlist' WHERE signup_status = 'waiting';

CREATE UNIQUE INDEX IF NOT EXISTS idx_session_signups_uuid ON session_signups(signup_uuid);
CREATE INDEX IF NOT EXISTS idx_session_signups_sess_stat ON session_signups(session_id, signup_status);
CREATE INDEX IF NOT EXISTS idx_session_signups_person ON session_signups(person_id);

-- 6. Operation-Level Idempotency Log
CREATE TABLE IF NOT EXISTS operation_idempotency_log (
    operation_uuid TEXT PRIMARY KEY,
    operation_type TEXT NOT NULL,
    session_id INTEGER NOT NULL,
    result_json TEXT NOT NULL,
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

-- 7. Session Audit & Lifecycle History
CREATE TABLE IF NOT EXISTS session_audit_log (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    session_id INTEGER NOT NULL,
    person_id INTEGER,
    action TEXT NOT NULL,
    actor_id TEXT,
    actor TEXT NOT NULL DEFAULT 'System',
    detail_json TEXT,
    timestamp TEXT NOT NULL DEFAULT (datetime('now')),
    FOREIGN KEY(session_id) REFERENCES sessions(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_session_audit_sess ON session_audit_log(session_id);
CREATE INDEX IF NOT EXISTS idx_session_audit_person ON session_audit_log(person_id);
