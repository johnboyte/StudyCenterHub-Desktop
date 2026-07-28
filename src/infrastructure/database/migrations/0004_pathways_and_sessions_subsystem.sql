-- Migration 0004: Pathways & Sessions Subsystem (DIR-SPR1-007)
-- Complies with [PD-001] (Offline Storage) and [PD-007] (Admin Configuration First)

CREATE TABLE IF NOT EXISTS pathways (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    pathway_key TEXT UNIQUE NOT NULL,
    name TEXT NOT NULL,
    description TEXT,
    total_milestones INTEGER NOT NULL DEFAULT 4,
    is_active INTEGER NOT NULL DEFAULT 1,
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS person_pathways (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    person_id INTEGER NOT NULL,
    pathway_id INTEGER NOT NULL,
    current_stage TEXT NOT NULL DEFAULT 'In Progress',
    progress_percent INTEGER NOT NULL DEFAULT 25,
    status TEXT NOT NULL DEFAULT 'active',
    started_at TEXT NOT NULL DEFAULT (datetime('now')),
    completed_at TEXT,
    FOREIGN KEY(person_id) REFERENCES people(id) ON DELETE CASCADE,
    FOREIGN KEY(pathway_id) REFERENCES pathways(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS person_pathway_milestones (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    person_pathway_id INTEGER NOT NULL,
    milestone_name TEXT NOT NULL,
    milestone_order INTEGER NOT NULL DEFAULT 1,
    is_completed INTEGER NOT NULL DEFAULT 0,
    completed_at TEXT,
    FOREIGN KEY(person_pathway_id) REFERENCES person_pathways(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS sessions (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    title TEXT NOT NULL,
    session_type TEXT NOT NULL DEFAULT 'General Study',
    date_text TEXT NOT NULL,
    start_time TEXT NOT NULL,
    end_time TEXT NOT NULL,
    room_location TEXT,
    max_capacity INTEGER NOT NULL DEFAULT 30,
    is_active INTEGER NOT NULL DEFAULT 1,
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS person_sessions (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    person_id INTEGER NOT NULL,
    session_id INTEGER NOT NULL,
    attendance_status TEXT NOT NULL DEFAULT 'registered',
    registered_at TEXT NOT NULL DEFAULT (datetime('now')),
    FOREIGN KEY(person_id) REFERENCES people(id) ON DELETE CASCADE,
    FOREIGN KEY(session_id) REFERENCES sessions(id) ON DELETE CASCADE
);

-- Seed Default Pathways
INSERT OR IGNORE INTO pathways (pathway_key, name, description, total_milestones)
VALUES ('discipleship_track', 'Discipleship Track', 'Core spiritual growth & leadership development pathway', 4);

INSERT OR IGNORE INTO pathways (pathway_key, name, description, total_milestones)
VALUES ('academic_mastery', 'Academic Mastery', 'Subject tutoring & study skills milestone pathway', 3);

-- Seed Default Sessions
INSERT OR IGNORE INTO sessions (title, session_type, date_text, start_time, end_time, room_location, max_capacity)
VALUES ('Bible Study - Adults', 'Bible Study', '2024-05-20', '09:00 AM', '10:30 AM', 'Fellowship Hall', 40);

INSERT OR IGNORE INTO sessions (title, session_type, date_text, start_time, end_time, room_location, max_capacity)
VALUES ('Youth Group Tutoring', 'Tutoring', '2024-05-20', '11:00 AM', '12:30 PM', 'Youth Room', 25);
