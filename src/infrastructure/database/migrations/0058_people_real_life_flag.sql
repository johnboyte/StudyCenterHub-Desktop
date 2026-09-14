-- Migration 0058: Add real_life boolean flag to people table
ALTER TABLE people ADD COLUMN real_life INTEGER NOT NULL DEFAULT 0;
