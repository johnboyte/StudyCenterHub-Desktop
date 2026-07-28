-- Migration 0035: Session Staffing Requirement & Dedicated Session Staff Reference
-- Complies with [PD-001] (Offline Storage & Outbox) and [PD-008] (Warm & Welcoming Design System)

ALTER TABLE sessions ADD COLUMN staffing_requirement TEXT NOT NULL DEFAULT 'DEDICATED_SESSION_STAFF';
ALTER TABLE schedule_entries ADD COLUMN session_id INTEGER REFERENCES sessions(id) ON DELETE SET NULL;

UPDATE sessions SET staffing_requirement = 'DEDICATED_SESSION_STAFF' WHERE staffing_requirement IS NULL OR staffing_requirement = '';
