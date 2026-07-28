-- Migration 0027: Taxonomy Audit Log & Explicit Migration Source Metadata
-- Complies with [PD-001] (Offline Storage) and [PD-007] (Admin Configuration First)

-- 1. Add explicit is_migrated column to session_types
ALTER TABLE session_types ADD COLUMN is_migrated INTEGER NOT NULL DEFAULT 0;

-- Mark pre-existing legacy migrated session types
UPDATE session_types SET is_migrated = 1 WHERE type_key LIKE 'migrated_%' OR description LIKE '%Migrated%';

-- 2. Add explicit is_migrated column to session_locations
ALTER TABLE session_locations ADD COLUMN is_migrated INTEGER NOT NULL DEFAULT 0;

-- Mark pre-existing legacy migrated session locations
UPDATE session_locations SET is_migrated = 1 WHERE location_key LIKE 'migrated_%';

-- 3. Dedicated Taxonomy Audit Log Table (Decoupled from session_id audit log)
CREATE TABLE IF NOT EXISTS taxonomy_audit_log (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    entity_type TEXT NOT NULL, -- 'SessionType' or 'SessionLocation'
    entity_id INTEGER NOT NULL,
    action TEXT NOT NULL,
    actor_id TEXT NOT NULL,
    actor_name TEXT NOT NULL DEFAULT 'Administrator',
    detail_json TEXT,
    timestamp TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_taxonomy_audit_entity ON taxonomy_audit_log(entity_type, entity_id);
CREATE INDEX IF NOT EXISTS idx_taxonomy_audit_actor ON taxonomy_audit_log(actor_id);
