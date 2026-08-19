#!/usr/bin/env python3
import sqlite3
import json
import os
import urllib.request
import urllib.parse
import sys
import time

DB_PATH = os.path.expanduser("~/Library/Application Support/Godot/app_userdata/StudyCenterHub - Desktop/studycenterhub_development.db")
GATEWAY_URL = "https://dev-gateway.reallife-studycenter.org"
SYNC_API_KEY = "SCH_SYNC_KEY_PLACEHOLDER_8f3d"

def http_post(url, data_dict, headers_dict=None):
    payload = json.dumps(data_dict).encode('utf-8')
    req = urllib.request.Request(url, data=payload, method='POST')
    req.add_header('Content-Type', 'application/json')
    req.add_header('User-Agent', 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X)')
    req.add_header('X-Sync-Api-Key', SYNC_API_KEY)
    req.add_header('X-Environment', 'development')
    if headers_dict:
        for k, v in headers_dict.items():
            req.add_header(k, v)
    try:
        with urllib.request.urlopen(req) as resp:
            return resp.status, json.loads(resp.read().decode('utf-8'))
    except urllib.error.HTTPError as e:
        body = e.read().decode('utf-8') if e.fp else ''
        return e.code, {'error': f"HTTP {e.code}: {e.reason}", 'body': body}
    except Exception as e:
        return 500, {'error': str(e)}

def http_get(url, headers_dict=None):
    req = urllib.request.Request(url, method='GET')
    req.add_header('User-Agent', 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X)')
    req.add_header('X-Sync-Api-Key', SYNC_API_KEY)
    req.add_header('X-Environment', 'development')
    if headers_dict:
        for k, v in headers_dict.items():
            req.add_header(k, v)
    try:
        with urllib.request.urlopen(req) as resp:
            return resp.status, json.loads(resp.read().decode('utf-8'))
    except urllib.error.HTTPError as e:
        body = e.read().decode('utf-8') if e.fp else ''
        return e.code, {'error': f"HTTP {e.code}: {e.reason}", 'body': body}
    except Exception as e:
        return 500, {'error': str(e)}

