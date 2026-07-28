-- Migration 0030: Add claimed_at, claimed_by, and status_detail columns to scheduled_communications table
ALTER TABLE scheduled_communications ADD COLUMN claimed_at TEXT DEFAULT NULL;
ALTER TABLE scheduled_communications ADD COLUMN claimed_by TEXT DEFAULT NULL;
ALTER TABLE scheduled_communications ADD COLUMN status_detail TEXT DEFAULT NULL;
