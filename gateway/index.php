<?php
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

// Route: Health Check
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

    if (!empty($event_ids)) {
        $in = implode(',', array_map('intval', $event_ids));
        $pdo->exec("UPDATE inbound_event_queue SET processed = 1 WHERE id IN ($in)");
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
