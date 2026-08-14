-- Migration: 0052_add_session_public_signup_columns.sql
-- Description: Adds public signup, waitlist, and registration window control columns to sessions table.

ALTER TABLE sessions ADD COLUMN public_signup_enabled INTEGER NOT NULL DEFAULT 1;
ALTER TABLE sessions ADD COLUMN waitlist_enabled INTEGER NOT NULL DEFAULT 1;
ALTER TABLE sessions ADD COLUMN max_waitlist INTEGER DEFAULT NULL;
ALTER TABLE sessions ADD COLUMN registration_open_at TEXT DEFAULT NULL;
ALTER TABLE sessions ADD COLUMN registration_close_at TEXT DEFAULT NULL;
