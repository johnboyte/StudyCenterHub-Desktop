-- Migration 0050: Expand Master High School Institutions
PRAGMA foreign_keys = ON;

-- Seed Canonical High School Institutions
INSERT OR IGNORE INTO institutions (uuid, name, short_name, institution_type, display_order, is_active) VALUES
('inst_tl_hanna', 'T.L. Hanna High School', 'TLH', 'high_school', 10, 1),
('inst_westside', 'Westside High School', 'WHS', 'high_school', 11, 1),
('inst_palmetto', 'Palmetto High School', 'PHS', 'high_school', 12, 1),
('inst_crescent', 'Crescent High School', 'CHS', 'high_school', 13, 1),
('inst_bhp', 'Belton-Honea Path High School', 'BHP', 'high_school', 14, 1),
('inst_pendleton', 'Pendleton High School', 'PEND', 'high_school', 15, 1),
('inst_wren', 'Wren High School', 'WREN', 'high_school', 16, 1),
('inst_powdersville', 'Powdersville High School', 'PVHS', 'high_school', 17, 1),
('inst_anderson_christian', 'Anderson Christian School', 'ACS', 'high_school', 18, 1),
('inst_new_covenant', 'New Covenant School', 'NCS', 'high_school', 19, 1),
('inst_home_school', 'Home School', 'HomeSchool', 'high_school', 20, 1);
