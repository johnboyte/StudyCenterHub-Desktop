-- Migration 0028: Add communication_needed column to session_signups and attendance_log extensions
ALTER TABLE session_signups ADD COLUMN communication_needed INTEGER DEFAULT 0;
ALTER TABLE attendance_log ADD COLUMN session_id INTEGER DEFAULT NULL;
ALTER TABLE attendance_log ADD COLUMN mode TEXT DEFAULT 'Study Center Daily';
ALTER TABLE attendance_log ADD COLUMN shift_lead TEXT DEFAULT 'John Boyte';
