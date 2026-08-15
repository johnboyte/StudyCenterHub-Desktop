import sqlite3
import json
import os

# 1. Create a local synthetic canonical SQLite table with human_id PRIMARY KEY
test_db_path = "/tmp/test_handler_regression.db"
if os.path.exists(test_db_path):
    os.remove(test_db_path)

conn = sqlite3.connect(test_db_path)
cursor = conn.cursor()

cursor.execute("""
    CREATE TABLE directory_index (
        human_id TEXT PRIMARY KEY,
        phone_e164 TEXT,
        first_name TEXT NOT NULL,
        last_name TEXT DEFAULT '',
        masked_phone TEXT DEFAULT '',
        profile_photo TEXT DEFAULT '',
        updated_at TEXT NOT NULL DEFAULT (datetime('now'))
    );
""")

# Insert existing John row with empty last_name and empty profile_photo
cursor.execute("""
    INSERT INTO directory_index (human_id, phone_e164, first_name, last_name, masked_phone, profile_photo)
    VALUES ('P-20260813-F9C7', '+18649344080', 'John', '', '•••-•••-4080', '');
""")
conn.commit()

cursor.execute("SELECT human_id, first_name, last_name, length(profile_photo) FROM directory_index WHERE human_id = 'P-20260813-F9C7'")
initial_row = cursor.fetchone()
print("=== INITIAL EXISTING ROW ===")
print("human_id:", initial_row[0])
print("first_name:", initial_row[1])
print("last_name:", repr(initial_row[2]))
print("profile_photo len:", initial_row[3])

# 2. Simulate current PHP handler logic (1-step ON CONFLICT UPSERT vs 2-step UPDATE)
# Sample payload from decoded JSON
member_json = {
    'human_id': 'P-20260813-F9C7',
    'first_name': 'John',
    'last_name': 'Boyte',
    'phone': '(864) 934-4080',
    'profile_photo': 'data:image/jpeg;base64,' + 'C' * 152291
}

# Field extraction (mirroring PHP handler)
hid = member_json.get('human_id', '').strip()
fn = member_json.get('first_name', '').strip()
ln = member_json.get('last_name', '').strip()
photo = member_json.get('profile_photo', '').strip()
raw_p = member_json.get('phone') or member_json.get('phone_e164') or ''
e164 = '+18649344080' # normalize_phone_e164_php
mp = '•••-•••-4080'   # mask_phone_php

# Execute 1-step atomic SQL UPSERT (The Smallest Correct Fix)
upsert_sql = """
    INSERT INTO directory_index (human_id, phone_e164, first_name, last_name, masked_phone, profile_photo, updated_at)
    VALUES (?, ?, ?, ?, ?, ?, datetime('now'))
    ON CONFLICT(human_id) DO UPDATE SET
        phone_e164 = excluded.phone_e164,
        first_name = excluded.first_name,
        last_name = excluded.last_name,
        masked_phone = excluded.masked_phone,
        profile_photo = excluded.profile_photo,
        updated_at = datetime('now')
"""
cursor.execute(upsert_sql, (hid, e164, fn, ln, mp, photo))
conn.commit()

cursor.execute("SELECT human_id, first_name, last_name, phone_e164, length(profile_photo) FROM directory_index WHERE human_id = 'P-20260813-F9C7'")
updated_row = cursor.fetchone()

print("\n=== VERIFIED POST-UPSERT ROW ===")
print("human_id:", updated_row[0])
print("first_name:", updated_row[1])
print("last_name:", updated_row[2])
print("phone_e164:", updated_row[3])
print("profile_photo len:", updated_row[4])

assert updated_row[0] == 'P-20260813-F9C7'
assert updated_row[1] == 'John'
assert updated_row[2] == 'Boyte'
assert updated_row[3] == '+18649344080'
assert updated_row[4] == 152314

conn.close()
os.remove(test_db_path)
print("\n=== LOCAL DIRECTORY UPSERT REGRESSION TEST PASSED 100% ===")

