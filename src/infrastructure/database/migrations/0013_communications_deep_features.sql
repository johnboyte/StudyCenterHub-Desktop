-- Migration 0013: Deep Communications Subsystem (Voicemail, 2-Way SMS Threads, Email)
-- Complies with [PD-001] (Offline Storage) and [PD-008] (Warm & Welcoming Design System)

CREATE TABLE IF NOT EXISTS threaded_conversations (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    thread_uuid TEXT UNIQUE NOT NULL,
    person_id INTEGER,
    caller_phone TEXT NOT NULL,
    direction TEXT NOT NULL DEFAULT 'inbound', -- 'inbound' or 'outbound'
    channel TEXT NOT NULL DEFAULT 'SMS', -- 'SMS' or 'Email'
    message_text TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'received',
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    FOREIGN KEY(person_id) REFERENCES people(id) ON DELETE SET NULL
);

-- Seed sample 2-way SMS conversation threads
INSERT OR IGNORE INTO threaded_conversations (thread_uuid, caller_phone, direction, channel, message_text, status)
VALUES ('th_seed_001', '555-0142', 'inbound', 'SMS', 'Hi! Will there be tutoring available after school tomorrow?', 'received');

INSERT OR IGNORE INTO threaded_conversations (thread_uuid, caller_phone, direction, channel, message_text, status)
VALUES ('th_seed_002', '555-0142', 'outbound', 'SMS', 'Yes! Math and Science tutoring will run from 3:30 PM to 5:00 PM in Room 204.', 'sent');
