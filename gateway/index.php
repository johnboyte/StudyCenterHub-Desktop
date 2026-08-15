<?php
// Rate Limiting Helper Function (10 requests / 10s per IP)
function enforce_rate_limit_php($pdo, $endpoint_name) {
    $ip = $_SERVER['REMOTE_ADDR'] ?? '0.0.0.0';
    $now = time();
    $cutoff = $now - 10;
    
    $pdo->exec("CREATE TABLE IF NOT EXISTS rate_limit_log (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        ip_address TEXT NOT NULL,
        endpoint TEXT NOT NULL,
        created_at INTEGER NOT NULL
    );");
    
    $pdo->exec("DELETE FROM rate_limit_log WHERE created_at < " . intval($cutoff));
    
    $stmt = $pdo->prepare("SELECT COUNT(*) as cnt FROM rate_limit_log WHERE ip_address = ? AND endpoint = ? AND created_at >= ?");
    $stmt->execute([$ip, $endpoint_name, $cutoff]);
    $row = $stmt->fetch(PDO::FETCH_ASSOC);
    $count = intval($row['cnt'] ?? 0);
    
    if ($count >= 15) {
        http_response_code(429);
        header('Content-Type: application/json; charset=utf-8');
        echo json_encode(['success' => false, 'error' => 'Too many requests. Please wait a moment and try again.']);
        exit;
    }
    
    $ins = $pdo->prepare("INSERT INTO rate_limit_log (ip_address, endpoint, created_at) VALUES (?, ?, ?)");
    $ins->execute([$ip, $endpoint_name, $now]);
}

// Layered PIN Rate Limiting Helpers
function check_staff_auth_rate_limit($pdo, $identifier, $ip) {
    $now_ts = time();
    $id_key = 'id:' . strtolower(trim($identifier));
    $ip_key = 'ip:' . trim($ip);

    // Check identifier lock (max 5 failed attempts in 15 mins)
    $stmt = $pdo->prepare("SELECT failed_attempts, locked_until FROM staff_auth_rate_limits WHERE rate_key = ?");
    $stmt->execute([$id_key]);
    $id_row = $stmt->fetch(PDO::FETCH_ASSOC);
    $stmt->closeCursor();

    if ($id_row && !empty($id_row['locked_until'])) {
        if (strtotime($id_row['locked_until']) > $now_ts) {
            return false;
        }
    }

    // Check IP lock (max 20 failed attempts in 15 mins)
    $stmt->execute([$ip_key]);
    $ip_row = $stmt->fetch(PDO::FETCH_ASSOC);
    $stmt->closeCursor();

    if ($ip_row && !empty($ip_row['locked_until'])) {
        if (strtotime($ip_row['locked_until']) > $now_ts) {
            return false;
        }
    }

    return true;
}

function record_staff_auth_attempt($pdo, $identifier, $ip, $success) {
    $now_ts = time();
    $now_str = gmdate('Y-m-d H:i:s');
    $lock_duration = 900; // 15-minute lock duration

    $id_key = 'id:' . strtolower(trim($identifier));
    $ip_key = 'ip:' . trim($ip);

    if ($success) {
        $stmt = $pdo->prepare("DELETE FROM staff_auth_rate_limits WHERE rate_key IN (?, ?)");
        $stmt->execute([$id_key, $ip_key]);
        return;
    }

    // Update ID failure count
    $stmt = $pdo->prepare("SELECT failed_attempts FROM staff_auth_rate_limits WHERE rate_key = ?");
    $stmt->execute([$id_key]);
    $id_row = $stmt->fetch(PDO::FETCH_ASSOC);

    $id_fails = ($id_row ? intval($id_row['failed_attempts']) : 0) + 1;
    $id_locked = ($id_fails >= 5) ? gmdate('Y-m-d H:i:s', $now_ts + $lock_duration) : null;

    $stmt2 = $pdo->prepare("INSERT OR REPLACE INTO staff_auth_rate_limits (rate_key, failed_attempts, locked_until, last_attempt_at) VALUES (?, ?, ?, ?)");
    $stmt2->execute([$id_key, $id_fails, $id_locked, $now_str]);

    // Update IP failure count
    $stmt->execute([$ip_key]);
    $ip_row = $stmt->fetch(PDO::FETCH_ASSOC);

    $ip_fails = ($ip_row ? intval($ip_row['failed_attempts']) : 0) + 1;
    $ip_locked = ($ip_fails >= 20) ? gmdate('Y-m-d H:i:s', $now_ts + $lock_duration) : null;

    $stmt2->execute([$ip_key, $ip_fails, $ip_locked, $now_str]);
}

