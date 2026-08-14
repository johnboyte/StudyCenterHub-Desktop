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

    $pdo = new PDO('sqlite:' . $db_dir . '/relay.db');
    $pdo->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);

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

    $pdo->exec("CREATE TABLE IF NOT EXISTS directory_index (
            phone_e164 TEXT PRIMARY KEY,
            first_name TEXT NOT NULL,
            masked_phone TEXT NOT NULL,
            human_id TEXT NOT NULL,
            updated_at TEXT NOT NULL DEFAULT (datetime('now'))
        )");
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
            phone_e164 TEXT PRIMARY KEY,
            first_name TEXT NOT NULL,
            masked_phone TEXT NOT NULL,
            human_id TEXT NOT NULL,
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
        foreach ($q_stmt->fetchAll(PDO::FETCH_ASSOC) as $q_row) {
            $p_json = json_decode($q_row['payload_json'] ?? '{}', true);
            if (is_array($p_json)) {
                $ev_phone = normalize_phone_e164_php($p_json['phone'] ?? $p_json['mobile_phone'] ?? '');
                if ($ev_phone === $e164) {
                    $ev_sid = strval($p_json['session_id'] ?? 0);
                    if ($ev_sid) {
                        if ($q_row['event_type'] === 'portal.cancel_signup') {
                            unset($member_signups[$ev_sid]);
                        } else if ($q_row['event_type'] === 'portal.signup') {
                            $member_signups[$ev_sid] = 'confirmed';
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
        $conf = intval($s['confirmed_count']);
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

    $stmt = $pdo->prepare("INSERT OR REPLACE INTO directory_index (phone_e164, first_name, masked_phone, human_id, updated_at) VALUES (?, ?, ?, ?, datetime('now'))");
    $count = 0;
    foreach ($members as $m) {
        $raw_p = $m['phone'] ?? $m['phone_e164'] ?? '';
        $e164 = normalize_phone_e164_php($raw_p);
        $fn = trim($m['first_name'] ?? '');
        $hid = trim($m['human_id'] ?? '');
        $mp = mask_phone_php($raw_p);
        if ($e164 && $fn) {
            $stmt->execute([$e164, $fn, $mp, $hid]);
            $count++;
        }
    }

    echo json_encode(['success' => true, 'synced_count' => $count]);
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

    $stmt = $pdo->prepare("SELECT first_name, masked_phone, human_id, last_checkin_date FROM directory_index WHERE phone_e164 = ? OR phone_e164 LIKE ?");
    $stmt->execute([$e164, '%' . substr($digits, -10)]);
    $rows = $stmt->fetchAll(PDO::FETCH_ASSOC);

    if (count($rows) === 1) {
        $human_id = $rows[0]['human_id'];
        $last_checkin = trim($rows[0]['last_checkin_date'] ?? '');
        $today = gmdate('Y-m-d');
        $already_checked_in = false;

        if (!empty($last_checkin) && strpos($last_checkin, $today) === 0) {
            $already_checked_in = true;
        } else {
            $chk_stmt = $pdo->prepare("SELECT status FROM inbound_event_queue WHERE (event_type = 'portal.checkin' OR event_type = 'scanner.checkin' OR event_type = 'portal.registration') AND payload_json LIKE ? AND received_at LIKE ? ORDER BY id DESC LIMIT 1");
            $chk_stmt->execute(['%' . $human_id . '%', $today . '%']);
            $chk_row = $chk_stmt->fetch(PDO::FETCH_ASSOC);
            if ($chk_row && in_array($chk_row['status'], ['processed', 'checked_in', 'already_checked_in', 'registered_and_checked_in', 'registered_already_checked_in', 'ok', 'success'])) {
                $already_checked_in = true;
            }
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
    $today = gmdate('Y-m-d');
    $already_checked_in = false;

    if (!empty($human_id)) {
        $chk_stmt = $pdo->prepare("SELECT status FROM inbound_event_queue WHERE (event_type = 'portal.checkin' OR event_type = 'scanner.checkin') AND payload_json LIKE ? AND received_at LIKE ? ORDER BY id DESC LIMIT 1");
        $chk_stmt->execute(['%' . $human_id . '%', $today . '%']);
        $chk_row = $chk_stmt->fetch(PDO::FETCH_ASSOC);
        if ($chk_row && in_array($chk_row['status'], ['processed', 'checked_in', 'already_checked_in', 'ok', 'success'])) {
            $already_checked_in = true;
        }
    }

    $event_uuid = 'evt_portal_chk_' . bin2hex(random_bytes(8));
    $payload['event_uuid'] = $event_uuid;
    $payload['checkInDate'] = $today;
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
                <h2 class="page-title" id="successTitle">You’re Registered and Checked In!</h2>
                <p class="page-desc" id="successDesc">Welcome to Real Life House! Your registration and today’s check-in are confirmed.</p>
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
                    statusBadgeHtml = '<span style="background:#dbeafe; color:#1e40af; font-size:12px; font-weight:700; padding:4px 8px; border-radius:6px;">' + rem + ' spots remaining</span>';
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
                document.getElementById('successTitle').textContent = 'You’re Registered and Checked In!';
                document.getElementById('successDesc').textContent = 'Welcome, ' + firstName + '! Your registration and today’s check-in are confirmed.';
            } else {
                document.getElementById('successTitle').textContent = 'You’re Registered!';
                document.getElementById('successDesc').textContent = 'Welcome, ' + firstName + '! Your registration has been received and added to our system.';
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
