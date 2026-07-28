-- Migration 0020: Create inbound_sms_log table to keep local SQLite in sync with the gateway server
-- Complies with [PD-001] (Offline Storage)

CREATE TABLE IF NOT EXISTS inbound_sms_log (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    message_sid TEXT UNIQUE,
    from_phone_e164 TEXT,
    to_phone_e164 TEXT,
    raw_body TEXT NOT NULL,
    normalized_keyword TEXT,
    action_taken TEXT,
    source TEXT,
    processing_status TEXT NOT NULL DEFAULT 'processed',
    notes TEXT,
    received_at TEXT NOT NULL DEFAULT (datetime('now')),
    matched_person_id INTEGER REFERENCES people(id) ON DELETE SET NULL,
    assigned_to TEXT,
    follow_up_status TEXT NOT NULL DEFAULT 'Unassigned',
    follow_up_updated_at TEXT,
    follow_up_started_at TEXT,
    follow_up_completed_at TEXT,
    follow_up_reopened_at TEXT,
    is_read INTEGER NOT NULL DEFAULT 0,
    read_at TEXT
);

CREATE INDEX IF NOT EXISTS idx_inbound_sms_log_received_at ON inbound_sms_log(received_at);
CREATE INDEX IF NOT EXISTS idx_inbound_sms_log_is_read ON inbound_sms_log(is_read);
CREATE INDEX IF NOT EXISTS idx_inbound_sms_log_assigned_to ON inbound_sms_log(assigned_to);
CREATE INDEX IF NOT EXISTS idx_inbound_sms_log_follow_up_status ON inbound_sms_log(follow_up_status);
