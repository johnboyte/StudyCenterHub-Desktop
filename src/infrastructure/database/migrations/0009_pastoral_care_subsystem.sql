-- Migration 0009: Pastoral Care & Sensitive Notes Subsystem (PAST-SPR1-001)
-- Complies with [PD-001] (Offline Storage) and [PD-009] (Role-Based Access Control)

CREATE TABLE IF NOT EXISTS pastoral_notes (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    note_uuid TEXT UNIQUE NOT NULL,
    person_id INTEGER NOT NULL,
    author_user TEXT NOT NULL DEFAULT 'Pastor John',
    note_type TEXT NOT NULL DEFAULT 'Pastoral Care',
    body TEXT NOT NULL,
    sensitivity_level TEXT NOT NULL DEFAULT 'High',
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    FOREIGN KEY(person_id) REFERENCES people(id) ON DELETE CASCADE
);

-- Seed sample pastoral note
INSERT OR IGNORE INTO pastoral_notes (note_uuid, person_id, author_user, note_type, body, sensitivity_level)
SELECT 'pnote_seed_001', id, 'Pastor John', 'Pastoral Care', 'Met for monthly discipleship check-in. Family doing well.', 'High'
FROM people WHERE person_uuid = 'usr_david';
