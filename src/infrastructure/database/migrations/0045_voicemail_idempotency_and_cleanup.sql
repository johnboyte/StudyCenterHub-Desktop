-- Migration 0045: Voicemail Idempotency & Duplicate Cleanup
-- Ensures stable RecordingSid tracking and consolidates historical duplicate test voicemails

-- 1. Ensure columns exist on voicemails table
ALTER TABLE voicemails ADD COLUMN recording_sid TEXT DEFAULT NULL;
ALTER TABLE voicemails ADD COLUMN call_sid TEXT DEFAULT NULL;

-- 2. Populate recording_sid from recording_url if missing
UPDATE voicemails 
SET recording_sid = SUBSTR(recording_url, INSTR(recording_url, '/Recordings/') + 12)
WHERE (recording_sid IS NULL OR recording_sid = '') 
  AND recording_url LIKE '%/Recordings/%';

-- 3. Create Unique Index on recording_sid to guarantee DB-level idempotency
CREATE UNIQUE INDEX IF NOT EXISTS idx_voicemails_recording_sid ON voicemails(recording_sid) WHERE recording_sid IS NOT NULL AND recording_sid != '';

-- 4. Safely clean up duplicate records for RE3100bf5a5b17f91f9e2558e7e25b6866 (keeping earliest ID 2)
DELETE FROM voicemails WHERE id IN (3, 4, 5, 6) AND (recording_url LIKE '%RE3100bf5a5b17f91f9e2558e7e25b6866%' OR recording_sid = 'RE3100bf5a5b17f91f9e2558e7e25b6866');
