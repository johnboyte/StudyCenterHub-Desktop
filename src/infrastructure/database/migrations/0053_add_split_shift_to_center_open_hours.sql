-- Migration 0053: Add Split Shift and Session 2 columns to center_open_hours table
ALTER TABLE center_open_hours ADD COLUMN has_split_shift INTEGER NOT NULL DEFAULT 0;
ALTER TABLE center_open_hours ADD COLUMN session2_start TEXT DEFAULT '05:00 PM';
ALTER TABLE center_open_hours ADD COLUMN session2_end TEXT DEFAULT '08:00 PM';
