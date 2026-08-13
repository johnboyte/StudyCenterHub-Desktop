-- Migration 0051: Digital Pass Event & Audit Trail Subsystem

CREATE TABLE IF NOT EXISTS digital_pass_event_log (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    person_id INTEGER NOT NULL REFERENCES people(id) ON DELETE CASCADE,
    credential_id TEXT,
    event_type TEXT NOT NULL,
    delivery_channel TEXT,
    recipient_target TEXT,
    user_agent TEXT,
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_digital_pass_event_log_person ON digital_pass_event_log(person_id);
CREATE INDEX IF NOT EXISTS idx_digital_pass_event_log_type ON digital_pass_event_log(event_type);
