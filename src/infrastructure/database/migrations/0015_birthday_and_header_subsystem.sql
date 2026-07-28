-- Migration 0015: Shared Header Subtitles, Personalized Messages, and Birthday Recognition Subsystem
-- Complies with [PD-001] (Offline Storage & Outbox) and [PD-008] (Warm & Welcoming Design System)

-- Add birth_month and birth_day to people table if not present
ALTER TABLE people ADD COLUMN birth_month INTEGER DEFAULT NULL;
ALTER TABLE people ADD COLUMN birth_day INTEGER DEFAULT NULL;

-- Organization-Wide Page Header Messages Table
CREATE TABLE IF NOT EXISTS organization_page_header_messages (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    page_key TEXT UNIQUE NOT NULL,
    message TEXT NOT NULL,
    updated_by TEXT DEFAULT 'Administrator',
    updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);

-- User-Specific Page Header Message Overrides Table
CREATE TABLE IF NOT EXISTS user_page_header_messages (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id INTEGER NOT NULL,
    page_key TEXT NOT NULL,
    message TEXT NOT NULL,
    updated_by TEXT DEFAULT 'Administrator',
    updated_at TEXT NOT NULL DEFAULT (datetime('now')),
    UNIQUE(user_id, page_key)
);

-- Header Messages Audit Log Table
CREATE TABLE IF NOT EXISTS header_messages_audit_log (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    target_type TEXT NOT NULL, -- 'organization' or 'user'
    target_user_id INTEGER,
    page_key TEXT NOT NULL,
    old_message TEXT,
    new_message TEXT,
    changed_by TEXT NOT NULL DEFAULT 'Administrator',
    changed_at TEXT NOT NULL DEFAULT (datetime('now'))
);

-- Birthday Notification & Deduplication Log Table
CREATE TABLE IF NOT EXISTS birthday_notification_log (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    person_id INTEGER NOT NULL,
    birthday_year INTEGER NOT NULL,
    notification_type TEXT NOT NULL, -- 'birthday_today' or 'last_open_day_before_birthday'
    triggering_check_in_id INTEGER,
    triggered_at TEXT NOT NULL DEFAULT (datetime('now')),
    triggered_by_user_id INTEGER,
    on_screen_alert_acknowledged_at TEXT,
    acknowledged_by_user_id INTEGER,
    sms_attempted_at TEXT,
    sms_recipient_count INTEGER DEFAULT 0,
    sms_success_count INTEGER DEFAULT 0,
    sms_failure_count INTEGER DEFAULT 0,
    status TEXT NOT NULL DEFAULT 'completed',
    error_summary TEXT
);

-- Seed Default Organization Page Header Messages
INSERT OR IGNORE INTO organization_page_header_messages (page_key, message) VALUES ('home', 'Here’s what’s happening at StudyCenter today.');
INSERT OR IGNORE INTO organization_page_header_messages (page_key, message) VALUES ('people', 'Find, update, and manage constituent records.');
INSERT OR IGNORE INTO organization_page_header_messages (page_key, message) VALUES ('communications', 'Create, schedule, and review messages.');
INSERT OR IGNORE INTO organization_page_header_messages (page_key, message) VALUES ('attendance', 'Scan badges, find people, and record attendance.');
INSERT OR IGNORE INTO organization_page_header_messages (page_key, message) VALUES ('schedules', 'Coordinate staffing, sessions, volunteers, and operating hours.');
INSERT OR IGNORE INTO organization_page_header_messages (page_key, message) VALUES ('volunteers', 'Manage volunteer availability, assignments, and service.');
INSERT OR IGNORE INTO organization_page_header_messages (page_key, message) VALUES ('pathways', 'Review participant progress, follow-up, and next steps.');
INSERT OR IGNORE INTO organization_page_header_messages (page_key, message) VALUES ('administration', 'Manage users, permissions, integrations, and organization settings.');
INSERT OR IGNORE INTO organization_page_header_messages (page_key, message) VALUES ('reports', 'Review attendance, engagement, and ministry activity.');
INSERT OR IGNORE INTO organization_page_header_messages (page_key, message) VALUES ('settings', 'Customize your StudyCenter experience and preferences.');
