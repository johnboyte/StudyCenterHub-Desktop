-- Phase 2.1 Checkpoint 1A - Initial Schema Migration (Corrected)
PRAGMA journal_mode = WAL;
PRAGMA foreign_keys = ON;

-- Schema Migrations Table
CREATE TABLE IF NOT EXISTS schema_migrations (
    version TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    executed_at TEXT NOT NULL DEFAULT (datetime('now'))
);

-- Device Identity Table (Local Device Registration with Stable Device UUID)
CREATE TABLE IF NOT EXISTS device_identity (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    device_uuid TEXT NOT NULL UNIQUE,
    device_name TEXT NOT NULL,
    device_type TEXT NOT NULL DEFAULT 'desktop',
    registered_at TEXT NOT NULL DEFAULT (datetime('now'))
);

-- People Directory Table (with Stable Internal Person UUID and Customer-Visible Human ID)
CREATE TABLE IF NOT EXISTS people (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    person_uuid TEXT NOT NULL UNIQUE,
    human_id TEXT NOT NULL UNIQUE,
    first_name TEXT NOT NULL,
    last_name TEXT NOT NULL,
    phone TEXT,
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_people_person_uuid ON people(person_uuid);
CREATE INDEX IF NOT EXISTS idx_people_human_id ON people(human_id);

-- Attendance Log Table
CREATE TABLE IF NOT EXISTS attendance_log (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    checkin_uuid TEXT NOT NULL UNIQUE,
    person_id INTEGER NOT NULL REFERENCES people(id) ON DELETE CASCADE,
    person_uuid TEXT NOT NULL,
    human_id TEXT NOT NULL,
    check_in_date TEXT NOT NULL,
    check_in_time TEXT NOT NULL,
    method TEXT NOT NULL DEFAULT 'Manual',
    device_uuid TEXT NOT NULL,
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_attendance_log_person_uuid ON attendance_log(person_uuid);
CREATE INDEX IF NOT EXISTS idx_attendance_log_human_id ON attendance_log(human_id);
CREATE INDEX IF NOT EXISTS idx_attendance_log_date ON attendance_log(check_in_date);

-- Transactional Event Outbox Table
CREATE TABLE IF NOT EXISTS event_outbox (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    event_uuid TEXT NOT NULL UNIQUE,
    event_type TEXT NOT NULL,
    aggregate_type TEXT NOT NULL,
    aggregate_id TEXT NOT NULL,
    payload_json TEXT NOT NULL,
    device_uuid TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'pending',
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    processed_at TEXT
);

CREATE INDEX IF NOT EXISTS idx_event_outbox_status ON event_outbox(status);
