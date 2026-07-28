<?php
/**
 * index.php
 * Production Cloud Relay Router & Hardware Scanner Intake Controller.
 * Runs natively on SiteGround (PHP + SQLite PDO).
 */

header('Content-Type: application/json; charset=utf-8');

$config = require __DIR__ . '/config.php';
$sync_api_key = $config['SYNC_API_KEY'] ?? 'SCH_DEFAULT_KEY';

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

// Seed default hardware scanner if empty
$stmt_check = $pdo->query("SELECT COUNT(*) FROM registered_scanners");
if ($stmt_check->fetchColumn() == 0) {
    $pdo->exec("
        INSERT INTO registered_scanners (scanner_id, display_name, facility, location, mode, secret_key, status)
        VALUES ('N324D5G0010', 'NETUM DS2800 Entry Scanner', 'Real Life House', 'Main Entrance', 'Study Center Daily', 'SCH_SCANNER_SECRET_MASKED_N324D5G0010', 'active')
    ");
}

// 2. Parse URI Request Path
$uri = parse_url($_SERVER['REQUEST_URI'], PHP_URL_PATH);
$method = $_SERVER['REQUEST_METHOD'];

// Route: Health Check
if ($uri === '/api/v1/health' || $uri === '/health') {
    echo json_encode([
        'status' => 'ok',
        'database' => 'connected',
        'timestamp' => gmdate('Y-m-d H:i:s') . ' UTC'
    ]);
    exit;
}

// Route: NETUM DS2800 Hardware Scanner Intake
if ($uri === '/api/v1/scanners/checkin' || $uri === '/scanners/checkin') {
    $client_ip = $_SERVER['REMOTE_ADDR'] ?? '0.0.0.0';
    error_log("[DS2800-DIAGNOSTIC] Incoming scanner HTTP request from IP: " . $client_ip . " | Method: " . $method);

    if ($method !== 'POST') {
        error_log("[DS2800-DIAGNOSTIC] REJECTED: Method not allowed: " . $method);
        http_response_code(405);
        echo json_encode(['ply' => 3, 'msg' => 'SCAN REJECTED']);
        exit;
    }

    // Enforce 8KB max payload limit for hardware intake
    if (isset($_SERVER['CONTENT_LENGTH']) && intval($_SERVER['CONTENT_LENGTH']) > 8192) {
        error_log("[DS2800-DIAGNOSTIC] REJECTED: Payload size exceeds limit");
        http_response_code(400);
        echo json_encode(['ply' => 3, 'msg' => 'SCAN REJECTED']);
        exit;
    }

    $raw_input = file_get_contents('php://input');
    error_log("[DS2800-DIAGNOSTIC] Raw Body: " . substr($raw_input, 0, 150));

    if (strlen($raw_input) > 8192) {
        error_log("[DS2800-DIAGNOSTIC] REJECTED: Body length > 8KB");
        http_response_code(400);
        echo json_encode(['ply' => 3, 'msg' => 'SCAN REJECTED']);
        exit;
    }

    $input = json_decode($raw_input, true);

    if (json_last_error() !== JSON_ERROR_NONE || !is_array($input) || empty($input['id']) || empty($input['msg'])) {
        error_log("[DS2800-DIAGNOSTIC] REJECTED: JSON parse error or missing id/msg fields. JSON Error: " . json_last_error_msg());
        http_response_code(400);
        echo json_encode(['ply' => 3, 'msg' => 'SCAN REJECTED']);
        exit;
    }

    $scanner_id = trim((string)$input['id']);
    $raw_scanned_content = trim((string)$input['msg']);
    error_log("[DS2800-DIAGNOSTIC] Parsed Payload -> Scanner ID: " . $scanner_id . " | Content: " . substr($raw_scanned_content, 0, 40) . "...");

    // Check optional URL query parameter secret if scanner configured with ?secret=...
    $query_secret = $_GET['secret'] ?? null;

    // Validate Scanner Registration
    $stmt_sc = $pdo->prepare("SELECT * FROM registered_scanners WHERE scanner_id = ? AND status = 'active' LIMIT 1");
    $stmt_sc->execute([$scanner_id]);
    $scanner = $stmt_sc->fetch(PDO::FETCH_ASSOC);

    if (!$scanner) {
        error_log("[DS2800-DIAGNOSTIC] REJECTED: Unknown or inactive scanner_id: " . $scanner_id);
        http_response_code(403);
        echo json_encode(['ply' => 3, 'msg' => 'SCAN REJECTED']);
        exit;
    }

    if ($query_secret !== null && $query_secret !== $scanner['secret_key']) {
        error_log("[DS2800-DIAGNOSTIC] REJECTED: Mismatched scanner secret");
        http_response_code(403);
        echo json_encode(['ply' => 3, 'msg' => 'SCAN REJECTED']);
        exit;
    }

    // Deduplication check: Has this exact scan content from this scanner been received in the last 15 seconds?
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
        error_log("[DS2800-DIAGNOSTIC] DUPLICATE TRANSMISSION: Scan received within 15s window from scanner: " . $scanner_id);
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

    $stmt = $pdo->prepare("SELECT id, event_type, payload_json, received_at FROM inbound_event_queue WHERE id > ? ORDER BY id ASC LIMIT 100");
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
