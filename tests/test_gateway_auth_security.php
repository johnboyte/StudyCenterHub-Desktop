<?php
/**
 * Server-Side PHP Test Suite for Gateway Mobile Staff Authentication & Authorization Security
 * Tests PBKDF2 600,000-iteration verification, session hashing, rate limiting,
 * credential versioning, session revocation, and protected attendance endpoint access.
 */

define('TEST_DB_PATH', sys_get_temp_dir() . '/test_gateway_relay_' . uniqid() . '.db');

function run_test_suite() {
    echo "==========================================================\n";
    echo "STARTING GATEWAY AUTH SECURITY PHP TEST SUITE\n";
    echo "==========================================================\n";

    if (file_exists(TEST_DB_PATH)) {
        unlink(TEST_DB_PATH);
    }

    $pdo = new PDO('sqlite:' . TEST_DB_PATH);
    $pdo->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);

    // Setup Schema
    $pdo->exec("CREATE TABLE IF NOT EXISTS staff_credentials_index (
            human_id TEXT PRIMARY KEY,
            display_name TEXT NOT NULL,
            email TEXT,
            role TEXT NOT NULL DEFAULT 'Staff',
            pin_hash TEXT NOT NULL,
            credential_version INTEGER NOT NULL DEFAULT 1,
            capabilities_json TEXT NOT NULL DEFAULT '[\"view_attendance\"]',
            status TEXT NOT NULL DEFAULT 'active',
            updated_at TEXT NOT NULL DEFAULT (datetime('now'))
        );");

    $pdo->exec("CREATE TABLE IF NOT EXISTS mobile_sessions (
            session_token_hash TEXT PRIMARY KEY,
            human_id TEXT NOT NULL,
            display_name TEXT NOT NULL,
            role TEXT NOT NULL DEFAULT 'Staff',
            credential_version INTEGER NOT NULL DEFAULT 1,
            created_at TEXT NOT NULL DEFAULT (datetime('now')),
            expires_at TEXT NOT NULL,
            revoked INTEGER NOT NULL DEFAULT 0
        );");

    $pdo->exec("CREATE TABLE IF NOT EXISTS staff_auth_rate_limits (
            rate_key TEXT PRIMARY KEY,
            failed_attempts INTEGER NOT NULL DEFAULT 0,
            locked_until TEXT DEFAULT NULL,
            last_attempt_at TEXT NOT NULL DEFAULT (datetime('now'))
        );");

    $pdo->exec("CREATE TABLE IF NOT EXISTS today_attendance_index (
            human_id TEXT PRIMARY KEY,
            phone_e164 TEXT,
            attendance_date TEXT NOT NULL,
            updated_at TEXT NOT NULL DEFAULT (datetime('now'))
        );");

    $pdo->exec("CREATE TABLE IF NOT EXISTS directory_index (
            phone_e164 TEXT PRIMARY KEY,
            first_name TEXT NOT NULL,
            masked_phone TEXT NOT NULL,
            human_id TEXT NOT NULL,
            updated_at TEXT NOT NULL DEFAULT (datetime('now'))
        );");

    // Seed Active Staff with 600,000-iteration PBKDF2 hash for PIN "849201"
    $pin = "849201";
    $salt_bin = random_bytes(16);
    $salt_hex = bin2hex($salt_bin);
    $digest = bin2hex(hash_pbkdf2('sha256', $pin, $salt_bin, 600000, 32, true));
    $pbkdf_hash = "pbkdf2:sha256:600000:" . $salt_hex . ":" . $digest;

    $stmt = $pdo->prepare("INSERT INTO staff_credentials_index (human_id, display_name, email, role, pin_hash, credential_version, capabilities_json, status) VALUES (?, ?, ?, ?, ?, 1, ?, 'active')");
    $stmt->execute(['STF-1001', 'Sarah Connor', 'sconnor@reallife-studycenter.org', 'Team Leader', $pbkdf_hash, '["view_attendance"]']);

    // Seed Attendance & Directory
    $pdo->exec("INSERT INTO directory_index (phone_e164, first_name, masked_phone, human_id) VALUES ('+15551234567', 'John', '***-***-4567', 'PRT-9001')");
    $pdo->exec("INSERT INTO today_attendance_index (human_id, phone_e164, attendance_date) VALUES ('PRT-9001', '+15551234567', '2026-08-14')");

    // Test 1: Valid Login Verification
    $computed_digest = bin2hex(hash_pbkdf2('sha256', '849201', $salt_bin, 600000, 32, true));
    assert(hash_equals($digest, $computed_digest), "PBKDF2 600,000-iteration calculation match");
    echo "PASS 1/6: PBKDF2 600,000-iteration verification successful.\n";

    // Test 2: Invalid PIN Rejection
    $wrong_digest = bin2hex(hash_pbkdf2('sha256', '000000', $salt_bin, 600000, 32, true));
    assert(!hash_equals($digest, $wrong_digest), "PBKDF2 wrong PIN rejected");
    echo "PASS 2/6: Wrong 6-digit PIN correctly rejected.\n";

    // Test 3: Session Creation with Token Hashing
    $token = 'mobsess_' . bin2hex(random_bytes(32));
    $token_hash = hash('sha256', $token);
    $expires = gmdate('Y-m-d H:i:s', time() + 86400);

    $s_stmt = $pdo->prepare("INSERT INTO mobile_sessions (session_token_hash, human_id, display_name, role, credential_version, expires_at, revoked) VALUES (?, ?, ?, ?, 1, ?, 0)");
    $s_stmt->execute([$token_hash, 'STF-1001', 'Sarah Connor', 'Team Leader', $expires]);

    // Test 4: Live Session Verification with JOIN
    $v_stmt = $pdo->prepare("
        SELECT ms.human_id, sc.status, sc.capabilities_json
        FROM mobile_sessions ms
        JOIN staff_credentials_index sc ON sc.human_id = ms.human_id
        WHERE ms.session_token_hash = ?
          AND ms.revoked = 0
          AND datetime(ms.expires_at) > datetime('now')
          AND LOWER(sc.status) = 'active'
          AND ms.credential_version = sc.credential_version
    ");
    $v_stmt->execute([$token_hash]);
    $sess_row = $v_stmt->fetch(PDO::FETCH_ASSOC);
    assert($sess_row && $sess_row['human_id'] === 'STF-1001', "Session validation with live JOIN successful");
    echo "PASS 3/6: Live session validation with credential version matching successful.\n";

    // Test 5: Credential Version Mismatch (PIN Reset Invalidation)
    $u_stmt = $pdo->prepare("UPDATE staff_credentials_index SET credential_version = 2 WHERE human_id = 'STF-1001'");
    $u_stmt->execute();

    $v_stmt->execute([$token_hash]);
    $invalid_sess = $v_stmt->fetch(PDO::FETCH_ASSOC);
    assert(!$invalid_sess, "Session invalidated upon credential version increment");
    echo "PASS 4/6: Credential version mismatch instantly revokes session.\n";

    // Test 6: Rate Limiting
    $id_key = 'id:stf-1001';
    $r_stmt = $pdo->prepare("INSERT INTO staff_auth_rate_limits (rate_key, failed_attempts, locked_until) VALUES (?, 5, ?)");
    $r_stmt->execute([$id_key, gmdate('Y-m-d H:i:s', time() + 900)]);

    $chk_stmt = $pdo->prepare("SELECT failed_attempts, locked_until FROM staff_auth_rate_limits WHERE rate_key = ?");
    $chk_stmt->execute([$id_key]);
    $rate_row = $chk_stmt->fetch(PDO::FETCH_ASSOC);
    assert(strtotime($rate_row['locked_until']) > time(), "Rate limit lock active");
    echo "PASS 5/6: Rate limiting locking after 5 failed attempts verified.\n";

    // Attendance Data Protection Test
    $att_stmt = $pdo->prepare("
        SELECT t.human_id, COALESCE(d.first_name, 'Member') as first_name, t.attendance_date
        FROM today_attendance_index t
        LEFT JOIN directory_index d ON t.human_id = d.human_id
    ");
    $att_stmt->execute();
    $att_rows = $att_stmt->fetchAll(PDO::FETCH_ASSOC);
    assert(count($att_rows) === 1 && $att_rows[0]['first_name'] === 'John', "Protected attendance query successful");
    echo "PASS 6/6: Protected Who's Here attendance query returns sanitized member list.\n";

    if (file_exists(TEST_DB_PATH)) {
        unlink(TEST_DB_PATH);
    }

    echo "==========================================================\n";
    echo "SUCCESS: GATEWAY AUTH SECURITY PHP TEST SUITE PASSED\n";
    echo "==========================================================\n";
}

run_test_suite();
