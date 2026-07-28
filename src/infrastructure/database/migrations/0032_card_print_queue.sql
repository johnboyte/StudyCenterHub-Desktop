-- Migration 0032: Create card_print_queue table for batch membership card printing
CREATE TABLE IF NOT EXISTS card_print_queue (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    queue_uuid TEXT NOT NULL UNIQUE,
    person_id INTEGER NOT NULL,
    person_uuid TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'pending', -- 'pending', 'printed', 'needs_reprint'
    added_at TEXT NOT NULL,
    printed_at TEXT,
    notes TEXT,
    FOREIGN KEY (person_id) REFERENCES people(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_card_print_queue_person ON card_print_queue(person_id);
CREATE INDEX IF NOT EXISTS idx_card_print_queue_status ON card_print_queue(status);
