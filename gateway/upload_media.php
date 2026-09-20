<?php
/**
 * upload_media.php
 * Secure Temporary Outgoing Media Relay Endpoint for Twilio MMS & Communications.
 * Serves app.reallife-studycenter.org/upload_media.php
 */

header('X-Content-Type-Options: nosniff');
header('X-Frame-Options: DENY');

$media_dir = __DIR__ . '/media';
if (!file_exists($media_dir)) {
    @mkdir($media_dir, 0755, true);
    @file_put_contents($media_dir . '/.htaccess', "Options -Indexes\n<Files *>\n    SetHandler default-handler\n    RemoveHandler .php .phtml .php3 .php4 .php5 .phps\n    php_flag engine off\n</Files>\n");
}

// Auto-cleanup: remove files older than 48 hours (172800 seconds)
if (rand(1, 20) === 1) {
    $now = time();
    $files = @glob($media_dir . '/*');
    if ($files) {
        foreach ($files as $file) {
            if (is_file($file) && basename($file) !== '.htaccess') {
                if ($now - filemtime($file) > 172800) {
                    @unlink($file);
                }
            }
        }
    }
}

// 1. GET Request: Serve secure binary image to Twilio / Recipients
if ($_SERVER['REQUEST_METHOD'] === 'GET') {
    $media_id = $_GET['media_id'] ?? '';
    $token = $_GET['token'] ?? '';

    $clean_media_id = preg_replace('/[^a-zA-Z0-9_\-]/', '', $media_id);
    $clean_token = preg_replace('/[^a-zA-Z0-9_\-]/', '', $token);

    if (empty($clean_media_id) || empty($clean_token)) {
        http_response_code(400);
        echo "Missing required media parameter.";
        exit;
    }

    $target_file = $media_dir . '/' . $clean_media_id . '_' . $clean_token . '.img';
    if (!file_exists($target_file)) {
        http_response_code(404);
        echo "Media file not found or expired.";
        exit;
    }

    $finfo = finfo_open(FILEINFO_MIME_TYPE);
    $mime_type = finfo_file($finfo, $target_file);
    finfo_close($finfo);

    $allowed_mimes = [
        'image/jpeg' => 'jpg',
        'image/png'  => 'png',
        'image/webp' => 'webp'
    ];

    if (!isset($allowed_mimes[$mime_type])) {
        http_response_code(403);
        echo "Access denied.";
        exit;
    }

    if (ob_get_level()) {
        ob_end_clean();
    }

    header('Content-Type: ' . $mime_type);
    header('Content-Length: ' . filesize($target_file));
    header('Cache-Control: public, max-age=86400');
    header('Pragma: cache');

    readfile($target_file);
    exit;
}

// 2. POST Request: Store uploaded image payload from Desktop client
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $raw_bytes = file_get_contents('php://input');
    if (empty($raw_bytes)) {
        http_response_code(400);
        echo json_encode(['success' => false, 'error' => 'Empty media payload']);
        exit;
    }

    if (strlen($raw_bytes) > 10 * 1024 * 1024) { // 10MB absolute gateway upload cap
        http_response_code(413);
        echo json_encode(['success' => false, 'error' => 'Payload exceeds maximum allowed size']);
        exit;
    }

    // Verify binary is a real image
    $img_info = @getimagesizefromstring($raw_bytes);
    if (!$img_info || !isset($img_info['mime'])) {
        http_response_code(415);
        echo json_encode(['success' => false, 'error' => 'Invalid image payload format']);
        exit;
    }

    $mime_type = strtolower($img_info['mime']);
    $allowed_mimes = ['image/jpeg', 'image/png', 'image/webp'];
    if (!in_array($mime_type, $allowed_mimes, true)) {
        http_response_code(415);
        echo json_encode(['success' => false, 'error' => 'Unsupported image type. Only JPEG, PNG, WEBP supported.']);
        exit;
    }

    // Generate random unguessable media ID and access token
    $media_id = 'mms_' . bin2hex(random_bytes(8));
    $token = bin2hex(random_bytes(16));

    $target_file = $media_dir . '/' . $media_id . '_' . $token . '.img';
    if (file_put_contents($target_file, $raw_bytes) === false) {
        http_response_code(500);
        echo json_encode(['success' => false, 'error' => 'Failed to persist media file']);
        exit;
    }

    $public_url = "https://app.reallife-studycenter.org/upload_media.php?media_id=" . urlencode($media_id) . "&token=" . urlencode($token);

    echo json_encode([
        'success'    => true,
        'media_id'   => $media_id,
        'token'      => $token,
        'public_url' => $public_url,
        'bytes'      => strlen($raw_bytes),
        'mime'       => $mime_type,
        'width'      => $img_info[0],
        'height'     => $img_info[1]
    ]);
    exit;
}

http_response_code(405);
echo "Method not allowed.";
