-- Migration 0041: Academic Majors Subsystem & Audit Log Safeguards
PRAGMA foreign_keys = ON;

-- 1. Academic Majors Master Table
CREATE TABLE IF NOT EXISTS academic_majors (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    uuid TEXT NOT NULL UNIQUE,
    canonical_name TEXT NOT NULL UNIQUE,
    aliases TEXT,
    display_order INTEGER NOT NULL DEFAULT 0,
    is_active INTEGER NOT NULL DEFAULT 1,
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_academic_majors_uuid ON academic_majors(uuid);
CREATE INDEX IF NOT EXISTS idx_academic_majors_name ON academic_majors(canonical_name);

-- Seed Initial Distinct Majors
INSERT OR IGNORE INTO academic_majors (uuid, canonical_name, aliases, display_order, is_active) VALUES
('maj_cs', 'Computer Science', 'CS,CompSci,Computer Sci', 1, 1),
('maj_nursing', 'Nursing', 'BSN,RN', 2, 1),
('maj_engineering', 'Engineering', 'Eng,Engr', 3, 1),
('maj_business', 'Business Administration', 'Business,BBA', 4, 1),
('maj_biology', 'Biology', 'Bio,Biological Sciences', 5, 1),
('maj_psychology', 'Psychology', 'Psych', 6, 1),
('maj_education', 'Education', 'Edu', 7, 1);

-- Seed Any Additional Existing Distinct Majors from People Table
INSERT OR IGNORE INTO academic_majors (uuid, canonical_name, display_order, is_active)
SELECT 
    'maj_' || LOWER(REPLACE(TRIM(major), ' ', '_')),
    TRIM(major),
    10,
    1
FROM people 
WHERE major IS NOT NULL AND TRIM(major) != '' AND TRIM(major) NOT IN ('Computer Science', 'Nursing', 'Engineering', 'Business Administration', 'Biology', 'Psychology', 'Education');
