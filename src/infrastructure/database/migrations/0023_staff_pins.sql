-- Migration 0023: Staff PINs for voicemail privacy
-- Adds a simple PIN system so staff can protect their assigned voicemails.

CREATE TABLE IF NOT EXISTS staff_pins (
    display_name TEXT PRIMARY KEY,
    pin_hash TEXT NOT NULL,
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);
