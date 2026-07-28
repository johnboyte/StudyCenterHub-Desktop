-- Migration 0011: Supervisor Shift Briefings & Operational Logs (ATT-SPR1-002)
-- Complies with [PD-001] (Offline Storage) and [PD-008] (Warm & Welcoming Design System)

CREATE TABLE IF NOT EXISTS shift_briefings (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    briefing_uuid TEXT UNIQUE NOT NULL,
    leader_name TEXT NOT NULL DEFAULT 'John Smith',
    shift_date TEXT NOT NULL,
    summary_notes TEXT NOT NULL,
    incident_count INTEGER NOT NULL DEFAULT 0,
    status TEXT NOT NULL DEFAULT 'submitted',
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

-- Seed sample shift briefing
INSERT OR IGNORE INTO shift_briefings (briefing_uuid, leader_name, shift_date, summary_notes, incident_count)
VALUES ('brief_seed_001', 'John Smith', '2026-07-20', 'Great evening session! 45 total check-ins across Fellowship Hall and Youth Room. Zero facility issues.', 0);
