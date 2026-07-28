-- Migration 0017: Public Registration & Credential Verification Subsystem Tables

-- Add missing legacy columns to people table
ALTER TABLE people ADD COLUMN profile_photo TEXT;
ALTER TABLE people ADD COLUMN flag_notes TEXT;
ALTER TABLE people ADD COLUMN qr_code_value TEXT;
ALTER TABLE people ADD COLUMN sms_consent_at TEXT;
ALTER TABLE people ADD COLUMN sms_consent_source TEXT;
ALTER TABLE people ADD COLUMN sms_consent_version TEXT;

-- Create participant QR credential lifecycle table
CREATE TABLE IF NOT EXISTS participant_qr_credentials (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    credential_id TEXT NOT NULL UNIQUE,
    person_id INTEGER NOT NULL REFERENCES people(id) ON DELETE CASCADE,
    token_hash TEXT NOT NULL UNIQUE,
    token_hint TEXT,
    status TEXT NOT NULL DEFAULT 'active',
    issued_at TEXT NOT NULL DEFAULT (datetime('now')),
    issued_by TEXT,
    revoked_at TEXT,
    revoked_by TEXT,
    revoke_reason TEXT,
    replaced_by_credential_id TEXT,
    metadata_json TEXT
);

CREATE INDEX IF NOT EXISTS idx_participant_qr_credentials_person ON participant_qr_credentials(person_id);
CREATE INDEX IF NOT EXISTS idx_participant_qr_credentials_status ON participant_qr_credentials(status);
CREATE UNIQUE INDEX IF NOT EXISTS idx_participant_qr_credentials_active_person
    ON participant_qr_credentials(person_id)
    WHERE LOWER(status) = 'active';

-- Create participant PIN credential lifecycle table
CREATE TABLE IF NOT EXISTS participant_pin_credentials (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    credential_id TEXT NOT NULL UNIQUE,
    person_id INTEGER NOT NULL REFERENCES people(id) ON DELETE CASCADE,
    pin_hash TEXT NOT NULL,
    hash_algo TEXT NOT NULL DEFAULT 'scrypt',
    hash_params TEXT,
    status TEXT NOT NULL DEFAULT 'active',
    failed_attempts INTEGER NOT NULL DEFAULT 0,
    locked_until TEXT,
    issued_at TEXT NOT NULL DEFAULT (datetime('now')),
    issued_by TEXT,
    reset_at TEXT,
    reset_by TEXT,
    reset_reason TEXT,
    last_verified_at TEXT,
    metadata_json TEXT
);

CREATE INDEX IF NOT EXISTS idx_participant_pin_credentials_person ON participant_pin_credentials(person_id);
CREATE INDEX IF NOT EXISTS idx_participant_pin_credentials_status ON participant_pin_credentials(status);
CREATE UNIQUE INDEX IF NOT EXISTS idx_participant_pin_credentials_active_person
    ON participant_pin_credentials(person_id)
    WHERE LOWER(status) = 'active';

-- Create short-lived verification sessions table
CREATE TABLE IF NOT EXISTS participant_verification_sessions (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    session_id TEXT NOT NULL UNIQUE,
    person_id INTEGER NOT NULL REFERENCES people(id) ON DELETE CASCADE,
    method TEXT NOT NULL,
    token_hash TEXT NOT NULL UNIQUE,
    issued_at TEXT NOT NULL DEFAULT (datetime('now')),
    expires_at TEXT NOT NULL,
    consumed_at TEXT,
    revoked_at TEXT,
    revoked_reason TEXT,
    metadata_json TEXT
);

CREATE INDEX IF NOT EXISTS idx_participant_verification_sessions_person ON participant_verification_sessions(person_id);
CREATE INDEX IF NOT EXISTS idx_participant_verification_sessions_expiry ON participant_verification_sessions(expires_at);

-- Create verification and credential lifecycle audit history table
CREATE TABLE IF NOT EXISTS participant_verification_audit (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    occurred_at TEXT NOT NULL DEFAULT (datetime('now')),
    person_id INTEGER REFERENCES people(id) ON DELETE SET NULL,
    participant_id TEXT,
    method TEXT,
    action TEXT NOT NULL,
    success INTEGER NOT NULL DEFAULT 0,
    actor TEXT,
    source TEXT,
    ip_address TEXT,
    user_agent TEXT,
    detail TEXT
);

CREATE INDEX IF NOT EXISTS idx_participant_verification_audit_person ON participant_verification_audit(person_id);
CREATE INDEX IF NOT EXISTS idx_participant_verification_audit_occurred_at ON participant_verification_audit(occurred_at);
