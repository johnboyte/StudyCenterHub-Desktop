-- Migration 0046: True Hierarchical IVR Menu Nodes and Staff Members Directory
-- Complies with offline-first data integrity.

-- 1. Create staff_members table
CREATE TABLE IF NOT EXISTS staff_members (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    staff_uuid TEXT NOT NULL UNIQUE,
    display_name TEXT NOT NULL,
    transfer_number TEXT NOT NULL,
    is_active INTEGER NOT NULL DEFAULT 1,
    menu_digit TEXT NOT NULL,
    ring_timeout INTEGER NOT NULL DEFAULT 20,
    unanswered_destination TEXT NOT NULL DEFAULT 'voicemail',
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);

-- Seed John staff entry
INSERT OR IGNORE INTO staff_members (staff_uuid, display_name, transfer_number, is_active, menu_digit, ring_timeout, unanswered_destination)
VALUES ('staff_john', 'John', '8649344080', 1, '1', 20, 'voicemail');

-- 2. Create ivr_menu_nodes table
CREATE TABLE IF NOT EXISTS ivr_menu_nodes (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    parent_id INTEGER REFERENCES ivr_menu_nodes(id) ON DELETE CASCADE,
    digit TEXT NOT NULL,
    label TEXT NOT NULL,
    action_type TEXT NOT NULL, -- 'speak', 'voicemail', 'transfer', 'transfer_staff', 'submenu', 'return_to_main', 'hangup', 'staff_directory'
    action_param TEXT,
    script_text TEXT,
    dynamic_source TEXT DEFAULT NULL, -- 'today_house', 'weekly_hours', 'upcoming_events', 'location_directions'
    is_active INTEGER NOT NULL DEFAULT 1,
    display_order INTEGER NOT NULL DEFAULT 0,
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_ivr_menu_nodes_parent_digit 
ON ivr_menu_nodes (IFNULL(parent_id, 0), digit);

-- 3. Seed dynamic settings and Location & Directions default script
INSERT OR IGNORE INTO app_settings (setting_key, setting_value) VALUES ('PHONE_TODAY_SCRIPT_MODE', 'automatic');
INSERT OR IGNORE INTO app_settings (setting_key, setting_value) VALUES ('PHONE_TODAY_SPECIAL_MESSAGE', '');
INSERT OR IGNORE INTO app_settings (setting_key, setting_value) VALUES ('PHONE_TODAY_CUSTOM_SCRIPT', '');

-- Migrate old Location & Directions script if exists, otherwise write default seed
INSERT OR IGNORE INTO app_settings (setting_key, setting_value)
VALUES (
    'PHONE_LOCATION_DIRECTIONS_TEXT', 
    COALESCE(
        (SELECT script_text FROM ivr_menu_options WHERE digit='5'), 
        'Real Life House is located at 206 Williamston Road in Anderson, South Carolina, in the Anderson University community. Website is RealLifeHouse dot org...'
    )
);

-- 4. Seed Hierarchical IVR Menu Tree Nodes (preserves old script data where possible)
-- Seed Root nodes
INSERT OR IGNORE INTO ivr_menu_nodes (id, parent_id, digit, label, action_type, dynamic_source)
VALUES (1, NULL, '1', 'Today at the House', 'submenu', 'today_house');

INSERT OR IGNORE INTO ivr_menu_nodes (id, parent_id, digit, label, action_type, script_text)
SELECT 2, NULL, '2', 'Sunday Night Real Life', 'speak', COALESCE((SELECT script_text FROM ivr_menu_options WHERE digit='2'), 'Real Life Sunday evening script.');

INSERT OR IGNORE INTO ivr_menu_nodes (id, parent_id, digit, label, action_type, script_text)
VALUES (3, NULL, '3', 'Information About Real Life House', 'submenu', 'For What is Real Life House, press 1. For Location and Directions, press 2. For House Hours, press 3. For Upcoming Events, press 4. For Get Involved, press 5. To return to the main menu, press 9.');

INSERT OR IGNORE INTO ivr_menu_nodes (id, parent_id, digit, label, action_type, script_text)
VALUES (4, NULL, '4', 'Reach a Staff Member', 'staff_directory', 'To reach John, press 1. For General Staff Voicemail, press 3. To return to the main menu, press 9.');

INSERT OR IGNORE INTO ivr_menu_nodes (id, parent_id, digit, label, action_type, action_param, script_text)
SELECT 5, NULL, '5', 'Leave a General Message', 'voicemail', 'general', COALESCE((SELECT script_text FROM ivr_menu_options WHERE digit='6'), 'Please leave us a message.');

-- Seed Today at the House (Option 1) child nodes
INSERT OR IGNORE INTO ivr_menu_nodes (parent_id, digit, label, action_type, dynamic_source)
VALUES (1, '1', 'Location and Directions', 'speak', 'location_directions');

INSERT OR IGNORE INTO ivr_menu_nodes (parent_id, digit, label, action_type, script_text)
VALUES (1, '2', 'Speak With a Staff Member', 'staff_directory', 'To reach John, press 1. For General Staff Voicemail, press 3. To return to the main menu, press 9.');

INSERT OR IGNORE INTO ivr_menu_nodes (parent_id, digit, label, action_type)
VALUES (1, '9', 'Return to Main Menu', 'return_to_main');

-- Seed Information (Option 3) child nodes
INSERT OR IGNORE INTO ivr_menu_nodes (parent_id, digit, label, action_type, script_text)
SELECT 3, '1', 'What is Real Life House?', 'speak', COALESCE((SELECT script_text FROM ivr_menu_options WHERE digit='3'), 'What is Real Life House.');

INSERT OR IGNORE INTO ivr_menu_nodes (parent_id, digit, label, action_type, dynamic_source)
VALUES (3, '2', 'Location and Directions', 'speak', 'location_directions');

INSERT OR IGNORE INTO ivr_menu_nodes (parent_id, digit, label, action_type, dynamic_source)
VALUES (3, '3', 'House Hours for the Week', 'speak', 'weekly_hours');

INSERT OR IGNORE INTO ivr_menu_nodes (parent_id, digit, label, action_type, dynamic_source)
VALUES (3, '4', 'Upcoming Events and Programs', 'speak', 'upcoming_events');

INSERT OR IGNORE INTO ivr_menu_nodes (parent_id, digit, label, action_type, script_text)
SELECT 3, '5', 'How to Get Involved', 'speak', COALESCE((SELECT script_text FROM ivr_menu_options WHERE digit='4'), 'How to Get Involved.');

INSERT OR IGNORE INTO ivr_menu_nodes (parent_id, digit, label, action_type)
VALUES (3, '9', 'Return to Main Menu', 'return_to_main');
