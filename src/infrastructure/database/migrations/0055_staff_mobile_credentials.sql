-- Migration 0055: Dedicated Staff Mobile Authentication Credentials Subsystem
-- Creates a dedicated, secure credential storage for staff mobile access
-- using PBKDF2/bcrypt salted slow password hashes and credential versions.

CREATE TABLE IF NOT EXISTS staff_mobile_credentials (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    person_id INTEGER NOT NULL UNIQUE REFERENCES people(id) ON DELETE CASCADE,
    human_id TEXT NOT NULL UNIQUE,
    pin_pbkdf_hash TEXT NOT NULL,
    credential_version INTEGER NOT NULL DEFAULT 1,
    mobile_access_enabled INTEGER NOT NULL DEFAULT 1,
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_staff_mobile_credentials_person ON staff_mobile_credentials(person_id);
CREATE INDEX IF NOT EXISTS idx_staff_mobile_credentials_human_id ON staff_mobile_credentials(human_id);