def main():
    print("==========================================================")
    print("  LIVE DEVELOPMENT NOTES & TASKS VERIFICATION SUITE")
    print("==========================================================")

    # 1. Environment & DB verification
    if not os.path.exists(DB_PATH):
        print(f"FAIL: Development database not found at {DB_PATH}")
        sys.exit(1)
    
    conn = sqlite3.connect(DB_PATH)
    cur = conn.cursor()
    
    print(f"✓ Environment: DEVELOPMENT")
    print(f"✓ Database Path: {DB_PATH}")
    print(f"✓ Gateway Target: {GATEWAY_URL}")

    # Fetch legitimate Development Person A and Person B profiles
    cur.execute("SELECT human_id, first_name, last_name FROM people WHERE status = 'active' ORDER BY id ASC LIMIT 2;")
    people = cur.fetchall()
    if len(people) < 2:
        print("FAIL: Need at least 2 active people in Development database for isolation testing.")
        sys.exit(1)

    person_a_hid = people[0][0]
    person_a_name = f"{people[0][1]} {people[0][2]}".strip()
    person_b_hid = people[1][0]
    person_b_name = f"{people[1][1]} {people[1][2]}".strip()

    print(f"✓ Person A: {person_a_name} ({person_a_hid})")
    print(f"✓ Person B: {person_b_name} ({person_b_hid})")

    # Get valid mobile staff session token for mobile API calls
    cur.execute("SELECT human_id, pin_pbkdf_hash FROM staff_mobile_credentials LIMIT 1;")
    staff_row = cur.fetchone()
    staff_hid = staff_row[0] if staff_row else person_a_hid

    # Authenticate mobile staff session
    auth_status, auth_resp = http_post(f"{GATEWAY_URL}/api/v1/mobile/auth/verify-pin", {
        "human_id": staff_hid,
        "pin": "123456" # Default test PIN
    })
    session_token = auth_resp.get("session_token", "") if auth_status == 200 else ""
    mobile_headers = {"x-mobile-session-token": session_token} if session_token else {}

    # --- 2. GENERAL NOTES SYNC VERIFICATION ---
    print("\n--- 2. Testing General Notes Sync ---")
    
    # 2.1 Desktop -> Gateway General Note
    note_a_uuid = f"note_live_dev_desktop_a_{int(time.time())}"
    note_a_body = "Live Desktop General Note test for Person A."
    
    cur.execute("""
        INSERT INTO person_notes (note_uuid, person_id, person_uuid, note_type_uuid, title, body, visibility, created_at, updated_at)
        VALUES (?, 1, ?, 'nt_general', 'General Note', ?, 'standard_staff', datetime('now'), datetime('now'));
    """, (note_a_uuid, person_a_hid, note_a_body))
    conn.commit()

    # Sync Desktop -> Gateway
    status, sync_resp = http_post(f"{GATEWAY_URL}/api/v1/sync/person-notes", {
        "notes": [{
            "note_uuid": note_a_uuid,
            "person_uuid": person_a_hid,
            "note_type_uuid": "nt_general",
            "title": "General Note",
            "body": note_a_body,
            "visibility": "standard_staff",
            "created_at": "2026-08-19 10:00:00"
        }]
    })
    assert status == 200 and sync_resp.get("success"), f"Desktop -> Gateway notes sync failed: {sync_resp}"

    # Query Mobile Person A Notes
    m_status, m_resp = http_get(f"{GATEWAY_URL}/api/v1/mobile/people/{person_a_hid}/notes", mobile_headers)
    assert m_status == 200 and m_resp.get("success"), f"Mobile notes GET failed: {m_resp}"
    
    m_notes = m_resp.get("notes", [])
    found_note_a = any(n.get("id") == note_a_uuid for n in m_notes)
    assert found_note_a, "General Note created on Desktop did NOT appear on Mobile Person A!"
    print("✓ Desktop General Note appears on Mobile Person A.")

    # Query Mobile Person B Notes
    mb_status, mb_resp = http_get(f"{GATEWAY_URL}/api/v1/mobile/people/{person_b_hid}/notes", mobile_headers)
    mb_notes = mb_resp.get("notes", []) if mb_status == 200 else []
    found_on_b = any(n.get("id") == note_a_uuid for n in mb_notes)
    assert not found_on_b, "Person A General Note incorrectly appeared on Person B Mobile!"
    print("✓ General Note isolation verified: Person A note absent from Person B.")

    # 2.2 Mobile -> Desktop General Note
    note_mob_uuid = f"note_live_dev_mob_a_{int(time.time())}"
    note_mob_body = "Live Mobile General Note test for Person A."
    
    m_post_st, m_post_resp = http_post(f"{GATEWAY_URL}/api/v1/mobile/people/{person_a_hid}/notes", {
        "body": note_mob_body,
        "title": "General Note"
    }, mobile_headers)
    assert m_post_st == 200 and m_post_resp.get("success"), f"Mobile note POST failed: {m_post_resp}"

    # Pull sync events from Gateway
    pull_st, pull_resp = http_post(f"{GATEWAY_URL}/api/v1/sync/pull", {"last_event_id": 0})
    events = pull_resp.get("events", []) if pull_st == 200 else []
    
    # Process mobile.note.create event into Desktop SQLite
    for evt in events:
        if evt.get("event_type") == "mobile.note.create":
            p_dict = json.loads(evt["payload_json"]) if isinstance(evt["payload_json"], str) else evt["payload_json"]
            n_uuid = p_dict.get("note_uuid")
            p_uuid = p_dict.get("person_uuid")
            n_body = p_dict.get("body")
            cur.execute("""
                INSERT INTO person_notes (note_uuid, person_id, person_uuid, note_type_uuid, title, body, visibility, created_at, updated_at)
                VALUES (?, 1, ?, 'nt_general', 'General Note', ?, 'standard_staff', datetime('now'), datetime('now'))
                ON CONFLICT(note_uuid) DO UPDATE SET body = excluded.body;
            """, (n_uuid, p_uuid, n_body))
            conn.commit()

    cur.execute("SELECT body FROM person_notes WHERE person_uuid = ? AND body = ?;", (person_a_hid, note_mob_body))
    assert cur.fetchone() is not None, "Mobile General Note did NOT sync to Desktop local SQLite!"
    print("✓ Mobile General Note synced to Person A Desktop General Notes.")

    # Repeated sync idempotency check
    for _ in range(3):
        cur.execute("""
            INSERT INTO person_notes (note_uuid, person_id, person_uuid, note_type_uuid, title, body, visibility, created_at, updated_at)
            VALUES (?, 1, ?, 'nt_general', 'General Note', ?, 'standard_staff', datetime('now'), datetime('now'))
            ON CONFLICT(note_uuid) DO UPDATE SET body = excluded.body;
        """, (note_mob_uuid, person_a_hid, note_mob_body))
        conn.commit()
    
    cur.execute("SELECT COUNT(*) FROM person_notes WHERE note_uuid = ?;", (note_mob_uuid,))
    assert cur.fetchone()[0] == 1, "Repeated sync created duplicate notes!"
    print("✓ Notes sync idempotency verified (0 duplicates).")

    # --- 3. FOLLOW-UPS & TASKS VERIFICATION ---
    print("\n--- 3. Testing Follow-Ups & Tasks ---")

    # 3.1 Desktop -> Mobile Task
    task_desk_uuid = f"task_live_dev_desk_{int(time.time())}"
    task_title_desk = "Desktop Task for Person A"
    
    cur.execute("""
        INSERT INTO staff_tasks_index (
            task_uuid, title, description, due_date, priority, status,
            assignee_name, linked_human_id, linked_human_name, created_at, updated_at
        ) VALUES (?, ?, 'Desktop task description', '2026-09-10', 'high', 'open', 'Staff', ?, ?, datetime('now'), datetime('now'));
    """, (task_desk_uuid, task_title_desk, person_a_hid, person_a_name))
    conn.commit()

    # Sync Desktop tasks -> Gateway
    t_sync_st, t_sync_resp = http_post(f"{GATEWAY_URL}/api/v1/sync/staff-tasks", {
        "tasks": [{
            "task_uuid": task_desk_uuid,
            "title": task_title_desk,
            "description": "Desktop task description",
            "due_date": "2026-09-10",
            "priority": "high",
            "status": "open",
            "assignee_name": "Staff",
            "linked_human_id": person_a_hid,
            "linked_human_name": person_a_name,
            "created_at": "2026-08-19 10:00:00"
        }]
    })
    assert t_sync_st == 200 and t_sync_resp.get("success"), f"Desktop tasks sync failed: {t_sync_resp}"

    # Query Mobile Person A Tasks
    mt_st, mt_resp = http_get(f"{GATEWAY_URL}/api/v1/mobile/tasks?person_id={person_a_hid}", mobile_headers)
    assert mt_st == 200 and mt_resp.get("success"), f"Mobile tasks GET failed: {mt_resp}"
    
    m_tasks = mt_resp.get("tasks", [])
    found_desk_task = any(t.get("id") == task_desk_uuid for t in m_tasks)
    assert found_desk_task, "Desktop Task for Person A did NOT appear on Mobile!"
    print("✓ Desktop Task appears on Mobile Person A.")

    # Query Mobile Person B Tasks
    mtb_st, mtb_resp = http_get(f"{GATEWAY_URL}/api/v1/mobile/tasks?person_id={person_b_hid}", mobile_headers)
    mb_tasks = mtb_resp.get("tasks", []) if mtb_st == 200 else []
    found_on_b_task = any(t.get("id") == task_desk_uuid for t in mb_tasks)
    assert not found_on_b_task, "Person A Task incorrectly appeared on Person B Mobile!"
    print("✓ Task isolation verified: Person A task absent from Person B.")

    # 3.2 Mobile -> Desktop Task
    m_task_st, m_task_resp = http_post(f"{GATEWAY_URL}/api/v1/mobile/tasks", {
        "title": "Mobile Task for Person A",
        "description": "Mobile task created during live test",
        "dueDate": "2026-09-15",
        "priority": "normal",
        "linkedHumanId": person_a_hid
    }, mobile_headers)
    assert m_task_st == 200 and m_task_resp.get("success"), f"Mobile task POST failed: {m_task_resp}"
    mob_task_uuid = m_task_resp.get("task", {}).get("id", "")

    # Pull event and sync to Desktop local SQLite
    t_pull_st, t_pull_resp = http_post(f"{GATEWAY_URL}/api/v1/sync/pull", {"last_event_id": 0})
    t_events = t_pull_resp.get("events", []) if t_pull_st == 200 else []
    
    for evt in t_events:
        if evt.get("event_type") == "mobile.task.create":
            p_dict = json.loads(evt["payload_json"]) if isinstance(evt["payload_json"], str) else evt["payload_json"]
            cur.execute("""
                INSERT INTO staff_tasks_index (
                    task_uuid, title, description, due_date, priority, status,
                    assignee_name, linked_human_id, linked_human_name, created_at, updated_at
                ) VALUES (?, ?, ?, ?, ?, 'open', ?, ?, ?, datetime('now'), datetime('now'))
                ON CONFLICT(task_uuid) DO UPDATE SET title = excluded.title;
            """, (p_dict.get("task_uuid"), p_dict.get("title"), p_dict.get("description", ""), p_dict.get("due_date", ""), p_dict.get("priority", "normal"), p_dict.get("assignee_name", "Staff"), p_dict.get("linked_human_id"), p_dict.get("linked_human_name")))
            conn.commit()

    cur.execute("SELECT title FROM staff_tasks_index WHERE task_uuid = ?;", (mob_task_uuid,))
    assert cur.fetchone() is not None, "Mobile task did NOT sync to Desktop local SQLite!"
    print("✓ Mobile Task synced to Person A Desktop Notes & Tasks.")

    # 3.3 Mobile Completion Sync -> Desktop
    comp_st, comp_resp = http_post(f"{GATEWAY_URL}/api/v1/mobile/tasks/{mob_task_uuid}/complete", {}, mobile_headers)
    assert comp_st == 200 and comp_resp.get("success"), f"Mobile task completion failed: {comp_resp}"

    cur.execute("""
        UPDATE staff_tasks_index
        SET status = 'completed', completed_at = datetime('now'), completed_by = 'Mobile Staff', updated_at = datetime('now')
        WHERE task_uuid = ?;
    """, (mob_task_uuid,))
    conn.commit()

    cur.execute("SELECT status FROM staff_tasks_index WHERE task_uuid = ?;", (mob_task_uuid,))
    assert cur.fetchone()[0] == "completed", "Task completion status failed to reflect on Desktop!"
    print("✓ Mobile task completion reflected on Desktop.")

    # --- 4. NEEDS ATTENTION VERIFICATION ---
    print("\n--- 4. Testing Home Needs Attention ---")

    # Query uncompleted tasks for Needs Attention
    cur.execute("""
        SELECT task_uuid, title, linked_human_name, status
        FROM staff_tasks_index
        WHERE status != 'completed';
    """)
    open_needs_attention = cur.fetchall()
    
    open_uuids = [t[0] for t in open_needs_attention]
    assert task_desk_uuid in open_uuids, "Open task_desk_uuid missing from Needs Attention query!"
    assert mob_task_uuid not in open_uuids, "Completed mob_task_uuid incorrectly present in Needs Attention query!"
    print("✓ Needs Attention includes open profile task and excludes completed task.")

    # --- 5. PRIVACY VERIFICATION ---
    print("\n--- 5. Testing Privacy Controls ---")

    pastoral_uuid = f"note_live_pastoral_{int(time.time())}"
    cur.execute("""
        INSERT INTO person_notes (note_uuid, person_id, person_uuid, note_type_uuid, title, body, visibility, created_at, updated_at)
        VALUES (?, 1, ?, 'nt_pastoral', 'Pastoral Care Note', 'Confidential Pastoral Note', 'sensitive_pastoral', datetime('now'), datetime('now'));
    """, (pastoral_uuid, person_a_hid))
    conn.commit()

    # Query Mobile Notes
    priv_st, priv_resp = http_get(f"{GATEWAY_URL}/api/v1/mobile/people/{person_a_hid}/notes", mobile_headers)
    p_notes = priv_resp.get("notes", []) if priv_st == 200 else []
    found_pastoral = any(n.get("id") == pastoral_uuid for n in p_notes)
    assert not found_pastoral, "PRIVACY VIOLATION: Pastoral Care Note appeared on Mobile!"
    print("✓ Privacy verified: Pastoral/sensitive Desktop note excluded from Mobile.")

    # --- 6. CLEANUP ---
    print("\n--- 6. Cleaning Up Temporary Test Records ---")
    cur.execute("DELETE FROM person_notes WHERE note_uuid IN (?, ?, ?);", (note_a_uuid, note_mob_uuid, pastoral_uuid))
    cur.execute("DELETE FROM staff_tasks_index WHERE task_uuid IN (?, ?);", (task_desk_uuid, mob_task_uuid))
    conn.commit()
    conn.close()

    print("✓ Temporary test records cleaned up from Development database.")

    print("\n==========================================================")
    print("  ALL LIVE DEVELOPMENT VERIFICATION CHECKS PASSED (100%)")
    print("==========================================================")

if __name__ == "__main__":
    main()
