-- Migration 0054: Add Coverage and Team Leader Capability Flags to People
ALTER TABLE people ADD COLUMN can_cover_hours INTEGER NOT NULL DEFAULT 0;
ALTER TABLE people ADD COLUMN is_team_leader_eligible INTEGER NOT NULL DEFAULT 0;

-- Backfill existing Team Leaders to is_team_leader_eligible = 1
UPDATE people 
SET is_team_leader_eligible = 1 
WHERE staff_classification = 'Team Leader' 
   OR primary_role = 'Team Leader' 
   OR primary_role LIKE '%Supervisor%';
