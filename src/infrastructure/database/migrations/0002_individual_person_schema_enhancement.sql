-- Phase 2.1 Checkpoint - Story DIR-SPR1-001A Migration
-- Additive Individual Person Schema Enhancement

ALTER TABLE people ADD COLUMN status TEXT NOT NULL DEFAULT 'active';
ALTER TABLE people ADD COLUMN grade TEXT;
ALTER TABLE people ADD COLUMN notes TEXT;
ALTER TABLE people ADD COLUMN emergency_contact_name TEXT;
ALTER TABLE people ADD COLUMN emergency_contact_phone TEXT;
ALTER TABLE people ADD COLUMN medical_notes TEXT;
