-- Migration 0012: Deep Scheduling & Sessions Subsystem (Parity with Legacy Sessions.jsx)
-- Complies with [PD-001] (Offline Storage) and [PD-008] (Warm & Welcoming Design System)

CREATE TABLE IF NOT EXISTS center_open_hours (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    day_of_week TEXT UNIQUE NOT NULL,
    open_time TEXT NOT NULL DEFAULT '03:00 PM',
    close_time TEXT NOT NULL DEFAULT '08:00 PM',
    is_closed INTEGER NOT NULL DEFAULT 0
);

-- Seed Default Open Hours
INSERT OR IGNORE INTO center_open_hours (day_of_week, open_time, close_time, is_closed) VALUES ('Monday', '03:00 PM', '08:00 PM', 0);
INSERT OR IGNORE INTO center_open_hours (day_of_week, open_time, close_time, is_closed) VALUES ('Tuesday', '03:00 PM', '08:00 PM', 0);
INSERT OR IGNORE INTO center_open_hours (day_of_week, open_time, close_time, is_closed) VALUES ('Wednesday', '03:00 PM', '08:00 PM', 0);
INSERT OR IGNORE INTO center_open_hours (day_of_week, open_time, close_time, is_closed) VALUES ('Thursday', '03:00 PM', '08:00 PM', 0);
INSERT OR IGNORE INTO center_open_hours (day_of_week, open_time, close_time, is_closed) VALUES ('Friday', '03:00 PM', '06:00 PM', 0);
INSERT OR IGNORE INTO center_open_hours (day_of_week, open_time, close_time, is_closed) VALUES ('Saturday', '10:00 AM', '04:00 PM', 0);
INSERT OR IGNORE INTO center_open_hours (day_of_week, open_time, close_time, is_closed) VALUES ('Sunday', '12:00 PM', '05:00 PM', 1);

-- Session Pre-Registration Signups Table
CREATE TABLE IF NOT EXISTS session_signups (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    signup_uuid TEXT UNIQUE NOT NULL,
    session_id INTEGER NOT NULL,
    person_id INTEGER NOT NULL,
    signup_status TEXT NOT NULL DEFAULT 'registered', -- registered, attended, waitlisted, cancelled
    registered_at TEXT NOT NULL DEFAULT (datetime('now')),
    FOREIGN KEY(session_id) REFERENCES sessions(id) ON DELETE CASCADE,
    FOREIGN KEY(person_id) REFERENCES people(id) ON DELETE CASCADE
);

-- Session Operational Notes & Visitor Audit Table
CREATE TABLE IF NOT EXISTS session_notes_history (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    session_id INTEGER NOT NULL,
    author_user TEXT NOT NULL DEFAULT 'John Smith',
    visitor_count INTEGER NOT NULL DEFAULT 0,
    notes_body TEXT NOT NULL,
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    FOREIGN KEY(session_id) REFERENCES sessions(id) ON DELETE CASCADE
);
