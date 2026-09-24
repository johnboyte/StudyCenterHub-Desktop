-- Migration 0059: Protected Original Profile Photo Subsystem
ALTER TABLE people ADD COLUMN original_profile_photo TEXT;

-- Migration / Backfill baseline protected original for existing people who already have a profile_photo
UPDATE people
SET original_profile_photo = profile_photo
WHERE profile_photo IS NOT NULL AND profile_photo != '' AND (original_profile_photo IS NULL OR original_profile_photo = '');