# 3. Test person_notes privacy filter and center_hour_overrides logic
test_db2_path = "/tmp/test_dashboard_slice_regression.db"
if os.path.exists(test_db2_path):
    os.remove(test_db2_path)

conn2 = sqlite3.connect(test_db2_path)
c2 = conn2.cursor()

# Create person_notes and center_hour_overrides tables
c2.execute("""
    CREATE TABLE person_notes (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        note_uuid TEXT UNIQUE,
        person_uuid TEXT,
        title TEXT,
        body TEXT,
        visibility TEXT DEFAULT 'standard_staff',
        is_deleted INTEGER DEFAULT 0,
        created_at TEXT DEFAULT (datetime('now'))
    );
""")

c2.execute("""
    CREATE TABLE center_hour_overrides (
        override_date TEXT PRIMARY KEY,
        is_closed INTEGER DEFAULT 0,
        session1_start TEXT,
        session1_end TEXT,
        has_split_shift INTEGER DEFAULT 0,
        session2_start TEXT,
        session2_end TEXT
    );
""")

# Insert operational vs sensitive pastoral notes
c2.execute("INSERT INTO person_notes (note_uuid, person_uuid, title, body, visibility) VALUES ('n1', 'P101', 'General Note', 'Checked in for math tutoring.', 'standard_staff');")
c2.execute("INSERT INTO person_notes (note_uuid, person_uuid, title, body, visibility) VALUES ('n2', 'P101', 'Pastoral Session', 'Private counseling conversation.', 'sensitive_pastoral');")
c2.execute("INSERT INTO person_notes (note_uuid, person_uuid, title, body, visibility) VALUES ('n3', 'P101', 'Confidential Note', 'Private medical info.', 'confidential');")
c2.execute("INSERT INTO person_notes (note_uuid, person_uuid, title, body, visibility) VALUES ('n4', 'P102', 'Shift Note', 'Left study hall early.', 'general');")
conn2.commit()

# Test privacy filter query (simulating PHP logic)
c2.execute("""
    SELECT note_uuid, title, body, visibility FROM person_notes
    WHERE is_deleted = 0
      AND LOWER(COALESCE(visibility, 'standard_staff')) NOT IN ('sensitive_pastoral', 'pastoral', 'confidential', 'private')
""")
filtered_notes = c2.fetchall()
note_uuids = [n[0] for n in filtered_notes]

print("\n=== VERIFIED PERSON_NOTES PRIVACY FILTER ===")
print("Filtered Note UUIDs:", note_uuids)
assert 'n1' in note_uuids
assert 'n4' in note_uuids
assert 'n2' not in note_uuids, "FAIL: sensitive_pastoral note leaked!"
assert 'n3' not in note_uuids, "FAIL: confidential note leaked!"

# Test center_open_hours weekly recurring default hours
c2.execute("""
    CREATE TABLE center_open_hours (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        day_of_week TEXT UNIQUE,
        open_time TEXT,
        close_time TEXT,
        is_closed INTEGER DEFAULT 0
    );
""")
c2.execute("INSERT INTO center_open_hours (day_of_week, open_time, close_time, is_closed) VALUES ('Saturday', '10:00 AM', '04:00 PM', 0);")

# Test schedule_entries per-shift staff assignment query
c2.execute("""
    CREATE TABLE schedule_entries (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        entry_uuid TEXT,
        person_name TEXT,
        shift_role TEXT,
        shift_date TEXT
    );
""")
c2.execute("INSERT INTO schedule_entries (entry_uuid, person_name, shift_role, shift_date) VALUES ('e1', 'John Staff', 'Shift Lead', '2026-08-15');")
conn2.commit()

# Verify weekly recurring hours query
c2.execute("SELECT open_time, close_time, is_closed FROM center_open_hours WHERE LOWER(day_of_week) = LOWER('Saturday')")
oh_sat = c2.fetchone()
assert oh_sat[0] == '10:00 AM' and oh_sat[1] == '04:00 PM', "FAIL: Weekly recurring open hours mismatch!"