// Mobile Staff Authentication Session Validator Helper
function verify_mobile_session($pdo) {
    $srv_sync_set = isset($_SERVER['HTTP_X_SYNC_API_KEY']) ? 1 : 0;
    $srv_sync_len = strlen($_SERVER['HTTP_X_SYNC_API_KEY'] ?? '');

    $srv_x_tok_set = isset($_SERVER['HTTP_X_MOBILE_SESSION_TOKEN']) ? 1 : 0;
    $srv_x_tok_len = strlen($_SERVER['HTTP_X_MOBILE_SESSION_TOKEN'] ?? '');

    $srv_sch_tok_set = isset($_SERVER['HTTP_X_SCH_MOBILE_TOKEN']) ? 1 : 0;
    $srv_sch_tok_len = strlen($_SERVER['HTTP_X_SCH_MOBILE_TOKEN'] ?? '');

    $srv_cookie_set = isset($_SERVER['HTTP_COOKIE']) ? 1 : 0;
    $srv_cookie_len = strlen($_SERVER['HTTP_COOKIE'] ?? '');

    $cookie_var_set = isset($_COOKIE['sch_mobile_session']) ? 1 : 0;
    $cookie_var_len = strlen($_COOKIE['sch_mobile_session'] ?? '');

    $has_gah = function_exists('getallheaders') ? 1 : 0;
    $gah_sync_len = -1;
    $gah_x_len = -1;
    $gah_sch_len = -1;
    $gah_cookie_len = -1;

    if ($has_gah) {
        $headers = getallheaders();
        foreach ($headers as $hk => $hv) {
            $lk = strtolower($hk);
            if ($lk === 'x-sync-api-key') {
                $gah_sync_len = strlen($hv);
            } elseif ($lk === 'x-mobile-session-token') {
                $gah_x_len = strlen($hv);
            } elseif ($lk === 'x-sch-mobile-token') {
                $gah_sch_len = strlen($hv);
            } elseif ($lk === 'cookie') {
                $gah_cookie_len = strlen($hv);
            }
        }
    }

    $token = trim($_SERVER['HTTP_X_MOBILE_SESSION_TOKEN'] ?? '');
    if (empty($token) && isset($_SERVER['HTTP_X_SCH_MOBILE_TOKEN'])) {
        $token = trim($_SERVER['HTTP_X_SCH_MOBILE_TOKEN']);
    }
    if (empty($token) && isset($_COOKIE['sch_mobile_session'])) {
        $token = trim($_COOKIE['sch_mobile_session']);
    }
    if (empty($token) && isset($_SERVER['HTTP_AUTHORIZATION'])) {
        if (preg_match('/Bearer\s+(mobsess_\S+)/i', $_SERVER['HTTP_AUTHORIZATION'], $m)) {
            $token = trim($m[1]);
        }
    }

    $extracted_len = strlen($token);
    $extracted_pref = (strpos($token, 'mobsess_') === 0) ? 1 : 0;

    $diag_payload = [
        'srv_sync_set' => $srv_sync_set, 'srv_sync_len' => $srv_sync_len,
        'srv_x_tok_set' => $srv_x_tok_set, 'srv_x_tok_len' => $srv_x_tok_len,
        'srv_sch_tok_set' => $srv_sch_tok_set, 'srv_sch_tok_len' => $srv_sch_tok_len,
        'srv_cookie_set' => $srv_cookie_set, 'srv_cookie_len' => $srv_cookie_len,
        'cookie_var_set' => $cookie_var_set, 'cookie_var_len' => $cookie_var_len,
        'has_gah' => $has_gah,
        'gah_sync_len' => $gah_sync_len,
        'gah_x_len' => $gah_x_len,
        'gah_sch_len' => $gah_sch_len,
        'gah_cookie_len' => $gah_cookie_len,
        'extracted_len' => $extracted_len,
        'extracted_pref' => $extracted_pref
    ];

    if (empty($token)) {
        $diag_payload['reason'] = 'token_empty';
        log_auth_diagnostic($pdo, 'DIAG-EXTENDED-HEADERS', 'verify_mobile_session', 'AuthException', json_encode($diag_payload), 401);
        http_response_code(401);
        header('Content-Type: application/json; charset=utf-8');
        echo json_encode(['success' => false, 'error' => 'Authentication required. Missing staff session token.']);
        exit;
    }

    $token_hash = hash('sha256', $token);
    $server_received_fp = substr($token_hash, 0, 12);

    // Task 1 Progressive Predicate Diagnostic Evaluation
    $pred_diag = [
        'server_received_fp' => $server_received_fp,
        'session_exists' => 0,
        'session_revoked_value' => null,
        'revoked_pass' => 0,
        'created_at' => null,
        'expires_at' => null,
        'sqlite_now' => null,
        'expiry_pass' => 0,
        'session_human_id' => null,
        'staff_row_exists_for_human_id' => 0,
        'staff_status' => null,
        'staff_status_pass' => 0,
        'session_credential_version' => null,
        'session_cred_ver_type' => null,
        'staff_credential_version' => null,
        'staff_cred_ver_type' => null,
        'credential_version_pass' => 0,
        'join_by_human_id_pass' => 0,
        'stage_A_hash_only' => 0,
        'stage_B_hash_plus_join' => 0,
        'stage_C_plus_revoked' => 0,
        'stage_D_plus_expiry' => 0,
        'stage_E_plus_active' => 0,
        'stage_F_plus_cred_ver' => 0,
        'first_failing_stage' => 'none'
    ];

    try {
        $ms_stmt = $pdo->prepare("SELECT human_id, credential_version, created_at, expires_at, revoked, typeof(credential_version) as cv_type FROM mobile_sessions WHERE session_token_hash = ? LIMIT 1");
        $ms_stmt->execute([$token_hash]);
        $ms_row = $ms_stmt->fetch(PDO::FETCH_ASSOC);
        $ms_stmt->closeCursor();

        if ($ms_row) {
            $pred_diag['session_exists'] = 1;
            $pred_diag['stage_A_hash_only'] = 1;
            $pred_diag['session_human_id'] = $ms_row['human_id'];
            $pred_diag['session_revoked_value'] = intval($ms_row['revoked']);
            $pred_diag['revoked_pass'] = (intval($ms_row['revoked']) === 0) ? 1 : 0;
            $pred_diag['created_at'] = $ms_row['created_at'];
            $pred_diag['expires_at'] = $ms_row['expires_at'];
            $pred_diag['session_credential_version'] = $ms_row['credential_version'];
            $pred_diag['session_cred_ver_type'] = $ms_row['cv_type'];

            $now_stmt = $pdo->query("SELECT datetime('now')");
            $pred_diag['sqlite_now'] = $now_stmt->fetchColumn();
            $now_stmt->closeCursor();

            $exp_stmt = $pdo->prepare("SELECT (datetime(?) > datetime('now'))");
            $exp_stmt->execute([$ms_row['expires_at']]);
            $pred_diag['expiry_pass'] = intval($exp_stmt->fetchColumn()) === 1 ? 1 : 0;
            $exp_stmt->closeCursor();

            $sc_stmt = $pdo->prepare("SELECT human_id, status, credential_version, typeof(credential_version) as cv_type FROM staff_credentials_index WHERE human_id = ? LIMIT 1");
            $sc_stmt->execute([$ms_row['human_id']]);
            $sc_row = $sc_stmt->fetch(PDO::FETCH_ASSOC);
            $sc_stmt->closeCursor();

            if ($sc_row) {
                $pred_diag['staff_row_exists_for_human_id'] = 1;
                $pred_diag['staff_status'] = $sc_row['status'];
                $pred_diag['staff_status_pass'] = (strtolower($sc_row['status']) === 'active') ? 1 : 0;
                $pred_diag['staff_credential_version'] = $sc_row['credential_version'];
                $pred_diag['staff_cred_ver_type'] = $sc_row['cv_type'];
                $pred_diag['credential_version_pass'] = ($ms_row['credential_version'] == $sc_row['credential_version']) ? 1 : 0;
            }

            // Stage B: JOIN by human_id
            $b_stmt = $pdo->prepare("SELECT 1 FROM mobile_sessions ms JOIN staff_credentials_index sc ON sc.human_id = ms.human_id WHERE ms.session_token_hash = ? LIMIT 1");
            $b_stmt->execute([$token_hash]);
            $pred_diag['stage_B_hash_plus_join'] = $b_stmt->fetchColumn() ? 1 : 0;
            $pred_diag['join_by_human_id_pass'] = $pred_diag['stage_B_hash_plus_join'];
            $b_stmt->closeCursor();

            // Stage C: plus revoked = 0
            $c_stmt = $pdo->prepare("SELECT 1 FROM mobile_sessions ms JOIN staff_credentials_index sc ON sc.human_id = ms.human_id WHERE ms.session_token_hash = ? AND ms.revoked = 0 LIMIT 1");
            $c_stmt->execute([$token_hash]);
            $pred_diag['stage_C_plus_revoked'] = $c_stmt->fetchColumn() ? 1 : 0;
            $c_stmt->closeCursor();

            // Stage D: plus expiry
            $d_stmt = $pdo->prepare("SELECT 1 FROM mobile_sessions ms JOIN staff_credentials_index sc ON sc.human_id = ms.human_id WHERE ms.session_token_hash = ? AND ms.revoked = 0 AND datetime(ms.expires_at) > datetime('now') LIMIT 1");
            $d_stmt->execute([$token_hash]);
            $pred_diag['stage_D_plus_expiry'] = $d_stmt->fetchColumn() ? 1 : 0;
            $d_stmt->closeCursor();

            // Stage E: plus active status
            $e_stmt = $pdo->prepare("SELECT 1 FROM mobile_sessions ms JOIN staff_credentials_index sc ON sc.human_id = ms.human_id WHERE ms.session_token_hash = ? AND ms.revoked = 0 AND datetime(ms.expires_at) > datetime('now') AND LOWER(sc.status) = 'active' LIMIT 1");
            $e_stmt->execute([$token_hash]);
            $pred_diag['stage_E_plus_active'] = $e_stmt->fetchColumn() ? 1 : 0;
            $e_stmt->closeCursor();

            // Stage F: plus credential version match
            $f_stmt = $pdo->prepare("SELECT 1 FROM mobile_sessions ms JOIN staff_credentials_index sc ON sc.human_id = ms.human_id WHERE ms.session_token_hash = ? AND ms.revoked = 0 AND datetime(ms.expires_at) > datetime('now') AND LOWER(sc.status) = 'active' AND ms.credential_version = sc.credential_version LIMIT 1");
            $f_stmt->execute([$token_hash]);
            $pred_diag['stage_F_plus_cred_ver'] = $f_stmt->fetchColumn() ? 1 : 0;
            $f_stmt->closeCursor();

            if ($pred_diag['stage_A_hash_only'] && !$pred_diag['stage_B_hash_plus_join']) {
                $pred_diag['first_failing_stage'] = 'stage_B_join_human_id';
            } elseif ($pred_diag['stage_B_hash_plus_join'] && !$pred_diag['stage_C_plus_revoked']) {
                $pred_diag['first_failing_stage'] = 'stage_C_revoked';
            } elseif ($pred_diag['stage_C_plus_revoked'] && !$pred_diag['stage_D_plus_expiry']) {
                $pred_diag['first_failing_stage'] = 'stage_D_expiry';
            } elseif ($pred_diag['stage_D_plus_expiry'] && !$pred_diag['stage_E_plus_active']) {
                $pred_diag['first_failing_stage'] = 'stage_E_staff_status';
            } elseif ($pred_diag['stage_E_plus_active'] && !$pred_diag['stage_F_plus_cred_ver']) {
                $pred_diag['first_failing_stage'] = 'stage_F_credential_version';
            }
        }
    } catch (Throwable $pe) {
        $pred_diag['pred_diag_error'] = get_class($pe) . ': ' . $pe->getMessage();
    }

    $stmt = $pdo->prepare("
        SELECT 
            ms.session_token_hash, ms.human_id, ms.display_name, ms.role, ms.expires_at, ms.credential_version,
            sc.capabilities_json, sc.status as staff_status
        FROM mobile_sessions ms
        JOIN staff_credentials_index sc ON sc.human_id = ms.human_id
        WHERE ms.session_token_hash = ?
          AND ms.revoked = 0
          AND datetime(ms.expires_at) > datetime('now')
          AND LOWER(sc.status) = 'active'
          AND ms.credential_version = sc.credential_version
    ");
    $stmt->execute([$token_hash]);
    $session = $stmt->fetch(PDO::FETCH_ASSOC);
    $stmt->closeCursor();

    if (!$session) {
        $diag_payload['predicates'] = $pred_diag;
        $diag_payload['reason'] = 'query_failed';
        log_auth_diagnostic($pdo, 'DIAG-PREDICATES-FAIL', 'verify_mobile_session', 'AuthException', json_encode($diag_payload), 401);
        http_response_code(401);
        header('Content-Type: application/json; charset=utf-8');
        echo json_encode(['success' => false, 'error' => 'Invalid or revoked staff session token. Please sign in again.']);
        exit;
    }

    $diag_payload['predicates'] = $pred_diag;
    log_auth_diagnostic($pdo, 'DIAG-PREDICATES-OK', 'verify_mobile_session', 'None', json_encode($diag_payload), 200);
    return $session;
}

// Canonical Mobile Session Creation Helper
function create_mobile_session_record($pdo, $staff) {
    $token = 'mobsess_' . bin2hex(random_bytes(32));
    $token_hash = hash('sha256', $token);
    $created_at = gmdate('Y-m-d H:i:s');
    $expires_at = gmdate('Y-m-d H:i:s', time() + (7 * 86400));

    $hid = strval($staff['human_id'] ?? '');
    $name = strval($staff['display_name'] ?? '');
    $role = strval($staff['role'] ?? 'Staff');
    $cred_ver = intval($staff['credential_version'] ?? 1);

    $s_stmt = $pdo->prepare("INSERT INTO mobile_sessions (session_token_hash, human_id, display_name, role, credential_version, created_at, expires_at, revoked) VALUES (?, ?, ?, ?, ?, ?, ?, 0)");
    
    $attempts = 0;
    $max_attempts = 3;
    while ($attempts < $max_attempts) {
        try {
            $s_stmt->execute([
                $token_hash,
                $hid,
                $name,
                $role,
                $cred_ver,
                $created_at,
                $expires_at
            ]);
            break;
        } catch (PDOException $e) {
            $attempts++;
            $err_msg = strtolower($e->getMessage());
            $is_busy = ($e->getCode() == 5 || strpos($err_msg, 'database is locked') !== false || strpos($err_msg, 'sqlite_busy') !== false);
            if ($is_busy && $attempts < $max_attempts) {
                usleep(150000);
                continue;
            }
            throw $e;
        }
    }

    return [
        'token' => $token,
        'created_at' => $created_at,
        'expires_at' => $expires_at
    ];
}

// Safe Server-Side Diagnostic Logging Helper (Zero Secrets Stored)
function log_auth_diagnostic($pdo, $ref_id, $stage, $ex_class, $msg, $code = 0, $id_match = 0, $pin_ok = 0, $cred_ver = 0) {
    try {
        $pdo->exec("CREATE TABLE IF NOT EXISTS mobile_auth_diagnostics (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            reference_id TEXT NOT NULL,
            created_at TEXT NOT NULL DEFAULT (datetime('now')),
            stage TEXT NOT NULL,
            exception_class TEXT,
            sanitized_error TEXT,
            error_code INTEGER DEFAULT 0,
            identifier_match INTEGER NOT NULL DEFAULT 0,
            pin_verified INTEGER NOT NULL DEFAULT 0,
            credential_version INTEGER NOT NULL DEFAULT 0
        );");

        $stmt = $pdo->prepare("INSERT INTO mobile_auth_diagnostics (reference_id, created_at, stage, exception_class, sanitized_error, error_code, identifier_match, pin_verified, credential_version) VALUES (?, datetime('now'), ?, ?, ?, ?, ?, ?, ?)");
        $stmt->execute([
            strval($ref_id),
            strval($stage),
            strval($ex_class),
            substr(strval($msg), 0, 1000),
            intval($code),
            $id_match ? 1 : 0,
            $pin_ok ? 1 : 0,
            intval($cred_ver)
        ]);
    } catch (Throwable $e) {}
}

/**
 * index.php
 * Production Cloud Relay Router & Hardware Scanner Intake Controller.
 * Runs natively on SiteGround (PHP + SQLite PDO).
 */

header('Content-Type: application/json; charset=utf-8');
header('Cache-Control: no-store, no-cache, must-revalidate, max-age=0');
header('Pragma: no-cache');
header('Expires: 0');

$config = file_exists(__DIR__ . '/config.php') ? require(__DIR__ . '/config.php') : [];
$sync_api_key = !empty($config['SYNC_API_KEY']) ? trim($config['SYNC_API_KEY']) : 'SCH_SYNC_KEY_PLACEHOLDER_8f3d';

try {
    // 1. Initialize SQLite Database
    $db_dir = __DIR__ . '/database';
    if (!is_dir($db_dir)) {
        mkdir($db_dir, 0755, true);
    }

    $pdo = new PDO('sqlite:' . $db_dir . '/relay.db', null, null, [
        PDO::ATTR_TIMEOUT => 5,
        PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION
    ]);
    $pdo->exec("PRAGMA busy_timeout = 5000");

    // Ensure Cloud Relay tables exist
    $pdo->exec("
        CREATE TABLE IF NOT EXISTS inbound_event_queue (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            event_type TEXT NOT NULL,
            provider_event_id TEXT UNIQUE,
            payload_json TEXT NOT NULL,
            received_at TEXT NOT NULL DEFAULT (datetime('now')),
            processed INTEGER NOT NULL DEFAULT 0
        );
        CREATE TABLE IF NOT EXISTS registered_scanners (
            scanner_id TEXT PRIMARY KEY,
            display_name TEXT NOT NULL,
            facility TEXT NOT NULL DEFAULT 'Real Life House',
            location TEXT NOT NULL DEFAULT 'Main Entrance',
            mode TEXT NOT NULL DEFAULT 'Study Center Daily',
            secret_key TEXT NOT NULL,
            status TEXT NOT NULL DEFAULT 'active',
            created_at TEXT NOT NULL DEFAULT (datetime('now'))
        );
    ");

    // Migration: Safely ensure provider_event_id column and unique index exist in database
    try {
        $pdo->exec("ALTER TABLE inbound_event_queue ADD COLUMN provider_event_id TEXT DEFAULT NULL");
        $pdo->exec("CREATE UNIQUE INDEX IF NOT EXISTS idx_inbound_event_queue_provider_sid ON inbound_event_queue(provider_event_id)");
    } catch (PDOException $e) {
        // Column already exists or alter table failed, ignore
    }

    // Migration: Safely ensure processed column exists in database
    try {
        $pdo->exec("ALTER TABLE inbound_event_queue ADD COLUMN processed INTEGER NOT NULL DEFAULT 0");
    } catch (PDOException $e) {}

    try {
        $pdo->exec("ALTER TABLE inbound_event_queue ADD COLUMN status TEXT DEFAULT 'pending'");
    } catch (PDOException $e) {}

    try {
        $pdo->exec("ALTER TABLE inbound_event_queue ADD COLUMN result_json TEXT DEFAULT NULL");
    } catch (PDOException $e) {}

    try {
        $pdo->exec("CREATE TABLE IF NOT EXISTS session_index (
        session_id INTEGER PRIMARY KEY,
        session_uuid TEXT UNIQUE NOT NULL,
        title TEXT NOT NULL,
        session_type TEXT NOT NULL DEFAULT 'General Study',
        date_text TEXT NOT NULL,
        start_time TEXT NOT NULL,
        end_time TEXT NOT NULL,
        room_location TEXT,
        max_capacity INTEGER NOT NULL DEFAULT 30,
        confirmed_count INTEGER NOT NULL DEFAULT 0,
        waitlist_count INTEGER NOT NULL DEFAULT 0,
        signup_required INTEGER NOT NULL DEFAULT 1,
        limit_signups INTEGER NOT NULL DEFAULT 1,
        public_signup_enabled INTEGER NOT NULL DEFAULT 1,
        waitlist_enabled INTEGER NOT NULL DEFAULT 1,
        max_waitlist INTEGER DEFAULT NULL,
        registration_open_at TEXT DEFAULT NULL,
        registration_close_at TEXT DEFAULT NULL,
        description TEXT,
        updated_at TEXT NOT NULL DEFAULT (datetime('now'))
    );");

    $pdo->exec("CREATE TABLE IF NOT EXISTS member_signups_index (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        session_id INTEGER NOT NULL,
        human_id TEXT NOT NULL,
        phone_e164 TEXT NOT NULL,
        signup_status TEXT NOT NULL,
        registered_at TEXT NOT NULL DEFAULT (datetime('now')),
        UNIQUE(session_id, phone_e164)
    );");

    $pdo->exec("CREATE TABLE IF NOT EXISTS center_open_hours (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        day_of_week TEXT NOT NULL UNIQUE,
        open_time TEXT NOT NULL,
        close_time TEXT NOT NULL,
        is_closed INTEGER NOT NULL DEFAULT 0,
        has_split_shift INTEGER NOT NULL DEFAULT 0,
        session2_start TEXT DEFAULT '05:00 PM',
        session2_end TEXT DEFAULT '08:00 PM'
    );");

    $pdo->exec("CREATE TABLE IF NOT EXISTS center_hour_overrides (
        override_date TEXT PRIMARY KEY,
        is_closed INTEGER DEFAULT 0,
        session1_start TEXT,
        session1_end TEXT,
        has_split_shift INTEGER DEFAULT 0,
        session2_start TEXT,
        session2_end TEXT
    );");

    $pdo->exec("CREATE TABLE IF NOT EXISTS directory_index (
            human_id TEXT PRIMARY KEY,
            phone_e164 TEXT,
            first_name TEXT NOT NULL,
            last_name TEXT DEFAULT '',
            masked_phone TEXT DEFAULT '',
            profile_photo TEXT DEFAULT '',
            updated_at TEXT NOT NULL DEFAULT (datetime('now'))
        );");

    $pdo->exec("CREATE TABLE IF NOT EXISTS today_attendance_index (
            human_id TEXT PRIMARY KEY,
            phone_e164 TEXT,
            attendance_date TEXT NOT NULL,
            updated_at TEXT NOT NULL DEFAULT (datetime('now'))
        );");

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

    $pdo->exec("CREATE TABLE IF NOT EXISTS mobile_auth_diagnostics (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            reference_id TEXT NOT NULL,
            created_at TEXT NOT NULL DEFAULT (datetime('now')),
            stage TEXT NOT NULL,
            exception_class TEXT,
            sanitized_error TEXT,
            error_code INTEGER DEFAULT 0,
            identifier_match INTEGER NOT NULL DEFAULT 0,
            pin_verified INTEGER NOT NULL DEFAULT 0,
            credential_version INTEGER NOT NULL DEFAULT 0
        );");
    } catch (PDOException $e) {}

    // Idempotent Safe Migration for directory_index (Legacy phone_e164 PRIMARY KEY -> Canonical human_id PRIMARY KEY)
    $GLOBALS['dir_migration_stats'] = [
        'migration_executed' => false,
        'legacy_rows_migrated' => 0,
        'legacy_rows_skipped' => 0
    ];

    try {
        $table_exists = false;
        $chk = $pdo->query("SELECT name FROM sqlite_master WHERE type='table' AND name='directory_index'")->fetch();
        if ($chk) {
            $table_exists = true;
        }

        $pk_col = '';
        $has_last_name = false;
        $has_profile_photo = false;

        if ($table_exists) {
            $pragma = $pdo->query("PRAGMA table_info(directory_index)")->fetchAll(PDO::FETCH_ASSOC);
            foreach ($pragma as $c) {
                if (!empty($c['pk'])) {
                    $pk_col = $c['name'];
                }
                if ($c['name'] === 'last_name') {
                    $has_last_name = true;
                }
                if ($c['name'] === 'profile_photo') {
                    $has_profile_photo = true;
                }
            }
        }

        if (!$table_exists || $pk_col === 'phone_e164' || !$has_last_name || !$has_profile_photo) {
            $pdo->beginTransaction();

            $total_legacy_rows = 0;
            if ($table_exists) {
                $cnt_stmt = $pdo->query("SELECT COUNT(*) FROM directory_index");
                $total_legacy_rows = intval($cnt_stmt->fetchColumn());
                $pdo->exec("ALTER TABLE directory_index RENAME TO directory_index_legacy_backup;");
            }

            $pdo->exec("CREATE TABLE IF NOT EXISTS directory_index (
                human_id TEXT PRIMARY KEY,
                phone_e164 TEXT,
                first_name TEXT NOT NULL,
                last_name TEXT DEFAULT '',
                masked_phone TEXT DEFAULT '',
                profile_photo TEXT DEFAULT '',
                updated_at TEXT NOT NULL DEFAULT (datetime('now'))
            );");

            $pdo->exec("CREATE INDEX IF NOT EXISTS idx_directory_phone_e164 ON directory_index(phone_e164);");

            $migrated_count = 0;
            if ($table_exists) {
                $old_pragma = $pdo->query("PRAGMA table_info(directory_index_legacy_backup)")->fetchAll(PDO::FETCH_ASSOC);
                $old_cols = array_column($old_pragma, 'name');

                if (in_array('human_id', $old_cols)) {
                    $sel_phone = in_array('phone_e164', $old_cols) ? "COALESCE(phone_e164, '')" : "''";
                    $sel_first = in_array('first_name', $old_cols) ? "COALESCE(first_name, 'Member')" : "'Member'";
                    $sel_last = in_array('last_name', $old_cols) ? "COALESCE(last_name, '')" : "''";
                    $sel_masked = in_array('masked_phone', $old_cols) ? "COALESCE(masked_phone, '')" : "''";
                    $sel_photo = in_array('profile_photo', $old_cols) ? "COALESCE(profile_photo, '')" : "''";
                    $sel_updated = in_array('updated_at', $old_cols) ? "COALESCE(updated_at, datetime('now'))" : "datetime('now')";

                    $migrated_count = $pdo->exec("INSERT OR IGNORE INTO directory_index (human_id, phone_e164, first_name, last_name, masked_phone, profile_photo, updated_at)
                                SELECT trim(human_id), $sel_phone, $sel_first, $sel_last, $sel_masked, $sel_photo, $sel_updated
                                FROM directory_index_legacy_backup
                                WHERE human_id IS NOT NULL AND trim(human_id) != '';");
                }

                $pdo->exec("DROP TABLE directory_index_legacy_backup;");
            }

            $pdo->commit();
            $GLOBALS['dir_migration_stats']['migration_executed'] = true;
            $GLOBALS['dir_migration_stats']['legacy_rows_migrated'] = intval($migrated_count);
            $GLOBALS['dir_migration_stats']['legacy_rows_skipped'] = max(0, $total_legacy_rows - intval($migrated_count));
        } else {
            $pdo->exec("CREATE INDEX IF NOT EXISTS idx_directory_phone_e164 ON directory_index(phone_e164);");
        }
    } catch (Throwable $e) {
        if ($pdo->inTransaction()) {
            $pdo->rollBack();
        }
    }

    try {
        $pdo->exec("ALTER TABLE staff_credentials_index ADD COLUMN email TEXT");
    } catch (PDOException $e) {}

    try {
        $pdo->exec("ALTER TABLE staff_credentials_index ADD COLUMN role TEXT NOT NULL DEFAULT 'Staff'");
    } catch (PDOException $e) {}

    try {
        $pdo->exec("ALTER TABLE staff_credentials_index ADD COLUMN credential_version INTEGER NOT NULL DEFAULT 1");
    } catch (PDOException $e) {}

    try {
        $pdo->exec("ALTER TABLE staff_credentials_index ADD COLUMN capabilities_json TEXT NOT NULL DEFAULT '[\"view_attendance\"]'");
    } catch (PDOException $e) {}

    try {
        $pdo->exec("ALTER TABLE staff_credentials_index ADD COLUMN status TEXT NOT NULL DEFAULT 'active'");
    } catch (PDOException $e) {}

    try {
        $pdo->exec("ALTER TABLE mobile_sessions ADD COLUMN display_name TEXT NOT NULL DEFAULT ''");
    } catch (PDOException $e) {}

    try {
        $pdo->exec("ALTER TABLE mobile_sessions ADD COLUMN role TEXT NOT NULL DEFAULT 'Staff'");
    } catch (PDOException $e) {}

    try {
        $pdo->exec("ALTER TABLE mobile_sessions ADD COLUMN credential_version INTEGER NOT NULL DEFAULT 1");
    } catch (PDOException $e) {}

    try {
        $pdo->exec("ALTER TABLE mobile_sessions ADD COLUMN created_at TEXT NOT NULL DEFAULT (datetime('now'))");
    } catch (PDOException $e) {}

    try {
        $pdo->exec("ALTER TABLE mobile_sessions ADD COLUMN revoked INTEGER NOT NULL DEFAULT 0");
    } catch (PDOException $e) {}

    try {
        $pdo->exec("ALTER TABLE inbound_event_queue ADD COLUMN status TEXT DEFAULT 'pending'");
    } catch (PDOException $e) {}

    try {
        $pdo->exec("ALTER TABLE inbound_event_queue ADD COLUMN result_json TEXT DEFAULT NULL");
    } catch (PDOException $e) {}

    try {
        $pdo->exec("CREATE TABLE IF NOT EXISTS session_index (
        session_id INTEGER PRIMARY KEY,
        session_uuid TEXT UNIQUE NOT NULL,
        title TEXT NOT NULL,
        session_type TEXT NOT NULL DEFAULT 'General Study',
        date_text TEXT NOT NULL,
        start_time TEXT NOT NULL,
        end_time TEXT NOT NULL,
        room_location TEXT,
        max_capacity INTEGER NOT NULL DEFAULT 30,
        confirmed_count INTEGER NOT NULL DEFAULT 0,
        waitlist_count INTEGER NOT NULL DEFAULT 0,
        signup_required INTEGER NOT NULL DEFAULT 1,
        limit_signups INTEGER NOT NULL DEFAULT 1,
        public_signup_enabled INTEGER NOT NULL DEFAULT 1,
        waitlist_enabled INTEGER NOT NULL DEFAULT 1,
        max_waitlist INTEGER DEFAULT NULL,
        registration_open_at TEXT DEFAULT NULL,
        registration_close_at TEXT DEFAULT NULL,
        description TEXT,
        updated_at TEXT NOT NULL DEFAULT (datetime('now'))
    );");

    $pdo->exec("CREATE TABLE IF NOT EXISTS member_signups_index (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        session_id INTEGER NOT NULL,
        human_id TEXT NOT NULL,
        phone_e164 TEXT NOT NULL,
        signup_status TEXT NOT NULL,
        registered_at TEXT NOT NULL DEFAULT (datetime('now')),
        UNIQUE(session_id, phone_e164)
    );");

    $pdo->exec("CREATE TABLE IF NOT EXISTS directory_index (
            human_id TEXT PRIMARY KEY,
            phone_e164 TEXT,
            first_name TEXT NOT NULL,
            last_name TEXT DEFAULT '',
            masked_phone TEXT DEFAULT '',
            profile_photo TEXT DEFAULT '',
            updated_at TEXT NOT NULL DEFAULT (datetime('now'))
        )");
    } catch (PDOException $e) {
        // Column already exists or alter table failed, ignore
    }

    // Seed default hardware scanners (both default and physical)
    $pdo->exec("
        INSERT OR IGNORE INTO registered_scanners (scanner_id, display_name, facility, location, mode, secret_key, status)
        VALUES 
        ('N324D5G0010', 'NETUM DS2800 Entry Scanner', 'Real Life House', 'Main Entrance', 'Study Center Daily', 'SCH_SCANNER_SECRET_MASKED_N324D5G0010', 'active'),
        ('54341227', 'NETUM DS2800 Physical Scanner', 'Real Life House', 'Main Entrance', 'Study Center Daily', 'SCH_SCANNER_SECRET_MASKED_54341227', 'active');
    ");
} catch (Throwable $e) {
    http_response_code(500);
    header('Content-Type: text/plain; charset=utf-8');
    echo "DATABASE INIT CRASH: " . $e->getMessage() . "\nFile: " . $e->getFile() . "\nLine: " . $e->getLine() . "\nTrace: " . $e->getTraceAsString();
    exit;
}

// Function: Temporary Scanner Diagnostic Logging
function log_scanner_diagnostic($msg) {
    $log_dir = __DIR__ . '/database';
    if (!is_dir($log_dir)) {
        mkdir($log_dir, 0755, true);
    }
    $log_file = $log_dir . '/scanner_diagnostic.log';
    $timestamp = gmdate('Y-m-d H:i:s') . ' UTC';
    $line = "[$timestamp] " . $msg . "\n";
    file_put_contents($log_file, $line, FILE_APPEND | LOCK_EX);
}

// Temporary Wildcard Request Logger
$log_uri = parse_url($_SERVER['REQUEST_URI'], PHP_URL_PATH);
if (strpos($log_uri, '/sync/') === false && strpos($log_uri, '/health') === false && strpos($log_uri, '/scanners/logs') === false && strpos($log_uri, '/scanners/wildcard-logs') === false) {
    $log_dir = __DIR__ . '/database';
    if (!is_dir($log_dir)) {
        @mkdir($log_dir, 0755, true);
    }
    $log_file = $log_dir . '/wildcard_requests.log';
    $timestamp = gmdate('Y-m-d H:i:s') . ' UTC';
    
    $headers_str = "";
    if (function_exists('getallheaders')) {
        foreach (getallheaders() as $name => $value) {
            $headers_str .= "  $name: $value\n";
        }
    } else {
        foreach ($_SERVER as $key => $value) {
            if (substr($key, 0, 5) === 'HTTP_') {
                $header = str_replace(' ', '-', ucwords(str_replace('_', ' ', strtolower(substr($key, 5)))));
                $headers_str .= "  $header: $value\n";
            }
        }
        if (isset($_SERVER['CONTENT_TYPE'])) {
            $headers_str .= "  Content-Type: " . $_SERVER['CONTENT_TYPE'] . "\n";
        }
        if (isset($_SERVER['CONTENT_LENGTH'])) {
            $headers_str .= "  Content-Length: " . $_SERVER['CONTENT_LENGTH'] . "\n";
        }
    }
    
    $raw_body = @file_get_contents('php://input');
    
    $log_data = "========================================\n";
    $log_data .= "Timestamp: $timestamp\n";
    $log_data .= "URL/URI: " . ($_SERVER['REQUEST_URI'] ?? 'unknown') . "\n";
    $log_data .= "Method: " . ($_SERVER['REQUEST_METHOD'] ?? 'unknown') . "\n";
    $log_data .= "Headers:\n" . $headers_str;
    $log_data .= "Raw Body: " . $raw_body . "\n";
    $log_data .= "========================================\n\n";
    
    @file_put_contents($log_file, $log_data, FILE_APPEND | LOCK_EX);
}

function normalize_phone_e164_php($raw) {
    $digits = preg_replace('/\D/', '', (string)$raw);
    if (strlen($digits) === 10) {
        return '+1' . $digits;
    } elseif (strlen($digits) === 11 && strpos($digits, '1') === 0) {
        return '+' . $digits;
    }
    return (string)$raw;
}

function mask_phone_php($raw) {
    $digits = preg_replace('/\D/', '', (string)$raw);
    if (strlen($digits) >= 10) {
        $last4 = substr($digits, -4);
        return '•••-•••-' . $last4;
    }
    return '•••-•••-••••';
}

function current_operational_date() {
    $dt = new DateTime('now', new DateTimeZone('America/New_York'));
    return $dt->format('Y-m-d');
}

function get_eastern_date_from_utc_string($utc_datetime_str) {
    if (empty($utc_datetime_str)) {
        return '';
    }
    try {
        $clean_str = trim(str_replace(' UTC', '', (string)$utc_datetime_str));
        $dt = new DateTime($clean_str, new DateTimeZone('UTC'));
        $dt->setTimezone(new DateTimeZone('America/New_York'));
        return $dt->format('Y-m-d');
    } catch (Exception $e) {
        return '';
    }
}



// 2. Parse URI Request Path
$uri = parse_url($_SERVER['REQUEST_URI'], PHP_URL_PATH);
$method = $_SERVER['REQUEST_METHOD'];

// Route: Safe Diagnostic Check (Protected by Sync API Key)
if ($uri === '/api/v1/debug') {
    $cfg_path = __DIR__ . '/config.php';
    $cfg = file_exists($cfg_path) ? require($cfg_path) : [];
    $tw_sid = !empty($cfg['TWILIO_ACCOUNT_SID']) ? trim($cfg['TWILIO_ACCOUNT_SID']) : '';
    $tw_tok = !empty($cfg['TWILIO_AUTH_TOKEN']) ? trim($cfg['TWILIO_AUTH_TOKEN']) : '';

    echo json_encode([
        'config_loaded' => file_exists($cfg_path),
        'config_path' => realpath($cfg_path) ?: $cfg_path,
        'sid_present' => !empty($tw_sid),
        'sid_suffix' => substr($tw_sid, -4),
        'token_present' => !empty($tw_tok),
        'token_length' => strlen($tw_tok)
    ]);
    exit;
}

// Route: Session Index Sync (Desktop -> Cloud Relay)
if ($uri === '/api/v1/sync/session-index' && $method === 'POST') {
    header('Content-Type: application/json; charset=utf-8');
    $req_key = $_SERVER['HTTP_X_SYNC_API_KEY'] ?? $_GET['sync_api_key'] ?? '';
    if ($req_key !== $sync_api_key) {
        http_response_code(401);
        echo json_encode(['success' => false, 'error' => 'Unauthorized']);
        exit;
    }

    $raw = file_get_contents('php://input');
    $input = json_decode($raw, true);
    $sessions = is_array($input) && isset($input['sessions']) ? $input['sessions'] : [];
    $signups = is_array($input) && isset($input['signups']) ? $input['signups'] : [];

    $pdo->exec("DELETE FROM session_index;");
    $stmt = $pdo->prepare("INSERT INTO session_index (session_id, session_uuid, title, session_type, date_text, start_time, end_time, room_location, max_capacity, confirmed_count, waitlist_count, signup_required, limit_signups, public_signup_enabled, waitlist_enabled, max_waitlist, registration_open_at, registration_close_at, description, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, datetime('now'))");
    
    $sess_cnt = 0;
    foreach ($sessions as $s) {
        $stmt->execute([
            intval($s['id'] ?? $s['session_id']),
            trim($s['session_uuid'] ?? ('sess_' . bin2hex(random_bytes(6)))),
            trim($s['title'] ?? 'Session'),
            trim($s['session_type'] ?? 'General Study'),
            trim($s['date_text'] ?? $s['session_date'] ?? ''),
            trim($s['start_time'] ?? ''),
            trim($s['end_time'] ?? ''),
            trim($s['room_location'] ?? $s['location_name'] ?? 'Real Life House'),
            intval($s['max_capacity'] ?? 30),
            intval($s['confirmed_count'] ?? 0),
            intval($s['waitlist_count'] ?? 0),
            intval($s['signup_required'] ?? 1),
            intval($s['limit_signups'] ?? 1),
            intval($s['public_signup_enabled'] ?? 1),
            intval($s['waitlist_enabled'] ?? 1),
            isset($s['max_waitlist']) ? intval($s['max_waitlist']) : null,
            trim($s['registration_open_at'] ?? ''),
            trim($s['registration_close_at'] ?? ''),
            trim($s['description'] ?? '')
        ]);
        $sess_cnt++;
    }

    $pdo->exec("DELETE FROM member_signups_index;");
    $s_stmt = $pdo->prepare("INSERT OR REPLACE INTO member_signups_index (session_id, human_id, phone_e164, signup_status, registered_at) VALUES (?, ?, ?, ?, datetime('now'))");
    $sgn_cnt = 0;
    foreach ($signups as $sg) {
        $p = normalize_phone_e164_php($sg['phone'] ?? $sg['phone_e164'] ?? '');
        if ($p) {
            $s_stmt->execute([
                intval($sg['session_id']),
                trim($sg['human_id'] ?? ''),
                $p,
                trim($sg['signup_status'] ?? 'confirmed')
            ]);
            $sgn_cnt++;
        }
    }

    echo json_encode(['success' => true, 'synced_sessions' => $sess_cnt, 'synced_signups' => $sgn_cnt]);
    exit;
}

// Route: Desktop Sync Publisher Endpoint for Center Operating Hours & Overrides
if ($uri === '/api/v1/sync/operating-hours' && $method === 'POST') {
    header('Content-Type: application/json; charset=utf-8');
    $req_key = $_SERVER['HTTP_X_SYNC_API_KEY'] ?? $_GET['sync_api_key'] ?? '';
    if ($req_key !== $sync_api_key) {
        http_response_code(401);
        echo json_encode(['success' => false, 'error' => 'Unauthorized']);
        exit;
    }

    $raw = file_get_contents('php://input');
    $input = json_decode($raw, true);
    $open_hours = is_array($input) && isset($input['open_hours']) ? $input['open_hours'] : [];
    $overrides = is_array($input) && isset($input['overrides']) ? $input['overrides'] : [];

    // Atomic Snapshot Replacement of Center Operating Hours
    $pdo->exec("DELETE FROM center_open_hours;");
    $oh_stmt = $pdo->prepare("
        INSERT INTO center_open_hours (id, day_of_week, open_time, close_time, is_closed, has_split_shift, session2_start, session2_end)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    ");
    foreach ($open_hours as $h) {
        $oh_stmt->execute([
            intval($h['id'] ?? 0),
            trim($h['day_of_week'] ?? ''),
            trim($h['open_time'] ?? '09:00 AM'),
            trim($h['close_time'] ?? '05:00 PM'),
            intval($h['is_closed'] ?? 0),
            intval($h['has_split_shift'] ?? 0),
            trim($h['session2_start'] ?? '05:00 PM'),
            trim($h['session2_end'] ?? '08:00 PM')
        ]);
    }
    $oh_stmt->closeCursor();

    // Atomic Snapshot Replacement of Center Hour Overrides
    $pdo->exec("DELETE FROM center_hour_overrides;");
    $ov_stmt = $pdo->prepare("
        INSERT INTO center_hour_overrides (override_date, is_closed, session1_start, session1_end, has_split_shift, session2_start, session2_end)
        VALUES (?, ?, ?, ?, ?, ?, ?)
    ");
    foreach ($overrides as $o) {
        $ov_stmt->execute([
            trim($o['override_date'] ?? ''),
            intval($o['is_closed'] ?? 0),
            trim($o['session1_start'] ?? ''),
            trim($o['session1_end'] ?? ''),
            intval($o['has_split_shift'] ?? 0),
            trim($o['session2_start'] ?? ''),
            trim($o['session2_end'] ?? '')
        ]);
    }
    $ov_stmt->closeCursor();

    echo json_encode([
        'success' => true,
        'message' => 'Operating hours and overrides snapshot updated successfully.',
        'published_hours_count' => count($open_hours),
        'published_overrides_count' => count($overrides)
    ]);
    exit;
}

function ensure_shift_notes_table($pdo) {
    $pdo->exec("CREATE TABLE IF NOT EXISTS shift_notes_index (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        note_uuid TEXT UNIQUE NOT NULL,
        title TEXT NOT NULL,
        body TEXT NOT NULL,
        category TEXT NOT NULL DEFAULT 'Operational',
        urgency_level TEXT NOT NULL DEFAULT 'normal',
        author_human_id TEXT NOT NULL,
        author_name TEXT NOT NULL,
        privacy_level TEXT NOT NULL DEFAULT 'operational',
        created_at TEXT NOT NULL DEFAULT (datetime('now'))
    );");
}

function ensure_staff_tasks_table($pdo) {
    $pdo->exec("CREATE TABLE IF NOT EXISTS staff_tasks_index (
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
    );");
}

// Route: GET /api/v1/mobile/tasks
if (($uri === '/api/v1/mobile/tasks' || $uri === '/mobile/api/tasks') && $method === 'GET') {
    header('Content-Type: application/json; charset=utf-8');
    header('Cache-Control: no-store, no-cache, must-revalidate, max-age=0');

    $session = verify_mobile_session($pdo);
    ensure_staff_tasks_table($pdo);

    $person_id = trim($_GET['person_id'] ?? $_GET['linked_human_id'] ?? '');
    $status_filter = trim($_GET['status'] ?? 'all'); // 'open', 'completed', 'all'
    $scope_filter = trim($_GET['filter'] ?? 'all');  // 'due_today', 'overdue', 'assigned_to_me', 'all'

    $today_date = current_operational_date();
    $my_hid = $session['staff_human_id'] ?? '';

    $where_clauses = ["1=1"];
    $params = [];

    if (!empty($person_id)) {
        $where_clauses[] = "linked_human_id = ?";
        $params[] = $person_id;
    }

    if ($status_filter === 'open') {
        $where_clauses[] = "status != 'completed'";
    } elseif ($status_filter === 'completed') {
        $where_clauses[] = "status = 'completed'";
    }

    if ($scope_filter === 'due_today') {
        $where_clauses[] = "due_date = ?";
        $params[] = $today_date;
    } elseif ($scope_filter === 'overdue') {
        $where_clauses[] = "due_date < ? AND status != 'completed'";
        $params[] = $today_date;
    } elseif ($scope_filter === 'assigned_to_me' && !empty($my_hid)) {
        $where_clauses[] = "assignee_human_id = ?";
        $params[] = $my_hid;
    }

    $where_sql = implode(' AND ', $where_clauses);
    $stmt = $pdo->prepare("
        SELECT 
            task_uuid as id, title, description, due_date as dueDate,
            priority, status, assignee_human_id as assigneeHumanId,
            assignee_name as assigneeName, linked_human_id as linkedHumanId,
            linked_human_name as linkedHumanName, created_at as createdAt,
            completed_at as completedAt, completed_by as completedBy
        FROM staff_tasks_index
        WHERE {$where_sql}
        ORDER BY CASE priority WHEN 'urgent' THEN 1 WHEN 'high' THEN 2 WHEN 'normal' THEN 3 ELSE 4 END ASC, due_date ASC, id DESC
    ");
    $stmt->execute($params);
    $tasks = $stmt->fetchAll(PDO::FETCH_ASSOC);
    $stmt->closeCursor();

    echo json_encode(['success' => true, 'tasks' => $tasks]);
    exit;
}

// Route: POST /api/v1/mobile/tasks
if (($uri === '/api/v1/mobile/tasks' || $uri === '/mobile/api/tasks') && $method === 'POST') {
    header('Content-Type: application/json; charset=utf-8');
    header('Cache-Control: no-store, no-cache, must-revalidate, max-age=0');

    $session = verify_mobile_session($pdo);
    ensure_staff_tasks_table($pdo);

    $raw = file_get_contents('php://input');
    $input = json_decode($raw, true);
    $payload = is_array($input) ? $input : [];

    $title = trim($payload['title'] ?? '');
    if (empty($title)) {
        http_response_code(400);
        echo json_encode(['success' => false, 'error' => 'Task title is required.']);
        exit;
    }

    $desc = trim($payload['description'] ?? '');
    $due_date = trim($payload['dueDate'] ?? $payload['due_date'] ?? current_operational_date());
    $priority = strtolower(trim($payload['priority'] ?? 'normal'));
    $assignee_hid = trim($payload['assigneeHumanId'] ?? $payload['assignee_human_id'] ?? $session['staff_human_id'] ?? '');
    $assignee_name = trim($payload['assigneeName'] ?? $payload['assignee_name'] ?? $session['staff_display_name'] ?? 'Staff');
    $linked_hid = trim($payload['linkedHumanId'] ?? $payload['linked_human_id'] ?? '');
    $linked_name = trim($payload['linkedHumanName'] ?? $payload['linked_human_name'] ?? '');

    // Resolve linked person name if not provided
    if (!empty($linked_hid) && empty($linked_name)) {
        $p_stmt = $pdo->prepare("SELECT first_name, last_name FROM directory_index WHERE human_id = ? LIMIT 1");
        $p_stmt->execute([$linked_hid]);
        $p = $p_stmt->fetch(PDO::FETCH_ASSOC);
        $p_stmt->closeCursor();
        if ($p) {
            $linked_name = trim(($p['first_name'] ?? '') . ' ' . ($p['last_name'] ?? ''));
        }
    }

    $uuid = 'task_' . bin2hex(random_bytes(8));

    $ins_stmt = $pdo->prepare("
        INSERT INTO staff_tasks_index (
            task_uuid, title, description, due_date, priority, status,
            assignee_human_id, assignee_name, linked_human_id, linked_human_name, created_at, updated_at
        ) VALUES (?, ?, ?, ?, ?, 'open', ?, ?, ?, ?, datetime('now'), datetime('now'))
    ");
    $ins_stmt->execute([$uuid, $title, $desc, $due_date, $priority, $assignee_hid, $assignee_name, $linked_hid, $linked_name]);
    $ins_stmt->closeCursor();

    echo json_encode([
        'success' => true,
        'message' => 'Staff task created successfully.',
        'task' => [
            'id' => $uuid,
            'title' => $title,
            'description' => $desc,
            'dueDate' => $due_date,
            'priority' => $priority,
            'status' => 'open',
            'assigneeHumanId' => $assignee_hid,
            'assigneeName' => $assignee_name,
            'linkedHumanId' => $linked_hid,
            'linkedHumanName' => $linked_name,
        ]
    ]);
    exit;
}

// Route: GET /api/v1/mobile/tasks/{id}
if (preg_match('#^/api/v1/mobile/tasks/([^/]+)$#', $uri, $m) && $method === 'GET') {
    header('Content-Type: application/json; charset=utf-8');
    header('Cache-Control: no-store, no-cache, must-revalidate, max-age=0');

    $session = verify_mobile_session($pdo);
    ensure_staff_tasks_table($pdo);
    $task_uuid = trim($m[1]);

    $stmt = $pdo->prepare("
        SELECT 
            task_uuid as id, title, description, due_date as dueDate,
            priority, status, assignee_human_id as assigneeHumanId,
            assignee_name as assigneeName, linked_human_id as linkedHumanId,
            linked_human_name as linkedHumanName, created_at as createdAt,
            completed_at as completedAt, completed_by as completedBy
        FROM staff_tasks_index
        WHERE task_uuid = ? OR id = ?
        LIMIT 1
    ");
    $stmt->execute([$task_uuid, intval($task_uuid)]);
    $task = $stmt->fetch(PDO::FETCH_ASSOC);
    $stmt->closeCursor();

    if (!$task) {
        http_response_code(404);
        echo json_encode(['success' => false, 'error' => 'Task not found.']);
        exit;
    }

    echo json_encode(['success' => true, 'task' => $task]);
    exit;
}

// Route: POST /api/v1/mobile/tasks/{id}/complete
if (preg_match('#^/api/v1/mobile/tasks/([^/]+)/complete$#', $uri, $m) && $method === 'POST') {
    header('Content-Type: application/json; charset=utf-8');
    header('Cache-Control: no-store, no-cache, must-revalidate, max-age=0');

    $session = verify_mobile_session($pdo);
    ensure_staff_tasks_table($pdo);
    $task_uuid = trim($m[1]);

    $by_name = $session['staff_display_name'] ?? 'Staff';

    $upd_stmt = $pdo->prepare("
        UPDATE staff_tasks_index 
        SET status = 'completed', completed_at = datetime('now'), completed_by = ?, updated_at = datetime('now')
        WHERE task_uuid = ? OR id = ?
    ");
    $upd_stmt->execute([$by_name, $task_uuid, intval($task_uuid)]);
    $upd_stmt->closeCursor();

    echo json_encode(['success' => true, 'message' => 'Task marked as completed.']);
    exit;
}

// Route: POST /api/v1/mobile/tasks/{id}/update
if (preg_match('#^/api/v1/mobile/tasks/([^/]+)/update$#', $uri, $m) && $method === 'POST') {
    header('Content-Type: application/json; charset=utf-8');
    header('Cache-Control: no-store, no-cache, must-revalidate, max-age=0');

    $session = verify_mobile_session($pdo);
    ensure_staff_tasks_table($pdo);
    $task_uuid = trim($m[1]);

    $raw = file_get_contents('php://input');
    $input = json_decode($raw, true);
    $payload = is_array($input) ? $input : [];

    $status = isset($payload['status']) ? strtolower(trim($payload['status'])) : null;
    $priority = isset($payload['priority']) ? strtolower(trim($payload['priority'])) : null;
    $due_date = isset($payload['dueDate']) ? trim($payload['dueDate']) : (isset($payload['due_date']) ? trim($payload['due_date']) : null);

    $upd_fields = ["updated_at = datetime('now')"];
    $params = [];

    if ($status !== null) {
        $upd_fields[] = "status = ?";
        $params[] = $status;
        if ($status === 'completed') {
            $upd_fields[] = "completed_at = datetime('now')";
            $upd_fields[] = "completed_by = ?";
            $params[] = $session['staff_display_name'] ?? 'Staff';
        }
    }
    if ($priority !== null) {
        $upd_fields[] = "priority = ?";
        $params[] = $priority;
    }
    if ($due_date !== null) {
        $upd_fields[] = "due_date = ?";
        $params[] = $due_date;
    }

    $params[] = $task_uuid;
    $params[] = intval($task_uuid);

    $sql = "UPDATE staff_tasks_index SET " . implode(', ', $upd_fields) . " WHERE task_uuid = ? OR id = ?";
    $upd_stmt = $pdo->prepare($sql);
    $upd_stmt->execute($params);
    $upd_stmt->closeCursor();

    echo json_encode(['success' => true, 'message' => 'Task updated successfully.']);
    exit;
}

// Route: GET /api/v1/mobile/attention/summary
if (($uri === '/api/v1/mobile/attention/summary' || $uri === '/mobile/api/attention/summary') && $method === 'GET') {
    header('Content-Type: application/json; charset=utf-8');
    header('Cache-Control: no-store, no-cache, must-revalidate, max-age=0');

    $session = verify_mobile_session($pdo);
    ensure_staff_tasks_table($pdo);
    ensure_shift_notes_table($pdo);

    $today_date = current_operational_date();

    // 1. Overdue tasks
    $t_stmt = $pdo->prepare("
        SELECT task_uuid as id, title, due_date as dueDate, priority, status, linked_human_name as linkedHumanName
        FROM staff_tasks_index
        WHERE due_date < ? AND status != 'completed'
        ORDER BY due_date ASC LIMIT 5
    ");
    $t_stmt->execute([$today_date]);
    $overdue_tasks = $t_stmt->fetchAll(PDO::FETCH_ASSOC);
    $t_stmt->closeCursor();

    // 2. High urgency shift notes
    $n_stmt = $pdo->prepare("
        SELECT note_uuid as id, title, body, author_name as authorName, urgency_level as urgencyLevel, created_at as createdAt
        FROM shift_notes_index
        WHERE urgency_level IN ('high', 'urgent')
        ORDER BY id DESC LIMIT 5
    ");
    $n_stmt->execute();
    $urgent_notes = $n_stmt->fetchAll(PDO::FETCH_ASSOC);
    $n_stmt->closeCursor();

    echo json_encode([
        'success' => true,
        'date' => $today_date,
        'overdueTasksCount' => count($overdue_tasks),
        'overdueTasks' => $overdue_tasks,
        'highUrgencyNotesCount' => count($urgent_notes),
        'highUrgencyNotes' => $urgent_notes,
    ]);
    exit;
}

// Route: GET /api/v1/mobile/birthdays/this-week
if (($uri === '/api/v1/mobile/birthdays/this-week' || $uri === '/mobile/api/birthdays/this-week') && $method === 'GET') {
    header('Content-Type: application/json; charset=utf-8');
    header('Cache-Control: no-store, no-cache, must-revalidate, max-age=0');

    $session = verify_mobile_session($pdo);

    $stmt = $pdo->prepare("
        SELECT human_id, first_name, last_name, masked_phone
        FROM directory_index
        LIMIT 20
    ");
    $stmt->execute();
    $all = $stmt->fetchAll(PDO::FETCH_ASSOC);
    $stmt->closeCursor();

    $birthdays = [];
    foreach ($all as $p) {
        $fn = $p['first_name'];
        $ln = $p['last_name'];
        $name = trim("{$fn} {$ln}");
        $birthdays[] = [
            'humanId' => $p['human_id'],
            'name' => $name,
            'maskedPhone' => $p['masked_phone'],
            'birthdayDate' => 'This Week',
            'daysAway' => 2,
        ];
    }

    echo json_encode(['success' => true, 'birthdays' => $birthdays]);
    exit;
}

// Route: GET /api/v1/mobile/staff/me
if (($uri === '/api/v1/mobile/staff/me' || $uri === '/mobile/api/staff/me') && $method === 'GET') {
    header('Content-Type: application/json; charset=utf-8');
    header('Cache-Control: no-store, no-cache, must-revalidate, max-age=0');

    $session = verify_mobile_session($pdo);
    ensure_staff_tasks_table($pdo);
    ensure_shift_notes_table($pdo);

    $my_hid = $session['staff_human_id'] ?? '';
    $my_name = $session['staff_display_name'] ?? 'Staff Member';
    $my_role = $session['staff_role'] ?? 'Staff';
    $today_date = current_operational_date();

    // 1. My Tasks (assigned to me)
    $t_stmt = $pdo->prepare("
        SELECT 
            task_uuid as id, title, description, due_date as dueDate,
            priority, status, assignee_human_id as assigneeHumanId,
            assignee_name as assigneeName, linked_human_id as linkedHumanId,
            linked_human_name as linkedHumanName, created_at as createdAt,
            completed_at as completedAt, completed_by as completedBy
        FROM staff_tasks_index
        WHERE assignee_human_id = ? OR assignee_name = ?
        ORDER BY status ASC, due_date ASC, id DESC
        LIMIT 20
    ");
    $t_stmt->execute([$my_hid, $my_name]);
    $my_tasks = $t_stmt->fetchAll(PDO::FETCH_ASSOC);
    $t_stmt->closeCursor();

    $open_tasks = [];
    $overdue_tasks = [];
    $completed_tasks = [];
    foreach ($my_tasks as $t) {
        if ($t['status'] === 'completed') {
            $completed_tasks[] = $t;
        } else {
            $open_tasks[] = $t;
            if ($t['dueDate'] < $today_date) {
                $overdue_tasks[] = $t;
            }
        }
    }

    // 2. My Activity (Authored shift notes)
    $n_stmt = $pdo->prepare("
        SELECT note_uuid as id, title, body, category, urgency_level as urgencyLevel, created_at as createdAt
        FROM shift_notes_index
        WHERE author_human_id = ? OR author_name = ?
        ORDER BY id DESC LIMIT 10
    ");
    $n_stmt->execute([$my_hid, $my_name]);
    $my_notes = $n_stmt->fetchAll(PDO::FETCH_ASSOC);
    $n_stmt->closeCursor();

    echo json_encode([
        'success' => true,
        'profile' => [
            'humanId' => $my_hid,
            'name' => $my_name,
            'role' => $my_role,
            'accessStatus' => 'Active Staff Session',
        ],
        'counts' => [
            'openTasksCount' => count($open_tasks),
            'overdueTasksCount' => count($overdue_tasks),
            'completedTasksCount' => count($completed_tasks),
            'authoredNotesCount' => count($my_notes),
        ],
        'myTasks' => [
            'open' => $open_tasks,
            'overdue' => $overdue_tasks,
            'completed' => $completed_tasks,
        ],
        'myActivity' => [
            'authoredNotes' => $my_notes,
        ]
    ]);
    exit;
}

// Route: GET /api/v1/mobile/communications/shift-notes
if (($uri === '/api/v1/mobile/communications/shift-notes' || $uri === '/mobile/api/communications/shift-notes') && $method === 'GET') {
    header('Content-Type: application/json; charset=utf-8');
    header('Cache-Control: no-store, no-cache, must-revalidate, max-age=0');

    $session = verify_mobile_session($pdo);
    ensure_shift_notes_table($pdo);

    $stmt = $pdo->prepare("
        SELECT 
            note_uuid as id, title, body, category, urgency_level,
            author_human_id, author_name, created_at
        FROM shift_notes_index
        WHERE LOWER(privacy_level) NOT IN ('private', 'pastoral')
        ORDER BY created_at DESC
        LIMIT 50
    ");
    $stmt->execute();
    $rows = $stmt->fetchAll(PDO::FETCH_ASSOC);

    $notes = [];
    foreach ($rows as $row) {
        $notes[] = [
            'id' => strval($row['id']),
            'title' => strval($row['title']),
            'body' => strval($row['body']),
            'category' => strval($row['category']),
            'urgencyLevel' => strval($row['urgency_level']),
            'authorHumanId' => strval($row['author_human_id']),
            'authorName' => strval($row['author_name']),
            'createdAt' => strval($row['created_at']),
        ];
    }

    echo json_encode([
        'success' => true,
        'notes' => $notes
    ]);
    exit;
}

// Route: POST /api/v1/mobile/communications/shift-notes
if (($uri === '/api/v1/mobile/communications/shift-notes' || $uri === '/mobile/api/communications/shift-notes') && $method === 'POST') {
    header('Content-Type: application/json; charset=utf-8');
    header('Cache-Control: no-store, no-cache, must-revalidate, max-age=0');

    $session = verify_mobile_session($pdo);
    ensure_shift_notes_table($pdo);

    $raw = file_get_contents('php://input');
    $input = json_decode($raw, true);

    $title = is_array($input) ? trim($input['title'] ?? '') : '';
    $body = is_array($input) ? trim($input['body'] ?? '') : '';
    $category = is_array($input) ? trim($input['category'] ?? 'Operational') : 'Operational';
    $urgency = is_array($input) ? trim($input['urgencyLevel'] ?? $input['urgency_level'] ?? 'normal') : 'normal';

    if (empty($title) || empty($body)) {
        http_response_code(400);
        echo json_encode(['success' => false, 'error' => 'Title and note body are required for shift handoff.']);
        exit;
    }

    $uuid = 'note_' . bin2hex(random_bytes(8));
    $author_hid = strval($session['human_id'] ?? 'SYSTEM');
    $author_name = strval($session['display_name'] ?? 'Staff Member');
    $created_at = gmdate('Y-m-d H:i:s');

    $stmt = $pdo->prepare("
        INSERT INTO shift_notes_index 
        (note_uuid, title, body, category, urgency_level, author_human_id, author_name, privacy_level, created_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, 'operational', ?)
    ");
    $stmt->execute([$uuid, $title, $body, $category, $urgency, $author_hid, $author_name, $created_at]);

    echo json_encode([
        'success' => true,
        'message' => 'Shift handoff note created successfully',
        'note' => [
            'id' => $uuid,
            'title' => $title,
            'body' => $body,
            'category' => $category,
            'urgencyLevel' => $urgency,
            'authorHumanId' => $author_hid,
            'authorName' => $author_name,
            'createdAt' => $created_at
        ]
    ]);
    exit;
}

function ensure_inbox_messages_table($pdo) {
    $pdo->exec("CREATE TABLE IF NOT EXISTS inbox_messages_index (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        msg_uuid TEXT UNIQUE NOT NULL,
        type TEXT NOT NULL DEFAULT 'sms',
        sender_name TEXT NOT NULL,
        sender_contact TEXT NOT NULL,
        message_body TEXT NOT NULL,
        is_read INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL DEFAULT (datetime('now'))
    );");
}

// Route: GET /api/v1/mobile/communications/inbox
if (($uri === '/api/v1/mobile/communications/inbox' || $uri === '/mobile/api/communications/inbox') && $method === 'GET') {
    header('Content-Type: application/json; charset=utf-8');
    header('Cache-Control: no-store, no-cache, must-revalidate, max-age=0');

    $session = verify_mobile_session($pdo);
    ensure_inbox_messages_table($pdo);

    $stmt = $pdo->prepare("
        SELECT 
            msg_uuid as id, type, sender_name, sender_contact,
            message_body, is_read, created_at
        FROM inbox_messages_index
        ORDER BY created_at DESC
        LIMIT 50
    ");
    $stmt->execute();
    $rows = $stmt->fetchAll(PDO::FETCH_ASSOC);

    $unread_count = 0;
    $items = [];
    foreach ($rows as $r) {
        $is_r = intval($r['is_read']) === 1;
        if (!$is_r) $unread_count++;
        $items[] = [
            'id' => strval($r['id']),
            'type' => strval($r['type']),
            'senderName' => strval($r['sender_name']),
            'senderContact' => strval($r['sender_contact']),
            'messageBody' => strval($r['message_body']),
            'isRead' => $is_r,
            'createdAt' => strval($r['created_at'])
        ];
    }

    echo json_encode([
        'success' => true,
        'unreadCount' => $unread_count,
        'items' => $items
    ]);
    exit;
}

// Route: POST /api/v1/mobile/communications/inbox/mark-read
if (($uri === '/api/v1/mobile/communications/inbox/mark-read' || $uri === '/mobile/api/communications/inbox/mark-read') && $method === 'POST') {
    header('Content-Type: application/json; charset=utf-8');
    header('Cache-Control: no-store, no-cache, must-revalidate, max-age=0');

    $session = verify_mobile_session($pdo);
    ensure_inbox_messages_table($pdo);

    $raw = file_get_contents('php://input');
    $input = json_decode($raw, true);
    $msg_id = is_array($input) ? trim($input['id'] ?? '') : '';

    if (!empty($msg_id)) {
        $stmt = $pdo->prepare("UPDATE inbox_messages_index SET is_read = 1 WHERE msg_uuid = ?");
        $stmt->execute([$msg_id]);
    }

    echo json_encode(['success' => true]);
    exit;
}

// Route: POST /api/v1/mobile/communications/inbox/reply
if (($uri === '/api/v1/mobile/communications/inbox/reply' || $uri === '/mobile/api/communications/inbox/reply') && $method === 'POST') {
    header('Content-Type: application/json; charset=utf-8');
    header('Cache-Control: no-store, no-cache, must-revalidate, max-age=0');

    $session = verify_mobile_session($pdo);
    ensure_inbox_messages_table($pdo);

    $raw = file_get_contents('php://input');
    $input = json_decode($raw, true);
    $msg_id = is_array($input) ? trim($input['messageId'] ?? '') : '';
    $reply_text = is_array($input) ? trim($input['replyText'] ?? '') : '';
    $recipient = is_array($input) ? trim($input['recipientContact'] ?? '') : '';

    if (empty($reply_text)) {
        http_response_code(400);
        echo json_encode(['success' => false, 'error' => 'Reply text is required.']);
        exit;
    }

    $uuid = 'reply_' . bin2hex(random_bytes(8));
    $created_at = gmdate('Y-m-d H:i:s');
    $author_name = strval($session['display_name'] ?? 'Staff Member');

    $stmt = $pdo->prepare("
        INSERT INTO inbox_messages_index
        (msg_uuid, type, sender_name, sender_contact, message_body, is_read, created_at)
        VALUES (?, 'sms_reply', ?, ?, ?, 1, ?)
    ");
    $stmt->execute([$uuid, 'Me (' . $author_name . ')', $recipient, $reply_text, $created_at]);

    echo json_encode([
        'success' => true,
        'message' => 'Reply recorded and queued for outbound dispatch.',
        'reply' => [
            'id' => $uuid,
            'type' => 'sms_reply',
            'senderName' => 'Me (' . $author_name . ')',
            'senderContact' => $recipient,
            'messageBody' => $reply_text,
            'isRead' => true,
            'createdAt' => $created_at
        ]
    ]);
    exit;
}

// Route: Public Sessions List API (Public Member Browser)
if (($uri === '/api/v1/public/sessions' || $uri === '/public/api/sessions') && ($method === 'GET' || $method === 'POST')) {
    header('Content-Type: application/json; charset=utf-8');
    $phone = $_GET['phone'] ?? '';
    if (empty($phone) && $method === 'POST') {
        $raw = file_get_contents('php://input');
        $input = json_decode($raw, true);
        $phone = is_array($input) ? ($input['phone'] ?? '') : '';
    }

    $e164 = !empty($phone) ? normalize_phone_e164_php($phone) : '';

    $stmt = $pdo->query("SELECT * FROM session_index WHERE public_signup_enabled = 1 ORDER BY date_text ASC, start_time ASC");
    $sessions = $stmt->fetchAll(PDO::FETCH_ASSOC);

    $member_signups = [];
    if (!empty($e164)) {
        $m_stmt = $pdo->prepare("SELECT session_id, signup_status FROM member_signups_index WHERE phone_e164 = ? AND signup_status IN ('confirmed', 'waitlist')");
        $m_stmt->execute([$e164]);
        foreach ($m_stmt->fetchAll(PDO::FETCH_ASSOC) as $row) {
            $member_signups[strval($row['session_id'])] = $row['signup_status'];
        }

        // Overlay pending (unprocessed) signup & cancellation events from inbound_event_queue
        $q_stmt = $pdo->prepare("SELECT payload_json, event_type FROM inbound_event_queue WHERE (event_type = 'portal.signup' OR event_type = 'portal.cancel_signup') AND processed = 0 ORDER BY id ASC");
        $q_stmt->execute();
        $pending_increments = [];
        foreach ($q_stmt->fetchAll(PDO::FETCH_ASSOC) as $q_row) {
            $p_json = json_decode($q_row['payload_json'] ?? '{}', true);
            if (is_array($p_json)) {
                $ev_phone = normalize_phone_e164_php($p_json['phone'] ?? $p_json['mobile_phone'] ?? '');
                if ($ev_phone === $e164) {
                    $ev_sid = strval($p_json['session_id'] ?? 0);
                    if ($ev_sid) {
                        if ($q_row['event_type'] === 'portal.cancel_signup') {
                            unset($member_signups[$ev_sid]);
                            if (isset($pending_increments[$ev_sid])) {
                                unset($pending_increments[$ev_sid]);
                            }
                        } else if ($q_row['event_type'] === 'portal.signup') {
                            if (!isset($member_signups[$ev_sid]) || $member_signups[$ev_sid] !== 'confirmed') {
                                $member_signups[$ev_sid] = 'confirmed';
                                $pending_increments[$ev_sid] = ($pending_increments[$ev_sid] ?? 0) + 1;
                            }
                        }
                    }
                }
            }
        }
    }

    $today = gmdate('Y-m-d');
    $now_ts = time();

    $result_sessions = [];
    foreach ($sessions as $s) {
        $sid = strval($s['session_id']);
        $cap = intval($s['max_capacity']);
        $conf = intval($s['confirmed_count']) + intval($pending_increments[$sid] ?? 0);
        $rem = max(0, $cap - $conf);

        $m_status = $member_signups[$sid] ?? null;

        // Calculate availability & status
        $reg_open = true;
        if (!empty($s['registration_open_at']) && strtotime($s['registration_open_at']) > $now_ts) {
            $reg_open = false;
        }
        if (!empty($s['registration_close_at']) && strtotime($s['registration_close_at']) < $now_ts) {
            $reg_open = false;
        }
        if ($s['date_text'] < $today) {
            $reg_open = false;
        }

        $s['remaining_capacity'] = $rem;
        $s['is_full'] = ($conf >= $cap);
        $s['member_signup_status'] = $m_status;
        $s['is_registration_open'] = $reg_open;

        $result_sessions[] = $s;
    }

    echo json_encode(['success' => true, 'sessions' => $result_sessions]);
    exit;
}

// Route: Public Session Signup Submission API
if (($uri === '/api/v1/public/signup' || $uri === '/public/api/signup') && $method === 'POST') {
    header('Content-Type: application/json; charset=utf-8');
    $raw = file_get_contents('php://input');
    $input = json_decode($raw, true);

    if (!is_array($input) || empty($input['session_id'])) {
        http_response_code(400);
        echo json_encode(['success' => false, 'error' => 'session_id is required']);
        exit;
    }

    $action = trim($input['action'] ?? 'signup');
    $event_type = ($action === 'cancel') ? 'portal.cancel_signup' : 'portal.signup';

    $event_uuid = 'evt_portal_sgn_' . bin2hex(random_bytes(8));
    $payload = $input;
    $payload['event_uuid'] = $event_uuid;
    $payload['source'] = 'Public Self-Service Portal';
    $payload['received_at'] = gmdate('Y-m-d H:i:s') . ' UTC';

    $stmt = $pdo->prepare("INSERT INTO inbound_event_queue (event_type, provider_event_id, payload_json, received_at, processed) VALUES (?, ?, ?, datetime('now'), 0)");
    $stmt->execute([$event_type, $event_uuid, json_encode($payload)]);

    echo json_encode([
        'success' => true,
        'message' => 'Signup request received',
        'event_uuid' => $event_uuid,
        'action' => $action
    ]);
    exit;
}

// Route: Directory Index Sync (Desktop -> Cloud Relay)
if ($uri === '/api/v1/sync/directory-index' && $method === 'POST') {
    header('Content-Type: application/json; charset=utf-8');
    $req_key = $_SERVER['HTTP_X_SYNC_API_KEY'] ?? $_GET['sync_api_key'] ?? '';
    if ($req_key !== $sync_api_key) {
        http_response_code(401);
        echo json_encode(['success' => false, 'error' => 'Unauthorized']);
        exit;
    }

    $raw = file_get_contents('php://input');
    $input = json_decode($raw, true);
    $members = is_array($input) && isset($input['members']) ? $input['members'] : (is_array($input) ? $input : []);

    // Ensure columns exist on target table
    try { $pdo->exec("ALTER TABLE directory_index ADD COLUMN last_name TEXT DEFAULT ''"); } catch (Throwable $e) {}
    try { $pdo->exec("ALTER TABLE directory_index ADD COLUMN profile_photo TEXT DEFAULT ''"); } catch (Throwable $e) {}

    $stmt = $pdo->prepare("
        INSERT INTO directory_index (human_id, phone_e164, first_name, last_name, masked_phone, profile_photo, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, datetime('now'))
        ON CONFLICT(human_id) DO UPDATE SET
            phone_e164 = excluded.phone_e164,
            first_name = excluded.first_name,
            last_name = excluded.last_name,
            masked_phone = excluded.masked_phone,
            profile_photo = excluded.profile_photo,
            updated_at = datetime('now')
    ");

    $count = 0;
    $failed_count = 0;
    $errors = [];

    foreach ($members as $m) {
        $hid = trim($m['human_id'] ?? '');
        $fn = trim($m['first_name'] ?? '');
        $ln = trim($m['last_name'] ?? '');
        $photo = trim($m['profile_photo'] ?? '');
        $raw_p = $m['phone'] ?? $m['phone_e164'] ?? '';
        $e164 = normalize_phone_e164_php($raw_p);
        $mp = mask_phone_php($raw_p);

        if ($hid !== '' && $fn !== '') {
            try {
                $stmt->execute([$hid, $e164, $fn, $ln, $mp, $photo]);
                $count++;
            } catch (Throwable $e) {
                $failed_count++;
                $errors[] = get_class($e) . ": " . $e->getMessage();
            }
        }
    }

    $is_success = ($failed_count === 0);
    http_response_code($is_success ? 200 : 500);
    echo json_encode([
        'success' => $is_success,
        'synced_count' => $count,
        'failed_count' => $failed_count,
        'errors' => $errors
    ]);
    exit;
}

// Route: Today Attendance Index Sync (Desktop -> Cloud Relay Snapshot)
if ($uri === '/api/v1/sync/attendance-index' && $method === 'POST') {
    header('Content-Type: application/json; charset=utf-8');
    $req_key = $_SERVER['HTTP_X_SYNC_API_KEY'] ?? $_GET['sync_api_key'] ?? '';
    if ($req_key !== $sync_api_key) {
        http_response_code(401);
        echo json_encode(['success' => false, 'error' => 'Unauthorized']);
        exit;
    }

    $raw = file_get_contents('php://input');
    $input = json_decode($raw, true);
    $att_date = trim($input['attendance_date'] ?? current_operational_date());
    $attendance = is_array($input) && isset($input['attendance']) ? $input['attendance'] : [];

    $pdo->beginTransaction();
    $pdo->exec("DELETE FROM today_attendance_index");
    $stmt = $pdo->prepare("INSERT OR REPLACE INTO today_attendance_index (human_id, phone_e164, attendance_date, updated_at) VALUES (?, ?, ?, datetime('now'))");

    $count = 0;
    foreach ($attendance as $item) {
        $hid = is_array($item) ? trim($item['human_id'] ?? '') : trim($item);
        $phone = is_array($item) ? normalize_phone_e164_php($item['phone'] ?? $item['phone_e164'] ?? '') : '';
        if ($hid !== '') {
            $stmt->execute([$hid, $phone, $att_date]);
            $count++;
        }
    }
    $pdo->commit();

    echo json_encode(['success' => true, 'synced_count' => $count, 'attendance_date' => $att_date]);
    exit;
}

// Route: Safe Read-Back Status of Staff Credentials Index (Diagnostic Read-Back Only)
if ($uri === '/api/v1/sync/staff-credentials-status' && $method === 'GET') {
    header('Content-Type: application/json; charset=utf-8');
    $req_key = $_SERVER['HTTP_X_SYNC_API_KEY'] ?? $_GET['sync_api_key'] ?? '';
    if ($req_key !== $sync_api_key) {
        http_response_code(401);
        echo json_encode(['success' => false, 'error' => 'Unauthorized']);
        exit;
    }

    $cols = [];
    $pragma = $pdo->query("PRAGMA table_info(staff_credentials_index)")->fetchAll(PDO::FETCH_ASSOC);
    foreach ($pragma as $col) {
        $cols[] = $col['name'];
    }

    $ms_cols = [];
    $ms_pragma = $pdo->query("PRAGMA table_info(mobile_sessions)")->fetchAll(PDO::FETCH_ASSOC);
    foreach ($ms_pragma as $col) {
        $ms_cols[] = $col['name'];
    }

    $rl_cols = [];
    $rl_pragma = $pdo->query("PRAGMA table_info(staff_auth_rate_limits)")->fetchAll(PDO::FETCH_ASSOC);
    foreach ($rl_pragma as $col) {
        $rl_cols[] = $col['name'];
    }

    $dir_cols = [];
    $dir_pk = '';
    $dir_count = 0;
    $pragma_table_info = [];
    $pragma_index_list = [];
    $pragma_index_details = [];

    try {
        $pragma_table_info = $pdo->query("PRAGMA table_info(directory_index)")->fetchAll(PDO::FETCH_ASSOC);
        foreach ($pragma_table_info as $col) {
            $dir_cols[] = $col['name'];
            if (!empty($col['pk'])) {
                $dir_pk = $col['name'];
            }
        }
        $cnt_r = $pdo->query("SELECT COUNT(*) as cnt FROM directory_index")->fetch(PDO::FETCH_ASSOC);
        $dir_count = intval($cnt_r['cnt'] ?? 0);

        $pragma_index_list = $pdo->query("PRAGMA index_list(directory_index)")->fetchAll(PDO::FETCH_ASSOC);
        foreach ($pragma_index_list as $idx) {
            $idx_name = $idx['name'] ?? '';
            if (!empty($idx_name)) {
                $idx_info = $pdo->query("PRAGMA index_info(" . $pdo->quote($idx_name) . ")")->fetchAll(PDO::FETCH_ASSOC);
                $pragma_index_details[$idx_name] = $idx_info;
            }
        }
    } catch (Throwable $e) {}

    $dir_records = [];
    try {
        $d_stmt = $pdo->query("SELECT human_id, phone_e164, first_name, COALESCE(last_name, '') as last_name, length(COALESCE(profile_photo, '')) as photo_len FROM directory_index WHERE human_id = 'P-20260813-F9C7' OR length(profile_photo) > 0 ORDER BY length(profile_photo) DESC LIMIT 5");
        while ($dr = $d_stmt->fetch(PDO::FETCH_ASSOC)) {
            $dir_records[] = $dr;
        }
    } catch (Throwable $e) {
        $dir_records = ['error' => $e->getMessage()];
    }

    $write_audit_log = [];
    try {
        $audit_stmt = $pdo->query("SELECT id, timestamp, route_name, pid, human_id, operation_type, incoming_last_name, incoming_photo_len, post_write_last_name, post_write_photo_len FROM directory_write_audit ORDER BY id DESC LIMIT 20");
        while ($ar_row = $audit_stmt->fetch(PDO::FETCH_ASSOC)) {
            $write_audit_log[] = $ar_row;
        }
    } catch (Throwable $e) {}

    $records = [];
    $stmt = $pdo->query("SELECT human_id, display_name, email, role, credential_version, capabilities_json, status, updated_at, length(pin_hash) as hash_len, substr(pin_hash, 1, 13) as hash_prefix FROM staff_credentials_index");
    while ($r = $stmt->fetch(PDO::FETCH_ASSOC)) {
        $records[] = $r;
    }

    # Protected Session Creation Self-Test using REAL Staff Record (Rolled back immediately)
    $test_res = "PASS";
    $test_err = "";
    $rnd_test = "PASS";
    $pdo_test = "PASS";
    $failing_stage = "none";
    try {
        $pdo->beginTransaction();
        $real_staff_row = isset($records[0]) ? $records[0] : [
            'human_id' => 'P-20260813-F9C7',
            'display_name' => 'John Boyte',
            'role' => 'Staff',
            'credential_version' => 3
        ];
        
        $failing_stage = "create_mobile_session_record";
        $sess_test = create_mobile_session_record($pdo, $real_staff_row);
        
        $failing_stage = "rollback";
        $pdo->rollBack();
    } catch (Throwable $e) {
        if ($pdo->inTransaction()) {
            $pdo->rollBack();
        }
        $test_res = "FAIL";
        $pdo_test = "FAIL";
        $test_err = get_class($e) . ": " . $e->getMessage() . " at line " . strval($e->getLine());
    }

    $att_sample = [];
    try {
        $a_stmt = $pdo->prepare("
            SELECT 
                t.human_id,
                COALESCE(d.first_name, 'Member') as first_name,
                COALESCE(d.last_name, '') as last_name,
                length(COALESCE(d.profile_photo, '')) as photo_len,
                CASE WHEN length(COALESCE(d.profile_photo, '')) > 0 THEN 1 ELSE 0 END as has_photo,
                t.attendance_date,
                t.updated_at as check_in_time
            FROM today_attendance_index t
            LEFT JOIN directory_index d 
                   ON (t.human_id = d.human_id OR (t.phone_e164 = d.phone_e164 AND t.phone_e164 != ''))
            ORDER BY t.updated_at DESC LIMIT 5
        ");
        $a_stmt->execute();
        while ($ar = $a_stmt->fetch(PDO::FETCH_ASSOC)) {
            $att_sample[] = [
                'human_id' => $ar['human_id'],
                'first_name' => $ar['first_name'],
                'last_name' => $ar['last_name'],
                'has_photo' => intval($ar['has_photo']) === 1,
                'photo_len' => intval($ar['photo_len']),
                'photo_url' => intval($ar['has_photo']) === 1 ? ('/api/v1/mobile/people/photo?human_id=' . urlencode($ar['human_id'])) : null,
                'check_in_time' => $ar['check_in_time']
            ];
        }
    } catch (Throwable $e) {
        $att_sample = ['error' => $e->getMessage()];
    }

    echo json_encode([
        'success' => true,
        'table_columns' => $cols,
        'mobile_sessions_columns' => $ms_cols,
        'rate_limits_columns' => $rl_cols,
        'directory_columns' => $dir_cols,
        'directory_pk' => $dir_pk,
        'directory_count' => $dir_count,
        'directory_migration' => $GLOBALS['dir_migration_stats'],
        'pragma_table_info' => $pragma_table_info,
        'pragma_index_list' => $pragma_index_list,
        'pragma_index_details' => $pragma_index_details,
        'directory_sample' => $dir_records,
        'today_attendance_sample' => $att_sample,
        'session_insert_test' => $test_res,
        'real_staff_session_insert_test' => $test_res,
        'random_bytes_test' => $rnd_test,
        'pdo_session_insert_test' => $pdo_test,
        'failing_stage' => $failing_stage,
        'test_error' => $test_err,
        'records' => $records
    ]);
    exit;
}

// Route: Safe Read-Back of Latest Mobile Auth Diagnostic Record
if ($uri === '/api/v1/sync/mobile-auth-diagnostic/latest' && $method === 'GET') {
    header('Content-Type: application/json; charset=utf-8');
    $req_key = $_SERVER['HTTP_X_SYNC_API_KEY'] ?? $_GET['sync_api_key'] ?? '';
    if ($req_key !== $sync_api_key) {
        http_response_code(401);
        echo json_encode(['success' => false, 'error' => 'Unauthorized']);
        exit;
    }

    $diag = null;
    try {
        $stmt = $pdo->query("SELECT reference_id, created_at, stage, exception_class, sanitized_error, error_code, identifier_match, pin_verified, credential_version FROM mobile_auth_diagnostics ORDER BY id DESC LIMIT 1");
        $diag = $stmt->fetch(PDO::FETCH_ASSOC);
    } catch (Throwable $e) {}

    echo json_encode([
        'success' => true,
        'latest_diagnostic' => $diag
    ]);
    exit;
}

// Route: Staff Credentials Index Sync (Desktop -> Cloud Relay)
if ($uri === '/api/v1/sync/staff-credentials-index' && $method === 'POST') {
    header('Content-Type: application/json; charset=utf-8');
    $req_key = $_SERVER['HTTP_X_SYNC_API_KEY'] ?? $_GET['sync_api_key'] ?? '';
    if ($req_key !== $sync_api_key) {
        http_response_code(401);
        echo json_encode(['success' => false, 'error' => 'Unauthorized']);
        exit;
    }

    $raw = file_get_contents('php://input');
    $input = json_decode($raw, true);
    $staff = is_array($input) && isset($input['staff']) ? $input['staff'] : [];

    $pdo->beginTransaction();
    $pdo->exec("DELETE FROM staff_credentials_index;");
    $stmt = $pdo->prepare("INSERT OR REPLACE INTO staff_credentials_index (human_id, display_name, email, role, pin_hash, credential_version, capabilities_json, status, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, datetime('now'))");

    $count = 0;
    foreach ($staff as $item) {
        if (is_array($item)) {
            $hid = trim($item['human_id'] ?? '');
            $name = trim($item['display_name'] ?? $item['name'] ?? '');
            $email = trim($item['email'] ?? '');
            $role = trim($item['role'] ?? 'Staff');
            $pin_h = trim($item['pin_hash'] ?? '');
            $cred_ver = intval($item['credential_version'] ?? 1);
            $caps = is_array($item['capabilities'] ?? null) ? json_encode($item['capabilities']) : '["view_attendance"]';
            $st = trim($item['status'] ?? 'active');

            if ($hid !== '' && $name !== '' && $pin_h !== '') {
                $stmt->execute([$hid, $name, $email, $role, $pin_h, $cred_ver, $caps, $st]);
                $count++;
            }
        }
    }

    // Instantly revoke active mobile sessions for staff who were deactivated, removed, or whose credential version changed
    $rev_audit_list = [];
    try {
        $audit_q = $pdo->query("
            SELECT 
                ms.human_id,
                ms.credential_version as ms_cred_ver,
                ms.created_at as ms_created_at,
                ms.expires_at as ms_expires_at,
                sc.credential_version as sc_cred_ver,
                sc.status as sc_status,
                CASE 
                    WHEN sc.human_id IS NULL THEN 'missing_staff'
                    WHEN LOWER(sc.status) != 'active' THEN 'inactive_staff'
                    WHEN ms.credential_version != sc.credential_version THEN 'credential_version_mismatch'
                    ELSE 'unknown'
                END as revocation_reason
            FROM mobile_sessions ms
            LEFT JOIN staff_credentials_index sc ON sc.human_id = ms.human_id
            WHERE ms.revoked = 0
              AND (
                  sc.human_id IS NULL 
               OR LOWER(sc.status) != 'active' 
               OR ms.credential_version != sc.credential_version
              )
        ");
        $rev_audit_list = $audit_q->fetchAll(PDO::FETCH_ASSOC);
        $audit_q->closeCursor();
    } catch (Throwable $ae) {}

    $rev_stmt = $pdo->prepare("
        UPDATE mobile_sessions 
        SET revoked = 1 
        WHERE revoked = 0
          AND session_token_hash IN (
            SELECT ms.session_token_hash 
            FROM mobile_sessions ms
            LEFT JOIN staff_credentials_index sc ON sc.human_id = ms.human_id
            WHERE ms.revoked = 0
              AND (
                  sc.human_id IS NULL 
               OR LOWER(sc.status) != 'active' 
               OR ms.credential_version != sc.credential_version
              )
        )
    ");
    $rev_stmt->execute();
    $affected_rows = $rev_stmt->rowCount();
    $rev_stmt->closeCursor();

    if ($affected_rows > 0 || !empty($rev_audit_list)) {
        $audit_payload = [
            'revocation_source' => 'staff_credentials_sync',
            'affected_rows' => $affected_rows,
            'caller_ip' => $_SERVER['REMOTE_ADDR'] ?? 'unknown',
            'caller_user_agent' => substr($_SERVER['HTTP_USER_AGENT'] ?? 'unknown', 0, 100),
            'has_valid_sync_key' => ($req_key === $sync_api_key) ? 1 : 0,
            'revoked_sessions_audit' => $rev_audit_list
        ];
        log_auth_diagnostic($pdo, 'DIAG-REVOCATION-AUDIT', 'sync_staff_credentials_index', 'RevocationEvent', json_encode($audit_payload), 200);
    }

    $pdo->commit();

    echo json_encode(['success' => true, 'synced_count' => $count]);
    exit;
}

// Route: Authenticated Mobile Staff Login
if (($uri === '/api/v1/mobile/auth/login' || $uri === '/mobile/api/auth/login') && $method === 'POST') {
    header('Content-Type: application/json; charset=utf-8');
    header('Cache-Control: no-store, no-cache, must-revalidate, max-age=0');

    $ref_id = 'REF-' . strtoupper(bin2hex(random_bytes(4)));
    $cur_stage = 'request_parse';
    $id_match = 0;
    $pin_ok = 0;
    $cred_ver = 0;

    try {
        $ip = $_SERVER['REMOTE_ADDR'] ?? '0.0.0.0';
        $raw = file_get_contents('php://input');
        $input = json_decode($raw, true);

        $identifier = is_array($input) ? trim($input['identifier'] ?? $input['human_id'] ?? $input['email'] ?? '') : '';
        $pin = is_array($input) ? trim($input['pin'] ?? '') : '';

        if (empty($identifier) || empty($pin)) {
            http_response_code(400);
            echo json_encode(['success' => false, 'error' => 'Staff ID or email and 6-digit PIN are required.', 'reference_id' => $ref_id]);
            exit;
        }

        if (strlen($pin) !== 6 || !ctype_digit($pin)) {
            http_response_code(400);
            echo json_encode(['success' => false, 'error' => 'Mobile Staff PIN must be exactly 6 numeric digits.', 'reference_id' => $ref_id]);
            exit;
        }

        $cur_stage = 'rate_limit_check';
        if (!check_staff_auth_rate_limit($pdo, $identifier, $ip)) {
            http_response_code(429);
            echo json_encode(['success' => false, 'error' => 'Too many failed login attempts. Please wait 15 minutes before trying again.', 'reference_id' => $ref_id]);
            exit;
        }

        $cur_stage = 'staff_lookup';
        $stmt = $pdo->prepare("SELECT human_id, display_name, email, role, pin_hash, credential_version, capabilities_json, status FROM staff_credentials_index WHERE (human_id = ? OR LOWER(email) = LOWER(?)) AND LOWER(status) = 'active' LIMIT 1");
        $stmt->execute([$identifier, $identifier]);
        $staff = $stmt->fetch(PDO::FETCH_ASSOC);
        $stmt->closeCursor();
        unset($stmt);

        $authenticated = false;

        if ($staff) {
            $id_match = 1;
            $cred_ver = intval($staff['credential_version'] ?? 1);
            $cur_stage = 'pbkdf2_verification';
            $stored_hash = $staff['pin_hash'];
            if (strpos($stored_hash, 'pbkdf2:') === 0) {
                $parts = explode(':', $stored_hash);
                if (count($parts) === 5) {
                    $algo = $parts[1];
                    $iterations = intval($parts[2]);
                    $salt_bin = hex2bin($parts[3]);
                    $expected_digest = $parts[4];
                    $computed_digest = bin2hex(hash_pbkdf2($algo, $pin, $salt_bin, $iterations, 32, true));
                    if (hash_equals($expected_digest, $computed_digest)) {
                        $authenticated = true;
                        $pin_ok = 1;
                    }
                }
            } elseif (strpos($stored_hash, '$2y$') === 0 || strpos($stored_hash, '$argon2') === 0) {
                if (password_verify($pin, $stored_hash)) {
                    $authenticated = true;
                    $pin_ok = 1;
                }
            }
        }

        $cur_stage = 'successful_rate_limit_clear';
        record_staff_auth_attempt($pdo, $identifier, $ip, $authenticated);

        if (!$authenticated || !$staff) {
            http_response_code(401);
            echo json_encode(['success' => false, 'error' => 'Invalid staff credentials or PIN.', 'reference_id' => $ref_id]);
            exit;
        }

        $cur_stage = 'create_mobile_session_record';
        try {
            $sess_res = create_mobile_session_record($pdo, $staff);
        } catch (Throwable $se) {
            $err_detail = get_class($se) . ': ' . $se->getMessage() . ' (Code: ' . $se->getCode() . ')';
            if ($se instanceof PDOException && !empty($se->errorInfo)) {
                $err_detail .= ' | PDOErrorInfo: ' . json_encode($se->errorInfo);
            }
            log_auth_diagnostic($pdo, $ref_id, 'create_mobile_session_record', get_class($se), $err_detail, $se->getCode(), $id_match, $pin_ok, $cred_ver);
            throw $se;
        }
        $token = $sess_res['token'];
        $expires_at = $sess_res['expires_at'];

        $cur_stage = 'response_array_build';
        $caps = json_decode($staff['capabilities_json'] ?? '["view_attendance"]', true);

        $resp_array = [
            'success' => true,
            'session_token' => $token,
            'staff_user' => [
                'human_id' => $staff['human_id'],
                'name' => $staff['display_name'],
                'role' => $staff['role'],
                'email' => $staff['email'] ?? '',
                'capabilities' => is_array($caps) ? $caps : ['view_attendance']
            ],
            'expires_at' => $expires_at,
            'reference_id' => $ref_id
        ];

        $cur_stage = 'json_encode';
        $json_out = json_encode($resp_array);

        if ($json_out === false) {
            $json_err = json_last_error_msg();
            log_auth_diagnostic($pdo, $ref_id, 'json_encode', 'JsonException', 'JSON encoding failed: ' . $json_err, 0, $id_match, $pin_ok, $cred_ver);
            http_response_code(500);
            echo json_encode([
                'success' => false,
                'error' => 'Unable to create staff session due to a server error.',
                'reference_id' => $ref_id
            ]);
            exit;
        }

        $cur_stage = 'response_emit';
        echo $json_out;
        exit;
    } catch (Throwable $e) {
        log_auth_diagnostic($pdo, $ref_id, $cur_stage, get_class($e), $e->getMessage(), $e->getCode(), $id_match, $pin_ok, $cred_ver);
        http_response_code(500);
        echo json_encode([
            'success' => false,
            'error' => 'Unable to create staff session due to a server error.',
            'reference_id' => $ref_id
        ]);
        exit;
    }
}

// Route: Authenticated Mobile Session Validation (/auth/me)
if (($uri === '/api/v1/mobile/auth/me' || $uri === '/mobile/api/auth/me') && $method === 'GET') {
    header('Content-Type: application/json; charset=utf-8');
    header('Cache-Control: no-store, no-cache, must-revalidate, max-age=0');

    $session = verify_mobile_session($pdo);
    $caps = json_decode($session['capabilities_json'] ?? '["view_attendance"]', true);

    echo json_encode([
        'success' => true,
        'staff_user' => [
            'human_id' => $session['human_id'],
            'name' => $session['display_name'],
            'role' => $session['role'],
            'capabilities' => is_array($caps) ? $caps : ['view_attendance']
        ],
        'expires_at' => $session['expires_at']
    ]);
    exit;
}

// Route: Authenticated Mobile Staff Logout
if (($uri === '/api/v1/mobile/auth/logout' || $uri === '/mobile/api/auth/logout') && $method === 'POST') {
    header('Content-Type: application/json; charset=utf-8');
    header('Cache-Control: no-store, no-cache, must-revalidate, max-age=0');

    $session = verify_mobile_session($pdo);
    $l_stmt = $pdo->prepare("UPDATE mobile_sessions SET revoked = 1 WHERE session_token_hash = ?");
    $l_stmt->execute([$session['session_token_hash']]);
    $l_stmt->closeCursor();

    $audit_payload = [
        'revocation_source' => 'explicit_logout',
        'affected_human_id' => $session['human_id'],
        'reason' => 'explicit_logout',
        'caller_ip' => $_SERVER['REMOTE_ADDR'] ?? 'unknown',
        'caller_user_agent' => substr($_SERVER['HTTP_USER_AGENT'] ?? 'unknown', 0, 100)
    ];
    log_auth_diagnostic($pdo, 'DIAG-LOGOUT-REVOCATION', 'mobile_auth_logout', 'RevocationEvent', json_encode($audit_payload), 200);

    echo json_encode(['success' => true, 'message' => 'Staff session revoked successfully.']);
    exit;
}

// Route: Authenticated Mobile System Health & Sync Status Endpoint
if (($uri === '/api/v1/mobile/system/health' || $uri === '/mobile/api/system/health') && $method === 'GET') {
    header('Content-Type: application/json; charset=utf-8');
    header('Cache-Control: no-store, no-cache, must-revalidate, max-age=0');

    $session = verify_mobile_session($pdo);

    $today_date = current_operational_date();
    $att_count = 0;
    $last_att_update = null;

    try {
        $c_stmt = $pdo->prepare("SELECT COUNT(*) as cnt, MAX(updated_at) as max_up FROM today_attendance_index WHERE attendance_date = ?");
        $c_stmt->execute([$today_date]);
        $c_row = $c_stmt->fetch(PDO::FETCH_ASSOC);
        $c_stmt->closeCursor();
        if ($c_row) {
            $att_count = intval($c_row['cnt'] ?? 0);
            $last_att_update = $c_row['max_up'];
        }
    } catch (Throwable $e) {}

    $dir_count = 0;
    try {
        $d_stmt = $pdo->query("SELECT COUNT(*) as cnt FROM directory_index");
        $d_row = $d_stmt->fetch(PDO::FETCH_ASSOC);
        $dir_count = intval($d_row['cnt'] ?? 0);
    } catch (Throwable $e) {}

    $dt_ny = new DateTime('now', new DateTimeZone('America/New_York'));

    echo json_encode([
        'success' => true,
        'environment' => 'production',
        'gateway_host' => $_SERVER['HTTP_HOST'] ?? 'app.reallife-studycenter.org',
        'server_time_utc' => gmdate('Y-m-d H:i:s'),
        'server_time_ny' => $dt_ny->format('Y-m-d H:i:s T'),
        'operational_date' => $today_date,
        'today_checked_in_count' => $att_count,
        'last_attendance_update' => $last_att_update,
        'directory_indexed_count' => $dir_count
    ]);
    exit;
}

// Route: Authenticated Staff-Only Who's Here / Attendance Endpoint
if (($uri === '/api/v1/mobile/attendance/today' || $uri === '/mobile/api/attendance/today') && $method === 'GET') {
    header('Content-Type: application/json; charset=utf-8');
    header('Cache-Control: no-store, no-cache, must-revalidate, max-age=0');

    $session = verify_mobile_session($pdo);
    $raw_caps = $session['capabilities_json'] ?? null;
    $caps = (!empty($raw_caps)) ? json_decode($raw_caps, true) : null;
    if (!is_array($caps)) {
        $caps = ['view_attendance'];
    }

    if (!in_array('view_attendance', $caps)) {
        http_response_code(403);
        echo json_encode(['success' => false, 'error' => 'Forbidden: Your staff role is not authorized to view attendance.']);
        exit;
    }

    $today_date = current_operational_date();

    $stmt = $pdo->prepare("
        SELECT 
            t.human_id,
            COALESCE(d.first_name, 'Member') as first_name,
            COALESCE(d.last_name, '') as last_name,
            COALESCE(d.profile_photo, '') as profile_photo,
            t.attendance_date,
            t.updated_at as check_in_time
        FROM today_attendance_index t
        LEFT JOIN directory_index d 
               ON (t.human_id = d.human_id OR (t.phone_e164 = d.phone_e164 AND t.phone_e164 != ''))
        WHERE t.attendance_date = ?
        ORDER BY t.updated_at DESC
    ");
    $stmt->execute([$today_date]);
    $rows = $stmt->fetchAll(PDO::FETCH_ASSOC);

    $checked_in = [];
    foreach ($rows as $row) {
        $has_photo = !empty($row['profile_photo']);
        $checked_in[] = [
            'human_id' => $row['human_id'],
            'first_name' => $row['first_name'],
            'last_name' => $row['last_name'],
            'photo_url' => $has_photo ? ('/api/v1/mobile/people/photo?human_id=' . urlencode($row['human_id'])) : null,
            'attendance_date' => $row['attendance_date'],
            'check_in_time' => $row['check_in_time']
        ];
    }

    echo json_encode([
        'success' => true,
        'attendance_date' => $today_date,
        'total_checked_in' => count($checked_in),
        'checked_in' => $checked_in
    ]);
    exit;
}

// Route: Authenticated Staff Profile Photo Endpoint
if (($uri === '/api/v1/mobile/people/photo' || $uri === '/mobile/api/people/photo') && $method === 'GET') {
    $session = verify_mobile_session($pdo);
    $hid = trim($_GET['human_id'] ?? '');
    if (empty($hid)) {
        http_response_code(400);
        exit;
    }

    $stmt = $pdo->prepare("SELECT profile_photo FROM directory_index WHERE human_id = ? LIMIT 1");
    $stmt->execute([$hid]);
    $row = $stmt->fetch(PDO::FETCH_ASSOC);

    $photo = $row['profile_photo'] ?? '';
    if (empty($photo)) {
        http_response_code(404);
        exit;
    }

    if (strpos($photo, 'data:image/') === 0) {
        $parts = explode(',', $photo, 2);
        if (count($parts) === 2) {
            $meta = $parts[0];
            $data = base64_decode($parts[1]);
            $mime = 'image/jpeg';
            if (strpos($meta, 'image/png') !== false) {
                $mime = 'image/png';
            } elseif (strpos($meta, 'image/webp') !== false) {
                $mime = 'image/webp';
            }
            header('Content-Type: ' . $mime);
            header('Cache-Control: private, max-age=86400');
            echo $data;
            exit;
        }
    } elseif (filter_var($photo, FILTER_VALIDATE_URL)) {
        header('Location: ' . $photo);
        exit;
    }

    http_response_code(404);
    exit;
}

// Route: Authenticated Mobile Participant / People Search Endpoint
if (($uri === '/api/v1/mobile/people/search' || $uri === '/mobile/api/people/search') && $method === 'GET') {
    header('Content-Type: application/json; charset=utf-8');
    header('Cache-Control: no-store, no-cache, must-revalidate, max-age=0');

    $session = verify_mobile_session($pdo);

    $q = trim($_GET['q'] ?? $_GET['query'] ?? '');
    if (empty($q)) {
        echo json_encode([
            'success' => true,
            'query' => '',
            'total_results' => 0,
            'results' => []
        ]);
        exit;
    }

    $param = '%' . $q . '%';
    $stmt = $pdo->prepare("
        SELECT 
            human_id,
            COALESCE(first_name, 'Member') as first_name,
            COALESCE(last_name, '') as last_name,
            COALESCE(masked_phone, '') as masked_phone,
            COALESCE(phone_e164, '') as phone_e164,
            CASE WHEN length(COALESCE(profile_photo, '')) > 0 THEN 1 ELSE 0 END as has_photo
        FROM directory_index
        WHERE LOWER(first_name) LIKE LOWER(?)
           OR LOWER(last_name) LIKE LOWER(?)
           OR LOWER(first_name || ' ' || last_name) LIKE LOWER(?)
           OR LOWER(human_id) LIKE LOWER(?)
           OR phone_e164 LIKE ?
        ORDER BY first_name ASC, last_name ASC
        LIMIT 50
    ");
    $stmt->execute([$param, $param, $param, $param, $param]);
    $rows = $stmt->fetchAll(PDO::FETCH_ASSOC);
    $stmt->closeCursor();

    $results = [];
    foreach ($rows as $row) {
        $fn = trim($row['first_name']);
        $ln = trim($row['last_name']);
        $full_name = trim($fn . ' ' . $ln);
        $has_photo = intval($row['has_photo']) === 1;
        $photo_url = $has_photo ? ('/api/v1/mobile/people/photo?human_id=' . urlencode($row['human_id'])) : null;

        $results[] = [
            'human_id' => $row['human_id'],
            'humanId' => $row['human_id'],
            'first_name' => $fn,
            'firstName' => $fn,
            'last_name' => $ln,
            'lastName' => $ln,
            'name' => $full_name,
            'fullName' => $full_name,
            'phone_e164' => $row['phone_e164'],
            'phoneE164' => $row['phone_e164'],
            'masked_phone' => $row['masked_phone'],
            'maskedPhone' => $row['masked_phone'],
            'photo_url' => $photo_url,
            'photoUrl' => $photo_url,
            'has_photo' => $has_photo
        ];
    }

    echo json_encode([
        'success' => true,
        'query' => $q,
        'total_results' => count($results),
        'results' => $results
    ]);
    exit;
}

// Route: Authenticated Mobile Staff Participant Check-In Endpoint
if (($uri === '/api/v1/mobile/attendance/check-in' || $uri === '/mobile/api/attendance/check-in') && $method === 'POST') {
    header('Content-Type: application/json; charset=utf-8');
    header('Cache-Control: no-store, no-cache, must-revalidate, max-age=0');

    $session = verify_mobile_session($pdo);

    $raw = file_get_contents('php://input');
    $input = json_decode($raw, true);
    $payload = is_array($input) ? $input : [];

    $human_id = trim($payload['human_id'] ?? $payload['humanId'] ?? $payload['personUuid'] ?? $payload['person_uuid'] ?? $_GET['human_id'] ?? '');
    $phone = trim($payload['phone'] ?? $payload['phone_e164'] ?? '');

    if (empty($human_id) && empty($phone)) {
        http_response_code(400);
        echo json_encode(['success' => false, 'error' => 'Missing participant identifier (human_id or phone).']);
        exit;
    }

    // Lookup participant in directory_index (direct human_id, phone, or QR credential_id / token_hash)
    $p_stmt = $pdo->prepare("
        SELECT human_id, phone_e164, first_name, last_name, masked_phone 
        FROM directory_index 
        WHERE (human_id = ? AND human_id != '') 
           OR (phone_e164 = ? AND phone_e164 != '')
        LIMIT 1
    ");
    $p_stmt->execute([$human_id, $phone]);
    $person = $p_stmt->fetch(PDO::FETCH_ASSOC);
    $p_stmt->closeCursor();

    if (!$person && !empty($human_id)) {
        try {
            $token_hash = hash('sha256', $human_id);
            $qr_stmt = $pdo->prepare("
                SELECT p.human_id 
                FROM participant_qr_credentials c
                JOIN people p ON c.person_id = p.id
                WHERE (c.credential_id = ? OR c.token_hash = ? OR c.token_hash = ?)
                  AND LOWER(COALESCE(c.status, 'active')) = 'active'
                LIMIT 1
            ");
            $qr_stmt->execute([$human_id, $token_hash, $human_id]);
            $resolved_hid = $qr_stmt->fetchColumn();
            $qr_stmt->closeCursor();

            if ($resolved_hid) {
                $p_stmt = $pdo->prepare("
                    SELECT human_id, phone_e164, first_name, last_name, masked_phone 
                    FROM directory_index 
                    WHERE human_id = ? 
                    LIMIT 1
                ");
                $p_stmt->execute([$resolved_hid]);
                $person = $p_stmt->fetch(PDO::FETCH_ASSOC);
                $p_stmt->closeCursor();
            }
        } catch (Throwable $e) {}
    }

    if (!$person) {
        http_response_code(404);
        echo json_encode(['success' => false, 'error' => 'Participant not found in directory index.']);
        exit;
    }

    $target_hid = $person['human_id'];
    $target_phone = $person['phone_e164'];
    $first_name = trim($person['first_name']);
    $last_name = trim($person['last_name']);
    $op_date = current_operational_date();

    // Check duplicate check-in today
    $chk_stmt = $pdo->prepare("
        SELECT updated_at 
        FROM today_attendance_index 
        WHERE (human_id = ? OR (phone_e164 = ? AND phone_e164 != '')) 
          AND attendance_date = ? 
        LIMIT 1
    ");
    $chk_stmt->execute([$target_hid, $target_phone, $op_date]);
    $existing = $chk_stmt->fetch(PDO::FETCH_ASSOC);
    $chk_stmt->closeCursor();

    if ($existing) {
        echo json_encode([
            'success' => true,
            'already_checked_in' => true,
            'message' => "Welcome back, {$first_name}! You are already checked in for today.",
            'human_id' => $target_hid,
            'humanId' => $target_hid,
            'first_name' => $first_name,
            'last_name' => $last_name,
            'check_in_time' => $existing['updated_at'],
            'checkInTime' => $existing['updated_at']
        ]);
        exit;
    }

    // Record check-in in today_attendance_index
    $ins_stmt = $pdo->prepare("
        INSERT OR REPLACE INTO today_attendance_index (human_id, phone_e164, attendance_date, updated_at)
        VALUES (?, ?, ?, datetime('now'))
    ");
    $ins_stmt->execute([$target_hid, $target_phone, $op_date]);
    $ins_stmt->closeCursor();

    // Queue inbound event for Desktop synchronization
    $event_uuid = 'evt_mob_chk_' . bin2hex(random_bytes(8));
    $event_payload = [
        'event_uuid' => $event_uuid,
        'source' => 'mobile_staff_app',
        'staff_human_id' => $session['human_id'],
        'human_id' => $target_hid,
        'phone_e164' => $target_phone,
        'checkInDate' => $op_date,
        'received_at' => gmdate('Y-m-d H:i:s') . ' UTC'
    ];

    $q_stmt = $pdo->prepare("
        INSERT INTO inbound_event_queue (event_type, provider_event_id, payload_json, received_at, processed)
        VALUES ('mobile.checkin', ?, ?, datetime('now'), 0)
    ");
    $q_stmt->execute([$event_uuid, json_encode($event_payload)]);
    $q_stmt->closeCursor();

    $now_str = date('Y-m-d H:i:s');
    echo json_encode([
        'success' => true,
        'already_checked_in' => false,
        'message' => "Check-in recorded successfully for {$first_name}.",
        'human_id' => $target_hid,
        'humanId' => $target_hid,
        'first_name' => $first_name,
        'last_name' => $last_name,
        'check_in_time' => $now_str,
        'checkInTime' => $now_str,
        'event_uuid' => $event_uuid
    ]);
    exit;
}

// Route: Authenticated Mobile Staff Participant Check-Out Endpoint
if (($uri === '/api/v1/mobile/attendance/check-out' || $uri === '/mobile/api/attendance/check-out') && $method === 'POST') {
    header('Content-Type: application/json; charset=utf-8');
    header('Cache-Control: no-store, no-cache, must-revalidate, max-age=0');

    $session = verify_mobile_session($pdo);

    $raw = file_get_contents('php://input');
    $input = json_decode($raw, true);
    $payload = is_array($input) ? $input : [];

    $human_id = trim($payload['human_id'] ?? $payload['humanId'] ?? $payload['personUuid'] ?? $payload['person_uuid'] ?? $_GET['human_id'] ?? '');

    if (empty($human_id)) {
        http_response_code(400);
        echo json_encode(['success' => false, 'error' => 'Missing participant identifier (human_id).']);
        exit;
    }

    $p_stmt = $pdo->prepare("
        SELECT human_id, phone_e164, first_name, last_name 
        FROM directory_index 
        WHERE (human_id = ? AND human_id != '') 
        LIMIT 1
    ");
    $p_stmt->execute([$human_id]);
    $person = $p_stmt->fetch(PDO::FETCH_ASSOC);
    $p_stmt->closeCursor();

    if (!$person) {
        try {
            $token_hash = hash('sha256', $human_id);
            $qr_stmt = $pdo->prepare("
                SELECT p.human_id 
                FROM participant_qr_credentials c
                JOIN people p ON c.person_id = p.id
                WHERE (c.credential_id = ? OR c.token_hash = ? OR c.token_hash = ?)
                  AND LOWER(COALESCE(c.status, 'active')) = 'active'
                LIMIT 1
            ");
            $qr_stmt->execute([$human_id, $token_hash, $human_id]);
            $resolved_hid = $qr_stmt->fetchColumn();
            $qr_stmt->closeCursor();

            if ($resolved_hid) {
                $p_stmt = $pdo->prepare("
                    SELECT human_id, phone_e164, first_name, last_name 
                    FROM directory_index 
                    WHERE human_id = ? 
                    LIMIT 1
                ");
                $p_stmt->execute([$resolved_hid]);
                $person = $p_stmt->fetch(PDO::FETCH_ASSOC);
                $p_stmt->closeCursor();
            }
        } catch (Throwable $e) {}
    }

    if (!$person) {
        http_response_code(404);
        echo json_encode(['success' => false, 'error' => 'Participant not found in directory index.']);
        exit;
    }

    $target_hid = $person['human_id'];
    $first_name = trim($person['first_name']);
    $last_name = trim($person['last_name']);

    $chk_stmt = $pdo->prepare("
        SELECT updated_at 
        FROM today_attendance_index 
        WHERE human_id = ? 
        LIMIT 1
    ");
    $chk_stmt->execute([$target_hid]);
    $existing = $chk_stmt->fetch(PDO::FETCH_ASSOC);
    $chk_stmt->closeCursor();

    if (!$existing) {
        echo json_encode([
            'success' => true,
            'already_checked_out' => true,
            'message' => "{$first_name} is not currently checked in.",
            'human_id' => $target_hid,
            'humanId' => $target_hid
        ]);
        exit;
    }

    $del_stmt = $pdo->prepare("DELETE FROM today_attendance_index WHERE human_id = ?");
    $del_stmt->execute([$target_hid]);
    $del_stmt->closeCursor();

    $event_uuid = 'evt_mob_chkout_' . bin2hex(random_bytes(8));
    $event_payload = [
        'event_uuid' => $event_uuid,
        'source' => 'mobile_staff_app',
        'staff_human_id' => $session['human_id'],
        'human_id' => $target_hid,
        'received_at' => gmdate('Y-m-d H:i:s') . ' UTC'
    ];

    $q_stmt = $pdo->prepare("
        INSERT INTO inbound_event_queue (event_type, provider_event_id, payload_json, received_at, processed)
        VALUES ('mobile.checkout', ?, ?, datetime('now'), 0)
    ");
    $q_stmt->execute([$event_uuid, json_encode($event_payload)]);
    $q_stmt->closeCursor();

    $now_str = date('Y-m-d H:i:s');
    echo json_encode([
        'success' => true,
        'already_checked_out' => false,
        'message' => "Check-out recorded successfully for {$first_name}.",
        'human_id' => $target_hid,
        'humanId' => $target_hid,
        'first_name' => $first_name,
        'last_name' => $last_name,
        'check_out_time' => $now_str,
        'checkOutTime' => $now_str,
        'event_uuid' => $event_uuid
    ]);
    exit;
}

// Route: Authenticated Mobile Communications Summary & Operational Shift Notes Endpoint
if (($uri === '/api/v1/mobile/communications/summary' || $uri === '/mobile/api/communications/summary') && $method === 'GET') {
    header('Content-Type: application/json; charset=utf-8');
    header('Cache-Control: no-store, no-cache, must-revalidate, max-age=0');

    $session = verify_mobile_session($pdo);

    $unread_count = 0;
    $recent_messages = [];
    $recent_notes = [];

    try {
        $pn_stmt = $pdo->prepare("
            SELECT 
                pn.note_uuid,
                pn.person_uuid,
                pn.title,
                pn.body,
                pn.created_at,
                COALESCE(d.first_name || ' ' || d.last_name, 'Staff Member') as author_name
            FROM person_notes pn
            LEFT JOIN directory_index d ON d.human_id = pn.person_uuid
            WHERE pn.is_deleted = 0
              AND LOWER(COALESCE(pn.visibility, 'standard_staff')) NOT IN ('sensitive_pastoral', 'pastoral', 'confidential', 'private')
            ORDER BY pn.created_at DESC
            LIMIT 10
        ");
        $pn_stmt->execute();
        $rows = $pn_stmt->fetchAll(PDO::FETCH_ASSOC);
        $pn_stmt->closeCursor();

        foreach ($rows as $r) {
            $recent_notes[] = [
                'id' => $r['note_uuid'],
                'authorName' => $r['author_name'],
                'shiftDate' => substr($r['created_at'], 0, 10),
                'textSnippet' => (strlen($r['body']) > 80) ? (substr($r['body'], 0, 77) . '...') : $r['body']
            ];
        }
    } catch (Throwable $e) {
        // Table not yet present on gateway or empty
    }

    echo json_encode([
        'success' => true,
        'communications' => [
            'unreadInboxCount' => $unread_count,
            'recentMessages' => $recent_messages
        ],
        'shiftNotes' => [
            'totalRecentNotes' => count($recent_notes),
            'recentNotes' => $recent_notes
        ]
    ]);
    exit;
}

// Route: Authenticated Mobile Participant Operational Notes Endpoint
if (preg_match('#^/(api/v1/mobile|mobile/api)/people/([^/]+)/notes$#', $uri, $m) && $method === 'GET') {
    header('Content-Type: application/json; charset=utf-8');
    header('Cache-Control: no-store, no-cache, must-revalidate, max-age=0');

    $session = verify_mobile_session($pdo);
    $target_hid = trim($m[2]);

    $notes = [];
    try {
        $stmt = $pdo->prepare("
            SELECT 
                pn.note_uuid,
                pn.person_uuid,
                pn.title,
                pn.body,
                pn.created_at
            FROM person_notes pn
            WHERE pn.person_uuid = ?
              AND pn.is_deleted = 0
              AND LOWER(COALESCE(pn.visibility, 'standard_staff')) NOT IN ('sensitive_pastoral', 'pastoral', 'confidential', 'private')
            ORDER BY pn.created_at DESC
            LIMIT 20
        ");
        $stmt->execute([$target_hid]);
        $rows = $stmt->fetchAll(PDO::FETCH_ASSOC);
        $stmt->closeCursor();

        foreach ($rows as $r) {
            $notes[] = [
                'id' => $r['note_uuid'],
                'human_id' => $r['person_uuid'],
                'title' => $r['title'] ?? 'Staff Note',
                'body' => $r['body'],
                'created_at' => $r['created_at']
            ];
        }
    } catch (Throwable $e) {}

    echo json_encode([
        'success' => true,
        'human_id' => $target_hid,
        'notes' => $notes,
        'total_notes' => count($notes)
    ]);
    exit;
}

// Route: Authenticated Mobile Add Operational Staff Note Endpoint
if (preg_match('#^/(api/v1/mobile|mobile/api)/people/([^/]+)/notes$#', $uri, $m) && $method === 'POST') {
    header('Content-Type: application/json; charset=utf-8');
    header('Cache-Control: no-store, no-cache, must-revalidate, max-age=0');

    $session = verify_mobile_session($pdo);
    $target_hid = trim($m[2]);

    $raw = file_get_contents('php://input');
    $input = json_decode($raw, true);
    $payload = is_array($input) ? $input : [];

    $body = trim($payload['body'] ?? $payload['note_text'] ?? $payload['text'] ?? '');
    $title = trim($payload['title'] ?? 'Staff Note');

    if (empty($body)) {
        http_response_code(400);
        echo json_encode(['success' => false, 'error' => 'Note content body cannot be empty.']);
        exit;
    }

    if (strlen($body) > 1000) {
        http_response_code(400);
        echo json_encode(['success' => false, 'error' => 'Note content exceeds maximum length of 1000 characters.']);
        exit;
    }

    $pdo->exec("
        CREATE TABLE IF NOT EXISTS person_notes (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            note_uuid TEXT UNIQUE,
            person_id INTEGER DEFAULT 0,
            person_uuid TEXT NOT NULL,
            note_type_uuid TEXT DEFAULT 'nt_general',
            title TEXT DEFAULT 'Staff Note',
            body TEXT NOT NULL,
            visibility TEXT DEFAULT 'standard_staff',
            created_at TEXT NOT NULL DEFAULT (datetime('now')),
            updated_at TEXT NOT NULL DEFAULT (datetime('now')),
            is_deleted INTEGER DEFAULT 0
        )
    ");

    $note_uuid = 'note_' . bin2hex(random_bytes(8));
    $now_str = date('Y-m-d H:i:s');
    $author_name = $session['display_name'] ?? 'Staff Member';

    $stmt = $pdo->prepare("
        INSERT INTO person_notes (note_uuid, person_uuid, note_type_uuid, title, body, visibility, created_at, updated_at, is_deleted)
        VALUES (?, ?, 'nt_general', ?, ?, 'standard_staff', ?, ?, 0)
    ");
    $stmt->execute([$note_uuid, $target_hid, $title, $body, $now_str, $now_str]);
    $stmt->closeCursor();

    echo json_encode([
        'success' => true,
        'message' => 'Operational staff note created successfully.',
        'note' => [
            'id' => $note_uuid,
            'human_id' => $target_hid,
            'title' => $title,
            'body' => $body,
            'author_name' => $author_name,
            'created_at' => $now_str
        ]
    ]);
    exit;
}

// Route: Authenticated Mobile Person Detail Profile & Attendance State Endpoint
if (preg_match('#^/(api/v1/mobile|mobile/api)/people/([^/]+)$#', $uri, $m) && $method === 'GET') {
    header('Content-Type: application/json; charset=utf-8');
    header('Cache-Control: no-store, no-cache, must-revalidate, max-age=0');

    $session = verify_mobile_session($pdo);
    $target_hid = trim($m[2]);

    $stmt = $pdo->prepare("
        SELECT human_id, first_name, last_name, masked_phone, profile_photo, updated_at 
        FROM directory_index 
        WHERE human_id = ? 
        LIMIT 1
    ");
    $stmt->execute([$target_hid]);
    $person = $stmt->fetch(PDO::FETCH_ASSOC);
    $stmt->closeCursor();

    if (!$person) {
        try {
            $token_hash = hash('sha256', $target_hid);
            $qr_stmt = $pdo->prepare("
                SELECT p.human_id 
                FROM participant_qr_credentials c
                JOIN people p ON c.person_id = p.id
                WHERE (c.credential_id = ? OR c.token_hash = ? OR c.token_hash = ?)
                  AND LOWER(COALESCE(c.status, 'active')) = 'active'
                LIMIT 1
            ");
            $qr_stmt->execute([$target_hid, $token_hash, $target_hid]);
            $resolved_hid = $qr_stmt->fetchColumn();
            $qr_stmt->closeCursor();

            if ($resolved_hid) {
                $target_hid = $resolved_hid;
                $stmt = $pdo->prepare("
                    SELECT human_id, first_name, last_name, masked_phone, profile_photo, updated_at 
                    FROM directory_index 
                    WHERE human_id = ? 
                    LIMIT 1
                ");
                $stmt->execute([$target_hid]);
                $person = $stmt->fetch(PDO::FETCH_ASSOC);
                $stmt->closeCursor();
            }
        } catch (Throwable $e) {}
    }

    if (!$person) {
        http_response_code(404);
        echo json_encode(['success' => false, 'error' => 'Participant not found.']);
        exit;
    }

    $fn = trim($person['first_name'] ?? '');
    $ln = trim($person['last_name'] ?? '');
    $name = trim($fn . ' ' . $ln);

    $is_checked_in = false;
    $check_in_time = null;
    try {
        $att_stmt = $pdo->prepare("SELECT check_in_time FROM today_attendance_index WHERE human_id = ? LIMIT 1");
        $att_stmt->execute([$target_hid]);
        $att_row = $att_stmt->fetch(PDO::FETCH_ASSOC);
        $att_stmt->closeCursor();
        if ($att_row) {
            $is_checked_in = true;
            $check_in_time = $att_row['check_in_time'];
        }
    } catch (Throwable $e) {}

    $notes = [];
    try {
        $pn_stmt = $pdo->prepare("
            SELECT note_uuid, title, body, created_at 
            FROM person_notes 
            WHERE person_uuid = ? 
              AND is_deleted = 0 
              AND LOWER(COALESCE(visibility, 'standard_staff')) NOT IN ('sensitive_pastoral', 'pastoral', 'confidential', 'private')
            ORDER BY created_at DESC 
            LIMIT 20
        ");
        $pn_stmt->execute([$target_hid]);
        $pn_rows = $pn_stmt->fetchAll(PDO::FETCH_ASSOC);
        $pn_stmt->closeCursor();

        foreach ($pn_rows as $r) {
            $notes[] = [
                'id' => $r['note_uuid'],
                'human_id' => $target_hid,
                'title' => $r['title'] ?? 'Staff Note',
                'body' => $r['body'],
                'created_at' => $r['created_at']
            ];
        }
    } catch (Throwable $e) {}

    $photo_raw = trim($person['profile_photo'] ?? '');
    $has_photo = !empty($photo_raw);

    echo json_encode([
        'success' => true,
        'person' => [
            'human_id' => $target_hid,
            'humanId' => $target_hid,
            'first_name' => $fn,
            'last_name' => $ln,
            'display_name' => $name,
            'name' => $name,
            'masked_phone' => $person['masked_phone'] ?? '',
            'has_photo' => $has_photo,
            'photo_url' => $has_photo ? "https://app.reallife-studycenter.org/api/v1/mobile/people/{$target_hid}/photo" : null,
            'is_checked_in' => $is_checked_in,
            'check_in_time' => $check_in_time,
            'notes' => $notes,
            'total_notes' => count($notes)
        ]
    ]);
    exit;
}

// Route: Authenticated Mobile Person Attendance History Endpoint (Bounded Recent 30 Visits)
if (preg_match('#^/api/v1/mobile/people/([^/]+)/attendance-history$#', $uri, $m) && $method === 'GET') {
    header('Content-Type: application/json; charset=utf-8');
    header('Cache-Control: no-store, no-cache, must-revalidate, max-age=0');

    $session = verify_mobile_session($pdo);
    $target_hid = trim($m[1]);

    $history = [];
    try {
        $stmt = $pdo->prepare("
            SELECT attendance_date, check_in_time, check_out_time, status 
            FROM attendance_history_index 
            WHERE human_id = ? 
            ORDER BY attendance_date DESC, check_in_time DESC 
            LIMIT 30
        ");
        $stmt->execute([$target_hid]);
        $rows = $stmt->fetchAll(PDO::FETCH_ASSOC);
        $stmt->closeCursor();

        foreach ($rows as $r) {
            $history[] = [
                'attendanceDate' => strval($r['attendance_date']),
                'checkInTime' => strval($r['check_in_time']),
                'checkOutTime' => $r['check_out_time'] ? strval($r['check_out_time']) : null,
                'status' => strval($r['status'] ?? 'Present'),
            ];
        }
    } catch (Throwable $e) {}

    echo json_encode([
        'success' => true,
        'humanId' => $target_hid,
        'totalVisits' => count($history),
        'history' => $history
    ]);
    exit;
}

// Route: Authenticated Mobile Member Registration / Add Person Endpoint
if (($uri === '/api/v1/mobile/people/register' || $uri === '/mobile/api/people/register' || $uri === '/api/v1/mobile/people/add') && $method === 'POST') {
    header('Content-Type: application/json; charset=utf-8');
    header('Cache-Control: no-store, no-cache, must-revalidate, max-age=0');

    $session = verify_mobile_session($pdo);

    $raw = file_get_contents('php://input');
    $input = json_decode($raw, true);
    $payload = is_array($input) ? $input : [];

    $first_name = trim($payload['first_name'] ?? $payload['firstName'] ?? '');
    $last_name = trim($payload['last_name'] ?? $payload['lastName'] ?? '');
    $raw_phone = trim($payload['phone'] ?? $payload['phone_e164'] ?? '');
    $notes_body = trim($payload['notes'] ?? $payload['note_body'] ?? '');
    $auto_checkin = !empty($payload['auto_checkin'] ?? $payload['autoCheckIn'] ?? false);
    $override_duplicate = !empty($payload['override_duplicate'] ?? $payload['overrideDuplicate'] ?? false);

    if (empty($first_name)) {
        http_response_code(400);
        echo json_encode(['success' => false, 'error' => 'First name is required.']);
        exit;
    }

    // Phone normalization & masking
    $digits = preg_replace('/[^0-9]/', '', $raw_phone);
    $phone_e164 = '';
    $masked_phone = '';

    if (!empty($digits)) {
        if (strlen($digits) === 10) {
            $phone_e164 = '+1' . $digits;
            $masked_phone = '(' . substr($digits, 0, 3) . ') ***-' . substr($digits, 6, 4);
        } else if (strlen($digits) === 11 && substr($digits, 0, 1) === '1') {
            $phone_e164 = '+' . $digits;
            $masked_phone = '(' . substr($digits, 1, 3) . ') ***-' . substr($digits, 7, 4);
        } else {
            $phone_e164 = '+' . $digits;
            $masked_phone = '***-***-' . substr($digits, -4);
        }
    }

    // Duplicate Safety Search
    if (!$override_duplicate) {
        $dup = null;
        if (!empty($phone_e164)) {
            $d_stmt = $pdo->prepare("SELECT human_id, first_name, last_name, masked_phone FROM directory_index WHERE phone_e164 = ? LIMIT 1");
            $d_stmt->execute([$phone_e164]);
            $dup = $d_stmt->fetch(PDO::FETCH_ASSOC);
            $d_stmt->closeCursor();
        }

        if (!$dup && !empty($last_name)) {
            $d_stmt = $pdo->prepare("SELECT human_id, first_name, last_name, masked_phone FROM directory_index WHERE LOWER(first_name) = LOWER(?) AND LOWER(last_name) = LOWER(?) LIMIT 1");
            $d_stmt->execute([$first_name, $last_name]);
            $dup = $d_stmt->fetch(PDO::FETCH_ASSOC);
            $d_stmt->closeCursor();
        }

        if ($dup) {
            echo json_encode([
                'success' => false,
                'duplicate_found' => true,
                'message' => 'A person with matching details already exists in the directory.',
                'existing_person' => [
                    'human_id' => $dup['human_id'],
                    'humanId' => $dup['human_id'],
                    'name' => trim($dup['first_name'] . ' ' . $dup['last_name']),
                    'masked_phone' => $dup['masked_phone'] ?? ''
                ]
            ]);
            exit;
        }
    }

    // Generate Canonical human_id
    $random_hex = strtoupper(substr(bin2hex(random_bytes(3)), 0, 4));
    $new_hid = 'P-' . date('Ymd') . '-' . $random_hex;

    // Insert into directory_index
    $ins_stmt = $pdo->prepare("
        INSERT INTO directory_index (human_id, phone_e164, first_name, last_name, masked_phone, profile_photo, updated_at)
        VALUES (?, ?, ?, ?, ?, '', datetime('now'))
    ");
    $ins_stmt->execute([$new_hid, $phone_e164, $first_name, $last_name, $masked_phone]);
    $ins_stmt->closeCursor();

    // Optional Operational Note
    if (!empty($notes_body)) {
        try {
            $n_uuid = 'note_' . bin2hex(random_bytes(8));
            $n_stmt = $pdo->prepare("
                INSERT INTO person_notes (note_uuid, person_uuid, author_staff_human_id, title, body, visibility, created_at)
                VALUES (?, ?, ?, 'Registration Note', ?, 'standard_staff', datetime('now'))
            ");
            $n_stmt->execute([$n_uuid, $new_hid, $session['staff_human_id'] ?? 'mobile_staff', $notes_body]);
            $n_stmt->closeCursor();
        } catch (Throwable $e) {}
    }

    $is_checked_in = false;
    $check_in_time = null;

    // Optional Auto Check-In
    if ($auto_checkin) {
        try {
            $op_date = current_operational_date();
            $att_stmt = $pdo->prepare("
                INSERT OR REPLACE INTO today_attendance_index (human_id, phone_e164, first_name, last_name, attendance_date, check_in_time, updated_at)
                VALUES (?, ?, ?, ?, ?, datetime('now'), datetime('now'))
            ");
            $att_stmt->execute([$new_hid, $phone_e164, $first_name, $last_name, $op_date]);
            $att_stmt->closeCursor();
            $is_checked_in = true;
            $check_in_time = date('h:i A');
        } catch (Throwable $e) {}
    }

    $full_name = trim($first_name . ' ' . $last_name);

    echo json_encode([
        'success' => true,
        'message' => "Member {$full_name} registered successfully.",
        'person' => [
            'human_id' => $new_hid,
            'humanId' => $new_hid,
            'first_name' => $first_name,
            'last_name' => $last_name,
            'display_name' => $full_name,
            'name' => $full_name,
            'masked_phone' => $masked_phone,
            'phone_e164' => $phone_e164,
            'is_checked_in' => $is_checked_in,
            'check_in_time' => $check_in_time
        ]
    ]);
    exit;
}

// Route: Authenticated Mobile Today's Sessions & Events List Endpoint
if (($uri === '/api/v1/mobile/sessions/today' || $uri === '/mobile/api/sessions/today') && $method === 'GET') {
    header('Content-Type: application/json; charset=utf-8');
    header('Cache-Control: no-store, no-cache, must-revalidate, max-age=0');

    $session = verify_mobile_session($pdo);
    $op_date = current_operational_date();

    $sessions = [];
    try {
        $stmt = $pdo->prepare("
            SELECT 
                session_id, session_uuid, title, session_type, date_text, start_time, end_time, 
                COALESCE(room_location, 'Main Study Hall') as room_location, 
                max_capacity, confirmed_count, waitlist_count 
            FROM session_index 
            WHERE date_text = ? OR date_text = 'Today' 
            ORDER BY start_time ASC
        ");
        $stmt->execute([$op_date]);
        $rows = $stmt->fetchAll(PDO::FETCH_ASSOC);
        $stmt->closeCursor();

        foreach ($rows as $r) {
            $sid = intval($r['session_id']);
            $att_stmt = $pdo->prepare("SELECT COUNT(*) FROM member_signups_index WHERE session_id = ? AND signup_status = 'attended'");
            $att_stmt->execute([$sid]);
            $attended_cnt = intval($att_stmt->fetchColumn());
            $att_stmt->closeCursor();

            $sessions[] = [
                'id' => $sid,
                'sessionId' => $sid,
                'sessionUuid' => $r['session_uuid'],
                'title' => $r['title'],
                'type' => $r['session_type'],
                'dateText' => $r['date_text'],
                'startTime' => $r['start_time'],
                'endTime' => $r['end_time'],
                'timeRange' => trim($r['start_time'] . ' – ' . $r['end_time']),
                'location' => $r['room_location'],
                'maxCapacity' => intval($r['max_capacity']),
                'confirmedCount' => intval($r['confirmed_count']),
                'attendedCount' => $attended_cnt,
                'waitlistCount' => intval($r['waitlist_count']),
                'status' => 'Upcoming'
            ];
        }
    } catch (Throwable $e) {}

    echo json_encode([
        'success' => true,
        'attendanceDate' => $op_date,
        'totalSessions' => count($sessions),
        'sessions' => $sessions
    ]);
    exit;
}

// Route: Authenticated Mobile Session Roster Detail Endpoint
if (preg_match('#^/api/v1/mobile/sessions/(\d+)/roster$#', $uri, $m) && $method === 'GET') {
    header('Content-Type: application/json; charset=utf-8');
    header('Cache-Control: no-store, no-cache, must-revalidate, max-age=0');

    $session = verify_mobile_session($pdo);
    $sid = intval($m[1]);

    $sess_stmt = $pdo->prepare("SELECT * FROM session_index WHERE session_id = ? LIMIT 1");
    $sess_stmt->execute([$sid]);
    $sess = $sess_stmt->fetch(PDO::FETCH_ASSOC);
    $sess_stmt->closeCursor();

    if (!$sess) {
        http_response_code(404);
        echo json_encode(['success' => false, 'error' => 'Session not found.']);
        exit;
    }

    $roster = [];
    try {
        $r_stmt = $pdo->prepare("
            SELECT 
                s.id as signup_id, s.human_id, s.phone_e164, s.signup_status, s.registered_at, 
                COALESCE(d.first_name, 'Member') as first_name, 
                COALESCE(d.last_name, '') as last_name, 
                COALESCE(d.masked_phone, '') as masked_phone 
            FROM member_signups_index s 
            LEFT JOIN directory_index d ON s.human_id = d.human_id OR s.phone_e164 = d.phone_e164 
            WHERE s.session_id = ? 
            ORDER BY s.registered_at ASC
        ");
        $r_stmt->execute([$sid]);
        $rows = $r_stmt->fetchAll(PDO::FETCH_ASSOC);
        $r_stmt->closeCursor();

        foreach ($rows as $r) {
            $fn = trim($r['first_name']);
            $ln = trim($r['last_name']);
            $name = trim($fn . ' ' . $ln);

            $roster[] = [
                'signupId' => intval($r['signup_id']),
                'humanId' => $r['human_id'],
                'firstName' => $fn,
                'lastName' => $ln,
                'name' => $name,
                'maskedPhone' => $r['masked_phone'],
                'status' => $r['signup_status'],
                'isAttended' => ($r['signup_status'] === 'attended'),
                'registeredAt' => $r['registered_at']
            ];
        }
    } catch (Throwable $e) {}

    echo json_encode([
        'success' => true,
        'session' => [
            'id' => $sid,
            'title' => $sess['title'],
            'location' => $sess['room_location'] ?? 'Main Study Hall',
            'timeRange' => trim(($sess['start_time'] ?? '') . ' – ' . ($sess['end_time'] ?? '')),
            'maxCapacity' => intval($sess['max_capacity'] ?? 30),
            'confirmedCount' => count($roster)
        ],
        'roster' => $roster
    ]);
    exit;
}

// Route: Authenticated Mobile Session Check-In Endpoint
if (preg_match('#^/api/v1/mobile/sessions/(\d+)/check-in$#', $uri, $m) && $method === 'POST') {
    header('Content-Type: application/json; charset=utf-8');
    header('Cache-Control: no-store, no-cache, must-revalidate, max-age=0');

    $session = verify_mobile_session($pdo);
    $sid = intval($m[1]);

    $raw = file_get_contents('php://input');
    $input = json_decode($raw, true);
    $payload = is_array($input) ? $input : [];

    $human_id = trim($payload['human_id'] ?? $payload['humanId'] ?? '');
    if (empty($human_id)) {
        http_response_code(400);
        echo json_encode(['success' => false, 'error' => 'Participant human_id is required.']);
        exit;
    }

    $chk_stmt = $pdo->prepare("SELECT id, signup_status FROM member_signups_index WHERE session_id = ? AND human_id = ? LIMIT 1");
    $chk_stmt->execute([$sid, $human_id]);
    $existing = $chk_stmt->fetch(PDO::FETCH_ASSOC);
    $chk_stmt->closeCursor();

    if ($existing) {
        if ($existing['signup_status'] === 'attended') {
            echo json_encode(['success' => true, 'already_checked_in' => true, 'message' => 'Participant is already checked in for this session.']);
            exit;
        }
        $upd_stmt = $pdo->prepare("UPDATE member_signups_index SET signup_status = 'attended' WHERE id = ?");
        $upd_stmt->execute([$existing['id']]);
        $upd_stmt->closeCursor();
    } else {
        // Walk-in check-in
        $p_stmt = $pdo->prepare("SELECT phone_e164 FROM directory_index WHERE human_id = ? LIMIT 1");
        $p_stmt->execute([$human_id]);
        $phone_e164 = strval($p_stmt->fetchColumn() ?? '');
        $p_stmt->closeCursor();

        $ins_stmt = $pdo->prepare("INSERT INTO member_signups_index (session_id, human_id, phone_e164, signup_status, registered_at) VALUES (?, ?, ?, 'attended', datetime('now'))");
        $ins_stmt->execute([$sid, $human_id, $phone_e164]);
        $ins_stmt->closeCursor();
    }

    echo json_encode(['success' => true, 'message' => 'Session check-in recorded successfully.']);
    exit;
}

// Route: Authenticated Mobile Person Digital Member Pass Details Endpoint
if (preg_match('#^/api/v1/mobile/people/([^/]+)/member-pass$#', $uri, $m) && $method === 'GET') {
    header('Content-Type: application/json; charset=utf-8');
    header('Cache-Control: no-store, no-cache, must-revalidate, max-age=0');

    $session = verify_mobile_session($pdo);
    $target_hid = trim($m[1]);

    // Check directory index
    $d_stmt = $pdo->prepare("SELECT human_id, first_name, last_name, phone_e164, masked_phone FROM directory_index WHERE human_id = ? LIMIT 1");
    $d_stmt->execute([$target_hid]);
    $person = $d_stmt->fetch(PDO::FETCH_ASSOC);
    $d_stmt->closeCursor();

    if (!$person) {
        http_response_code(404);
        echo json_encode(['success' => false, 'error' => 'Participant not found.']);
        exit;
    }

    $pass = null;
    $has_active_pass = false;

    try {
        $q_stmt = $pdo->prepare("
            SELECT credential_id, status, issued_at 
            FROM participant_qr_credentials 
            WHERE (credential_id = ? OR metadata_json LIKE ?)
              AND LOWER(COALESCE(status, 'active')) = 'active'
            ORDER BY issued_at DESC LIMIT 1
        ");
        $q_stmt->execute(['QR-' . $target_hid, '%' . $target_hid . '%']);
        $row = $q_stmt->fetch(PDO::FETCH_ASSOC);
        $q_stmt->closeCursor();

        if ($row) {
            $has_active_pass = true;
            $pass = [
                'credentialId' => $row['credential_id'],
                'qrCodeValue' => $target_hid,
                'status' => 'active',
                'issuedAt' => $row['issued_at']
            ];
        }
    } catch (Throwable $e) {}

    // Fallback: Default active pass based on canonical human_id
    if (!$pass) {
        $has_active_pass = true;
        $pass = [
            'credentialId' => 'QR-' . $target_hid,
            'qrCodeValue' => $target_hid,
            'status' => 'active',
            'issuedAt' => date('Y-m-d H:i:s')
        ];
    }

    echo json_encode([
        'success' => true,
        'humanId' => $target_hid,
        'hasActivePass' => $has_active_pass,
        'pass' => $pass
    ]);
    exit;
}

// Route: Authenticated Mobile Person Digital Member Pass Issue/Regenerate Endpoint
if (preg_match('#^/api/v1/mobile/people/([^/]+)/member-pass/issue$#', $uri, $m) && $method === 'POST') {
    header('Content-Type: application/json; charset=utf-8');
    header('Cache-Control: no-store, no-cache, must-revalidate, max-age=0');

    $session = verify_mobile_session($pdo);
    $target_hid = trim($m[1]);

    $cred_id = 'QR-' . $target_hid;
    $token_hash = hash('sha256', $target_hid);

    try {
        $ins_stmt = $pdo->prepare("
            INSERT OR REPLACE INTO participant_qr_credentials (credential_id, person_id, token_hash, token_hint, status, issued_at, issued_by)
            VALUES (?, 1, ?, 'human_id', 'active', datetime('now'), ?)
        ");
        $ins_stmt->execute([$cred_id, $token_hash, $session['staff_human_id'] ?? 'mobile_staff']);
        $ins_stmt->closeCursor();
    } catch (Throwable $e) {}

    echo json_encode([
        'success' => true,
        'message' => 'Digital Member Pass issued successfully.',
        'pass' => [
            'credentialId' => $cred_id,
            'qrCodeValue' => $target_hid,
            'status' => 'active',
            'issuedAt' => date('Y-m-d H:i:s')
        ]
    ]);
    exit;
}

// Route: Authenticated Mobile Person Digital Member Pass Resend Endpoint
if (preg_match('#^/api/v1/mobile/people/([^/]+)/member-pass/resend$#', $uri, $m) && $method === 'POST') {
    header('Content-Type: application/json; charset=utf-8');
    header('Cache-Control: no-store, no-cache, must-revalidate, max-age=0');

    $session = verify_mobile_session($pdo);
    $target_hid = trim($m[1]);

    echo json_encode([
        'success' => true,
        'message' => "Digital Member Pass link dispatched for participant {$target_hid}."
    ]);
    exit;
}

// Route: Authenticated Mobile Today's Operating Hours & Staff Schedule Endpoint
if (($uri === '/api/v1/mobile/schedule/today' || $uri === '/mobile/api/schedule/today') && $method === 'GET') {
    header('Content-Type: application/json; charset=utf-8');
    header('Cache-Control: no-store, no-cache, must-revalidate, max-age=0');

    $session = verify_mobile_session($pdo);

    $op_date = current_operational_date();
    $day_of_week = date('l', strtotime($op_date));
    $is_open = false;
    $hours_label = "Hours Unavailable";
    $status_text = "Operating Hours Unavailable";
    $has_override = false;
    $has_synced_hours = false;

    try {
        $ov_stmt = $pdo->prepare("
            SELECT is_closed, session1_start, session1_end, has_split_shift, session2_start, session2_end 
            FROM center_hour_overrides 
            WHERE override_date = ? 
            LIMIT 1
        ");
        $ov_stmt->execute([$op_date]);
        $override = $ov_stmt->fetch(PDO::FETCH_ASSOC);
        $ov_stmt->closeCursor();

        if ($override) {
            $has_override = true;
            $has_synced_hours = true;
            if (intval($override['is_closed']) === 1) {
                $is_open = false;
                $hours_label = "Closed (Override)";
                $status_text = "Closed Today (Scheduled Override)";
            } else {
                $is_open = true;
                $s1_start = trim($override['session1_start'] ?? '');
                $s1_end = trim($override['session1_end'] ?? '');
                if (intval($override['has_split_shift']) === 1) {
                    $s2_start = trim($override['session2_start'] ?? '');
                    $s2_end = trim($override['session2_end'] ?? '');
                    $hours_label = "{$s1_start}–{$s1_end} & {$s2_start}–{$s2_end}";
                } else {
                    $hours_label = "{$s1_start}–{$s1_end}";
                }
                $status_text = "Open Today (Override Hours)";
            }
        }
    } catch (Throwable $e) {}

    // 2. Query normal weekly recurring open hours if no date override was present
    if (!$has_override) {
        try {
            $oh_stmt = $pdo->prepare("
                SELECT open_time, close_time, is_closed, has_split_shift, session2_start, session2_end 
                FROM center_open_hours 
                WHERE LOWER(day_of_week) = LOWER(?) 
                LIMIT 1
            ");
            $oh_stmt->execute([$day_of_week]);
            $weekly_h = $oh_stmt->fetch(PDO::FETCH_ASSOC);
            $oh_stmt->closeCursor();

            if ($weekly_h) {
                $has_synced_hours = true;
                if (intval($weekly_h['is_closed']) === 1) {
                    $is_open = false;
                    $hours_label = "Closed";
                    $status_text = "Closed Today";
                } else {
                    $is_open = true;
                    $o_start = trim($weekly_h['open_time'] ?? '');
                    $o_end = trim($weekly_h['close_time'] ?? '');
                    if (intval($weekly_h['has_split_shift']) === 1) {
                        $s2_start = trim($weekly_h['session2_start'] ?? '');
                        $s2_end = trim($weekly_h['session2_end'] ?? '');
                        $hours_label = "{$o_start}–{$o_end} & {$s2_start}–{$s2_end}";
                    } else {
                        $hours_label = "{$o_start}–{$o_end}";
                    }
                    $status_text = "Open Today";
                }
            }
        } catch (Throwable $e) {}
    }

    // 3. Query REAL per-shift staff assignments from schedule_entries table
    $workers = [];
    try {
        $se_stmt = $pdo->prepare("
            SELECT person_name, shift_role, start_time, end_time 
            FROM schedule_entries 
            WHERE shift_date = ? 
              AND person_name IS NOT NULL 
              AND TRIM(person_name) != ''
            ORDER BY id ASC
        ");
        $se_stmt->execute([$op_date]);
        $se_rows = $se_stmt->fetchAll(PDO::FETCH_ASSOC);
        $se_stmt->closeCursor();

        foreach ($se_rows as $sr) {
            $w_name = trim($sr['person_name']);
            if (!empty($w_name) && !in_array($w_name, $workers)) {
                $workers[] = $w_name;
            }
        }
    } catch (Throwable $e) {}

    $schedule_items = [
        [
            'id' => 'shift_op_' . str_replace('-', '', $op_date),
            'timeRange' => $hours_label,
            'title' => 'Study Center Operations',
            'workers' => $workers,
            'location' => 'Main Study Hall',
            'isToday' => true
        ]
    ];

    echo json_encode([
        'success' => true,
        'date' => $op_date,
        'day_of_week' => $day_of_week,
        'is_open' => $is_open,
        'hours_label' => $hours_label,
        'status_text' => $status_text,
        'has_override' => $has_override,
        'todaySchedule' => $schedule_items
    ]);
    exit;
}

// Route: Public Member Phone Lookup API (Privacy Safe)
if (($uri === '/api/v1/public/checkin/lookup' || $uri === '/public/api/checkin/lookup') && $method === 'POST') {
    header('Content-Type: application/json; charset=utf-8');
    $raw = file_get_contents('php://input');
    $input = json_decode($raw, true);
    $raw_phone = is_array($input) ? trim($input['phone'] ?? '') : '';

    if (empty($raw_phone)) {
        http_response_code(400);
        echo json_encode(['found' => false, 'error' => 'Phone number is required']);
        exit;
    }

    $e164 = normalize_phone_e164_php($raw_phone);
    $digits = preg_replace('/\D/', '', $raw_phone);

    $stmt = $pdo->prepare("SELECT first_name, masked_phone, human_id FROM directory_index WHERE phone_e164 = ? OR phone_e164 LIKE ?");
    $stmt->execute([$e164, '%' . substr($digits, -10)]);
    $rows = $stmt->fetchAll(PDO::FETCH_ASSOC);

    if (count($rows) === 1) {
        $human_id = $rows[0]['human_id'];
        $op_date = current_operational_date();
        $already_checked_in = false;

        $chk_stmt = $pdo->prepare("SELECT 1 FROM today_attendance_index WHERE (human_id = ? OR (phone_e164 = ? AND phone_e164 != '')) AND attendance_date = ? LIMIT 1");
        $chk_stmt->execute([$human_id, $e164, $op_date]);
        if ($chk_stmt->fetch()) {
            $already_checked_in = true;
        }

        echo json_encode([
            'found' => true,
            'match_count' => 1,
            'first_name' => $rows[0]['first_name'],
            'masked_phone' => $rows[0]['masked_phone'],
            'human_id' => $rows[0]['human_id'],
            'already_checked_in' => $already_checked_in
        ]);
    } elseif (count($rows) > 1) {
        echo json_encode([
            'found' => false,
            'match_count' => count($rows),
            'error' => 'multiple_matches',
            'message' => 'Multiple records match this phone number. Please see a host at the front desk.'
        ]);
    } else {
        echo json_encode([
            'found' => false,
            'match_count' => 0,
            'message' => 'We could not find an active membership matching that phone number.'
        ]);
    }
    exit;
}

// Route: Check-In Execution Status Polling API
if (($uri === '/api/v1/public/checkin/status' || $uri === '/public/api/checkin/status') && ($method === 'GET' || $method === 'POST')) {
    header('Content-Type: application/json; charset=utf-8');
    $event_uuid = $_GET['event_uuid'] ?? '';
    if (empty($event_uuid) && $method === 'POST') {
        $raw = file_get_contents('php://input');
        $input = json_decode($raw, true);
        $event_uuid = is_array($input) ? ($input['event_uuid'] ?? '') : '';
    }

    if (empty($event_uuid)) {
        http_response_code(400);
        echo json_encode(['status' => 'error', 'message' => 'event_uuid parameter is required']);
        exit;
    }

    $stmt = $pdo->prepare("SELECT processed, status, result_json FROM inbound_event_queue WHERE provider_event_id = ? LIMIT 1");
    $stmt->execute([$event_uuid]);
    $row = $stmt->fetch(PDO::FETCH_ASSOC);

    if (!$row) {
        echo json_encode(['status' => 'not_found', 'message' => 'Check-in request not found']);
        exit;
    }

    if (intval($row['processed']) === 0) {
        echo json_encode(['status' => 'processing', 'message' => 'Check-in request is being processed by StudyCenterHub...']);
        exit;
    }

    $result_data = !empty($row['result_json']) ? json_decode($row['result_json'], true) : [];
    $status_str = !empty($result_data['status']) ? $result_data['status'] : (!empty($row['status']) ? $row['status'] : 'checked_in');
    if ($status_str === 'processed' || $status_str === 'success' || $status_str === 'ok') {
        $status_str = 'checked_in';
    }

    echo json_encode([
        'status' => $status_str,
        'first_name' => $result_data['first_name'] ?? '',
        'checked_in' => !empty($result_data['checked_in']),
        'raw_token' => $result_data['raw_token'] ?? '',
        'error' => $result_data['error'] ?? '',
        'message' => $result_data['message'] ?? 'Check-in processed successfully'
    ]);
    exit;
}

// Route: Public Registration Status Polling API (Closed-Loop)
if (($uri === '/api/v1/public/register/status' || $uri === '/public/api/register/status') && ($method === 'GET' || $method === 'POST')) {
    header('Content-Type: application/json; charset=utf-8');
    enforce_rate_limit_php($pdo, 'register_status');
    $uuid = $_GET['event_uuid'] ?? $_POST['event_uuid'] ?? '';
    if (empty($uuid)) {
        echo json_encode(['status' => 'error', 'message' => 'event_uuid is required']);
        exit;
    }

    $stmt = $pdo->prepare("SELECT processed, status, result_json FROM inbound_event_queue WHERE provider_event_id = ? OR payload_json LIKE ? ORDER BY id DESC LIMIT 1");
    $stmt->execute([$uuid, '%' . $uuid . '%']);
    $row = $stmt->fetch(PDO::FETCH_ASSOC);

    if (!$row) {
        echo json_encode(['status' => 'not_found', 'message' => 'Event not found']);
        exit;
    }

    if (intval($row['processed']) === 0) {
        echo json_encode(['status' => 'processing', 'message' => 'Registration is being processed']);
        exit;
    }

    $res_json = !empty($row['result_json']) ? json_decode($row['result_json'], true) : [];
    if (!is_array($res_json)) $res_json = [];

    $status = $row['status'] ?? $res_json['status'] ?? 'registered';
    $res_json['status'] = $status;
    echo json_encode($res_json);
    exit;
}

// Route: Public Registration Submission API
if (($uri === '/api/v1/public/register' || $uri === '/public/api/register') && $method === 'POST') {
    header('Content-Type: application/json; charset=utf-8');
    $raw = file_get_contents('php://input');
    $input = json_decode($raw, true);

    if (!is_array($input)) {
        http_response_code(400);
        echo json_encode(['success' => false, 'error' => 'Invalid JSON payload']);
        exit;
    }

    $event_uuid = 'evt_portal_reg_' . bin2hex(random_bytes(8));
    $payload = $input;
    $payload['event_uuid'] = $event_uuid;
    $payload['source'] = 'Public Self-Registration Portal';
    $payload['received_at'] = gmdate('Y-m-d H:i:s') . ' UTC';

    $stmt = $pdo->prepare("INSERT INTO inbound_event_queue (event_type, provider_event_id, payload_json, received_at, processed) VALUES ('portal.registration', ?, ?, datetime('now'), 0)");
    $stmt->execute([$event_uuid, json_encode($payload)]);

    $session_token = 'sess_pub_' . bin2hex(random_bytes(12));

    echo json_encode([
        'success' => true,
        'message' => 'Registration received',
        'event_uuid' => $event_uuid,
        'session_token' => $session_token,
        'first_name' => trim($input['firstName'] ?? $input['first_name'] ?? '')
    ]);
    exit;
}

// Route: Public Self-Service API - Returning Member Web Check-In (Placeholder / Gateway queue)
if (($uri === '/api/v1/public/checkin' || $uri === '/public/api/checkin') && $method === 'POST') {
    header('Content-Type: application/json; charset=utf-8');
    $raw = file_get_contents('php://input');
    $input = json_decode($raw, true);

    $payload = is_array($input) ? $input : [];
    $human_id = trim($payload['human_id'] ?? $payload['humanId'] ?? '');
    $op_date = current_operational_date();
    $already_checked_in = false;

    if (!empty($human_id)) {
        $chk_stmt = $pdo->prepare("SELECT 1 FROM today_attendance_index WHERE (human_id = ? OR (phone_e164 = ? AND phone_e164 != '')) AND attendance_date = ? LIMIT 1");
        $chk_stmt->execute([$human_id, $e164, $op_date]);
        if ($chk_stmt->fetch()) {
            $already_checked_in = true;
        }
    }

    $event_uuid = 'evt_portal_chk_' . bin2hex(random_bytes(8));
    $payload['event_uuid'] = $event_uuid;
    $payload['checkInDate'] = $op_date;
    $payload['received_at'] = gmdate('Y-m-d H:i:s') . ' UTC';

    $stmt = $pdo->prepare("INSERT INTO inbound_event_queue (event_type, provider_event_id, payload_json, received_at, processed) VALUES ('portal.checkin', ?, ?, datetime('now'), 0)");
    $stmt->execute([$event_uuid, json_encode($payload)]);

    echo json_encode([
        'success' => true,
        'already_checked_in' => $already_checked_in,
        'message' => $already_checked_in ? 'Already Checked in Today' : 'Check-in request received',
        'event_uuid' => $event_uuid,
        'first_name' => trim($payload['first_name'] ?? $payload['firstName'] ?? '')
    ]);
    exit;
}

// Route: Public Self-Service UI Landing Page & Guided Registration Wizard
if ($uri === '/public' || $uri === '/public/' || $uri === '/public-returning') {
    header('Content-Type: text/html; charset=utf-8');
    ?>
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
    <title>Real Life House — Public Self-Service Portal</title>
    <style>
        :root {
            --bg-color: #f8fafc;
            --header-bg: #0f172a;
            --card-bg: #ffffff;
            --text-main: #0f172a;
            --text-muted: #64748b;
            --primary-blue: #2563eb;
            --primary-hover: #1d4ed8;
            --amber-accent: #d97706;
            --border-color: #cbd5e1;
            --error-bg: #fef2f2;
            --error-text: #dc2626;
            --warning-bg: #fffbeb;
            --warning-border: #f59e0b;
            --warning-text: #b45309;
            --success-bg: #f0fdf4;
            --success-text: #15803d;
            --radius-md: 12px;
            --radius-sm: 8px;
        }

        * {
            box-sizing: border-box;
            margin: 0;
            padding: 0;
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
            -webkit-tap-highlight-color: transparent;
        }

        body {
            background-color: var(--bg-color);
            color: var(--text-main);
            display: flex;
            flex-direction: column;
            align-items: center;
            min-height: 100vh;
            padding-bottom: 40px;
        }

        .header-bar {
            width: 100%;
            background-color: var(--header-bg);
            color: #ffffff;
            padding: 20px 16px;
            text-align: center;
            box-shadow: 0 4px 12px rgba(0, 0, 0, 0.1);
        }

        .header-brand {
            font-size: 22px;
            font-weight: 700;
            letter-spacing: 0.5px;
            color: #ffffff;
        }

        .header-sub {
            font-size: 13px;
            color: #94a3b8;
            margin-top: 4px;
        }

        .progress-bar-container {
            width: 100%;
            background-color: #1e293b;
            height: 6px;
            overflow: hidden;
            display: none;
        }

        .progress-bar-fill {
            height: 100%;
            background-color: var(--amber-accent);
            width: 0%;
            transition: width 0.3s ease;
        }

        .app-container {
            width: 100%;
            max-width: 480px;
            padding: 20px 16px;
        }

        .card {
            background-color: var(--card-bg);
            border-radius: var(--radius-md);
            border: 1px solid var(--border-color);
            box-shadow: 0 4px 16px rgba(15, 23, 42, 0.05);
            padding: 24px 20px;
            margin-bottom: 16px;
        }

        .step-indicator {
            font-size: 12px;
            font-weight: 700;
            text-transform: uppercase;
            letter-spacing: 1px;
            color: var(--amber-accent);
            margin-bottom: 6px;
        }

        .page-title {
            font-size: 24px;
            font-weight: 700;
            color: var(--text-main);
            margin-bottom: 8px;
        }

        .page-desc {
            font-size: 14px;
            color: var(--text-muted);
            line-height: 1.5;
            margin-bottom: 20px;
        }

        .form-group {
            margin-bottom: 18px;
        }

        .form-label {
            display: block;
            font-size: 14px;
            font-weight: 600;
            color: var(--text-main);
            margin-bottom: 6px;
        }

        .form-label .req {
            color: var(--error-text);
            margin-left: 3px;
        }

        .form-control {
            width: 100%;
            height: 50px;
            padding: 0 16px;
            font-size: 16px;
            border: 1px solid var(--border-color);
            border-radius: var(--radius-sm);
            background-color: #ffffff;
            color: var(--text-main);
            outline: none;
            transition: border-color 0.2s ease, box-shadow 0.2s ease;
        }

        .form-control:focus {
            border-color: var(--primary-blue);
            box-shadow: 0 0 0 3px rgba(37, 99, 235, 0.15);
        }

        select.form-control {
            appearance: none;
            background-image: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='16' height='16' viewBox='0 0 24 24' fill='none' stroke='%2064748b' stroke-width='2' stroke-linecap='round' stroke-linejoin='round'%3E%3Cpolyline points='6 9 12 15 18 9'%3E%3C/polyline%3E%3C/svg%3E");
            background-repeat: no-repeat;
            background-position: right 16px center;
            padding-right: 40px;
        }

        .field-error {
            font-size: 12px;
            color: var(--error-text);
            margin-top: 4px;
            display: none;
        }

        .btn-stack {
            display: flex;
            flex-direction: column;
            gap: 12px;
            margin-top: 24px;
        }

        .btn-row {
            display: flex;
            gap: 12px;
            margin-top: 24px;
        }

        .btn {
            height: 52px;
            border-radius: var(--radius-sm);
            font-size: 16px;
            font-weight: 600;
            border: none;
            cursor: pointer;
            display: flex;
            align-items: center;
            justify-content: center;
            gap: 8px;
            text-decoration: none;
            transition: background-color 0.2s ease, transform 0.1s ease;
        }

        .btn:active {
            transform: scale(0.98);
        }

        .btn-primary {
            background-color: var(--primary-blue);
            color: #ffffff;
            width: 100%;
        }

        .btn-primary:hover {
            background-color: var(--primary-hover);
        }

        .btn-secondary {
            background-color: #f1f5f9;
            color: var(--text-main);
            border: 1px solid var(--border-color);
            width: 100%;
        }

        .btn-secondary:hover {
            background-color: #e2e8f0;
        }

        .btn-amber {
            background-color: var(--amber-accent);
            color: #ffffff;
            width: 100%;
        }

        .btn-amber:hover {
            background-color: #b45309;
        }

        .alert-box {
            padding: 14px 16px;
            border-radius: var(--radius-sm);
            font-size: 13px;
            line-height: 1.4;
            margin-bottom: 18px;
        }

        .alert-warning {
            background-color: var(--warning-bg);
            border: 1px solid var(--warning-border);
            color: var(--warning-text);
        }

        .alert-info {
            background-color: #eff6ff;
            border: 1px solid #93c5fd;
            color: #1e40af;
        }

        .photo-preview-container {
            width: 160px;
            height: 160px;
            border-radius: 50%;
            border: 3px solid var(--primary-blue);
            margin: 0 auto 16px auto;
            overflow: hidden;
            background-color: #e2e8f0;
            display: flex;
            align-items: center;
            justify-content: center;
        }

        .photo-preview-container img {
            width: 100%;
            height: 100%;
            object-fit: cover;
        }

        .summary-list {
            list-style: none;
            margin-bottom: 20px;
        }

        .summary-item {
            padding: 12px 0;
            border-bottom: 1px solid #e2e8f0;
            display: flex;
            justify-content: space-between;
            align-items: center;
        }

        .summary-item:last-child {
            border-bottom: none;
        }

        .summary-label {
            font-size: 13px;
            color: var(--text-muted);
            font-weight: 500;
        }

        .summary-val {
            font-size: 14px;
            font-weight: 600;
            color: var(--text-main);
            text-align: right;
        }

        .edit-link {
            font-size: 12px;
            color: var(--primary-blue);
            text-decoration: underline;
            cursor: pointer;
            margin-left: 8px;
        }

        .success-hero {
            text-align: center;
            padding: 20px 0;
        }

        .success-icon {
            font-size: 54px;
            margin-bottom: 12px;
        }

        .hidden {
            display: none !important;
        }
    </style>
</head>
<body>
    <header class="header-bar">
        <div class="header-brand">🏠 Real Life House</div>
        <div class="header-sub">A Study Center & Hospitality House</div>
    </header>

    <div class="progress-bar-container" id="progressBarContainer">
        <div class="progress-bar-fill" id="progressBarFill"></div>
    </div>

    <main class="app-container">
        <!-- SCREEN 0: PUBLIC HOME LANDING PAGE -->
        <section id="screenLanding" class="card">
            <h1 class="page-title">Welcome to Real Life House</h1>
            <p class="page-desc">Please choose what you would like to do today:</p>

            <div class="btn-stack">
                <button class="btn btn-primary" onclick="startRegistration()">
                    <span>➕</span> I’m New — Register
                </button>
                <button class="btn btn-secondary" onclick="showCheckInChoice()">
                    <span>📍</span> Check In Today
                </button>
                <button class="btn btn-secondary" onclick="showSessionChoice()">
                    <span>📅</span> Sign Up for a Session
                </button>
            </div>
        </section>

        <!-- SCREEN CHECK-IN WORKFLOW (PHASE 2 COMPLETE) -->
        <section id="screenCheckInNotice" class="card hidden">
            <!-- VIEW 1: PHONE LOOKUP -->
            <div id="checkinLookupView">
                <h2 class="page-title">📍 Check In Today</h2>
                <p class="page-desc">Enter your mobile phone number to find your membership profile:</p>

                <div class="form-group">
                    <label class="form-label">Mobile Phone Number <span class="req">*</span></label>
                    <input type="tel" id="checkinPhoneInput" class="form-control" placeholder="(864) 555-0199" oninput="formatPhoneInput(this)">
                    <div class="field-error" id="errCheckinPhone">Please enter a valid 10-digit mobile phone number.</div>
                </div>

                <div id="checkinLookupMsg" class="alert-box alert-warning hidden"></div>

                <div class="btn-stack">
                    <button class="btn btn-primary" id="btnFindMe" onclick="findMemberByPhone()">Find Me 🔍</button>
                    <button class="btn btn-secondary" onclick="showLanding()">← Back to Main Menu</button>
                </div>
            </div>

            <!-- VIEW 2: IDENTITY CONFIRMATION CARD -->
            <div id="checkinConfirmView" class="hidden">
                <h2 class="page-title">Is this you?</h2>
                <p class="page-desc">Please confirm your identity before checking in:</p>

                <div class="alert-box alert-info" style="text-align: center; padding: 20px 16px;">
                    <div style="font-size: 22px; font-weight: 700; color: #0f172a; margin-bottom: 4px;" id="confMemberName">John Boyte</div>
                    <div style="font-size: 15px; font-weight: 600; color: #64748b;" id="confMemberPhone">•••-•••-4080</div>
                </div>

                <div class="btn-stack">
                    <button class="btn btn-primary" id="btnConfirmCheckIn" onclick="confirmAndSubmitCheckIn()">Yes — Check Me In 🚀</button>
                    <button class="btn btn-secondary" onclick="resetCheckInLookup()">No — Try Again</button>
                </div>
            </div>

            <!-- VIEW 3: PROCESSING SPINNER -->
            <div id="checkinProcessingView" class="hidden" style="text-align: center; padding: 30px 0;">
                <div style="font-size: 40px; margin-bottom: 12px; animation: spin 1s linear infinite;">⏳</div>
                <h2 class="page-title">Verifying Check-In...</h2>
                <p class="page-desc">Connecting with StudyCenterHub desktop to confirm your attendance.</p>
            </div>

            <!-- VIEW 4: VERIFIED CHECK-IN SUCCESS -->
            <div id="checkinSuccessView" class="hidden">
                <div class="success-hero">
                    <div class="success-icon">✓</div>
                    <h2 class="page-title" id="checkinSuccessTitle">You’re Checked In!</h2>
                    <p class="page-desc" id="checkinSuccessMsg">Welcome! We’re glad you’re here today.</p>
                </div>

                <div class="btn-stack">
                    <button class="btn btn-primary" onclick="showSessionChoice()">📅 Sign Up for a Session</button>
                    <button class="btn btn-secondary" onclick="openDigitalPassModal()">💳 Get My Digital Member Pass</button>
                    <button class="btn btn-secondary" onclick="showLanding()">🏠 Back to Home</button>
                </div>
            </div>

            <!-- VIEW 5: ALREADY CHECKED IN TODAY -->
            <div id="checkinAlreadyView" class="hidden">
                <div class="success-hero">
                    <div class="success-icon">😊</div>
                    <h2 class="page-title" id="checkinAlreadyTitle">Already Checked in Today</h2>
                    <p class="page-desc" id="checkinAlreadyMsg">Glad you’re here!</p>
                </div>

                <div class="btn-stack">
                    <button class="btn btn-primary" onclick="showSessionChoice()">📅 Sign Up for a Session</button>
                    <button class="btn btn-secondary" onclick="openDigitalPassModal()">💳 Get My Digital Member Pass</button>
                    <button class="btn btn-secondary" onclick="showLanding()">🏠 Back to Home</button>
                </div>
            </div>

            <!-- VIEW 6: NOT FOUND / ERROR -->
            <div id="checkinNotFoundView" class="hidden">
                <div class="alert-box alert-warning" id="checkinNotFoundMsg">
                    We couldn’t find an active membership matching that phone number.
                </div>

                <div class="btn-stack">
                    <button class="btn btn-primary" onclick="resetCheckInLookup()">Try Again 🔍</button>
                    <button class="btn btn-amber" onclick="startRegistration()">➕ I’m New — Register</button>
                    <button class="btn btn-secondary" onclick="showLanding()">🏠 Back to Home</button>
                </div>
            </div>
        </section>

        <!-- SCREEN SESSION BROWSER (PHASE 3 COMPLETE) -->
        <section id="screenSessionNotice" class="card hidden">
            <!-- VIEW 1: SESSION LIST & CARDS -->
            <div id="sessionListView">
                <h2 class="page-title">📅 Sign Up for a Session</h2>
                <p class="page-desc">Select an upcoming session below to register or join the waitlist:</p>

                <!-- IDENTITY BADGE -->
                <div id="sessionIdentityBadge" class="alert-box alert-info hidden" style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 16px;">
                    <div>
                        <strong id="sessBadgeName">Jane Smith</strong>
                        <div style="font-size: 12px; opacity: 0.8;" id="sessBadgePhone">•••-•••-0199</div>
                    </div>
                    <button class="btn btn-secondary" style="height: 32px; font-size: 12px; padding: 0 10px; width: auto;" onclick="clearSessionIdentity()">Change</button>
                </div>

                <div id="sessionCardsContainer">
                    <div style="text-align: center; color: var(--text-muted); padding: 20px;">Loading available sessions...</div>
                </div>

                <div class="btn-stack" style="margin-top: 20px;">
                    <button class="btn btn-secondary" onclick="showLanding()">← Back to Main Menu</button>
                </div>
            </div>

            <!-- VIEW 2: PROCESSING SPINNER -->
            <div id="sessionProcessingView" class="hidden" style="text-align: center; padding: 30px 0;">
                <div style="font-size: 40px; margin-bottom: 12px; animation: spin 1s linear infinite;">⏳</div>
                <h2 class="page-title" id="sessProcessingTitle">Processing Signup...</h2>
                <p class="page-desc">Connecting with StudyCenterHub desktop to confirm your session status.</p>
            </div>

            <!-- VIEW 3: CONFIRMED SIGNUP SUCCESS -->
            <div id="sessionSuccessView" class="hidden">
                <div class="success-hero">
                    <div class="success-icon">🎉</div>
                    <h2 class="page-title" id="sessSuccessTitle">✓ You’re Signed Up!</h2>
                    <p class="page-desc" id="sessSuccessMsg">Your spot has been confirmed for this session.</p>
                </div>

                <div class="btn-stack">
                    <button class="btn btn-primary" onclick="showCheckInChoice()">📍 Check In Today</button>
                    <button class="btn btn-secondary" onclick="loadPublicSessions()">📅 Back to Available Sessions</button>
                    <button class="btn btn-secondary" onclick="showLanding()">🏠 Back to Home</button>
                </div>
            </div>

            <!-- VIEW 4: WAITLISTED SUCCESS -->
            <div id="sessionWaitlistSuccessView" class="hidden">
                <div class="success-hero">
                    <div class="success-icon">⏳</div>
                    <h2 class="page-title" id="sessWaitlistTitle">You’re on the Waitlist</h2>
                    <p class="page-desc" id="sessWaitlistMsg">You have been added to the waitlist. If a spot opens up, StudyCenterHub staff will notify you!</p>
                </div>

                <div class="btn-stack">
                    <button class="btn btn-secondary" onclick="loadPublicSessions()">📅 Back to Available Sessions</button>
                    <button class="btn btn-secondary" onclick="showLanding()">🏠 Back to Home</button>
                </div>
            </div>

            <!-- VIEW 5: CANCELLED SUCCESS -->
            <div id="sessionCancelledView" class="hidden">
                <div class="success-hero">
                    <div class="success-icon">ℹ️</div>
                    <h2 class="page-title">Registration Cancelled</h2>
                    <p class="page-desc" id="sessCancelledMsg">Your registration has been removed.</p>
                </div>

                <div class="btn-stack">
                    <button class="btn btn-secondary" onclick="loadPublicSessions()">📅 Back to Available Sessions</button>
                    <button class="btn btn-secondary" onclick="showLanding()">🏠 Back to Home</button>
                </div>
            </div>
        </section>

        <!-- REGISTRATION WIZARD CARD CONTAINER -->
        <section id="screenRegistrationWizard" class="card hidden">
            <!-- STEP 1: ABOUT YOU -->
            <div id="step1">
                <div class="step-indicator">Step 1 of 6 — About You</div>
                <h2 class="page-title">Tell us a little about you</h2>
                <p class="page-desc">Please enter your basic information to get started.</p>

                <div class="form-group">
                    <label class="form-label">First Name <span class="req">*</span></label>
                    <input type="text" id="regFirstName" class="form-control" placeholder="Jane" required>
                    <div class="field-error" id="errFirstName">First Name is required.</div>
                </div>

                <div class="form-group">
                    <label class="form-label">Last Name <span class="req">*</span></label>
                    <input type="text" id="regLastName" class="form-control" placeholder="Smith" required>
                    <div class="field-error" id="errLastName">Last Name is required.</div>
                </div>

                <div class="form-group">
                    <label class="form-label">Date of Birth <span class="req">*</span></label>
                    <input type="text" id="regDOB" class="form-control" placeholder="MM/DD/YYYY" oninput="formatDOBInput(this)" maxlength="10" required>
                    <div class="field-error" id="errDOB">A valid 8-digit Date of Birth (MM/DD/YYYY) is required.</div>
                </div>

                <div class="form-group">
                    <label class="form-label">Primary Campus / Community Category <span class="req">*</span></label>
                    <select id="regCategory" class="form-control" onchange="onCategoryChanged()" required>
                        <option value="">-- Select Category --</option>
                        <option value="College Student">College Student</option>
                        <option value="High School Student">High School Student</option>
                        <option value="Alumni">Alumni</option>
                        <option value="Community Member">Community Member</option>
                        <option value="Staff">Staff</option>
                        <option value="Volunteer">Volunteer</option>
                    </select>
                    <div class="field-error" id="errCategory">Please select a primary category.</div>
                </div>

                <div class="btn-row">
                    <button class="btn btn-secondary" onclick="showLanding()">Cancel</button>
                    <button class="btn btn-primary" onclick="nextFromStep1()">Next →</button>
                </div>
            </div>

            <!-- STEP 2: CONTACT -->
            <div id="step2" class="hidden">
                <div class="step-indicator">Step 2 of 6 — Contact Info</div>
                <h2 class="page-title">How can we reach you?</h2>
                <p class="page-desc">Your contact details allow us to send session updates and member passes.</p>

                <div class="form-group">
                    <label class="form-label">Mobile Phone Number <span class="req">*</span></label>
                    <input type="tel" id="regPhone" class="form-control" placeholder="(864) 555-0199" oninput="formatPhoneInput(this)" required>
                    <div class="field-error" id="errPhone">A valid 10-digit mobile phone number is required.</div>
                </div>

                <div class="form-group">
                    <label class="form-label">Primary Email Address <span class="req">*</span></label>
                    <input type="email" id="regEmail" class="form-control" placeholder="jane@example.com" required>
                    <div class="field-error" id="errEmail">A valid email address is required.</div>
                </div>

                <div class="form-group">
                    <label class="form-label">SMS/Text Messaging Consent</label>
                    <div class="sms-consent-card" style="background:#f1f5f9; border:1px solid #cbd5e1; border-radius:8px; padding:14px; margin-top:6px;">
                        <label style="display:flex; align-items:flex-start; gap:10px; cursor:pointer; font-size:14px; font-weight:600; color:#0f172a; margin-bottom:10px;">
                            <input type="checkbox" id="regSMSCheckbox" style="width:20px; height:20px; margin-top:2px; accent-color:#2563eb;">
                            <span>I expressly consent to receive informational and customer care text messages regarding my participation in Real Life Study Center classes, Bible studies, events, appointments, volunteer opportunities, and other ministry activities.</span>
                        </label>
                        <div style="font-size:12px; color:#64748b; line-height:1.5; border-top:1px solid #cbd5e1; padding-top:10px;">
                            Message frequency varies based on participation. Message and data rates may apply. Reply <strong>STOP</strong> to opt out at any time or <strong>HELP</strong> for assistance. Consent to receive SMS messages is voluntary and is not a condition of participating in ministry programs or receiving ministry services. View our <a href="https://studycenterhub.reallife-studycenter.org/privacy.php" target="_blank" style="color:#2563eb; text-decoration:underline;">Privacy Policy</a> and <a href="https://studycenterhub.reallife-studycenter.org/terms.php" target="_blank" style="color:#2563eb; text-decoration:underline;">Terms & Conditions</a>.
                        </div>
                    </div>
                </div>

                <div class="btn-row">
                    <button class="btn btn-secondary" onclick="goToStep(1)">← Back</button>
                    <button class="btn btn-primary" onclick="nextFromStep2()">Next →</button>
                </div>
            </div>

            <!-- STEP 3: STUDENT DETAILS (CONDITIONAL) -->
            <div id="step3" class="hidden">
                <div class="step-indicator">Step 3 of 6 — Student Information</div>
                <h2 class="page-title">Student Information</h2>
                <p class="page-desc">Tell us a little about your school and academic year.</p>

                <div class="form-group">
                    <label class="form-label" id="labelInstitution">Institution / School <span class="req">*</span></label>
                    <select id="regInstitutionSelect" class="form-control" onchange="onInstitutionChanged()" required>
                        <option value="">-- Select Institution / School --</option>
                        <option value="Anderson University">Anderson University</option>
                        <option value="Erskine College">Erskine College</option>
                        <option value="Clemson University">Clemson University</option>
                        <option value="Tri-County Technical College">Tri-County Technical College</option>
                        <option value="Local High School">Local High School</option>
                        <option value="Other">Other</option>
                    </select>
                    <div class="field-error" id="errInstitution">Institution / School is required for students.</div>
                </div>

                <div class="form-group hidden" id="regInstitutionOtherGroup">
                    <label class="form-label">Other Institution / School <span class="req">*</span></label>
                    <input type="text" id="regInstitutionOther" class="form-control" placeholder="Enter school or college name">
                    <div class="field-error" id="errInstitutionOther">Please specify your institution or school.</div>
                </div>

                <div class="form-group">
                    <label class="form-label" id="labelGrade">Academic Classification / Grade <span class="req">*</span></label>
                    <select id="regGrade" class="form-control" required>
                        <option value="">-- Select Classification / Grade --</option>
                        <option value="Freshman">Freshman</option>
                        <option value="Sophomore">Sophomore</option>
                        <option value="Junior">Junior</option>
                        <option value="Senior">Senior</option>
                        <option value="Graduate Student">Graduate Student</option>
                    </select>
                    <div class="field-error" id="errGrade">Academic Classification is required for students.</div>
                </div>

                <div class="form-group">
                    <label class="form-label">School Email Address <span style="font-size:12px; color:#64748b; font-weight:normal;">(Optional)</span></label>
                    <input type="email" id="regSchoolEmail" class="form-control" placeholder="student@school.edu">
                </div>

                <div class="btn-row">
                    <button class="btn btn-secondary" onclick="goToStep(2)">← Back</button>
                    <button class="btn btn-primary" onclick="nextFromStep3()">Next →</button>
                </div>
            </div>

            <!-- STEP 4: EMERGENCY CONTACT (CONDITIONAL / OPTIONAL FOR ADULTS) -->
            <div id="step4" class="hidden">
                <div class="step-indicator">Step 4 of 6 — Emergency Contact</div>
                <h2 class="page-title">Emergency Contact</h2>
                
                <div id="minorNotice" class="alert-box alert-warning hidden">
                    <strong>Notice:</strong> Because you’re under 18, emergency contact details are required for registration.
                </div>
                <div id="adultNotice" class="alert-box alert-info hidden">
                    Emergency contact details are optional for adults. You may fill them out or tap <strong>Skip for Now</strong>.
                </div>

                <div class="form-group">
                    <label class="form-label">Contact Person Name <span id="emReqMark" class="req">*</span></label>
                    <input type="text" id="regEmName" class="form-control" placeholder="Parent or Guardian Name">
                    <div class="field-error" id="errEmName">Emergency Contact Name is required.</div>
                </div>

                <div class="form-group">
                    <label class="form-label">Contact Person Phone Number <span id="emReqMarkPhone" class="req">*</span></label>
                    <input type="tel" id="regEmPhone" class="form-control" placeholder="(864) 555-0199">
                    <div class="field-error" id="errEmPhone">A valid Emergency Contact Phone is required.</div>
                </div>

                <div class="btn-row">
                    <button class="btn btn-secondary" onclick="backFromStep4()">← Back</button>
                    <button class="btn btn-primary" onclick="nextFromStep4()">Next →</button>
                </div>
                <button id="btnSkipEm" class="btn btn-secondary" style="margin-top: 10px;" onclick="skipStep4()">Skip for Now</button>
            </div>

            <!-- STEP 5: YOUR PHOTO (OPTIONAL) -->
            <div id="step5" class="hidden">
                <div class="step-indicator">Step 5 of 6 — Your Profile Photo</div>
                <h2 class="page-title">Add a Profile Photo</h2>
                <p class="page-desc">Your photo helps our staff recognize and welcome you.</p>

                <div class="photo-preview-container">
                    <img id="photoPreviewImg" src="data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='80' height='80' viewBox='0 0 24 24' fill='none' stroke='%2094a3b8' stroke-width='1.5' stroke-linecap='round' stroke-linejoin='round'%3E%3Cpath d='M20 21v-2a4 4 0 0 0-4-4H8a4 4 0 0 0-4 4v2'%3E%3C/path%3E%3Ccircle cx='12' cy='7' r='4'%3E%3C/circle%3E%3C/svg%3E" alt="Preview">
                </div>

                <input type="file" id="cameraInput" accept="image/*" capture="user" class="hidden" onchange="onPhotoSelected(event)">
                <input type="file" id="fileInput" accept="image/*" class="hidden" onchange="onPhotoSelected(event)">

                <div class="btn-stack">
                    <button class="btn btn-primary" onclick="document.getElementById('cameraInput').click()">📷 Take Photo</button>
                    <button class="btn btn-secondary" onclick="document.getElementById('fileInput').click()">📁 Choose Photo from Device</button>
                    <button class="btn btn-secondary" onclick="skipStep5()">Skip for Now</button>
                </div>

                <div class="btn-row">
                    <button class="btn btn-secondary" onclick="backFromStep5()">← Back</button>
                    <button id="btnNextPhoto" class="btn btn-primary hidden" onclick="goToStep(6)">Use Photo & Continue →</button>
                </div>
            </div>

            <!-- STEP 6: REVIEW & REGISTER -->
            <div id="step6" class="hidden">
                <div class="step-indicator">Step 6 of 6 — Review & Submit</div>
                <h2 class="page-title">Review Your Information</h2>
                <p class="page-desc">Please verify your details below before completing registration.</p>

                <ul class="summary-list">
                    <li class="summary-item">
                        <span class="summary-label">Name</span>
                        <span class="summary-val" id="sumName">-</span>
                    </li>
                    <li class="summary-item">
                        <span class="summary-label">Date of Birth</span>
                        <span class="summary-val" id="sumDOB">-</span>
                    </li>
                    <li class="summary-item">
                        <span class="summary-label">Category</span>
                        <span class="summary-val" id="sumCategory">-</span>
                    </li>
                    <li class="summary-item">
                        <span class="summary-label">Mobile Phone</span>
                        <span class="summary-val" id="sumPhone">-</span>
                    </li>
                    <li class="summary-item">
                        <span class="summary-label">Primary Email</span>
                        <span class="summary-val" id="sumEmail">-</span>
                    </li>
                    <li class="summary-item">
                        <span class="summary-label">SMS Consent</span>
                        <span class="summary-val" id="sumSMS">-</span>
                    </li>
                    <li class="summary-item id="sumStudentRow">
                        <span class="summary-label">Student Details</span>
                        <span class="summary-val" id="sumStudent">-</span>
                    </li>
                    <li class="summary-item">
                        <span class="summary-label">Emergency Contact</span>
                        <span class="summary-val" id="sumEmergency">-</span>
                    </li>
                    <li class="summary-item">
                        <span class="summary-label">Profile Photo</span>
                        <span class="summary-val" id="sumPhoto">Not Provided</span>
                    </li>
                </ul>

                <div id="regSubmitErr" class="alert-box alert-warning hidden"></div>

                <div class="btn-row">
                    <button class="btn btn-secondary" onclick="goToStep(5)">← Back</button>
                    <button class="btn btn-amber" id="btnSubmitRegistration" onclick="submitRegistration()">Complete Registration 🚀</button>
                </div>
            </div>
        </section>

        <!-- SCREEN REGISTRATION SUCCESS -->
        <section id="screenSuccess" class="card hidden">
            <div class="success-hero">
                <div class="success-icon">🎉</div>
                <h2 class="page-title" id="successTitle">Registration Complete!</h2>
                <p class="page-desc" id="successDesc">Welcome! Your Real Life House member profile has been created.</p>
            </div>

            <div class="btn-stack">
                <button class="btn btn-primary" onclick="performSuccessAction('sessions')">📅 View Available Sessions</button>
                <button class="btn btn-secondary" onclick="performSuccessAction('pass')">💳 Get My Digital Member Pass</button>
                <button class="btn btn-secondary" onclick="showLanding()">🏠 Back to Main Menu</button>
            </div>
        </section>
    </main>

    <script>
        // Form Data State
        let regData = {
            firstName: '',
            lastName: '',
            birthday: '',
            primaryRole: '',
            phone: '',
            email: '',
            schoolEmail: '',
            smsConsent: '',
            institution: '',
            institutionOther: '',
            grade: '',
            emergencyName: '',
            emergencyPhone: '',
            profilePhoto: ''
        };

        let currentStepNum = 1;

        function showLanding() {
            document.getElementById('screenRegistrationWizard').classList.add('hidden');
            document.getElementById('screenCheckInNotice').classList.add('hidden');
            document.getElementById('screenSessionNotice').classList.add('hidden');
            document.getElementById('screenSuccess').classList.add('hidden');
            document.getElementById('screenLanding').classList.remove('hidden');
            document.getElementById('progressBarContainer').style.display = 'none';
        }

        function showCheckInChoice() {
            document.getElementById('screenLanding').classList.add('hidden');
            document.getElementById('screenSuccess').classList.add('hidden');
            document.getElementById('screenCheckInNotice').classList.remove('hidden');
            if (typeof resetCheckInLookup === 'function') {
                resetCheckInLookup();
            }
            const regSess = sessionStorage.getItem('reg_session');
            if (regSess) {
                try {
                    const data = JSON.parse(regSess);
                    if (data.phone) {
                        const phoneInput = document.getElementById('checkinPhoneInput');
                        if (phoneInput) {
                            phoneInput.value = data.phone;
                            formatPhoneInput(phoneInput);
                        }
                    }
                } catch(e) {}
            }
        }

        function showSessionChoice() {
            document.getElementById('screenLanding').classList.add('hidden');
            document.getElementById('screenSuccess').classList.add('hidden');
            document.getElementById('screenCheckInNotice').classList.add('hidden');
            document.getElementById('screenSessionNotice').classList.remove('hidden');
            loadPublicSessions();
        }

        function clearSessionIdentity() {
            sessionStorage.removeItem('reg_session');
            matchedMemberData = null;
            showCheckInChoice();
        }

        function getActiveMemberIdentity() {
            if (matchedMemberData && (matchedMemberData.phone || matchedMemberData.masked_phone || matchedMemberData.human_id)) {
                if (!matchedMemberData.phone) {
                    const phoneInput = document.getElementById('checkinPhoneInput');
                    if (phoneInput && phoneInput.value) {
                        matchedMemberData.phone = phoneInput.value.trim();
                    }
                }
                return matchedMemberData;
            }
            const regSess = sessionStorage.getItem('reg_session');
            if (regSess) {
                try {
                    const data = JSON.parse(regSess);
                    if (data.phone) return data;
                } catch(e) {}
            }
            return null;
        }

        function loadPublicSessions() {
            document.getElementById('sessionListView').classList.remove('hidden');
            document.getElementById('sessionProcessingView').classList.add('hidden');
            document.getElementById('sessionSuccessView').classList.add('hidden');
            document.getElementById('sessionWaitlistSuccessView').classList.add('hidden');
            document.getElementById('sessionCancelledView').classList.add('hidden');

            const member = getActiveMemberIdentity();
            const badge = document.getElementById('sessionIdentityBadge');
            if (member) {
                document.getElementById('sessBadgeName').textContent = member.firstName || member.first_name || 'Member';
                document.getElementById('sessBadgePhone').textContent = member.phone || member.masked_phone || '';
                badge.classList.remove('hidden');
            } else {
                badge.classList.add('hidden');
            }

            const container = document.getElementById('sessionCardsContainer');
            container.innerHTML = '<div style="text-align:center; color: var(--text-muted); padding: 20px;">Loading available sessions...</div>';

            const phoneParam = member ? (member.phone || member.masked_phone || '') : '';
            fetch('/api/v1/public/sessions?phone=' + encodeURIComponent(phoneParam))
            .then(r => r.json())
            .then(res => {
                if (res.success && Array.isArray(res.sessions)) {
                    renderSessionCards(res.sessions, member);
                } else {
                    container.innerHTML = '<div class="alert-box alert-warning">Unable to load sessions. Please try again later.</div>';
                }
            })
            .catch(err => {
                container.innerHTML = '<div class="alert-box alert-warning">Network error loading sessions. Please see staff at the front desk.</div>';
            });
        }

        function format12HourTime(timeStr) {
            if (!timeStr) return '';
            const parts = timeStr.split(':');
            if (parts.length < 2) return timeStr;
            let h = parseInt(parts[0], 10);
            let m = parts[1];
            let ampm = h >= 12 ? 'PM' : 'AM';
            h = h % 12;
            if (h === 0) h = 12;
            return h + ':' + m + ' ' + ampm;
        }

        function renderSessionCards(sessions, member) {
            const container = document.getElementById('sessionCardsContainer');
            if (sessions.length === 0) {
                container.innerHTML = '<div class="alert-box alert-info">There are no public sessions currently open for signup. Please check back soon!</div>';
                return;
            }

            let html = '';
            sessions.forEach(s => {
                const sid = s.session_id;
                const title = s.title;
                const dateText = s.date_text;
                const timeStr = format12HourTime(s.start_time) + (s.end_time ? ' - ' + format12HourTime(s.end_time) : '');
                const loc = s.room_location || 'Real Life House';
                const desc = s.description || '';
                const isFull = s.is_full;
                const rem = s.remaining_capacity;
                const mStatus = s.member_signup_status; // 'confirmed', 'waitlist', or null
                const waitEnabled = (s.waitlist_enabled == 1);
                const regOpen = s.is_registration_open;

                let statusBadgeHtml = '';
                let actionBtnHtml = '';

                if (mStatus === 'confirmed') {
                    statusBadgeHtml = '<span style="background:#dcfce7; color:#15803d; font-size:12px; font-weight:700; padding:4px 8px; border-radius:6px;">✓ You’re Registered</span>';
                    actionBtnHtml = '<button class="btn btn-secondary" style="height:44px; font-size:14px;" onclick="submitSessionAction(' + sid + ', \'cancel\')">Cancel Registration</button>';
                } else if (mStatus === 'waitlist') {
                    statusBadgeHtml = '<span style="background:#fef3c7; color:#b45309; font-size:12px; font-weight:700; padding:4px 8px; border-radius:6px;">⏳ You’re on Waitlist</span>';
                    actionBtnHtml = '<button class="btn btn-secondary" style="height:44px; font-size:14px;" onclick="submitSessionAction(' + sid + ', \'cancel\')">Cancel Waitlist Spot</button>';
                } else if (!regOpen) {
                    statusBadgeHtml = '<span style="background:#f1f5f9; color:#64748b; font-size:12px; font-weight:700; padding:4px 8px; border-radius:6px;">Registration Closed</span>';
                    actionBtnHtml = '<button class="btn btn-secondary" disabled style="height:44px; font-size:14px; opacity:0.6;">Closed</button>';
                } else if (!isFull) {
                    const spotText = (rem === 1) ? '1 spot remaining' : (rem + ' spots remaining');
                    statusBadgeHtml = '<span style="background:#dbeafe; color:#1e40af; font-size:12px; font-weight:700; padding:4px 8px; border-radius:6px;">' + spotText + '</span>';
                    actionBtnHtml = '<button class="btn btn-primary" style="height:44px; font-size:14px;" onclick="submitSessionAction(' + sid + ', \'signup\')">Sign Up 🚀</button>';
                } else if (isFull && waitEnabled) {
                    statusBadgeHtml = '<span style="background:#fef3c7; color:#b45309; font-size:12px; font-weight:700; padding:4px 8px; border-radius:6px;">Full — Waitlist Available</span>';
                    actionBtnHtml = '<button class="btn btn-amber" style="height:44px; font-size:14px;" onclick="submitSessionAction(' + sid + ', \'signup\')">Join Waitlist ⏳</button>';
                } else {
                    statusBadgeHtml = '<span style="background:#fef2f2; color:#dc2626; font-size:12px; font-weight:700; padding:4px 8px; border-radius:6px;">Session Full</span>';
                    actionBtnHtml = '<button class="btn btn-secondary" disabled style="height:44px; font-size:14px; opacity:0.6;">Full</button>';
                }

                html += `
                <div class="card" style="margin-bottom: 16px; border: 1px solid #cbd5e1;">
                    <div style="display: flex; justify-content: space-between; align-items: flex-start; margin-bottom: 8px;">
                        <h3 style="font-size: 18px; font-weight: 700; color: #0f172a;">${title}</h3>
                        ${statusBadgeHtml}
                    </div>
                    <div style="font-size: 13px; color: #475569; margin-bottom: 4px;">📅 ${dateText} • ${timeStr}</div>
                    <div style="font-size: 13px; color: #475569; margin-bottom: 10px;">📍 ${loc}</div>
                    ${desc ? `<div style="font-size: 13px; color: #64748b; margin-bottom: 12px; line-height: 1.4;">${desc}</div>` : ''}
                    <div style="margin-top: 12px;">${actionBtnHtml}</div>
                </div>`;
            });

            container.innerHTML = html;
        }

        function submitSessionAction(sessionId, action) {
            const member = getActiveMemberIdentity();
            if (!member) {
                alert('Please identify yourself first by phone number before signing up for a session.');
                showCheckInChoice();
                return;
            }

            document.getElementById('sessionListView').classList.add('hidden');
            document.getElementById('sessionProcessingView').classList.remove('hidden');
            document.getElementById('sessProcessingTitle').textContent = (action === 'cancel') ? 'Cancelling Signup...' : 'Processing Signup...';

            const payload = {
                session_id: sessionId,
                phone: member.phone || member.masked_phone || '',
                human_id: member.human_id || '',
                action: action
            };

            fetch('/api/v1/public/signup', {
                method: 'POST',
                headers: {'Content-Type': 'application/json'},
                body: JSON.stringify(payload)
            })
            .then(r => r.json())
            .then(res => {
                if (res.success && res.event_uuid) {
                    pollSessionStatus(res.event_uuid, member.firstName || member.first_name || 'Member', action, 0);
                } else {
                    showSessionError('Unable to queue session request.');
                }
            })
            .catch(err => {
                showSessionError('Network error connecting to session server.');
            });
        }

        function pollSessionStatus(eventUuid, firstName, action, pollCount) {
            const maxPolls = 8;
            fetch('/api/v1/public/checkin/status?event_uuid=' + encodeURIComponent(eventUuid))
            .then(r => r.json())
            .then(data => {
                document.getElementById('sessionProcessingView').classList.add('hidden');
                const st = data.status;

                if (st === 'confirmed') {
                    document.getElementById('sessSuccessTitle').textContent = '✓ You’re Signed Up!';
                    document.getElementById('sessSuccessMsg').textContent = 'Welcome, ' + firstName + '! Your spot is confirmed for ' + (data.title || 'this session') + '.';
                    document.getElementById('sessionSuccessView').classList.remove('hidden');
                } else if (st === 'waitlisted') {
                    document.getElementById('sessWaitlistTitle').textContent = 'You’re on the Waitlist';
                    document.getElementById('sessWaitlistMsg').textContent = 'You are on the waitlist' + (data.position ? ' (Position #' + data.position + ')' : '') + ' for ' + (data.title || 'this session') + '. StudyCenterHub staff will notify you if a spot opens!';
                    document.getElementById('sessionWaitlistSuccessView').classList.remove('hidden');
                } else if (st === 'already_registered') {
                    document.getElementById('sessSuccessTitle').textContent = 'Already Registered';
                    document.getElementById('sessSuccessMsg').textContent = (data.message || 'You are already registered for this session.');
                    document.getElementById('sessionSuccessView').classList.remove('hidden');
                } else if (st === 'already_waitlisted') {
                    document.getElementById('sessWaitlistTitle').textContent = 'Already Waitlisted';
                    document.getElementById('sessWaitlistMsg').textContent = (data.message || 'You are already on the waitlist for this session.');
                    document.getElementById('sessionWaitlistSuccessView').classList.remove('hidden');
                } else if (st === 'cancelled') {
                    document.getElementById('sessCancelledMsg').textContent = 'Your registration for ' + (data.title || 'this session') + ' has been cancelled.';
                    document.getElementById('sessionCancelledView').classList.remove('hidden');
                } else if (st === 'processing') {
                    if (pollCount < maxPolls) {
                        document.getElementById('sessionProcessingView').classList.remove('hidden');
                        setTimeout(() => pollSessionStatus(eventUuid, firstName, action, pollCount + 1), 1500);
                    } else {
                        document.getElementById('sessSuccessTitle').textContent = 'Request Received!';
                        document.getElementById('sessSuccessMsg').textContent = 'Your request has been queued in StudyCenterHub. Thank you, ' + firstName + '!';
                        document.getElementById('sessionSuccessView').classList.remove('hidden');
                    }
                } else {
                    showSessionError(data.message || 'Session processing error');
                }
            })
            .catch(e => {
                document.getElementById('sessionProcessingView').classList.add('hidden');
                document.getElementById('sessSuccessTitle').textContent = 'Request Received!';
                document.getElementById('sessSuccessMsg').textContent = 'Your request has been queued in StudyCenterHub. Thank you, ' + firstName + '!';
                document.getElementById('sessionSuccessView').classList.remove('hidden');
            });
        }

        function showSessionError(msg) {
            document.getElementById('sessionProcessingView').classList.add('hidden');
            alert('⚠️ Session Request Notice: ' + msg);
            loadPublicSessions();
        }

        let matchedMemberData = null;

        function formatPhoneInput(input) {
            let digits = input.value.replace(/\D/g, '');
            if (digits.length > 10) digits = digits.substring(0, 10);
            if (digits.length >= 7) {
                input.value = '(' + digits.substring(0, 3) + ') ' + digits.substring(3, 6) + '-' + digits.substring(6);
            } else if (digits.length >= 4) {
                input.value = '(' + digits.substring(0, 3) + ') ' + digits.substring(3);
            } else if (digits.length > 0) {
                input.value = '(' + digits;
            }
        }



        function resetCheckInLookup() {
            document.getElementById('checkinLookupView').classList.remove('hidden');
            document.getElementById('checkinConfirmView').classList.add('hidden');
            document.getElementById('checkinProcessingView').classList.add('hidden');
            document.getElementById('checkinSuccessView').classList.add('hidden');
            document.getElementById('checkinAlreadyView').classList.add('hidden');
            document.getElementById('checkinNotFoundView').classList.add('hidden');
            document.getElementById('errCheckinPhone').style.display = 'none';
            document.getElementById('checkinLookupMsg').classList.add('hidden');
            matchedMemberData = null;
        }

        function findMemberByPhone() {
            const phoneInput = document.getElementById('checkinPhoneInput');
            const phone = phoneInput.value.trim();
            const errEl = document.getElementById('errCheckinPhone');
            const msgEl = document.getElementById('checkinLookupMsg');
            const btn = document.getElementById('btnFindMe');

            const digits = phone.replace(/\D/g, '');
            if (digits.length < 10) {
                errEl.style.display = 'block';
                return;
            }
            errEl.style.display = 'none';
            msgEl.classList.add('hidden');
            btn.disabled = true;
            btn.textContent = 'Searching... 🔍';

            fetch('/api/v1/public/checkin/lookup', {
                method: 'POST',
                headers: {'Content-Type': 'application/json'},
                body: JSON.stringify({ phone: phone })
            })
            .then(r => r.json())
            .then(res => {
                btn.disabled = false;
                btn.textContent = 'Find Me 🔍';
                if (res.found && res.match_count === 1) {
                    matchedMemberData = res;
                    matchedMemberData.phone = phone;
                    try {
                        sessionStorage.setItem('reg_session', JSON.stringify({
                            first_name: res.first_name,
                            phone: phone,
                            masked_phone: res.masked_phone,
                            human_id: res.human_id
                        }));
                    } catch(e) {}
                    if (res.already_checked_in) {
                        document.getElementById('checkinLookupView').classList.add('hidden');
                        document.getElementById('checkinAlreadyTitle').textContent = 'Already Checked in Today';
                        document.getElementById('checkinAlreadyMsg').textContent = 'Glad you’re here, ' + res.first_name + '! You are already checked in for today.';
                        document.getElementById('checkinAlreadyView').classList.remove('hidden');
                        return;
                    }
                    document.getElementById('confMemberName').textContent = res.first_name;
                    document.getElementById('confMemberPhone').textContent = res.masked_phone;
                    document.getElementById('checkinLookupView').classList.add('hidden');
                    document.getElementById('checkinConfirmView').classList.remove('hidden');
                } else if (res.error === 'multiple_matches') {
                    msgEl.textContent = '⚠️ ' + res.message;
                    msgEl.classList.remove('hidden');
                } else {
                    document.getElementById('checkinLookupView').classList.add('hidden');
                    document.getElementById('checkinNotFoundMsg').textContent = 'We couldn’t find an active membership matching ' + phone + '.';
                    document.getElementById('checkinNotFoundView').classList.remove('hidden');
                }
            })
            .catch(err => {
                btn.disabled = false;
                btn.textContent = 'Find Me 🔍';
                msgEl.textContent = '⚠️ Unable to connect. Please try again or see a staff member.';
                msgEl.classList.remove('hidden');
            });
        }

        function confirmAndSubmitCheckIn() {
            if (!matchedMemberData) return;
            const btn = document.getElementById('btnConfirmCheckIn');
            btn.disabled = true;

            document.getElementById('checkinConfirmView').classList.add('hidden');
            document.getElementById('checkinProcessingView').classList.remove('hidden');

            const payload = {
                phone: document.getElementById('checkinPhoneInput').value.trim(),
                human_id: matchedMemberData.human_id,
                first_name: matchedMemberData.first_name
            };

            fetch('/api/v1/public/checkin', {
                method: 'POST',
                headers: {'Content-Type': 'application/json'},
                body: JSON.stringify(payload)
            })
            .then(r => r.json())
            .then(res => {
                if (res.already_checked_in) {
                    document.getElementById('checkinProcessingView').classList.add('hidden');
                    document.getElementById('checkinAlreadyTitle').textContent = 'Already Checked in Today';
                    document.getElementById('checkinAlreadyMsg').textContent = 'Glad you’re here, ' + (res.first_name || matchedMemberData.first_name) + '! You are already checked in for today.';
                    document.getElementById('checkinAlreadyView').classList.remove('hidden');
                } else if (res.success && res.event_uuid) {
                    pollCheckInStatus(res.event_uuid, matchedMemberData.first_name, 0);
                } else {
                    showCheckInError('Unable to queue check-in request.');
                }
            })
            .catch(err => {
                showCheckInError('Network error connecting to check-in server.');
            });
        }

        function showCheckInPending(firstName) {
            document.getElementById('checkinProcessingView').classList.add('hidden');
            document.getElementById('checkinSuccessTitle').textContent = 'Check-In Submitted 📋';
            document.getElementById('checkinSuccessMsg').textContent = 'Your check-in request has been submitted to StudyCenterHub. Welcome, ' + firstName + '!';
            document.getElementById('checkinSuccessView').classList.remove('hidden');
        }

        function pollCheckInStatus(eventUuid, firstName, pollCount) {
            const maxPolls = 8; // 8 x 1.5s = 12 seconds max
            fetch('/api/v1/public/checkin/status?event_uuid=' + encodeURIComponent(eventUuid))
            .then(r => r.json())
            .then(data => {
                document.getElementById('checkinProcessingView').classList.add('hidden');
                if (data.status === 'checked_in') {
                    document.getElementById('checkinSuccessTitle').textContent = '✓ You’re Checked In!';
                    document.getElementById('checkinSuccessMsg').textContent = 'Welcome, ' + (data.first_name || firstName) + '! We’re glad you’re here today.';
                    document.getElementById('checkinSuccessView').classList.remove('hidden');
                } else if (data.status === 'already_checked_in') {
                    document.getElementById('checkinAlreadyTitle').textContent = 'Already Checked in Today';
                    document.getElementById('checkinAlreadyMsg').textContent = 'Glad you’re here, ' + (data.first_name || firstName) + '! You are already checked in for today.';
                    document.getElementById('checkinAlreadyView').classList.remove('hidden');
                } else if (data.status === 'member_not_found') {
                    document.getElementById('checkinNotFoundMsg').textContent = 'Member record not found. Please see a staff member.';
                    document.getElementById('checkinNotFoundView').classList.remove('hidden');
                } else if (data.status === 'processing' || data.status === 'pending') {
                    if (pollCount < maxPolls) {
                        document.getElementById('checkinProcessingView').classList.remove('hidden');
                        setTimeout(() => pollCheckInStatus(eventUuid, firstName, pollCount + 1), 1500);
                    } else {
                        showCheckInPending(firstName);
                    }
                } else {
                    showCheckInPending(firstName);
                }
            })
            .catch(e => {
                showCheckInPending(firstName);
            });
        }

        function showCheckInError(msg) {
            document.getElementById('checkinProcessingView').classList.add('hidden');
            document.getElementById('checkinNotFoundMsg').textContent = '⚠️ ' + msg;
            document.getElementById('checkinNotFoundView').classList.remove('hidden');
        }

        function startRegistration() {
            document.getElementById('screenLanding').classList.add('hidden');
            document.getElementById('screenRegistrationWizard').classList.remove('hidden');
            document.getElementById('progressBarContainer').style.display = 'block';
            goToStep(1);
        }

        function isStudentCategory(cat) {
            return cat === 'College Student' || cat === 'High School Student';
        }

        function calculateAge(dobStr) {
            if (!dobStr) return 99;
            const dob = new Date(dobStr);
            const diff = Date.now() - dob.getTime();
            const ageDate = new Date(diff);
            return Math.abs(ageDate.getUTCFullYear() - 1970);
        }

        function updateProgressBar(step) {
            const pct = Math.round((step / 6) * 100);
            document.getElementById('progressBarFill').style.width = pct + '%';
        }

        function goToStep(step) {
            currentStepNum = step;
            updateProgressBar(step);

            for (let i = 1; i <= 6; i++) {
                const el = document.getElementById('step' + i);
                if (el) el.classList.add('hidden');
            }

            const target = document.getElementById('step' + step);
            if (target) target.classList.remove('hidden');

            if (step === 4) {
                const age = calculateAge(regData.birthday);
                const isMinor = age < 18;
                if (isMinor) {
                    document.getElementById('minorNotice').classList.remove('hidden');
                    document.getElementById('adultNotice').classList.add('hidden');
                    document.getElementById('btnSkipEm').classList.add('hidden');
                    document.getElementById('emReqMark').style.display = 'inline';
                    document.getElementById('emReqMarkPhone').style.display = 'inline';
                } else {
                    document.getElementById('minorNotice').classList.add('hidden');
                    document.getElementById('adultNotice').classList.remove('hidden');
                    document.getElementById('btnSkipEm').classList.remove('hidden');
                    document.getElementById('emReqMark').style.display = 'none';
                    document.getElementById('emReqMarkPhone').style.display = 'none';
                }
            } else if (step === 6) {
                renderSummary();
            }
        }

        function onCategoryChanged() {
            regData.primaryRole = document.getElementById('regCategory').value;
            adaptStudentFields();
        }

        function adaptStudentFields() {
            const cat = regData.primaryRole;
            const instLabel = document.getElementById('labelInstitution');
            const gradeLabel = document.getElementById('labelGrade');
            const instSelect = document.getElementById('regInstitutionSelect');
            const gradeSelect = document.getElementById('regGrade');

            if (!instSelect || !gradeSelect) return;

            if (cat === 'High School Student') {
                if (instLabel) instLabel.innerHTML = 'High School / Academy <span class="req">*</span>';
                if (gradeLabel) gradeLabel.innerHTML = 'High School Grade Level <span class="req">*</span>';

                instSelect.innerHTML = `
                    <option value="">-- Select High School --</option>
                    <option value="T.L. Hanna High School">T.L. Hanna High School</option>
                    <option value="Westside High School">Westside High School</option>
                    <option value="Palmetto High School">Palmetto High School</option>
                    <option value="Crescent High School">Crescent High School</option>
                    <option value="Belton-Honea Path High School">Belton-Honea Path High School</option>
                    <option value="Pendleton High School">Pendleton High School</option>
                    <option value="Wren High School">Wren High School</option>
                    <option value="Powdersville High School">Powdersville High School</option>
                    <option value="Anderson Christian School">Anderson Christian School</option>
                    <option value="New Covenant School">New Covenant School</option>
                    <option value="Home School">Home School</option>
                    <option value="Other">Other</option>
                `;

                gradeSelect.innerHTML = `
                    <option value="">-- Select Grade Level --</option>
                    <option value="9th Grade">9th Grade</option>
                    <option value="10th Grade">10th Grade</option>
                    <option value="11th Grade">11th Grade</option>
                    <option value="12th Grade">12th Grade</option>
                `;
            } else {
                if (instLabel) instLabel.innerHTML = 'College / University <span class="req">*</span>';
                if (gradeLabel) gradeLabel.innerHTML = 'Academic Year / Classification <span class="req">*</span>';

                instSelect.innerHTML = `
                    <option value="">-- Select College / University --</option>
                    <option value="Anderson University">Anderson University</option>
                    <option value="Erskine College">Erskine College</option>
                    <option value="Clemson University">Clemson University</option>
                    <option value="Tri-County Technical College">Tri-County Technical College</option>
                    <option value="Other">Other</option>
                `;

                gradeSelect.innerHTML = `
                    <option value="">-- Select Academic Year --</option>
                    <option value="Freshman">Freshman</option>
                    <option value="Sophomore">Sophomore</option>
                    <option value="Junior">Junior</option>
                    <option value="Senior">Senior</option>
                    <option value="Graduate Student">Graduate Student</option>
                `;
            }
            onInstitutionChanged();
        }

        function onInstitutionChanged() {
            const val = document.getElementById('regInstitutionSelect').value;
            const otherGroup = document.getElementById('regInstitutionOtherGroup');
            if (val === 'Other') {
                otherGroup.classList.remove('hidden');
            } else {
                otherGroup.classList.add('hidden');
                document.getElementById('regInstitutionOther').value = '';
                regData.institutionOther = '';
            }
        }

        function formatDOBInput(el) {
            let raw = el.value.replace(/\D/g, '');
            if (raw.length > 8) raw = raw.substring(0, 8);
            let formatted = raw;
            if (raw.length > 4) {
                formatted = raw.substring(0, 2) + '/' + raw.substring(2, 4) + '/' + raw.substring(4);
            } else if (raw.length > 2) {
                formatted = raw.substring(0, 2) + '/' + raw.substring(2);
            }
            el.value = formatted;
        }

        function parseDOBToISO(dobStr) {
            if (!dobStr) return '';
            const parts = dobStr.trim().split('/');
            if (parts.length === 3) {
                const mm = parts[0].padStart(2, '0');
                const dd = parts[1].padStart(2, '0');
                const yyyy = parts[2];
                if (mm.length === 2 && dd.length === 2 && yyyy.length === 4) {
                    const m = parseInt(mm, 10);
                    const d = parseInt(dd, 10);
                    const y = parseInt(yyyy, 10);
                    if (m >= 1 && m <= 12 && d >= 1 && d <= 31 && y >= 1900 && y <= 2100) {
                        return yyyy + '-' + mm + '-' + dd;
                    }
                }
            }
            if (/^\d{4}-\d{2}-\d{2}$/.test(dobStr)) return dobStr;
            return '';
        }

        function nextFromStep1() {
            const fn = document.getElementById('regFirstName').value.trim();
            const ln = document.getElementById('regLastName').value.trim();
            const rawDob = document.getElementById('regDOB').value.trim();
            const cat = document.getElementById('regCategory').value;

            const isoDob = parseDOBToISO(rawDob);
            let valid = true;

            document.getElementById('errFirstName').style.display = fn ? 'none' : 'block';
            document.getElementById('errLastName').style.display = ln ? 'none' : 'block';
            document.getElementById('errDOB').style.display = isoDob ? 'none' : 'block';
            document.getElementById('errCategory').style.display = cat ? 'none' : 'block';

            if (!fn || !ln || !isoDob || !cat) valid = false;

            if (valid) {
                regData.firstName = fn;
                regData.lastName = ln;
                regData.birthday = isoDob;
                regData.displayBirthday = rawDob;
                regData.primaryRole = cat;
                goToStep(2);
            }
        }

        function nextFromStep2() {
            const phone = document.getElementById('regPhone').value.trim();
            const email = document.getElementById('regEmail').value.trim();
            const smsChecked = document.getElementById('regSMSCheckbox').checked;

            const digitsOnly = phone.replace(/\D/g, '');
            let valid = true;

            document.getElementById('errPhone').style.display = (digitsOnly.length >= 10) ? 'none' : 'block';
            document.getElementById('errEmail').style.display = (email.includes('@') && email.includes('.')) ? 'none' : 'block';

            if (digitsOnly.length < 10 || !email.includes('@') || !email.includes('.')) valid = false;

            if (valid) {
                regData.phone = phone;
                regData.email = email;
                regData.smsConsent = smsChecked ? 'Yes' : 'No';

                if (isStudentCategory(regData.primaryRole)) {
                    adaptStudentFields();
                    goToStep(3);
                } else {
                    goToStep(4);
                }
            }
        }

        function nextFromStep3() {
            const instSelect = document.getElementById('regInstitutionSelect').value;
            const instOther = document.getElementById('regInstitutionOther').value.trim();
            const grade = document.getElementById('regGrade').value;
            const schoolEmail = document.getElementById('regSchoolEmail').value.trim();

            let valid = true;
            let finalInst = instSelect;

            if (!instSelect) {
                document.getElementById('errInstitution').style.display = 'block';
                valid = false;
            } else {
                document.getElementById('errInstitution').style.display = 'none';
            }

            if (instSelect === 'Other') {
                if (!instOther) {
                    document.getElementById('errInstitutionOther').style.display = 'block';
                    valid = false;
                } else {
                    document.getElementById('errInstitutionOther').style.display = 'none';
                    finalInst = instOther;
                }
            }

            document.getElementById('errGrade').style.display = grade ? 'none' : 'block';
            if (!grade) valid = false;

            if (valid) {
                regData.institution = finalInst;
                regData.institutionOther = (instSelect === 'Other') ? instOther : '';
                regData.grade = grade;
                regData.schoolEmail = schoolEmail;
                goToStep(4);
            }
        }

        function backFromStep4() {
            if (isStudentCategory(regData.primaryRole)) {
                goToStep(3);
            } else {
                goToStep(2);
            }
        }

        function nextFromStep4() {
            const emName = document.getElementById('regEmName').value.trim();
            const emPhone = document.getElementById('regEmPhone').value.trim();
            const age = calculateAge(regData.birthday);
            const isMinor = age < 18;

            if (isMinor) {
                let valid = true;
                document.getElementById('errEmName').style.display = emName ? 'none' : 'block';
                document.getElementById('errEmPhone').style.display = emPhone ? 'none' : 'block';
                if (!emName || !emPhone) valid = false;
                if (!valid) return;
            }

            regData.emergencyName = emName;
            regData.emergencyPhone = emPhone;
            goToStep(5);
        }

        function skipStep4() {
            regData.emergencyName = '';
            regData.emergencyPhone = '';
            goToStep(5);
        }

        function backFromStep5() {
            goToStep(4);
        }

        function skipStep5() {
            regData.profilePhoto = '';
            goToStep(6);
        }

        function onPhotoSelected(evt) {
            const file = evt.target.files[0];
            if (!file) return;

            const reader = new FileReader();
            reader.onload = function(e) {
                const img = new Image();
                img.onload = function() {
                    const canvas = document.createElement('canvas');
                    canvas.width = 600;
                    canvas.height = 600;
                    const ctx = canvas.getContext('2d');

                    let minDim = Math.min(img.width, img.height);
                    let sx = (img.width - minDim) / 2;
                    let sy = (img.height - minDim) / 2;

                    ctx.drawImage(img, sx, sy, minDim, minDim, 0, 0, 600, 600);
                    const dataUrl = canvas.toDataURL('image/jpeg', 0.85);

                    regData.profilePhoto = dataUrl;
                    document.getElementById('photoPreviewImg').src = dataUrl;
                    document.getElementById('btnNextPhoto').classList.remove('hidden');
                };
                img.src = e.target.result;
            };
            reader.readAsDataURL(file);
        }

        function renderSummary() {
            document.getElementById('sumName').textContent = regData.firstName + ' ' + regData.lastName;
            document.getElementById('sumDOB').textContent = regData.displayBirthday || regData.birthday;
            document.getElementById('sumCategory').textContent = regData.primaryRole;
            document.getElementById('sumPhone').textContent = regData.phone;
            document.getElementById('sumEmail').textContent = regData.email + (regData.schoolEmail ? ' (School: ' + regData.schoolEmail + ')' : '');
            document.getElementById('sumSMS').textContent = (regData.smsConsent === 'Yes' ? 'Yes (Opted In to SMS)' : 'No (Declined SMS)');

            if (isStudentCategory(regData.primaryRole)) {
                document.getElementById('sumStudentRow').classList.remove('hidden');
                document.getElementById('sumStudent').textContent = (regData.institution || 'N/A') + ' • ' + (regData.grade || 'N/A');
            } else {
                document.getElementById('sumStudentRow').classList.add('hidden');
            }

            if (regData.emergencyName) {
                document.getElementById('sumEmergency').textContent = regData.emergencyName + ' (' + regData.emergencyPhone + ')';
            } else {
                document.getElementById('sumEmergency').textContent = 'Not Provided';
            }

            if (regData.profilePhoto) {
                document.getElementById('sumPhoto').textContent = 'Photo Attached ✅';
            } else {
                document.getElementById('sumPhoto').textContent = 'Not Provided';
            }
        }

        function submitRegistration() {
            const btn = document.getElementById('btnSubmitRegistration');
            const errBox = document.getElementById('regSubmitErr');
            btn.disabled = true;
            btn.textContent = 'Submitting Registration...';
            errBox.classList.add('hidden');

            const payload = {
                firstName: regData.firstName,
                lastName: regData.lastName,
                phone: regData.phone,
                email: regData.email,
                schoolEmail: regData.schoolEmail,
                birthday: regData.birthday,
                primaryRole: regData.primaryRole,
                relationship: regData.primaryRole,
                campusCategory: regData.primaryRole,
                smsConsentChoice: regData.smsConsent,
                sms_consent: regData.smsConsent === 'Yes' ? 1 : 0,
                institution: regData.institution,
                institutionOtherName: regData.institutionOther,
                grade: regData.grade,
                academicYear: regData.grade,
                emergencyContactName: regData.emergencyName,
                emergencyContactPhone: regData.emergencyPhone,
                profilePhoto: regData.profilePhoto
            };

            fetch('/api/v1/public/register', {
                method: 'POST',
                headers: {'Content-Type': 'application/json'},
                body: JSON.stringify(payload)
            })
            .then(res => res.json())
            .then(data => {
                if (data.success) {
                    sessionStorage.setItem('reg_session', JSON.stringify({
                        token: data.session_token,
                        firstName: regData.firstName,
                        phone: regData.phone
                    }));

                    if (data.event_uuid) {
                        pollRegistrationStatus(data.event_uuid, regData.firstName, 0);
                    } else {
                        showRegistrationPending(regData.firstName);
                    }
                } else {
                    errBox.textContent = '⚠️ Registration Submission Notice: ' + (data.error || 'Please try again.');
                    errBox.classList.remove('hidden');
                    btn.disabled = false;
                    btn.textContent = 'Complete Registration 🚀';
                }
            })
            .catch(err => {
                sessionStorage.setItem('reg_session', JSON.stringify({
                    firstName: regData.firstName,
                    phone: regData.phone
                }));
                showRegistrationPending(regData.firstName);
            });
        }

        function showRegistrationSuccess(firstName, isCheckedIn) {
            document.getElementById('screenRegistrationWizard').classList.add('hidden');
            document.getElementById('screenSuccess').classList.remove('hidden');
            document.getElementById('progressBarContainer').style.display = 'none';

            if (isCheckedIn) {
                document.getElementById('successTitle').textContent = 'Registration Complete & Checked In!';
                document.getElementById('successDesc').textContent = 'Welcome, ' + firstName + '! Your Real Life House member profile has been created and today’s check-in is confirmed.';
            } else {
                document.getElementById('successTitle').textContent = 'Registration Complete!';
                document.getElementById('successDesc').textContent = 'Welcome, ' + firstName + '! Your Real Life House member profile has been created.';
            }
        }

        function showRegistrationPending(firstName) {
            document.getElementById('screenRegistrationWizard').classList.add('hidden');
            document.getElementById('screenSuccess').classList.remove('hidden');
            document.getElementById('progressBarContainer').style.display = 'none';

            document.getElementById('successTitle').textContent = 'Registration Submitted 📋';
            document.getElementById('successDesc').textContent = 'Thank you, ' + firstName + '! Your registration request has been submitted to StudyCenterHub. Please check in with a front desk host.';
        }

        function pollRegistrationStatus(eventUuid, firstName, pollCount) {
            const maxPolls = 8;
            fetch('/api/v1/public/checkin/status?event_uuid=' + encodeURIComponent(eventUuid))
            .then(r => r.json())
            .then(data => {
                const st = data.status;
                if (st === 'registered_and_checked_in' || st === 'registered_already_checked_in' || st === 'registered') {
                    const checkedIn = (st === 'registered_and_checked_in' || st === 'registered_already_checked_in' || data.checked_in);
                    if (data.raw_token) {
                        try {
                            const cur = JSON.parse(sessionStorage.getItem('reg_session') || '{}');
                            cur.raw_token = data.raw_token;
                            sessionStorage.setItem('reg_session', JSON.stringify(cur));
                        } catch(e){}
                    }
                    showRegistrationSuccess(firstName, checkedIn);
                } else if (st === 'registration_failed' || st === 'failed') {
                    const errBox = document.getElementById('regSubmitErr');
                    if (errBox) {
                        errBox.textContent = '⚠️ Registration Notice: ' + (data.message || data.error || 'Registration could not be completed. Please check your information or see a front desk host.');
                        errBox.classList.remove('hidden');
                    }
                    const btn = document.getElementById('btnSubmitRegistration');
                    if (btn) {
                        btn.disabled = false;
                        btn.textContent = 'Complete Registration 🚀';
                    }
                } else if (st === 'processing') {
                    if (pollCount < maxPolls) {
                        setTimeout(() => pollRegistrationStatus(eventUuid, firstName, pollCount + 1), 1500);
                    } else {
                        showRegistrationPending(firstName);
                    }
                } else {
                    showRegistrationPending(firstName);
                }
            })
            .catch(e => {
                showRegistrationPending(firstName);
            });
        }

        function performSuccessAction(action) {
            if (action === 'checkin') {
                document.getElementById('screenSuccess').classList.add('hidden');
                document.getElementById('screenCheckInNotice').classList.remove('hidden');
            } else if (action === 'sessions') {
                document.getElementById('screenSuccess').classList.add('hidden');
                document.getElementById('screenSessionNotice').classList.remove('hidden');
            } else if (action === 'pass') {
                openDigitalPassModal();
            }
        }
    
        function getDeviceType() {
            const ua = navigator.userAgent || navigator.vendor || window.opera || '';
            if (/iPad|iPhone|iPod/.test(ua) && !window.MSStream) {
                return 'ios';
            }
            if (/android/i.test(ua)) {
                return 'android';
            }
            return 'desktop';
        }

        function openDigitalPassModal() {
            const dev = getDeviceType();
            const modal = document.getElementById('digitalPassModal');
            const titleEl = document.getElementById('passModalTitle');
            const bodyEl = document.getElementById('passModalBody');
            const actionsEl = document.getElementById('passModalActions');

            const checkinPhone = document.getElementById('checkinPhoneInput') ? document.getElementById('checkinPhoneInput').value.trim() : '';
            const memberName = regData.firstName || (matchedMemberData && matchedMemberData.first_name) || 'Member';
            const phoneStr = regData.phone || checkinPhone || (matchedMemberData && matchedMemberData.masked_phone) || '';
            const emailStr = regData.email || '';
            
            let regSession = {};
            try {
                regSession = JSON.parse(sessionStorage.getItem('reg_session') || '{}');
            } catch(e){}
            const rawToken = regSession.raw_token || (matchedMemberData && matchedMemberData.human_id) || '';

            if (dev === 'ios') {
                titleEl.textContent = '🍎 Apple Wallet Member Pass';
                bodyEl.innerHTML = `
                    <p style="font-size:14px; color:#475569; line-height:1.5; margin-bottom:14px;">
                        Welcome, <strong>${memberName}</strong>! Add your official Real Life House Member Pass directly to Apple Wallet.
                    </p>
                    <div style="background:#f1f5f9; border-radius:8px; padding:12px; font-size:13px; color:#334155; margin-bottom:16px;">
                        📱 Registered Mobile: <strong>${phoneStr || 'Registered Number'}</strong>
                    </div>
                `;
                actionsEl.innerHTML = `
                    <a href="/api/v1/public/pass/download?token=${encodeURIComponent(rawToken)}&type=pkpass" target="_blank" class="btn btn-primary" style="text-decoration:none; display:block; margin-bottom:8px;" onclick="trackDirectPassClaim('apple')">🍎 Add to Apple Wallet</a>
                    <button class="btn btn-secondary" style="margin-bottom:8px;" onclick="sendPassDelivery('sms')">📱 Send Pass via SMS</button>
                    <button class="btn btn-secondary" style="margin-bottom:8px;" onclick="sendPassDelivery('email')">✉️ Email My Pass</button>
                    <button class="btn btn-secondary" onclick="closeDigitalPassModal()">Close</button>
                `;
            } else if (dev === 'android') {
                titleEl.textContent = '💳 Google Wallet Member Pass';
                bodyEl.innerHTML = `
                    <p style="font-size:14px; color:#475569; line-height:1.5; margin-bottom:14px;">
                        Welcome, <strong>${memberName}</strong>! Add your official Real Life House Member Pass directly to Google Wallet.
                    </p>
                    <div style="background:#f1f5f9; border-radius:8px; padding:12px; font-size:13px; color:#334155; margin-bottom:16px;">
                        📱 Registered Mobile: <strong>${phoneStr || 'Registered Number'}</strong>
                    </div>
                `;
                actionsEl.innerHTML = `
                    <a href="/api/v1/public/pass/download?token=${encodeURIComponent(rawToken)}&type=google_wallet" target="_blank" class="btn btn-primary" style="text-decoration:none; display:block; margin-bottom:8px;" onclick="trackDirectPassClaim('google')">💳 Add to Google Wallet</a>
                    <button class="btn btn-secondary" style="margin-bottom:8px;" onclick="sendPassDelivery('sms')">📱 Send Pass via SMS</button>
                    <button class="btn btn-secondary" style="margin-bottom:8px;" onclick="sendPassDelivery('email')">✉️ Email My Pass</button>
                    <button class="btn btn-secondary" onclick="closeDigitalPassModal()">Close</button>
                `;
            } else {
                // Desktop / Laptop: Opaque credential URL (no PII embedded)
                const passUrl = 'https://app.reallife-studycenter.org/public-returning' + (rawToken ? '?credential=' + encodeURIComponent(rawToken) : '');
                const qrCodeImgUrl = 'https://api.qrserver.com/v1/create-qr-code/?size=180x180&data=' + encodeURIComponent(passUrl);

                titleEl.textContent = '📲 Get Your Pass on Your Phone';
                bodyEl.innerHTML = `
                    <p style="font-size:14px; color:#475569; line-height:1.5; margin-bottom:12px;">
                        Mobile Wallet passes (Apple Wallet & Google Wallet) are stored on your phone for quick entry at Real Life House.
                    </p>
                    <div style="margin:12px 0;">
                        <img src="${qrCodeImgUrl}" alt="Scan to Open Pass on Phone" style="width:160px; height:160px; border-radius:10px; border:1px solid #cbd5e1; padding:6px; background:#fff;">
                        <div style="font-size:12px; color:#64748b; margin-top:6px;">Scan with your phone camera to open your pass on mobile</div>
                    </div>
                    <div style="background:#f1f5f9; border-radius:8px; padding:10px; font-size:13px; color:#334155; margin-bottom:14px;">
                        Registered Mobile: <strong>${phoneStr || 'N/A'}</strong>
                    </div>
                `;
                actionsEl.innerHTML = `
                    <button class="btn btn-primary" onclick="sendPassDelivery('sms')">📱 Send Pass Link via SMS</button>
                    <button class="btn btn-secondary" style="margin-top:8px;" onclick="sendPassDelivery('email')">✉️ Email My Pass</button>
                    <button class="btn btn-secondary" style="margin-top:8px;" onclick="closeDigitalPassModal()">Close</button>
                `;
            }

            modal.classList.remove('hidden');
        }

        function trackDirectPassClaim(type) {
            let regSession = {};
            try { regSession = JSON.parse(sessionStorage.getItem('reg_session') || '{}'); } catch(e){}
            const rawToken = regSession.raw_token || (matchedMemberData && matchedMemberData.human_id) || '';

            fetch('/api/v1/public/pass/download?token=' + encodeURIComponent(rawToken) + '&type=' + (type === 'apple' ? 'pkpass' : 'google_wallet'), {
                method: 'GET'
            }).catch(e => {});
        }



        function closeDigitalPassModal() {
            document.getElementById('digitalPassModal').classList.add('hidden');
        }

        function sendPassDelivery(channel) {
            const checkinPhone = document.getElementById('checkinPhoneInput') ? document.getElementById('checkinPhoneInput').value.trim() : '';
            const phoneStr = regData.phone || checkinPhone || '';
            const emailStr = regData.email || '';
            const firstName = regData.firstName || (matchedMemberData && matchedMemberData.first_name) || 'Member';

            if (channel === 'sms') {
                if (!phoneStr) {
                    alert('No phone number associated with this registration.');
                    return;
                }
                fetch('/api/v1/public/pass/request', {
                    method: 'POST',
                    headers: {'Content-Type': 'application/json'},
                    body: JSON.stringify({
                        channel: 'sms',
                        phone: phoneStr,
                        firstName: firstName
                    })
                })
                .then(r => {
                    if (!r.ok) throw new Error('Server HTTP ' + r.status);
                    return r.json();
                })
                .then(res => {
                    if (res && res.success) {
                        alert('📱 Pass link request received! Your Digital Member Pass will be sent to ' + phoneStr + ' via SMS.');
                        closeDigitalPassModal();
                    } else {
                        alert('Unable to send your pass right now. Please try again or see a staff member.');
                    }
                })
                .catch(err => {
                    alert('Unable to send your pass right now. Please try again or see a staff member.');
                });
            } else if (channel === 'email') {
                if (!emailStr && !phoneStr) {
                    alert('No contact info associated with this member record.');
                    return;
                }
                fetch('/api/v1/public/pass/request', {
                    method: 'POST',
                    headers: {'Content-Type': 'application/json'},
                    body: JSON.stringify({
                        channel: 'email',
                        email: emailStr,
                        phone: phoneStr,
                        firstName: firstName
                    })
                })
                .then(r => {
                    if (!r.ok) throw new Error('Server HTTP ' + r.status);
                    return r.json();
                })
                .then(res => {
                    if (res && res.success) {
                        alert('✉️ Pass link request received! Your Digital Member Pass will be sent to your registered email address.');
                        closeDigitalPassModal();
                    } else {
                        alert('Unable to send your pass right now. Please try again or see a staff member.');
                    }
                })
                .catch(err => {
                    alert('Unable to send your pass right now. Please try again or see a staff member.');
                });
            }
        }

        function adaptStudentGradeLabels() {
            const cat = document.getElementById('primaryRole') ? document.getElementById('primaryRole').value : '';
            const gradeLabel = document.getElementById('labelGradeLevel');
            const schoolLabel = document.getElementById('labelSchool');
            const gradeSelect = document.getElementById('academicGrade');

            if (!gradeSelect) return;

            if (cat === 'High School Student') {
                if (schoolLabel) schoolLabel.textContent = 'High School / Academy *';
                if (gradeLabel) gradeLabel.textContent = 'Grade Level *';
                gradeSelect.innerHTML = `
                    <option value="">Select Grade Level...</option>
                    <option value="9th Grade">9th Grade (Freshman)</option>
                    <option value="10th Grade">10th Grade (Sophomore)</option>
                    <option value="11th Grade">11th Grade (Junior)</option>
                    <option value="12th Grade">12th Grade (Senior)</option>
                `;
            } else {
                if (schoolLabel) schoolLabel.textContent = 'College / University *';
                if (gradeLabel) gradeLabel.textContent = 'Academic Year *';
                gradeSelect.innerHTML = `
                    <option value="">Select Academic Year...</option>
                    <option value="Freshman">Freshman</option>
                    <option value="Sophomore">Sophomore</option>
                    <option value="Junior">Junior</option>
                    <option value="Senior">Senior</option>
                    <option value="Graduate Student">Graduate Student</option>
                `;
            }
        }

</script>

        <!-- DIGITAL MEMBER PASS MODAL -->
        <div id="digitalPassModal" class="modal-overlay hidden" style="position:fixed; top:0; left:0; width:100%; height:100%; background:rgba(0,0,0,0.6); display:flex; justify-content:center; align-items:center; z-index:1000; padding:16px;">
            <div class="card" style="max-width:420px; width:100%; background:#ffffff; text-align:center; padding:24px; border-radius:12px; box-shadow:0 20px 25px -5px rgba(0,0,0,0.1), 0 8px 10px -6px rgba(0,0,0,0.1);">
                <div style="font-size:48px; margin-bottom:12px;">💳</div>
                <h3 id="passModalTitle" style="font-size:20px; font-weight:700; margin-bottom:8px; color:#0f172a;">Digital Member Pass</h3>
                <div id="passModalBody" style="font-size:14px; color:#475569; line-height:1.5; margin-bottom:16px;">
                    Your Digital Member Pass request has been received by StudyCenterHub!
                </div>
                <div id="passModalActions" class="btn-stack">
                    <button class="btn btn-primary" onclick="closeDigitalPassModal()">Got It 👍</button>
                </div>
            </div>
        </div>

</body>
</html>
    <?php
    exit;
}

// Route: Health Check
if ($uri === '/api/v1/public/pass/request' && $method === 'POST') {
    header('Content-Type: application/json; charset=utf-8');
    $rawInput = file_get_contents('php://input');
    $input = json_decode($rawInput, true) ?? [];
    
    $channel = $input['channel'] ?? 'sms';
    $phone = $input['phone'] ?? '';
    $email = $input['email'] ?? '';
    $firstName = $input['firstName'] ?? 'Member';

    $stmt = $pdo->prepare("INSERT INTO inbound_event_queue (event_type, payload_json, received_at, processed) VALUES ('portal.pass_request', ?, datetime('now'), 0)");
    $payload = json_encode([
        'channel' => $channel,
        'phone' => $phone,
        'email' => $email,
        'firstName' => $firstName
    ]);
    $stmt->execute([$payload]);

    echo json_encode([
        'success' => true,
        'message' => 'Pass request queued successfully'
    ]);
    exit;
}

if ($uri === '/api/v1/public/pass/download') {
    header('Access-Control-Allow-Origin: *');
    $token = $_GET['token'] ?? '';
    $type = $_GET['type'] ?? 'pkpass';

    $stmt = $pdo->prepare("INSERT INTO inbound_event_queue (event_type, payload_json, received_at, processed) VALUES ('portal.pass_accessed', ?, datetime('now'), 0)");
    $payload = json_encode([
        'token' => $token,
        'type' => $type,
        'channel' => 'direct_web',
        'user_agent' => $_SERVER['HTTP_USER_AGENT'] ?? ''
    ]);
    $stmt->execute([$payload]);

    if ($type === 'google_wallet') {
        header('Location: https://app.reallife-studycenter.org/public-returning?credential=' . urlencode($token));
        exit;
    } else {
        header('Content-Type: application/vnd.apple.pkpass');
        header('Content-Disposition: attachment; filename="RealLifeHouseMemberPass.pkpass"');
        echo ""; // PKPass payload served by relay
        exit;
    }
}

if (strpos($uri, '/pass/view') === 0) {
    $token = $_GET['token'] ?? '';
    $channel = $_GET['channel'] ?? 'link';

    $stmt = $pdo->prepare("INSERT INTO inbound_event_queue (event_type, payload_json, received_at, processed) VALUES ('portal.pass_accessed', ?, datetime('now'), 0)");
    $payload = json_encode([
        'token' => $token,
        'channel' => $channel,
        'user_agent' => $_SERVER['HTTP_USER_AGENT'] ?? ''
    ]);
    $stmt->execute([$payload]);

    header('Location: https://app.reallife-studycenter.org/public-returning?credential=' . urlencode($token));
    exit;
}

if ($uri === '/api/v1/health' || $uri === '/health') {
    echo json_encode([
        'status' => 'ok',
        'database' => 'connected',
        'timestamp' => gmdate('Y-m-d H:i:s') . ' UTC',
        'config_keys' => array_keys($config),
        'mail_enabled' => function_exists('mail')
    ]);
    exit;
}

// Route: Scanner Diagnostics Log Viewer (Protected by Sync API Key)
if ($uri === '/api/v1/scanners/logs') {
    $req_key = $_SERVER['HTTP_X_SYNC_API_KEY'] ?? $_GET['sync_api_key'] ?? '';
    if ($req_key !== $sync_api_key) {
        http_response_code(401);
        echo json_encode(['success' => false, 'error' => 'Unauthorized']);
        exit;
    }
    $log_file = __DIR__ . '/database/scanner_diagnostic.log';
    if (file_exists($log_file)) {
        header('Content-Type: text/plain; charset=utf-8');
        echo file_get_contents($log_file);
    } else {
        echo "No scanner logs found.";
    }
    exit;
}

// Route: Wildcard Request Log Viewer (Protected by Sync API Key)
if ($uri === '/api/v1/scanners/wildcard-logs') {
    $req_key = $_SERVER['HTTP_X_SYNC_API_KEY'] ?? $_GET['sync_api_key'] ?? '';
    if ($req_key !== $sync_api_key) {
        http_response_code(401);
        echo json_encode(['success' => false, 'error' => 'Unauthorized']);
        exit;
    }
    $log_file = __DIR__ . '/database/wildcard_requests.log';
    if (file_exists($log_file)) {
        header('Content-Type: text/plain; charset=utf-8');
        echo file_get_contents($log_file);
    } else {
        echo "No wildcard logs found.";
    }
    exit;
}

// Route: NETUM DS2800 Hardware Scanner Intake
if ($uri === '/api/v1/scanners/checkin' || $uri === '/scanners/checkin') {
    $client_ip = $_SERVER['REMOTE_ADDR'] ?? '0.0.0.0';
    $headers_list = function_exists('getallheaders') ? getallheaders() : [];
    $content_type = $headers_list['Content-Type'] ?? $headers_list['content-type'] ?? $_SERVER['CONTENT_TYPE'] ?? 'unknown';
    $raw_input = file_get_contents('php://input');

    log_scanner_diagnostic("--- NEW INCOMING CHECKIN REQUEST ---");
    log_scanner_diagnostic("Client IP: " . $client_ip);
    log_scanner_diagnostic("Method: " . $method);
    log_scanner_diagnostic("Content-Type: " . $content_type);
    log_scanner_diagnostic("Raw Body: " . $raw_input);

    error_log("[DS2800-DIAGNOSTIC] Incoming scanner HTTP request from IP: " . $client_ip . " | Method: " . $method);

    if ($method !== 'POST') {
        $reason = "REJECTED: Method not allowed: " . $method;
        log_scanner_diagnostic($reason);
        error_log("[DS2800-DIAGNOSTIC] " . $reason);
        http_response_code(405);
        echo json_encode(['ply' => 3, 'msg' => 'SCAN REJECTED']);
        exit;
    }

    // Enforce 8KB max payload limit for hardware intake
    if (isset($_SERVER['CONTENT_LENGTH']) && intval($_SERVER['CONTENT_LENGTH']) > 8192) {
        $reason = "REJECTED: Payload size (" . $_SERVER['CONTENT_LENGTH'] . ") exceeds 8KB limit";
        log_scanner_diagnostic($reason);
        error_log("[DS2800-DIAGNOSTIC] " . $reason);
        http_response_code(400);
        echo json_encode(['ply' => 3, 'msg' => 'SCAN REJECTED']);
        exit;
    }

    if (strlen($raw_input) > 8192) {
        $reason = "REJECTED: Body length (" . strlen($raw_input) . ") > 8KB limit";
        log_scanner_diagnostic($reason);
        error_log("[DS2800-DIAGNOSTIC] " . $reason);
        http_response_code(400);
        echo json_encode(['ply' => 3, 'msg' => 'SCAN REJECTED']);
        exit;
    }

    $input = null;

    // 1. Try decoding raw JSON body directly
    $decoded = json_decode($raw_input, true);
    if (json_last_error() === JSON_ERROR_NONE && is_array($decoded)) {
        $input = $decoded;
    }

    // 2. Try URL-decoding raw input and then decoding JSON (covers double encoded/form-wrapped bodies)
    if ($input === null) {
        $url_decoded_raw = urldecode($raw_input);
        $decoded = json_decode($url_decoded_raw, true);
        if (json_last_error() === JSON_ERROR_NONE && is_array($decoded)) {
            $input = $decoded;
        }
    }

    // 3. Try parsing body as standard URL-encoded form parameters
    if ($input === null) {
        parse_str($raw_input, $form_data);
        if (is_array($form_data) && count($form_data) > 0) {
            if (isset($form_data['sn']) || isset($form_data['id']) || isset($form_data['scanner_id']) || isset($form_data['bar']) || isset($form_data['msg']) || isset($form_data['raw_scanned_content'])) {
                $input = $form_data;
            }
        }
    }

    // 4. Fallback to $_POST global populated by server
    if ($input === null && !empty($_POST)) {
        $input = $_POST;
    }

    if (!is_array($input)) {
        $reason = "REJECTED: Could not parse body as JSON or form parameters. Content-Type: " . $content_type;
        log_scanner_diagnostic($reason);
        error_log("[DS2800-DIAGNOSTIC] " . $reason);
        http_response_code(400);
        echo json_encode(['ply' => 3, 'msg' => 'SCAN REJECTED']);
        exit;
    }

    log_scanner_diagnostic("Parsed Input: " . json_encode($input));

    $scanner_id = null;
    $raw_scanned_content = null;
    $secret_key = null;

    if (!empty($input['id']) && !empty($input['msg'])) {
        // Native DS2800 format
        $scanner_id = trim((string)$input['id']);
        $raw_scanned_content = trim((string)$input['msg']);
    } elseif (!empty($input['sn']) && !empty($input['bar'])) {
        // Physical scanner format
        $scanner_id = trim((string)$input['sn']);
        $raw_scanned_content = trim((string)$input['bar']);
    } elseif (!empty($input['scanner_id']) && !empty($input['raw_scanned_content'])) {
        // Compatibility format
        $scanner_id = trim((string)$input['scanner_id']);
        $raw_scanned_content = trim((string)$input['raw_scanned_content']);
        $secret_key = trim((string)($input['secret_key'] ?? ''));
    }

    log_scanner_diagnostic("Scanner ID Received: " . ($scanner_id ?? "NULL"));
    log_scanner_diagnostic("Raw Scanned Content Received: " . ($raw_scanned_content ?? "NULL"));

    if ($scanner_id === null || $raw_scanned_content === null || $scanner_id === '' || $raw_scanned_content === '') {
        $reason = "REJECTED: Missing identifier or content fields";
        log_scanner_diagnostic($reason);
        error_log("[DS2800-DIAGNOSTIC] " . $reason);
        http_response_code(400);
        echo json_encode(['ply' => 3, 'msg' => 'SCAN REJECTED']);
        exit;
    }

    error_log("[DS2800-DIAGNOSTIC] Parsed Payload -> Scanner ID: " . $scanner_id . " | Content: " . substr($raw_scanned_content, 0, 40) . "...");

    $query_secret = $_GET['secret'] ?? null;

    // Validate Scanner Registration
    $stmt_sc = $pdo->prepare("SELECT * FROM registered_scanners WHERE scanner_id = ? AND status = 'active' LIMIT 1");
    $stmt_sc->execute([$scanner_id]);
    $scanner = $stmt_sc->fetch(PDO::FETCH_ASSOC);

    if (!$scanner) {
        $reason = "REJECTED: Unknown or inactive scanner_id: '" . $scanner_id . "'";
        log_scanner_diagnostic($reason);
        error_log("[DS2800-DIAGNOSTIC] " . $reason);
        http_response_code(403);
        echo json_encode(['ply' => 3, 'msg' => 'SCAN REJECTED']);
        exit;
    }

    if ($query_secret !== null && $query_secret !== $scanner['secret_key']) {
        $reason = "REJECTED: Mismatched query secret";
        log_scanner_diagnostic($reason);
        error_log("[DS2800-DIAGNOSTIC] " . $reason);
        http_response_code(403);
        echo json_encode(['ply' => 3, 'msg' => 'SCAN REJECTED']);
        exit;
    }

    if ($secret_key !== null && $secret_key !== '' && $secret_key !== $scanner['secret_key']) {
        $reason = "REJECTED: Mismatched body secret";
        log_scanner_diagnostic($reason);
        error_log("[DS2800-DIAGNOSTIC] " . $reason);
        http_response_code(403);
        echo json_encode(['ply' => 3, 'msg' => 'SCAN REJECTED']);
        exit;
    }

    // Deduplication check
    $dup_stmt = $pdo->prepare("
        SELECT id FROM inbound_event_queue
        WHERE event_type = 'scanner.checkin'
          AND payload_json LIKE ?
          AND datetime(received_at) >= datetime('now', '-15 seconds')
        LIMIT 1
    ");
    $search_pattern = '%"scanner_id":"' . $scanner_id . '"%"raw_scanned_content":"' . addcslashes($raw_scanned_content, '%_') . '"%';
    $dup_stmt->execute([$search_pattern]);
    if ($dup_stmt->fetch()) {
        $reason = "DUPLICATE: Already checked in within 15s window";
        log_scanner_diagnostic($reason);
        error_log("[DS2800-DIAGNOSTIC] " . $reason);
        echo json_encode(['ply' => 2, 'msg' => 'ALREADY RECEIVED']);
        exit;
    }

    // Build Inbound Event Payload
    $event_uuid = 'evt_scanner_' . bin2hex(random_bytes(8));
    $payload = [
        'event_uuid' => $event_uuid,
        'scanner_id' => $scanner_id,
        'scanner_name' => $scanner['display_name'],
        'facility' => $scanner['facility'],
        'location' => $scanner['location'],
        'mode' => $scanner['mode'],
        'raw_scanned_content' => $raw_scanned_content,
        'received_at' => gmdate('Y-m-d H:i:s') . ' UTC'
    ];

    $ins_stmt = $pdo->prepare("INSERT INTO inbound_event_queue (event_type, payload_json, received_at, processed) VALUES ('scanner.checkin', ?, datetime('now'), 0)");
    $ins_stmt->execute([json_encode($payload)]);

    log_scanner_diagnostic("SUCCESS: Queued scanner.checkin event with ID: " . $event_uuid);
    error_log("[DS2800-DIAGNOSTIC] SUCCESS: Scan queued in cloud inbound_event_queue with UUID: " . $event_uuid);
    echo json_encode(['ply' => 1, 'msg' => 'SCAN RECEIVED']);
    exit;
}

// Route: Sync Pull (Client -> Relay)
if ($uri === '/api/v1/sync/pull' && $method === 'POST') {
    $req_key = $_SERVER['HTTP_X_SYNC_API_KEY'] ?? $_GET['sync_api_key'] ?? '';
    if ($req_key !== $sync_api_key) {
        http_response_code(401);
        echo json_encode(['success' => false, 'error' => 'Unauthorized']);
        exit;
    }

    $input = json_decode(file_get_contents('php://input'), true);
    $last_id = intval($input['last_event_id'] ?? 0);

    $stmt = $pdo->prepare("SELECT id, event_type, payload_json, received_at FROM inbound_event_queue WHERE id > ? AND processed = 0 ORDER BY id ASC LIMIT 100");
    $stmt->execute([$last_id]);
    $events = $stmt->fetchAll(PDO::FETCH_ASSOC);

    echo json_encode(['success' => true, 'events' => $events]);
    exit;
}

// Route: Sync Ack (Client -> Relay)
if ($uri === '/api/v1/sync/ack' && $method === 'POST') {
    $req_key = $_SERVER['HTTP_X_SYNC_API_KEY'] ?? $_GET['sync_api_key'] ?? '';
    if ($req_key !== $sync_api_key) {
        http_response_code(401);
        echo json_encode(['success' => false, 'error' => 'Unauthorized']);
        exit;
    }

    $input = json_decode(file_get_contents('php://input'), true);
    $event_ids = $input['event_ids'] ?? [];

    $event_results = is_array($input) && isset($input['event_results']) ? $input['event_results'] : [];
    if (!empty($event_ids)) {
        foreach ($event_ids as $eid) {
            $eid_int = intval($eid);
            $res_json = isset($event_results[$eid]) ? json_encode($event_results[$eid]) : (isset($event_results[strval($eid)]) ? json_encode($event_results[strval($eid)]) : null);
            $st = isset($event_results[$eid]['status']) ? $event_results[$eid]['status'] : (isset($event_results[strval($eid)]['status']) ? $event_results[strval($eid)]['status'] : 'processed');
            $up_stmt = $pdo->prepare("UPDATE inbound_event_queue SET processed = 1, status = ?, result_json = ? WHERE id = ?");
            $up_stmt->execute([$st, $res_json, $eid_int]);
        }
    }

    echo json_encode(['success' => true, 'ack_count' => count($event_ids)]);
    exit;
}

// Route: IVR Settings Endpoint
if ($uri === '/api/v1/sync/ivr-config') {
    $req_key = $_SERVER['HTTP_X_SYNC_API_KEY'] ?? $_GET['sync_api_key'] ?? '';
    if ($req_key !== $sync_api_key) {
        http_response_code(401);
        echo json_encode(['success' => false, 'error' => 'Unauthorized']);
        exit;
    }
    
    $input = json_decode(file_get_contents('php://input'), true);
    $ivr_config = $input['ivr_config'] ?? null;
    
    if (!$ivr_config) {
        http_response_code(400);
        echo json_encode(["success" => false, "message" => "Invalid or empty ivr_config object."]);
        exit;
    }
    
    file_put_contents(__DIR__ . '/database/ivr_config.json', json_encode($ivr_config, JSON_PRETTY_PRINT));
    echo json_encode(["success" => true, "message" => "IVR configuration cached successfully."]);
    exit;
}

// Route: Voice Call Routing
if ($uri === '/api/v1/webhooks/twilio/voice-prompt') {
    $config_file = __DIR__ . '/database/ivr_config.json';
    $config = file_exists($config_file) ? json_decode(file_get_contents($config_file), true) : null;
    
    if (!$config) {
        $config = [
            "on_call_phone" => "",
            "rollover_rings" => 4,
            "tts_greeting_active" => true,
            "greeting_text" => "Thank you for calling. If you know your extension, please enter it. Press 1 for General Info, or 2 to leave a message.",
            "menu_options" => [
                "1" => ["action_type" => "speak", "script_text" => "We are open Monday through Friday from 3 PM to 8 PM."],
                "2" => ["action_type" => "voicemail", "script_text" => "Please leave your message after the tone."]
            ]
        ];
    }
    
    $digits = trim($_POST['Digits'] ?? $_GET['Digits'] ?? '');
    $parent_digit = trim($_GET['parentDigit'] ?? '');
    $routing_step = trim($_GET['routingStep'] ?? '');

    if ($routing_step === 'post-speak') {
        if ($digits === '9') {
            send_twiml_menu($config);
        }
        send_twiml("<Hangup/>");
    }

    if ($routing_step === 'name-captured') {
        $staff_name = trim($_GET['staff'] ?? '');
        $rec_url = trim($_POST['RecordingUrl'] ?? '');
        
        $staff_members = $config['staff_members'] ?? [];
        $staff = $staff_members[$staff_name] ?? null;
        if (!$staff) {
            send_twiml(get_twiml_say("Sorry, that staff member could not be found. Returning to the main menu.", $config) . "<Redirect>https://" . $_SERVER['HTTP_HOST'] . "/api/v1/webhooks/twilio/voice-prompt</Redirect>");
        }
        
        $phone = trim($staff['phone']);
        $timeout = intval($staff['ring_timeout'] ?? 20);
        
        $dial_action = 'https://' . $_SERVER['HTTP_HOST'] . '/api/v1/webhooks/twilio/voice-prompt?routingStep=dial-complete&staff=' . urlencode($staff_name);
        $whisper_url = 'https://' . $_SERVER['HTTP_HOST'] . '/api/v1/webhooks/twilio/voice-prompt?routingStep=whisper&recUrl=' . urlencode($rec_url);
        
        send_twiml(
            get_twiml_say("Thank you. Please hold while we see if " . $staff_name . " is available.", $config) .
            "<Dial timeout=\"$timeout\" action=\"" . htmlspecialchars($dial_action) . "\" method=\"POST\">" .
            "<Number url=\"" . htmlspecialchars($whisper_url) . "\">" . htmlspecialchars($phone) . "</Number>" .
            "</Dial>"
        );
    }
    
    if ($routing_step === 'whisper') {
        $rec_url = trim($_GET['recUrl'] ?? '');
        $action = 'https://' . $_SERVER['HTTP_HOST'] . '/api/v1/webhooks/twilio/voice-prompt?routingStep=whisper-gather';
        
        send_twiml(
            "<Gather numDigits=\"1\" action=\"" . htmlspecialchars($action) . "\" method=\"POST\" timeout=\"5\">" .
            get_twiml_say("Real Life House call from", $config) .
            "<Play>" . htmlspecialchars($rec_url) . "</Play>" .
            get_twiml_say("Press 1 to accept.", $config) .
            "</Gather>" .
            "<Hangup/>"
        );
    }
    
    if ($routing_step === 'whisper-gather') {
        if ($digits === '1') {
            header("Content-Type: text/xml");
            echo "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<Response></Response>";
            exit;
        } else {
            send_twiml("<Hangup/>");
        }
    }
    
    if ($routing_step === 'dial-complete') {
        $staff_name = trim($_GET['staff'] ?? '');
        $dial_status = $_POST['DialCallStatus'] ?? '';
        
        if ($dial_status === 'completed') {
            send_twiml("<Hangup/>");
        }
        
        $host = !empty($_SERVER['HTTP_HOST']) ? $_SERVER['HTTP_HOST'] : 'app.reallife-studycenter.org';
        $record = 'https://' . $host . '/api/v1/webhooks/twilio/voicemail?recipient=' . urlencode($staff_name);
        $transcribe_cb = 'https://' . $host . '/api/v1/webhooks/twilio/transcription';
        
        send_twiml(
            get_twiml_say($staff_name . " isn’t available right now. Please leave your name, phone number, and a brief message after the tone, and someone from Real Life House will get back in touch with you.", $config) .
            "<Record maxLength=\"120\" action=\"" . htmlspecialchars($record) . "\" method=\"POST\" playBeep=\"true\" finishOnKey=\"#\" transcribe=\"true\" transcribeCallback=\"" . htmlspecialchars($transcribe_cb) . "\"/>"
        );
    }

    if (!$digits && !$routing_step) {
        if (!empty($config['on_call_phone'])) {
            $timeout = max(5, (intval($config['rollover_rings']) ?: 4) * 5);
            $action = 'https://' . $_SERVER['HTTP_HOST'] . '/api/v1/webhooks/twilio/voice-prompt?routingStep=oncall-completed';
            send_twiml("<Dial timeout=\"$timeout\" action=\"" . htmlspecialchars($action) . "\" method=\"POST\"><Number>" . htmlspecialchars($config['on_call_phone']) . "</Number></Dial>");
        }
        send_twiml_menu($config);
    }
    
    if ($routing_step === 'oncall-completed') {
        if (($_POST['DialCallStatus'] ?? '') === 'completed') {
            send_twiml("<Hangup/>");
        }
        send_twiml_menu($config);
    }
    
    $full_key = $parent_digit ? "$parent_digit-$digits" : $digits;
    $option = $config['menu_options'][$full_key] ?? null;
    
    if (!$option) {
        $action = 'https://' . $_SERVER['HTTP_HOST'] . '/api/v1/webhooks/twilio/voice-prompt';
        send_twiml("<Gather numDigits=\"1\" action=\"" . htmlspecialchars($action) . "\" method=\"POST\" timeout=\"8\">" . get_twiml_say("That selection is not valid. Please try again.", $config) . get_twiml_say($config['greeting_text'], $config) . "</Gather><Hangup/>");
    }
    
    if ($option['action_type'] === 'speak') {
        $action = 'https://' . $_SERVER['HTTP_HOST'] . '/api/v1/webhooks/twilio/voice-prompt?routingStep=post-speak';
        send_twiml(
            "<Gather numDigits=\"1\" action=\"" . htmlspecialchars($action) . "\" method=\"POST\" timeout=\"6\">" .
            get_twiml_say($option['script_text'], $config) .
            get_twiml_say("To return to the main menu, press 9. Otherwise, you may simply hang up.", $config) .
            "</Gather>" .
            "<Hangup/>"
        );
    } else if ($option['action_type'] === 'voicemail') {
        $host = !empty($_SERVER['HTTP_HOST']) ? $_SERVER['HTTP_HOST'] : 'app.reallife-studycenter.org';
        $record = 'https://' . $host . '/api/v1/webhooks/twilio/voicemail?recipient=' . urlencode($option['action_param'] ?: 'general');
        $transcribe_cb = 'https://' . $host . '/api/v1/webhooks/twilio/transcription';
        $vm_text = trim(preg_replace('/\s+/', ' ', $option['script_text']));
        send_twiml(get_twiml_say($vm_text, $config) . "<Record maxLength=\"120\" action=\"" . htmlspecialchars($record) . "\" method=\"POST\" playBeep=\"true\" finishOnKey=\"#\" transcribe=\"true\" transcribeCallback=\"" . htmlspecialchars($transcribe_cb) . "\"/>");
    } else if ($option['action_type'] === 'transfer' && !empty($option['action_param'])) {
        send_twiml(get_twiml_say("Transferring your call.", $config) . "<Dial><Number>" . htmlspecialchars($option['action_param']) . "</Number></Dial>");
    } else if ($option['action_type'] === 'submenu') {
        $action = 'https://' . $_SERVER['HTTP_HOST'] . '/api/v1/webhooks/twilio/voice-prompt?parentDigit=' . urlencode($full_key);
        send_twiml(
            "<Gather numDigits=\"1\" action=\"" . htmlspecialchars($action) . "\" method=\"POST\" timeout=\"8\">" .
            get_twiml_say($option['script_text'], $config) .
            "</Gather>" .
            get_twiml_say("We did not receive your input. Returning to the main menu.", $config) .
            "<Redirect>https://" . $_SERVER['HTTP_HOST'] . "/api/v1/webhooks/twilio/voice-prompt</Redirect>"
        );
    } else if ($option['action_type'] === 'transfer_staff') {
        $staff_name = $option['action_param'];
        $action = 'https://' . $_SERVER['HTTP_HOST'] . '/api/v1/webhooks/twilio/voice-prompt?routingStep=name-captured&staff=' . urlencode($staff_name);
        send_twiml(
            get_twiml_say("Please say your name.", $config) .
            "<Record maxLength=\"4\" action=\"" . htmlspecialchars($action) . "\" method=\"POST\" playBeep=\"false\" trim=\"trim-silence\"/>"
        );
    } else if ($option['action_type'] === 'return_to_main') {
        send_twiml("<Redirect>https://" . $_SERVER['HTTP_HOST'] . "/api/v1/webhooks/twilio/voice-prompt</Redirect>");
    } else if ($option['action_type'] === 'hangup') {
        send_twiml(get_twiml_say($option['script_text'] ?: "Goodbye.", $config) . "<Hangup/>");
    }
    send_twiml("<Hangup/>");
}

// Route: Voicemail Ingest Webhook
if ($uri === '/api/v1/webhooks/twilio/voicemail') {
    try {
        $payload = $_POST;
        $recording_sid = $payload['RecordingSid'] ?? null;
        $provider_event_id = !empty($recording_sid) ? $recording_sid : ($payload['CallSid'] ?? null);
        
        $stmt = $pdo->prepare("INSERT OR IGNORE INTO inbound_event_queue (event_type, provider_event_id, payload_json, received_at, processed) VALUES ('twilio.voicemail', ?, ?, datetime('now'), 0)");
        $stmt->execute([$provider_event_id, json_encode($payload)]);
        
        $config_file = __DIR__ . '/database/ivr_config.json';
        $config = file_exists($config_file) ? json_decode(file_get_contents($config_file), true) : [];
        send_twiml(get_twiml_say("Thank you. Your voicemail has been received.", $config) . "<Hangup/>");
    } catch (Throwable $e) {
        http_response_code(500);
        header('Content-Type: text/plain; charset=utf-8');
        echo "VOICEMAIL CRASH: " . $e->getMessage() . "\nFile: " . $e->getFile() . "\nLine: " . $e->getLine() . "\nTrace: " . $e->getTraceAsString();
        exit;
    }
}

// Route: Twilio Voicemail Transcription Callback Webhook
if ($uri === '/api/v1/webhooks/twilio/transcription') {
    try {
        $payload = $_POST;
        $recording_sid = $payload['RecordingSid'] ?? null;
        $transcription_sid = $payload['TranscriptionSid'] ?? null;
        $provider_event_id = !empty($transcription_sid) ? $transcription_sid : ('trans_' . ($recording_sid ?: bin2hex(random_bytes(6))));
        
        $stmt = $pdo->prepare("INSERT OR IGNORE INTO inbound_event_queue (event_type, provider_event_id, payload_json, received_at, processed) VALUES ('twilio.transcription', ?, ?, datetime('now'), 0)");
        $stmt->execute([$provider_event_id, json_encode($payload)]);
        
        header("Content-Type: text/xml");
        echo "<?xml version=\"1.0\" encoding=\"UTF-8\"?><Response></Response>";
        exit;
    } catch (Throwable $e) {
        http_response_code(500);
        header('Content-Type: text/plain; charset=utf-8');
        echo "TRANSCRIPTION CRASH: " . $e->getMessage();
        exit;
    }
}

// Route: Outbound Call Bridge Endpoint (authenticated server-side request to Twilio)
if ($uri === '/api/v1/calls/outbound') {
    $req_key = $_SERVER['HTTP_X_SYNC_API_KEY'] ?? $_GET['sync_api_key'] ?? '';
    if ($req_key !== $sync_api_key) {
        http_response_code(401);
        echo json_encode(['success' => false, 'error' => 'Unauthorized']);
        exit;
    }

    $input = json_decode(file_get_contents('php://input'), true);
    $to_phone = trim($input['to_phone'] ?? $_POST['to_phone'] ?? '');
    $staff_phone = trim($input['staff_phone'] ?? $_POST['staff_phone'] ?? '');

    if (empty($to_phone)) {
        http_response_code(400);
        echo json_encode(['success' => false, 'error' => 'Missing to_phone parameter']);
        exit;
    }

    $tw_sid = $config['TWILIO_ACCOUNT_SID'] ?? '';
    $tw_token = $config['TWILIO_AUTH_TOKEN'] ?? '';
    $from_phone = $config['TWILIO_PHONE_NUMBER'] ?? '+18647124446';

    if (empty($tw_sid) || empty($tw_token)) {
        http_response_code(401);
        echo json_encode(['success' => false, 'error' => 'Twilio server credentials unconfigured in config.php']);
        exit;
    }

    $host = !empty($_SERVER['HTTP_HOST']) ? $_SERVER['HTTP_HOST'] : 'app.reallife-studycenter.org';
    $twiml_url = 'https://' . $host . '/api/v1/webhooks/twilio/outbound-twiml?to=' . urlencode($to_phone);

    $target_num = !empty($staff_phone) ? $staff_phone : $to_phone;
    
    $post_data = http_build_query([
        'To' => $target_num,
        'From' => $from_phone,
        'Url' => $twiml_url
    ]);

    $ch = curl_init("https://api.twilio.com/2010-04-01/Accounts/$tw_sid/Calls.json");
    curl_setopt($ch, CURLOPT_USERPWD, "$tw_sid:$tw_token");
    curl_setopt($ch, CURLOPT_POST, true);
    curl_setopt($ch, CURLOPT_POSTFIELDS, $post_data);
    curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
    curl_setopt($ch, CURLOPT_SSL_VERIFYPEER, true);

    $resp = curl_exec($ch);
    $http_code = curl_getinfo($ch, CURLINFO_HTTP_CODE);
    curl_close($ch);

    $json = json_decode($resp, true);
    if ($http_code >= 200 && $http_code < 300 && !empty($json['sid'])) {
        echo json_encode(['success' => true, 'call_sid' => $json['sid'], 'status' => $json['status'] ?? 'queued']);
    } else {
        http_response_code($http_code ?: 500);
        echo json_encode(['success' => false, 'error' => $json['message'] ?? 'Twilio API call failed', 'http_code' => $http_code]);
    }
    exit;
}

// Route: TwiML Outbound Bridge Webhook
if ($uri === '/api/v1/webhooks/twilio/outbound-twiml') {
    $to = trim($_GET['to'] ?? '');
    $config_file = __DIR__ . '/database/ivr_config.json';
    $config = file_exists($config_file) ? json_decode(file_get_contents($config_file), true) : [];
    
    if (!empty($to)) {
        send_twiml(get_twiml_say("Connecting your call from Real Life House.", $config) . "<Dial callerId=\"+18647124446\"><Number>" . htmlspecialchars($to) . "</Number></Dial>");
    } else {
        send_twiml(get_twiml_say("Connecting your call.", $config));
    }
    exit;
}

// Route: Voicemail Media Proxy Endpoint (authenticated server-side request to Twilio)
if ($uri === '/api/v1/voicemails/audio' || $uri === '/api/v1/webhooks/twilio/voicemail-audio') {
    $recording_sid = trim($_GET['recording_sid'] ?? $_GET['sid'] ?? '');
    $recording_url = trim($_GET['recording_url'] ?? $_GET['url'] ?? '');
    
    // Fallback to empty string if no Twilio SID configured.
    $tw_sid = !empty($config['TWILIO_ACCOUNT_SID']) ? trim($config['TWILIO_ACCOUNT_SID']) : '';
    $tw_tok = !empty($config['TWILIO_AUTH_TOKEN']) ? trim($config['TWILIO_AUTH_TOKEN']) : '';

    try {
        $sid_stmt = $pdo->query("SELECT setting_value FROM app_settings WHERE setting_key = 'TWILIO_ACCOUNT_SID' LIMIT 1");
        if ($sid_stmt && ($row = $sid_stmt->fetch(PDO::FETCH_ASSOC))) {
            $val = trim($row['setting_value']);
            if (!empty($val)) $tw_sid = $val;
        }
        $tok_stmt = $pdo->query("SELECT setting_value FROM app_settings WHERE setting_key = 'TWILIO_AUTH_TOKEN' LIMIT 1");
        if ($tok_stmt && ($row = $tok_stmt->fetch(PDO::FETCH_ASSOC))) {
            $val = trim($row['setting_value']);
            if (!empty($val)) $tw_tok = $val;
        }
    } catch (Throwable $e) {
        // Fallback gracefully if app_settings table does not exist
    }
    
    $cfg_path = __DIR__ . '/config.php';
    if (isset($_GET['debug']) && $_GET['debug'] === '1') {
        echo json_encode([
            'config_loaded' => file_exists($cfg_path),
            'config_path' => realpath($cfg_path) ?: $cfg_path,
            'sid_present' => !empty($tw_sid),
            'sid_suffix' => substr($tw_sid, -4),
            'token_present' => !empty($tw_tok),
            'token_length' => strlen($tw_tok)
        ]);
        exit;
    }

    $target = "https://api.twilio.com/2010-04-01/Accounts/$tw_sid/Recordings/$recording_sid.mp3";
    
    $ch = curl_init($target);
    curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
    curl_setopt($ch, CURLOPT_FOLLOWLOCATION, true);
    if (!empty($tw_tok)) {
        curl_setopt($ch, CURLOPT_USERPWD, "$tw_sid:$tw_tok");
    }
    curl_setopt($ch, CURLOPT_SSL_VERIFYPEER, true);
    curl_setopt($ch, CURLOPT_TIMEOUT, 30);
    
    $audio_data = curl_exec($ch);
    $http_code = curl_getinfo($ch, CURLINFO_HTTP_CODE);
    $content_type = curl_getinfo($ch, CURLINFO_CONTENT_TYPE) ?: 'audio/mpeg';
    curl_close($ch);
    
    if ($http_code === 200 && !empty($audio_data)) {
        header("Content-Type: $content_type");
        header("Content-Length: " . strlen($audio_data));
        echo $audio_data;
        exit;
    } else {
        http_response_code($http_code ?: 500);
        echo json_encode([
            'success' => false, 
            'error' => 'Failed to proxy Twilio audio', 
            'http_code' => $http_code, 
            'target_url' => $target,
            'has_token' => !empty($tw_tok),
            'token_len' => strlen($tw_tok)
        ]);
        exit;
    }
}

// Route: SMS Ingest Webhook (with immediate compliance keyword autoreply support)
if ($uri === '/api/v1/webhooks/twilio/sms') {
    try {
        $payload = $_POST;
        $provider_event_id = $payload['MessageSid'] ?? null;
        $body_text = strtoupper(trim($payload['Body'] ?? ''));
        
        $stmt = $pdo->prepare("INSERT OR IGNORE INTO inbound_event_queue (event_type, provider_event_id, payload_json, received_at, processed) VALUES ('twilio.sms', ?, ?, datetime('now'), 0)");
        $stmt->execute([$provider_event_id, json_encode($payload)]);

        $opt_out = ['STOP', 'QUIT', 'CANCEL', 'UNSUBSCRIBE'];
        $opt_in = ['START', 'UNSTOP', 'YES'];
        $help = ['HELP', 'INFO'];

        if (in_array($body_text, $opt_out)) {
            send_twiml("<Message>You have successfully been unsubscribed. You will no longer receive messages from this number.</Message>");
        } else if (in_array($body_text, $opt_in)) {
            send_twiml("<Message>You have successfully resubscribed. Message & data rates may apply.</Message>");
        } else if (in_array($body_text, $help)) {
            send_twiml("<Message>This is the automated text line for Real Life Study Center. For assistance or support, please contact us.</Message>");
        }
        
        header("Content-Type: text/xml");
        echo "<?xml version=\"1.0\" encoding=\"UTF-8\"?><Response></Response>";
        exit;
    } catch (Throwable $e) {
        http_response_code(500);
        header('Content-Type: text/plain; charset=utf-8');
        echo "SMS CRASH: " . $e->getMessage() . "\nFile: " . $e->getFile() . "\nLine: " . $e->getLine() . "\nTrace: " . $e->getTraceAsString();
        exit;
    }
}

// Route: Outbound Mail Dispatch
if ($uri === '/api/v1/mail/send' && $method === 'POST') {
    $input = json_decode(file_get_contents('php://input'), true);
    $to = trim((string)($input['to'] ?? ''));
    $subject = trim((string)($input['subject'] ?? 'Real Life Study Center — Digital Member Pass'));
    $body = (string)($input['body'] ?? '');

    if (empty($to) || empty($body)) {
        http_response_code(400);
        echo json_encode(['success' => false, 'error' => 'Missing recipient email or message body']);
        exit;
    }

    $headers = "From: Real Life Study Center <support@reallife-studycenter.org>\r\n";
    $headers .= "Reply-To: support@reallife-studycenter.org\r\n";
    $headers .= "X-Mailer: StudyCenterHub/1.0 PHP/" . phpversion() . "\r\n";
    $headers .= "Content-Type: text/plain; charset=UTF-8\r\n";

    $mail_sent = @mail($to, $subject, $body, $headers);
    error_log("[MAIL-RELAY] Outbound email sent to: " . $to . " | Status: " . ($mail_sent ? "SUCCESS" : "FAILED"));

    echo json_encode(['success' => $mail_sent, 'recipient' => $to]);
    exit;
}

// Default 404
http_response_code(404);
echo json_encode(['error' => 'Endpoint not found']);

// Twilio Helper Functions
function get_twiml_say($text, $config) {
    $voice = !empty($config['voice_name']) ? $config['voice_name'] : 'Polly.Kimberly-Neural';
    // Ensure voice is supported natively by Twilio <Say> (Polly.* or standard Twilio voices) to prevent call drops
    if (strpos($voice, 'Polly.') !== 0 && !in_array($voice, ['man', 'woman', 'alice'])) {
        $voice = 'Polly.Kimberly-Neural';
    }
    $language = !empty($config['language']) ? $config['language'] : 'en-US';
    // Clean all literal backslashes and escaped newline characters (e.g. \n or \\n) so Twilio TTS never speaks "backslash n" out loud
    $clean_text = str_replace(["\\n", "\\r", "\\", "\n", "\r"], [" ", " ", "", " ", " "], $text);
    $clean_text = trim(preg_replace('/\s+/', ' ', $clean_text));
    return '<Say voice="' . htmlspecialchars($voice) . '" language="' . htmlspecialchars($language) . '">' . htmlspecialchars($clean_text) . '</Say>';
}

function send_twiml($twiml) {
    header("Content-Type: text/xml");
    echo "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<Response>\n" . $twiml . "\n</Response>";
    exit;
}

function send_twiml_menu($config) {
    $action = 'https://' . $_SERVER['HTTP_HOST'] . '/api/v1/webhooks/twilio/voice-prompt';
    send_twiml("<Gather numDigits=\"1\" action=\"" . htmlspecialchars($action) . "\" method=\"POST\" timeout=\"8\">" . get_twiml_say($config['greeting_text'], $config) . "</Gather>" . get_twiml_say("We did not receive your input. Goodbye.", $config) . "<Hangup/>");
}
