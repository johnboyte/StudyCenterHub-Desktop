-- Migration 0014: Separation of Staff Shift Schedule & Student Sessions
-- Complies with [PD-001] (Offline Storage) and [PD-008] (Warm & Welcoming Design System)

CREATE TABLE IF NOT EXISTS schedule_entries (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    entry_uuid TEXT UNIQUE NOT NULL,
    person_name TEXT NOT NULL,
    person_id INTEGER,
    shift_role TEXT NOT NULL DEFAULT 'Shift Supervisor',
    shift_date TEXT NOT NULL,
    start_time TEXT NOT NULL DEFAULT '03:00 PM',
    end_time TEXT NOT NULL DEFAULT '08:00 PM',
    area TEXT NOT NULL DEFAULT 'Gathering Room',
    notes TEXT,
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    FOREIGN KEY(person_id) REFERENCES people(id) ON DELETE SET NULL
);

-- Seed sample staff shifts for current week
INSERT OR IGNORE INTO schedule_entries (entry_uuid, person_name, shift_role, shift_date, start_time, end_time, area, notes)
VALUES ('sh_seed_001', 'John Smith', 'Shift Supervisor', date('now'), '03:00 PM', '08:00 PM', 'Gathering Room', 'Lead supervisor shift');

INSERT OR IGNORE INTO schedule_entries (entry_uuid, person_name, shift_role, shift_date, start_time, end_time, area, notes)
VALUES ('sh_seed_002', 'Sarah Jenkins', 'Study Tutor', date('now'), '03:30 PM', '06:00 PM', 'Study Room #1', 'Math tutoring shift');