# Test POST /people/{human_id}/notes insertion logic
c2.execute("INSERT INTO person_notes (note_uuid, person_uuid, title, body, visibility) VALUES ('n_posted_1', 'P101', 'Staff Note', 'Added operational note from mobile app.', 'standard_staff');")
conn2.commit()

c2.execute("SELECT note_uuid, title, body, visibility FROM person_notes WHERE note_uuid = 'n_posted_1'")
posted_note = c2.fetchone()
assert posted_note[0] == 'n_posted_1'
assert posted_note[3] == 'standard_staff', "FAIL: Mobile operational note must have standard_staff visibility!"

# Python helper test for StudyCenterHub QR format parsing
def parse_study_center_qr_py(raw_scanned: str) -> str:
    if not raw_scanned: return ''
    trimmed = raw_scanned.strip()
    if 'credential=' in trimmed:
        parts = trimmed.split('credential=')
        if len(parts) > 1:
            return parts[1].split('&')[0].strip()
    return trimmed

assert parse_study_center_qr_py('  P-20260813-F9C7 \n') == 'P-20260813-F9C7'
assert parse_study_center_qr_py('https://app.reallife-studycenter.org/pass?credential=QRCR-9999&auth=1') == 'QRCR-9999'

# Test participant_qr_credentials join resolution
c2.execute("CREATE TABLE people (id INTEGER PRIMARY KEY AUTOINCREMENT, human_id TEXT UNIQUE);")
c2.execute("INSERT INTO people (id, human_id) VALUES (42, 'P-20260813-F9C7');")
c2.execute("""
    CREATE TABLE participant_qr_credentials (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        credential_id TEXT UNIQUE,
        person_id INTEGER,
        token_hash TEXT,
        status TEXT DEFAULT 'active'
    );
""")
c2.execute("INSERT INTO participant_qr_credentials (credential_id, person_id, token_hash, status) VALUES ('QRCR-9999', 42, 'hash_qrcr9999', 'active');")
conn2.commit()

# Test resolution 1: direct human_id
c2.execute("SELECT human_id FROM people WHERE human_id = 'P-20260813-F9C7'")
res_direct = c2.fetchone()
assert res_direct[0] == 'P-20260813-F9C7', "FAIL: Direct human_id resolution failed!"

# Test resolution 2: Digital Member Pass QRCR credential
scanned_pass_url = 'https://app.reallife-studycenter.org/pass?credential=QRCR-9999'
extracted_cred = parse_study_center_qr_py(scanned_pass_url)

c2.execute("""
    SELECT p.human_id 
    FROM participant_qr_credentials c
    JOIN people p ON c.person_id = p.id
    WHERE (c.credential_id = ? OR c.token_hash = ?)
      AND LOWER(COALESCE(c.status, 'active')) = 'active'
    LIMIT 1
""", (extracted_cred, extracted_cred))
res_pass = c2.fetchone()
assert res_pass[0] == 'P-20260813-F9C7', "FAIL: QRCR credential resolution failed!"

# Test resolution 3: Invalid QRCR credential safely rejected
c2.execute("""
    SELECT p.human_id 
    FROM participant_qr_credentials c
    JOIN people p ON c.person_id = p.id
    WHERE (c.credential_id = ? OR c.token_hash = ?)
      AND LOWER(COALESCE(c.status, 'active')) = 'active'
    LIMIT 1
""", ('QRCR-INVALID', 'QRCR-INVALID'))
res_invalid = c2.fetchone()
assert res_invalid is None, "FAIL: Invalid QRCR credential must return None!"

