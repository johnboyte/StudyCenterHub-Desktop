-- Migration 0005: Communications Subsystem (COM-SPR1-001)
-- Complies with [PD-001] (Offline Storage & Outbox) and [PD-008] (Warm & Welcoming Design System)

CREATE TABLE IF NOT EXISTS message_templates (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    title TEXT NOT NULL,
    category TEXT NOT NULL DEFAULT 'General',
    channel TEXT NOT NULL DEFAULT 'SMS',
    body_template TEXT NOT NULL,
    is_active INTEGER NOT NULL DEFAULT 1,
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS communications_log (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    message_uuid TEXT UNIQUE NOT NULL,
    recipient_person_id INTEGER,
    recipient_name TEXT NOT NULL,
    recipient_contact TEXT NOT NULL,
    channel TEXT NOT NULL DEFAULT 'SMS',
    message_body TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'sent',
    sent_by_user TEXT NOT NULL DEFAULT 'John Smith',
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    FOREIGN KEY(recipient_person_id) REFERENCES people(id) ON DELETE SET NULL
);

-- Seed Default Message Templates
INSERT OR IGNORE INTO message_templates (title, category, channel, body_template)
VALUES ('Parent Check-In Alert', 'Attendance', 'SMS', 'Hello! Your student has arrived safely at StudyCenter today.');

INSERT OR IGNORE INTO message_templates (title, category, channel, body_template)
VALUES ('Volunteer Shift Reminder', 'Volunteers', 'SMS', 'Reminder: You are scheduled for a volunteer shift at StudyCenter tomorrow.');

INSERT OR IGNORE INTO message_templates (title, category, channel, body_template)
VALUES ('Study Group Announcement', 'General', 'Email', 'Join us for our upcoming study session this week! Check the schedule for details.');
