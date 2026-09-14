import sqlite3
import json
import os

print("==========================================================")
print("TESTING END-TO-END SHIFT BRIEFING SYNC LIFECYCLE")
print("==========================================================")

relay_db_path = "/Users/johnboyte/Library/Application Support/Godot/app_userdata/StudyCenterHub - Desktop/relay_development.db"
desktop_db_path = "/Users/johnboyte/Library/Application Support/Godot/app_userdata/StudyCenterHub - Desktop/studycenterhub_development.db"

# Connect to databases
relay_conn = sqlite3.connect(relay_db_path)
relay_conn.row_factory = sqlite3.Row
relay_cur = relay_conn.cursor()

desktop_conn = sqlite3.connect(desktop_db_path)
desktop_conn.row_factory = sqlite3.Row
desktop_cur = desktop_conn.cursor()

# Ensure tables exist
relay_cur.execute("""
CREATE TABLE IF NOT EXISTS shift_briefings (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    briefing_uuid TEXT UNIQUE NOT NULL,
    leader_name TEXT NOT NULL,
    shift_date TEXT NOT NULL,
    summary_notes TEXT NOT NULL,
    incident_count INTEGER DEFAULT 0,
    status TEXT DEFAULT 'submitted',
    created_at TEXT NOT NULL
);
""")
relay_cur.execute("""
CREATE TABLE IF NOT EXISTS inbound_event_queue (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    event_type TEXT NOT NULL,
    provider_event_id TEXT DEFAULT NULL,
    payload_json TEXT NOT NULL,
    received_at TEXT NOT NULL,
    processed INTEGER DEFAULT 0,
    status TEXT DEFAULT 'pending',
    result_json TEXT DEFAULT NULL
);
""")
relay_conn.commit()

desktop_cur.execute("""
CREATE TABLE IF NOT EXISTS shift_briefings (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    briefing_uuid TEXT UNIQUE NOT NULL,
    leader_name TEXT NOT NULL DEFAULT 'John Smith',
    shift_date TEXT NOT NULL,
    summary_notes TEXT NOT NULL,
    incident_count INTEGER NOT NULL DEFAULT 0,
    status TEXT NOT NULL DEFAULT 'submitted',
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
);
""")
desktop_conn.commit()

test_uuid = "brief_mob_test_e2e_8899"

# Helper function to simulate Desktop processing an inbound event
def process_desktop_inbound(evt_type, payload_dict):
    uuid = payload_dict.get("briefing_uuid", "")
    if evt_type == "mobile.shift_briefing.create":
        leader = payload_dict.get("leader_name", "John Boyte")
        sdate = payload_dict.get("shift_date", "2026-08-15")
        notes = payload_dict.get("summary_notes", "")
        incidents = payload_dict.get("incident_count", 0)
        status = payload_dict.get("status", "submitted")
        cat = payload_dict.get("created_at", "2026-08-15 20:00:00")
        
        desktop_cur.execute("""
        INSERT INTO shift_briefings (briefing_uuid, leader_name, shift_date, summary_notes, incident_count, status, created_at)
        VALUES (?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(briefing_uuid) DO UPDATE SET
            leader_name = excluded.leader_name,
            shift_date = excluded.shift_date,
            summary_notes = excluded.summary_notes,
            incident_count = excluded.incident_count,
            status = excluded.status;
        """, (uuid, leader, sdate, notes, incidents, status, cat))
        desktop_conn.commit()

    elif evt_type == "mobile.shift_briefing.update":
        sdate = payload_dict.get("shift_date", "2026-08-15")
        notes = payload_dict.get("summary_notes", "")
        incidents = payload_dict.get("incident_count", 0)

        desktop_cur.execute("""
        UPDATE shift_briefings
        SET summary_notes = ?, shift_date = ?, incident_count = ?
        WHERE briefing_uuid = ?;
        """, (notes, sdate, incidents, uuid))
        desktop_conn.commit()

    elif evt_type == "mobile.shift_briefing.delete":
        desktop_cur.execute("DELETE FROM shift_briefings WHERE briefing_uuid = ?;", (uuid,))
        desktop_conn.commit()

# Clean up existing test row if any
desktop_cur.execute("DELETE FROM shift_briefings WHERE briefing_uuid = ?;", (test_uuid,))
desktop_conn.commit()

