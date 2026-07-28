-- Migration 0007: Volunteers & Shift Roster Subsystem (VOL-SPR1-001)
-- Complies with [PD-001] (Offline Storage & Outbox) and [PD-008] (Warm & Welcoming Design System)

CREATE TABLE IF NOT EXISTS volunteer_profiles (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    person_id INTEGER UNIQUE NOT NULL,
    background_check_status TEXT NOT NULL DEFAULT 'Verified',
    clearance_date TEXT NOT NULL DEFAULT '2024-01-15',
    primary_role TEXT NOT NULL DEFAULT 'Study Tutor',
    skills_notes TEXT,
    is_active INTEGER NOT NULL DEFAULT 1,
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    FOREIGN KEY(person_id) REFERENCES people(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS volunteer_shifts (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    shift_uuid TEXT UNIQUE NOT NULL,
    session_id INTEGER,
    person_id INTEGER NOT NULL,
    shift_role TEXT NOT NULL DEFAULT 'Lead Tutor',
    status TEXT NOT NULL DEFAULT 'assigned',
    assigned_at TEXT NOT NULL DEFAULT (datetime('now')),
    FOREIGN KEY(session_id) REFERENCES sessions(id) ON DELETE SET NULL,
    FOREIGN KEY(person_id) REFERENCES people(id) ON DELETE CASCADE
);
