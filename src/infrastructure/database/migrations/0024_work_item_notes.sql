-- Migration 0024: 2-Way Back-and-Forth Work Item Discussion Notes
CREATE TABLE IF NOT EXISTS work_item_notes (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    item_uuid TEXT NOT NULL,
    item_type TEXT NOT NULL DEFAULT 'voicemail',
    author_name TEXT NOT NULL,
    note_text TEXT NOT NULL,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS idx_work_item_notes_uuid ON work_item_notes(item_uuid);
