-- Migration 0039: Person Pathway Running Notes Subsystem
CREATE TABLE IF NOT EXISTS person_pathway_running_notes (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    uuid TEXT NOT NULL UNIQUE,
    person_pathway_id INTEGER NOT NULL REFERENCES person_pathways(id) ON DELETE CASCADE,
    note_text TEXT NOT NULL,
    author_person_id INTEGER REFERENCES people(id) ON DELETE SET NULL,
    author_name TEXT,
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_pp_running_notes_ppid ON person_pathway_running_notes(person_pathway_id);
