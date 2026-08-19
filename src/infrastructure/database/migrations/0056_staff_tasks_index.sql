-- Migration 0056: Staff Tasks Index Sub-system (Person-Linked Follow-Ups & Tasks)
PRAGMA journal_mode = WAL;
PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS staff_tasks_index (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    task_uuid TEXT UNIQUE NOT NULL,
    title TEXT NOT NULL,
    description TEXT DEFAULT '',
    due_date TEXT NOT NULL,
    priority TEXT NOT NULL DEFAULT 'normal',
    status TEXT NOT NULL DEFAULT 'open',
    assignee_human_id TEXT,
    assignee_name TEXT DEFAULT '',
    linked_human_id TEXT,
    linked_human_name TEXT DEFAULT '',
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    completed_at TEXT DEFAULT NULL,
    completed_by TEXT DEFAULT NULL,
    updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_staff_tasks_linked_human_id ON staff_tasks_index(linked_human_id);
CREATE INDEX IF NOT EXISTS idx_staff_tasks_status ON staff_tasks_index(status);
CREATE INDEX IF NOT EXISTS idx_staff_tasks_due_date ON staff_tasks_index(due_date);
