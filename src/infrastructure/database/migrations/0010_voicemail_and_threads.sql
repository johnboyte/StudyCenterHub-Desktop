-- Migration 0010: Voicemail Inbox & 2-Way Threaded Messages (COM-SPR1-002)
-- Complies with [PD-001] (Offline Storage) and [PD-008] (Warm & Welcoming Design System)

CREATE TABLE IF NOT EXISTS voicemails (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    voicemail_uuid TEXT UNIQUE NOT NULL,
    caller_name TEXT NOT NULL,
    caller_phone TEXT NOT NULL,
    duration_sec INTEGER NOT NULL DEFAULT 30,
    recording_url TEXT,
    transcription TEXT,
    status TEXT NOT NULL DEFAULT 'new',
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

-- Seed sample incoming voicemail
INSERT OR IGNORE INTO voicemails (voicemail_uuid, caller_name, caller_phone, duration_sec, transcription, status)
VALUES ('vm_seed_001', 'Sarah Jenkins', '555-0199', 42, 'Hi, I am calling to confirm if the Fellowship Hall study group is meeting tonight at 6pm.', 'new');
