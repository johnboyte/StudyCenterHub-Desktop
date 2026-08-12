-- Migration 0042: Phase A Messaging & Event Outbox Queue Extensions
PRAGMA foreign_keys = ON;

-- 1. Expand event_inbox for status tracking & failure recovery
ALTER TABLE event_inbox ADD COLUMN status TEXT NOT NULL DEFAULT 'pending';
ALTER TABLE event_inbox ADD COLUMN retry_count INTEGER NOT NULL DEFAULT 0;
ALTER TABLE event_inbox ADD COLUMN error_message TEXT;

CREATE INDEX IF NOT EXISTS idx_event_inbox_status ON event_inbox(status);

-- 2. Expand communications_log delivery status tracking
ALTER TABLE communications_log ADD COLUMN delivery_status TEXT NOT NULL DEFAULT 'delivered';
ALTER TABLE communications_log ADD COLUMN error_code TEXT;

CREATE INDEX IF NOT EXISTS idx_communications_log_delivery ON communications_log(delivery_status);
