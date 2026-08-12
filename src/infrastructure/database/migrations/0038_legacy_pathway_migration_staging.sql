-- Database Migration 0038: Legacy Pathway Migration Staging & Traceability
-- Creates legacy_pathway_migration_staging table for non-destructive staging, staff-confirmed conversion, and batch rollback.

CREATE TABLE IF NOT EXISTS legacy_pathway_migration_staging (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    source_legacy_id INTEGER,
    source_person_id INTEGER NOT NULL,
    real_life_enrolled INTEGER DEFAULT 0,
    fellows_enrolled INTEGER DEFAULT 0,
    fellows_certificate INTEGER DEFAULT 0,
    lead_enrolled INTEGER DEFAULT 0,
    lead_certificate INTEGER DEFAULT 0,
    lead_current_year TEXT,
    original_legacy_notes TEXT,
    source_snapshot_json TEXT,
    migration_batch_id TEXT NOT NULL,
    review_status TEXT NOT NULL DEFAULT 'pending_review', -- pending_review, reviewed_no_action, ready_to_convert, converted, conflict, archived, rolled_back
    reviewed_by TEXT,
    reviewed_at DATETIME,
    selected_academic_year TEXT,
    selected_fellows_action TEXT DEFAULT 'none', -- none, convert_standard, convert_certification
    selected_lead_action TEXT DEFAULT 'none', -- none, convert_standard, convert_certification
    validation_warnings TEXT,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (source_person_id) REFERENCES people(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_lpms_batch ON legacy_pathway_migration_staging(migration_batch_id);
CREATE INDEX IF NOT EXISTS idx_lpms_person ON legacy_pathway_migration_staging(source_person_id);
CREATE INDEX IF NOT EXISTS idx_lpms_status ON legacy_pathway_migration_staging(review_status);

-- Optional migration traceability columns on modern tables
ALTER TABLE person_pathways ADD COLUMN migration_batch_id TEXT;
ALTER TABLE person_pathways ADD COLUMN source_staging_id INTEGER;
ALTER TABLE person_pathway_program_years ADD COLUMN migration_batch_id TEXT;
