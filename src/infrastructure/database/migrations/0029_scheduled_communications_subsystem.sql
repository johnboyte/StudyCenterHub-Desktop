-- Migration 0029: Add scheduled_communications table and communications_log status/attachment extensions
CREATE TABLE IF NOT EXISTS scheduled_communications (
	id INTEGER PRIMARY KEY AUTOINCREMENT,
	schedule_uuid TEXT UNIQUE NOT NULL,
	session_id INTEGER,
	audience TEXT NOT NULL,
	channel TEXT NOT NULL DEFAULT 'SMS',
	subject TEXT,
	message_body TEXT NOT NULL,
	attachment_path TEXT,
	scheduled_time_utc TEXT NOT NULL,
	scheduled_time_local TEXT NOT NULL,
	status TEXT NOT NULL DEFAULT 'scheduled',
	created_by TEXT NOT NULL DEFAULT 'John Smith',
	created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

ALTER TABLE communications_log ADD COLUMN provider_sid TEXT DEFAULT NULL;
ALTER TABLE communications_log ADD COLUMN attachment_path TEXT DEFAULT NULL;
ALTER TABLE communications_log ADD COLUMN status_detail TEXT DEFAULT NULL;
ALTER TABLE communications_log ADD COLUMN scheduled_at TEXT DEFAULT NULL;
