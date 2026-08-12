-- Migration 0043: Add campus_community_applies to people table
ALTER TABLE people ADD COLUMN campus_community_applies INTEGER DEFAULT 0;

-- Default it to ON (1) for existing records that contain Campus & Community info
UPDATE people 
SET campus_community_applies = 1 
WHERE (institution_id IS NOT NULL AND institution_id != 0 AND institution_id != '')
   OR (institution_other_name IS NOT NULL AND institution_other_name != '')
   OR (relationship IS NOT NULL AND relationship != '')
   OR (school_email IS NOT NULL AND school_email != '')
   OR (academic_year IS NOT NULL AND academic_year != '' AND academic_year != 'None' AND academic_year != 'Not Applicable')
   OR (major IS NOT NULL AND major != '')
   OR (residence IS NOT NULL AND residence != '' AND residence != 'Not Applicable')
   OR (expected_grad_term IS NOT NULL AND expected_grad_term != '' AND expected_grad_term != 'Not Applicable')
   OR (expected_grad_year IS NOT NULL AND expected_grad_year != 0 AND expected_grad_year != '');
