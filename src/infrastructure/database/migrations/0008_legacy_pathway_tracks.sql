-- Migration 0008: Legacy Pathway Tracks (Real Life, Fellows, LEAD)
-- Complies with [PD-001] (Offline Storage) and [PD-007] (Admin Configuration First)

CREATE TABLE IF NOT EXISTS legacy_pathway_tracks (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    person_id INTEGER NOT NULL UNIQUE,
    real_life_enrolled INTEGER NOT NULL DEFAULT 0,
    fellows_enrolled INTEGER NOT NULL DEFAULT 0,
    fellows_certificate INTEGER NOT NULL DEFAULT 0,
    fellows_completions TEXT NOT NULL DEFAULT '[]',
    lead_enrolled INTEGER NOT NULL DEFAULT 0,
    lead_certificate INTEGER NOT NULL DEFAULT 0,
    lead_current_year TEXT NOT NULL DEFAULT 'Year 1',
    updated_at TEXT NOT NULL DEFAULT (datetime('now')),
    FOREIGN KEY(person_id) REFERENCES people(id) ON DELETE CASCADE
);

-- Seed sample legacy pathway enrollments
INSERT OR IGNORE INTO legacy_pathway_tracks (person_id, real_life_enrolled, fellows_enrolled, fellows_certificate, fellows_completions, lead_enrolled, lead_certificate, lead_current_year)
SELECT id, 1, 1, 0, 'Year 1 Foundations, Leadership Orientation', 1, 0, 'Year 2'
FROM people WHERE person_uuid = 'usr_david';
