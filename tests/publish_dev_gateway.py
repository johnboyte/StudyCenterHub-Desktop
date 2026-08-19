import sqlite3
import json
import urllib.request
import ssl

db_path = "/Users/johnboyte/Library/Application Support/Godot/app_userdata/StudyCenterHub - Desktop/studycenterhub_development.db"
conn = sqlite3.connect(db_path)
conn.row_factory = sqlite3.Row
cursor = conn.cursor()

gateway_url = "https://dev-gateway.reallife-studycenter.org"
sync_key = "SCH_SYNC_KEY_PLACEHOLDER_8f3d"

ctx = ssl.create_default_context()
ctx.check_hostname = False
ctx.verify_mode = ssl.CERT_NONE

def post_sync(endpoint, payload):
    url = gateway_url + endpoint
    data_bytes = json.dumps(payload).encode('utf-8')
    req = urllib.request.Request(url, data=data_bytes, headers={
        'Content-Type': 'application/json',
        'User-Agent': 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X)',
        'X-Sync-Api-Key': sync_key,
        'X-Environment': 'development'
    })
    try:
        with urllib.request.urlopen(req, context=ctx) as resp:
            res_text = resp.read().decode('utf-8')
            print(f"[{endpoint}] SUCCESS ({resp.status}):", res_text)
            return json.loads(res_text)
    except Exception as e:
        print(f"[{endpoint}] ERROR:", e)
        return None

print("==========================================================")
print("PUBLISHING DEVELOPMENT SEED DATASET TO DEV GATEWAY")
print("==========================================================")

# 1. Publish Directory Index (30 people)
cursor.execute("SELECT human_id, person_uuid, first_name, COALESCE(last_name, '') as last_name, phone, COALESCE(primary_email, '') as primary_email, COALESCE(sms_consent, 1) as sms_consent, COALESCE(profile_photo, '') as profile_photo FROM people;")
members = [dict(r) for r in cursor.fetchall()]
print(f"1. Directory Members Count: {len(members)}")
post_sync('/api/v1/sync/directory-index', {'members': members})

# 2. Publish Sessions Index (8 sessions)
cursor.execute("SELECT id as session_id, COALESCE(session_uuid, 'sess_' || id) as session_uuid, title, COALESCE(session_type, 'General') as session_type, date_text, start_time, end_time, room_location, max_capacity, COALESCE(signup_required, 1) as signup_required, COALESCE(public_signup_enabled, 1) as public_signup_enabled FROM sessions;")
sessions = [dict(r) for r in cursor.fetchall()]

# Add signup counts
for s in sessions:
    sid = s['session_id']
    cursor.execute("SELECT COUNT(*) FROM session_signups WHERE session_id = ? AND signup_status = 'confirmed';", (sid,))
    s['confirmed_count'] = cursor.fetchone()[0]
    cursor.execute("SELECT COUNT(*) FROM session_signups WHERE session_id = ? AND signup_status = 'waitlist';", (sid,))
    s['waitlist_count'] = cursor.fetchone()[0]

print(f"2. Sessions Count: {len(sessions)}")
post_sync('/api/v1/sync/session-index', {'sessions': sessions})

# 3. Publish Operating Hours
cursor.execute("SELECT day_of_week, open_time, close_time, is_closed FROM center_open_hours;")
hours = [dict(r) for r in cursor.fetchall()]
print(f"3. Operating Hours Count: {len(hours)}")
post_sync('/api/v1/sync/operating-hours', {'hours': hours})

# 4. Publish Today Attendance Index
today_date = "2026-08-15"
cursor.execute("SELECT human_id, check_in_date as attendance_date, check_in_time as updated_at FROM attendance_log WHERE check_in_date = ?;", (today_date,))
attendance = [dict(r) for r in cursor.fetchall()]
print(f"4. Today Attendance Count: {len(attendance)}")
post_sync('/api/v1/sync/attendance-index', {'attendance': attendance, 'date': today_date})

# 5. Publish Staff Credentials Index
cursor.execute("""
    SELECT 
        p.id as person_id,
        p.person_uuid,
        p.human_id,
        COALESCE(p.first_name, '') || ' ' || COALESCE(p.last_name, '') as display_name,
        COALESCE(p.primary_email, '') as email,
        COALESCE(p.primary_role, 'Staff') as role,
        smc.pin_pbkdf_hash as pin_hash,
        smc.credential_version,
        smc.mobile_access_enabled
    FROM people p
    JOIN staff_mobile_credentials smc ON smc.person_id = p.id AND smc.mobile_access_enabled = 1
    WHERE p.status = 'active';
""")
staff_items = [dict(r) for r in cursor.fetchall()]
print(f"5. Staff Credentials Count: {len(staff_items)}")
post_sync('/api/v1/sync/staff-credentials-index', {'staff': staff_items})

# 6. Publish General Notes Index
cursor.execute("""
    SELECT 
        pn.note_uuid,
        pn.person_uuid,
        p.human_id,
        pn.note_type_uuid,
        pn.title,
        pn.body,
        pn.visibility,
        pn.created_at,
        pn.updated_at
    FROM person_notes pn
    LEFT JOIN people p ON (pn.person_id = p.id OR pn.person_uuid = p.person_uuid OR pn.person_uuid = p.human_id)
    WHERE pn.is_deleted = 0
      AND (pn.note_type_uuid = 'nt_general' OR pn.title = 'General' OR pn.title = 'General Note' OR pn.title = 'Administrative')
      AND LOWER(COALESCE(pn.visibility, 'standard_staff')) NOT IN ('sensitive_pastoral', 'pastoral', 'confidential', 'private');
""")
notes_items = [dict(r) for r in cursor.fetchall()]
print(f"6. General Notes Count: {len(notes_items)}")
post_sync('/api/v1/sync/person-notes', {'notes': notes_items})

conn.close()
print("==========================================================")
print("DEVELOPMENT PUBLISH SCRIPT COMPLETE")
print("==========================================================")