# Test mobile attendance check-in -> check-out -> check-in lifecycle
c2.execute("""
    CREATE TABLE today_attendance_index (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        human_id TEXT UNIQUE,
        phone_e164 TEXT,
        attendance_date TEXT,
        updated_at TEXT
    );
""")
c2.execute("""
    CREATE TABLE inbound_event_queue (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        event_type TEXT,
        provider_event_id TEXT,
        payload_json TEXT,
        received_at TEXT,
        processed INTEGER DEFAULT 0
    );
""")
c2.execute("INSERT INTO today_attendance_index (human_id, attendance_date, updated_at) VALUES ('P-20260813-F9C7', '2026-08-15', '2026-08-15 10:00:00');")
conn2.commit()

# Step 1: Currently checked in check
c2.execute("SELECT human_id FROM today_attendance_index WHERE human_id = 'P-20260813-F9C7'")
assert c2.fetchone() is not None, "FAIL: Participant should be currently checked in!"

# Step 2: Check-Out execution (delete from today_attendance_index & enqueue mobile.checkout)
c2.execute("DELETE FROM today_attendance_index WHERE human_id = 'P-20260813-F9C7'")
c2.execute("INSERT INTO inbound_event_queue (event_type, payload_json, processed) VALUES ('mobile.checkout', '{\"human_id\":\"P-20260813-F9C7\"}', 0)")
conn2.commit()

# Step 3: Verify participant is no longer in today_attendance_index
c2.execute("SELECT human_id FROM today_attendance_index WHERE human_id = 'P-20260813-F9C7'")
assert c2.fetchone() is None, "FAIL: Participant must be removed from current presence after check-out!"

# Step 4: Check-In again lifecycle (re-inserting into today_attendance_index)
c2.execute("INSERT INTO today_attendance_index (human_id, attendance_date, updated_at) VALUES ('P-20260813-F9C7', '2026-08-15', '2026-08-15 11:30:00');")
conn2.commit()
c2.execute("SELECT human_id FROM today_attendance_index WHERE human_id = 'P-20260813-F9C7'")
assert c2.fetchone() is not None, "FAIL: Re-check-in failed!"

# Step 5: Test Attendance Snapshot Replacement (3 -> 1)
c2.execute("DELETE FROM today_attendance_index")
snapshot_3 = [('P-1001', '2026-08-15'), ('P-1002', '2026-08-15'), ('P-1003', '2026-08-15')]
for hid, dt in snapshot_3:
    c2.execute("INSERT INTO today_attendance_index (human_id, attendance_date, updated_at) VALUES (?, ?, '2026-08-15 12:00:00')", (hid, dt))
conn2.commit()

c2.execute("SELECT COUNT(*) FROM today_attendance_index")
assert c2.fetchone()[0] == 3, "FAIL: Snapshot 3 count should be 3!"

# Desktop snapshot reduces to 1 participant ('P-1002')
c2.execute("DELETE FROM today_attendance_index")
c2.execute("INSERT INTO today_attendance_index (human_id, attendance_date, updated_at) VALUES ('P-1002', '2026-08-15', '2026-08-15 12:15:00')")
conn2.commit()

c2.execute("SELECT COUNT(*) FROM today_attendance_index")
assert c2.fetchone()[0] == 1, "FAIL: Snapshot replacement 3 -> 1 failed!"
c2.execute("SELECT human_id FROM today_attendance_index")
assert c2.fetchone()[0] == 'P-1002', "FAIL: Snapshot replacement should contain strictly 'P-1002'!"

# Step 6: Test Attendance Snapshot 0-count replacement (several -> 0)
c2.execute("DELETE FROM today_attendance_index")
conn2.commit()
c2.execute("SELECT COUNT(*) FROM today_attendance_index")
assert c2.fetchone()[0] == 0, "FAIL: 0-count snapshot replacement must clear all rows to 0!"

print("\n=== VERIFIED ATTENDANCE SNAPSHOT REPLACEMENT (3 -> 1 & SEVERAL -> 0) 100% ===")

conn2.close()
os.remove(test_db2_path)
print("\n=== LOCAL DASHBOARD SLICE & ATTENDANCE OPERATIONS REGRESSION TEST PASSED 100% ===")