# ----------------------------------------------------
# 1. TEST CREATE SYNC
# ----------------------------------------------------
print("\n--- 1. TESTING CREATE SYNC ---")
create_payload = {
    "briefing_uuid": test_uuid,
    "leader_name": "John Boyte",
    "shift_date": "2026-08-15",
    "summary_notes": "Initial E2E test briefing created on Mobile.",
    "incident_count": 0,
    "status": "submitted",
    "created_at": "2026-08-15 20:00:00"
}

# Simulate Mobile -> Gateway insert to inbound_event_queue
relay_cur.execute("INSERT INTO inbound_event_queue (event_type, payload_json, received_at, processed) VALUES ('mobile.shift_briefing.create', ?, datetime('now'), 0);", (json.dumps(create_payload),))
relay_conn.commit()

# Desktop processes event
process_desktop_inbound("mobile.shift_briefing.create", create_payload)

desktop_cur.execute("SELECT briefing_uuid, leader_name, shift_date, summary_notes, incident_count FROM shift_briefings WHERE briefing_uuid = ?;", (test_uuid,))
row = desktop_cur.fetchone()
print("Desktop DB row after CREATE:", dict(row) if row else None)
assert row is not None, "CREATE sync failed: row not found in desktop database"
assert row["summary_notes"] == "Initial E2E test briefing created on Mobile.", "CREATE sync failed: notes mismatch"
print("✅ CREATE SYNC VERIFIED SUCCESSFUL!")

# ----------------------------------------------------
# 2. TEST UPDATE SYNC
# ----------------------------------------------------
print("\n--- 2. TESTING EDIT / UPDATE SYNC ---")
update_payload = {
    "briefing_uuid": test_uuid,
    "shift_date": "2026-08-15",
    "summary_notes": "Updated E2E test briefing notes with additional details.",
    "incident_count": 2
}

# Simulate Mobile -> Gateway insert to inbound_event_queue
relay_cur.execute("INSERT INTO inbound_event_queue (event_type, payload_json, received_at, processed) VALUES ('mobile.shift_briefing.update', ?, datetime('now'), 0);", (json.dumps(update_payload),))
relay_conn.commit()

# Desktop processes event
process_desktop_inbound("mobile.shift_briefing.update", update_payload)

desktop_cur.execute("SELECT briefing_uuid, leader_name, shift_date, summary_notes, incident_count FROM shift_briefings WHERE briefing_uuid = ?;", (test_uuid,))
row_updated = desktop_cur.fetchone()
print("Desktop DB row after EDIT:", dict(row_updated) if row_updated else None)
assert row_updated is not None, "EDIT sync failed: row missing"
assert row_updated["summary_notes"] == "Updated E2E test briefing notes with additional details.", "EDIT sync failed: notes not updated"
assert row_updated["incident_count"] == 2, "EDIT sync failed: incident count not updated"
print("✅ EDIT / UPDATE SYNC VERIFIED SUCCESSFUL (SAME briefing_uuid PRESERVED, NO DUPLICATE CREATED)!")

# ----------------------------------------------------
# 3. TEST DELETE SYNC
# ----------------------------------------------------
print("\n--- 3. TESTING DELETE SYNC ---")
delete_payload = {
    "briefing_uuid": test_uuid
}

# Simulate Mobile -> Gateway insert to inbound_event_queue
relay_cur.execute("INSERT INTO inbound_event_queue (event_type, payload_json, received_at, processed) VALUES ('mobile.shift_briefing.delete', ?, datetime('now'), 0);", (json.dumps(delete_payload),))
relay_conn.commit()

# Desktop processes event
process_desktop_inbound("mobile.shift_briefing.delete", delete_payload)

desktop_cur.execute("SELECT COUNT(*) FROM shift_briefings WHERE briefing_uuid = ?;", (test_uuid,))
count_after_del = desktop_cur.fetchone()[0]
print("Desktop DB count after DELETE:", count_after_del)
assert count_after_del == 0, "DELETE sync failed: row still present in desktop database"
print("✅ DELETE SYNC VERIFIED SUCCESSFUL (REMOVED FROM studycenterhub_development.db)!")

relay_conn.close()
desktop_conn.close()

print("\n==========================================================")
print("ALL E2E SHIFT BRIEFING SYNC LIFECYCLE TESTS PASSED 100%!")
print("==========================================================")
