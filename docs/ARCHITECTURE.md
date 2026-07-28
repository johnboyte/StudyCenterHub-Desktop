# StudyCenterHub Architecture Specification

Canonical system architecture, domain boundaries, database persistence schemas, environment variable configuration, and integration specifications.

---

## 1. Core Architecture Principles

1. **Offline-First & Local Storage**: StudyCenterHub Desktop uses local SQLite storage (`user://studycenter_desktop.db`) for zero-latency operations and complete offline capability (see `[PD-001]`).
2. **Outbox Synchronization**: All local write mutations record an entry in the `outbox_sync` table for eventual background synchronization with the central hub (`outbox_sync_worker.gd`).
3. **Read-Only UI Separation**: UI controllers (`directory_view.gd`) retrieve data strictly through read-only domain services (`directory_read_service.gd`), avoiding direct raw SQL mutations or direct state tampering (see `[PD-002]`).
4. **Configurable Application Data**: Operational settings, note types, and category labels are stored as configurable database rows (`app_settings`), avoiding hardcoded code enums (see `[PD-005]`).

---

## 2. Directory & Workspace Domain Architecture

```
[ UI Layer ]
  └─ DirectoryView (directory_view.gd / directory_view.tscn)
       ├─ Roster Panel (Filter, Search, Scrollable Roster Items)
       └─ Person Workspace Panel (Header, 5-Tab Navigation, Stacked Section Cards)
            ├─ Overview Section
            ├─ Profile Section
            ├─ Participation Section
            ├─ Communications Section
            └─ History Section

[ Read Service Layer ]
  └─ DirectoryReadService (directory_read_service.gd)
       ├─ fetch_roster(status_filter, search_query)
       ├─ get_person_details(person_uuid)
       └─ get_person_attendance_history(person_uuid)

[ Database Layer ]
  └─ SQLiteDatabase (sqlite_database.gd)
       ├─ people
       ├─ attendance_log
       └─ outbox_sync
```

---

## 3. SQLite Database Schema (Desktop Core)

### `people` Table
```sql
CREATE TABLE IF NOT EXISTS people (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    person_uuid TEXT UNIQUE NOT NULL,
    human_id TEXT UNIQUE NOT NULL,
    first_name TEXT NOT NULL,
    last_name TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'active',
    grade TEXT,
    phone TEXT,
    emergency_contact_name TEXT,
    emergency_contact_phone TEXT,
    medical_notes TEXT,
    notes TEXT,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
);
```

### `attendance_log` Table
```sql
CREATE TABLE IF NOT EXISTS attendance_log (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    checkin_uuid TEXT UNIQUE NOT NULL,
    person_id INTEGER NOT NULL,
    person_uuid TEXT NOT NULL,
    human_id TEXT NOT NULL,
    check_in_date TEXT NOT NULL,
    check_in_time TEXT NOT NULL,
    method TEXT NOT NULL DEFAULT 'Manual',
    device_uuid TEXT NOT NULL,
    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY(person_id) REFERENCES people(id) ON DELETE CASCADE
);
```

### `outbox_sync` Table
```sql
CREATE TABLE IF NOT EXISTS outbox_sync (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    event_uuid TEXT UNIQUE NOT NULL,
    event_type TEXT NOT NULL,
    payload_json TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'pending',
    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    synced_at TEXT
);
```

### `note_types` Table (PD-006, PD-007)
```sql
CREATE TABLE IF NOT EXISTS note_types (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    type_uuid TEXT NOT NULL UNIQUE,
    name TEXT NOT NULL,
    description TEXT,
    display_order INTEGER NOT NULL DEFAULT 0,
    is_active INTEGER NOT NULL DEFAULT 1,
    is_system INTEGER NOT NULL DEFAULT 0,
    org_visible INTEGER NOT NULL DEFAULT 1,
    org_enabled INTEGER NOT NULL DEFAULT 1,
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);
```

### `person_notes` Table
```sql
CREATE TABLE IF NOT EXISTS person_notes (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    note_uuid TEXT NOT NULL UNIQUE,
    person_id INTEGER NOT NULL REFERENCES people(id) ON DELETE CASCADE,
    person_uuid TEXT NOT NULL,
    note_type_uuid TEXT NOT NULL REFERENCES note_types(type_uuid),
    title TEXT,
    body TEXT NOT NULL,
    visibility TEXT NOT NULL DEFAULT 'standard_staff',
    is_pinned INTEGER NOT NULL DEFAULT 0,
    is_deleted INTEGER NOT NULL DEFAULT 0,
    author_uuid TEXT,
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);
```

---

## 4. Environment & Configuration Reference

* **Primary Process Runtime**: Native Godot 4.7+ runtime for Desktop (Offline-First).
* **Communications Gateway**: Node.js 20 microservice (Express) acting as a public HTTP webhook gateway for incoming communications (Twilio, voice/SMS prompts) and publishing normalized events to the sync queue.
* **Local Database Paths (Isolated by `STUDYCENTERHUB_ENV`)**:
  * **Development**: `user://studycenterhub_development.db`
  * **Staging**: `user://studycenterhub_staging.db`
  * **Production**: `user://studycenterhub_production.db`
* **Google Workspace Sync (System of Record)**: Two-way sync workers fetch and write directory spreadsheets and photos folder streams under `StudyCenterHub` workspace folders.
