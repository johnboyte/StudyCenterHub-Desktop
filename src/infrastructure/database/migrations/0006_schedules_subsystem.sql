-- Migration 0006: Schedules & Room Calendar Subsystem (SCH-SPR1-001 / Legacy Locations Parity)
-- Complies with [PD-001] (Offline Storage & Outbox) and [PD-008] (Warm & Welcoming Design System)

CREATE TABLE IF NOT EXISTS rooms (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    room_name TEXT UNIQUE NOT NULL,
    capacity INTEGER NOT NULL DEFAULT 30,
    location_notes TEXT,
    is_active INTEGER NOT NULL DEFAULT 1,
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

-- Seed Exact 11 Legacy Session Areas
INSERT OR IGNORE INTO rooms (room_name, capacity, location_notes) VALUES ('Gathering Room', 40, 'Main indoor gathering space');
INSERT OR IGNORE INTO rooms (room_name, capacity, location_notes) VALUES ('Kitchen', 15, 'Kitchen & food prep area');
INSERT OR IGNORE INTO rooms (room_name, capacity, location_notes) VALUES ('Study Room #1', 12, 'Quiet study room 1');
INSERT OR IGNORE INTO rooms (room_name, capacity, location_notes) VALUES ('Study Room #2', 12, 'Quiet study room 2');
INSERT OR IGNORE INTO rooms (room_name, capacity, location_notes) VALUES ('Study Room #3', 12, 'Quiet study room 3');
INSERT OR IGNORE INTO rooms (room_name, capacity, location_notes) VALUES ('The Study', 20, 'Executive study & resource area');
INSERT OR IGNORE INTO rooms (room_name, capacity, location_notes) VALUES ('The Back Porch', 25, 'Outdoor rear seating area');
INSERT OR IGNORE INTO rooms (room_name, capacity, location_notes) VALUES ('The Front Porch Area #1', 15, 'Front porch section 1');
INSERT OR IGNORE INTO rooms (room_name, capacity, location_notes) VALUES ('The Front Porch Area #2', 15, 'Front porch section 2');
INSERT OR IGNORE INTO rooms (room_name, capacity, location_notes) VALUES ('The Front Porch Area #3', 15, 'Front porch section 3');
INSERT OR IGNORE INTO rooms (room_name, capacity, location_notes) VALUES ('Whole Center', 150, 'Full center facility reservation');
