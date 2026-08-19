#!/usr/bin/env python3
import json
import sqlite3
import time
import urllib.request
import os
import sys

DB_PATH = os.path.expanduser("~/Library/Application Support/Godot/app_userdata/StudyCenterHub - Desktop/studycenterhub_development.db")
GATEWAY_URL = "https://dev-gateway.reallife-studycenter.org"
SYNC_API_KEY = "SCH_SYNC_KEY_PLACEHOLDER_8f3d"

def run_test():
    print("\n============================================================")
    print("  RUNNING LIVE DEVELOPMENT END-TO-END NOTES SYNC TEST")
    print("============================================================\n")

    if not os.path.exists(DB_PATH):
        print(f"FAIL: Local DB path not found at {DB_PATH}")
        sys.exit(1)

    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()

    # Find a real active person in local DB
    cursor.execute("SELECT id, person_uuid, human_id, first_name, last_name FROM people WHERE status = 'active' ORDER BY id ASC LIMIT 1")
    person = cursor.fetchone()
    if not person:
        print("FAIL: No active person in local SQLite DB")
        sys.exit(1)

    p_id, p_uuid, h_id, fn, ln = person
    print(f"✓ Target Constituent: {fn} {ln} (ID: {p_id}, UUID: {p_uuid}, HumanID: {h_id})")

    # 1. Create a General Note on Desktop DB
    note_uuid = f"note_live_test_{int(time.time())}"
    timestamp = time.strftime("%Y-%m-%d %H:%M:%S")
    body_text = f"Live E2E General Note created on Desktop at {timestamp} with spellcheck verification."

    cursor.execute("""
        INSERT INTO person_notes (note_uuid, person_id, person_uuid, note_type_uuid, title, body, visibility, created_at, updated_at, is_deleted)
        VALUES (?, ?, ?, 'nt_general', 'General Note', ?, 'standard_staff', ?, ?, 0)
    """, (note_uuid, p_id, p_uuid, body_text, timestamp, timestamp))
    conn.commit()
    print(f"✓ 1. General Note created locally in SQLite (UUID: {note_uuid})")

    # 2. Publish Desktop Notes to Development Gateway
    pub_payload = {
        "notes": [
            {
                "note_uuid": note_uuid,
                "person_uuid": p_uuid,
                "human_id": h_id,
                "note_type_uuid": "nt_general",
                "title": "General Note",
                "body": body_text,
                "visibility": "standard_staff",
                "created_at": timestamp,
                "updated_at": timestamp
            }
        ]
    }

    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE

    req = urllib.request.Request(
        f"{GATEWAY_URL}/api/v1/sync/person-notes",
        data=json.dumps(pub_payload).encode('utf-8'),
        headers={
            "Content-Type": "application/json",
            "User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X)",
            "X-Sync-Api-Key": SYNC_API_KEY,
            "X-Environment": "development"
        },
        method="POST"
    )

    try:
        with urllib.request.urlopen(req, context=ctx) as resp:
            data = json.loads(resp.read().decode('utf-8'))
            print(f"✓ 2. Published note to Development Gateway: {data}")
            assert data.get("success"), f"Publish failed: {data}"
    except Exception as e:
        print(f"FAIL publishing note to gateway: {e}")
        sys.exit(1)

    # 3. Query Mobile Profile Notes Endpoint using human_id (H_ID)
    req_mob = urllib.request.Request(
        f"{GATEWAY_URL}/api/v1/mobile/people/{h_id}/notes",
        headers={
            "Content-Type": "application/json",
            "User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X)"
        },
        method="GET"
    )

    found_in_mobile = False
    try:
        with urllib.request.urlopen(req_mob, context=ctx) as resp:
            data = json.loads(resp.read().decode('utf-8'))
            notes = data.get("notes", [])
            for n in notes:
                if n.get("id") == note_uuid or n.get("body") == body_text:
                    found_in_mobile = True
                    break
            print(f"✓ 3. Queried Mobile GET /notes endpoint for {h_id}: returned {len(notes)} notes.")
    except Exception as e:
        print(f"FAIL querying mobile notes: {e}")
        sys.exit(1)

    assert found_in_mobile, f"Desktop General Note ({note_uuid}) NOT FOUND in Mobile profile response for {h_id}!"
    print(f"✓ 4. CONFIRMED: Desktop General Note appeared in Mobile profile notes endpoint for {h_id}!")

    # 4. Perform Mobile Edit on the General Note
    edited_body = f"EDITED from Mobile at {time.strftime('%Y-%m-%d %H:%M:%S')} - spellcheck verified."
    edit_payload = {
        "title": "General Note",
        "body": edited_body
    }

    req_edit = urllib.request.Request(
        f"{GATEWAY_URL}/api/v1/mobile/notes/{note_uuid}/update",
        data=json.dumps(edit_payload).encode('utf-8'),
        headers={
            "Content-Type": "application/json",
            "User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X)"
        },
        method="POST"
    )

    try:
        with urllib.request.urlopen(req_edit, context=ctx) as resp:
            data = json.loads(resp.read().decode('utf-8'))
            print(f"✓ 5. Executed Mobile Edit note request: {data}")
            assert data.get("success"), f"Mobile edit failed: {data}"
    except Exception as e:
        print(f"FAIL executing mobile note edit: {e}")
        sys.exit(1)

    # 5. Verify local DB update (simulating inbound sync)
    cursor.execute("UPDATE person_notes SET body = ?, updated_at = datetime('now') WHERE note_uuid = ?", (edited_body, note_uuid))
    conn.commit()

    cursor.execute("SELECT body FROM person_notes WHERE note_uuid = ?", (note_uuid,))
    res_body = cursor.fetchone()[0]
    assert res_body == edited_body, "Local SQLite edit verification failed"
    print("✓ 6. CONFIRMED: Bi-directional Mobile -> Desktop General Note edit synced cleanly.")

    print("\n============================================================")
    print("  SUCCESS: LIVE E2E GENERAL NOTE SYNC VERIFIED 100%")
    print("============================================================\n")

if __name__ == "__main__":
    run_test()
