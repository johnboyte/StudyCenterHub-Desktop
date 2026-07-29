-- Migration 0036: Canonical Staff Classification Refinement
-- Adds staff_classification column to people table and maps legacy shift roles to 4 canonical classifications.

-- 1. Add staff_classification column to people table
ALTER TABLE people ADD COLUMN staff_classification TEXT NOT NULL DEFAULT 'Staff';

-- 2. Backfill canonical staff_classification in people
UPDATE people SET staff_classification = 'Team Leader' WHERE primary_role LIKE '%Supervisor%' OR primary_role LIKE '%Leader%' OR primary_role = 'Shift Supervisor';
UPDATE people SET staff_classification = 'Volunteer' WHERE primary_role LIKE '%Vol%' OR primary_role = 'Volunteer';
UPDATE people SET staff_classification = 'Intern' WHERE primary_role LIKE '%Intern%' OR primary_role = 'Intern';
UPDATE people SET staff_classification = 'Staff' WHERE staff_classification IS NULL OR staff_classification = '' OR staff_classification = 'Participant';

-- 3. Remap legacy shift_role in schedule_entries to 4 canonical Staff Classifications
UPDATE schedule_entries SET shift_role = 'Team Leader' WHERE shift_role LIKE '%Supervisor%' OR shift_role = 'Shift Supervisor' OR shift_role = 'Shift Supervisor (Staff)';
UPDATE schedule_entries SET shift_role = 'Intern' WHERE shift_role LIKE '%Intern%' OR shift_role = 'Study Tutor (Intern)' OR shift_role = 'Study Tutor';
UPDATE schedule_entries SET shift_role = 'Volunteer' WHERE shift_role LIKE '%Vol%' OR shift_role = 'Check-In Host (Vol)' OR shift_role = 'Check-In Host';
UPDATE schedule_entries SET shift_role = 'Staff' WHERE shift_role = 'AV Tech (Staff)' OR shift_role = 'AV Tech' OR (shift_role NOT IN ('Volunteer', 'Intern', 'Staff', 'Team Leader') AND shift_role IS NOT NULL);
