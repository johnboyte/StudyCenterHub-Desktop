-- Migration 0018: Communications Response Center & IVR configuration
-- Complies with [PD-001] (Offline Storage) and [PD-006] (Admin Config First)

-- 1. Extend voicemails table to support assignment and work status workflow
ALTER TABLE voicemails ADD COLUMN assigned_person_id INTEGER REFERENCES people(id) ON DELETE SET NULL;
ALTER TABLE voicemails ADD COLUMN priority TEXT NOT NULL DEFAULT 'Medium';
ALTER TABLE voicemails ADD COLUMN due_date TEXT;
ALTER TABLE voicemails ADD COLUMN internal_notes TEXT;

-- 2. Create IVR Script configuration table
CREATE TABLE IF NOT EXISTS ivr_menu_options (
    digit TEXT PRIMARY KEY,
    menu_option_name TEXT NOT NULL,
    script_text TEXT NOT NULL,
    action_type TEXT NOT NULL DEFAULT 'speak', -- speak, transfer, voicemail, work_item
    action_param TEXT
);

-- Seed Default IVR Menu Configuration
INSERT OR IGNORE INTO ivr_menu_options (digit, menu_option_name, script_text, action_type, action_param)
VALUES ('1', 'General Information', 'Thank you for calling the Real Life Study Center. We serve and support local students and families.', 'speak', NULL);

INSERT OR IGNORE INTO ivr_menu_options (digit, menu_option_name, script_text, action_type, action_param)
VALUES ('2', 'Hours & Location', 'We are open Monday through Thursday from 3 PM to 8 PM, and Friday from 3 PM to 6 PM. We are located next to the fellowship building.', 'speak', NULL);

INSERT OR IGNORE INTO ivr_menu_options (digit, menu_option_name, script_text, action_type, action_param)
VALUES ('3', 'Leave a Message', 'Please record your message after the tone. Our staff will review and respond shortly.', 'voicemail', NULL);

INSERT OR IGNORE INTO ivr_menu_options (digit, menu_option_name, script_text, action_type, action_param)
VALUES ('4', 'Emergency Pastoral Needs', 'Transferring your call directly to Pastor Marcus Vance.', 'transfer', '509-555-0101');
