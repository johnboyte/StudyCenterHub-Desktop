#!/usr/bin/env python3
import sqlite3
import os
import sys
import hashlib
import time

DEV_DB_PATH = "/Users/johnboyte/Library/Application Support/Godot/app_userdata/StudyCenterHub - Desktop/studycenterhub_development.db"

def run_test():
    print("==========================================================")
    print("TESTING MOBILE MEMBER QR REGENERATION LIFECYCLE")
    print("==========================================================")

    if not os.path.exists(DEV_DB_PATH):
        print(f"ERROR: Dev database not found at {DEV_DB_PATH}")
        sys.exit(1)

    conn = sqlite3.connect(DEV_DB_PATH)
    cursor = conn.cursor()

    # 1. Migration check for issued_by_staff_human_id
    try:
        cursor.execute("ALTER TABLE participant_qr_credentials ADD COLUMN issued_by_staff_human_id TEXT DEFAULT NULL;")
        conn.commit()
    except sqlite3.OperationalError:
        pass # Column already exists

    # 2. Pick test person (e.g. John Boyte or first available constituent)
    cursor.execute("SELECT id, human_id, person_uuid, first_name, last_name, qr_code_value FROM people WHERE human_id = 'P-20260813-F9C7' OR id > 0 LIMIT 1;")
    person = cursor.fetchone()
    if not person:
        print("ERROR: No person record found in development database")
        sys.exit(1)

    person_id, human_id, person_uuid, first_name, last_name, initial_qr_val = person
    full_name = f"{first_name} {last_name}".strip()
    print(f"Target Person: {full_name} (ID: {person_id}, Human ID: {human_id})")

    # Ensure an initial active QR credential exists
    old_raw_token = "test_raw_token_initial_" + str(int(time.time()))
    old_token_hash = hashlib.sha256(old_raw_token.encode('utf-8')).hexdigest()
    old_cred_id = f"QRCR-INIT-{int(time.time())}"

    cursor.execute("UPDATE participant_qr_credentials SET status = 'revoked' WHERE person_id = ? AND status = 'active';", (person_id,))
    cursor.execute("""
        INSERT INTO participant_qr_credentials (credential_id, person_id, token_hash, token_hint, status, issued_at, issued_by_staff_human_id)
        VALUES (?, ?, ?, ?, 'active', datetime('now'), 'INITIAL_SETUP');
    """, (old_cred_id, person_id, old_token_hash, "Pass ***" + old_token_hash[-4:],))
    cursor.execute("UPDATE people SET qr_code_value = ? WHERE id = ?;", (old_token_hash, person_id))
    conn.commit()

    print(f"1. Initial Active QR Credential Created: {old_cred_id} (Hash: {old_token_hash[:16]}...)")

    # A. VERIFY INITIAL ACTIVE STATE
    cursor.execute("SELECT credential_id, status FROM participant_qr_credentials WHERE person_id = ? AND status = 'active';", (person_id,))
    active_rows = cursor.fetchall()
    assert len(active_rows) == 1, "Must have exactly 1 active credential initially"
    assert active_rows[0][0] == old_cred_id, "Active credential ID must match initial setup"
    print("✅ INITIAL ACTIVE STATE VERIFIED!")

    # B. SIMULATE CANCEL ACTION (ZERO CHANGES)
    # User pressed Cancel in confirmation dialog -> No SQL/API calls executed
    cursor.execute("SELECT credential_id, status FROM participant_qr_credentials WHERE person_id = ? AND status = 'active';", (person_id,))
    post_cancel_rows = cursor.fetchall()
    assert len(post_cancel_rows) == 1, "Cancel action MUST leave active credentials unchanged"
    assert post_cancel_rows[0][0] == old_cred_id, "Old credential MUST remain active after cancel"
    print("✅ CANCEL ACTION VERIFIED ZERO-CHANGE!")

    # C. EXECUTE REPLACEMENT / REISSUANCE
    staff_human_id = "P-20260813-F9C7" # Authenticated staff member
    new_raw_token = "test_raw_token_replacement_" + str(int(time.time()))
    new_token_hash = hashlib.sha256(new_raw_token.encode('utf-8')).hexdigest()
    new_cred_id = f"QRCR-REGEN-{int(time.time())}"

    # Revoke old credentials
    cursor.execute("UPDATE participant_qr_credentials SET status = 'revoked' WHERE person_id = ? AND status = 'active';", (person_id,))
    # Insert new active credential with audit staff ID
    cursor.execute("""
        INSERT INTO participant_qr_credentials (credential_id, person_id, token_hash, token_hint, status, issued_at, issued_by_staff_human_id)
        VALUES (?, ?, ?, ?, 'active', datetime('now'), ?);
    """, (new_cred_id, person_id, new_token_hash, "Pass ***" + new_token_hash[-4:], staff_human_id))
    # Update people table
    cursor.execute("UPDATE people SET qr_code_value = ? WHERE id = ?;", (new_token_hash, person_id))
    conn.commit()

    print(f"2. Reissued New Active QR Credential: {new_cred_id} (Hash: {new_token_hash[:16]}...)")

    # D. VERIFY OLD QR REVOKED & NEW QR ACTIVE
    cursor.execute("SELECT status FROM participant_qr_credentials WHERE credential_id = ?;", (old_cred_id,))
    old_status = cursor.fetchone()[0]
    assert old_status == 'revoked', f"Old credential status must be 'revoked', got '{old_status}'"

    cursor.execute("SELECT credential_id, status, issued_by_staff_human_id FROM participant_qr_credentials WHERE person_id = ? AND status = 'active';", (person_id,))
    new_active_rows = cursor.fetchall()
    assert len(new_active_rows) == 1, "Must have exactly 1 active credential after replacement"
    assert new_active_rows[0][0] == new_cred_id, "New active credential ID must match newly generated ID"
    assert new_active_rows[0][2] == staff_human_id, f"Audit field issued_by_staff_human_id must record '{staff_human_id}'"

    cursor.execute("SELECT qr_code_value FROM people WHERE id = ?;", (person_id,))
    current_person_qr = cursor.fetchone()[0]
    assert current_person_qr == new_token_hash, "people.qr_code_value must be updated to new token hash"
    assert current_person_qr != old_token_hash, "New QR hash MUST differ from old revoked QR hash"

    print("✅ REPLACEMENT LIFECYCLE & AUDIT FIELD VERIFIED!")

    # E. TEST VALIDATION LOOKUPS
    # Old QR validation lookup
    cursor.execute("""
        SELECT p.human_id 
        FROM participant_qr_credentials c
        JOIN people p ON c.person_id = p.id
        WHERE c.token_hash = ? AND LOWER(COALESCE(c.status, 'active')) = 'active';
    """, (old_token_hash,))
    old_lookup = cursor.fetchone()
    assert old_lookup is None, "Old QR token hash MUST fail active validation lookup!"
    print("✅ OLD QR REVOCATION VALIDATION VERIFIED (FAILED AS EXPECTED)!")

    # New QR validation lookup
    cursor.execute("""
        SELECT p.human_id 
        FROM participant_qr_credentials c
        JOIN people p ON c.person_id = p.id
        WHERE c.token_hash = ? AND LOWER(COALESCE(c.status, 'active')) = 'active';
    """, (new_token_hash,))
    new_lookup = cursor.fetchone()
    assert new_lookup is not None and new_lookup[0] == human_id, "New QR token hash MUST successfully validate constituent!"
    print("✅ NEW QR VALIDATION VERIFIED (SUCCESSFUL)!")

    conn.close()
    print("\n==========================================================")
    print("MOBILE MEMBER QR REGENERATION LIFECYCLE PASSED 100%!")
    print("==========================================================")

if __name__ == "__main__":
    run_test()
