<?php
/**
 * upload_pass.php
 * Production SiteGround Digital Member Pass Relay & Web Delivery Handler.
 * Serves app.reallife-studycenter.org/upload_pass.php
 */

$pass_id = $_GET['pass_id'] ?? $_POST['pass_id'] ?? '';
$pass_id = preg_replace('/[^a-zA-Z0-9_\-]/', '', $pass_id);

$passes_dir = __DIR__ . '/passes';
if (!file_exists($passes_dir)) {
    @mkdir($passes_dir, 0755, true);
}

// 1. POST Request: Store uploaded .pkpass binary from Desktop client
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    if (empty($pass_id)) {
        http_response_code(400);
        echo json_encode(['success' => false, 'error' => 'Missing pass_id']);
        exit;
    }
    $raw_bytes = file_get_contents('php://input');
    if (empty($raw_bytes)) {
        http_response_code(400);
        echo json_encode(['success' => false, 'error' => 'Empty pass payload']);
        exit;
    }
    $target_file = $passes_dir . '/' . $pass_id . '.pkpass';
    file_put_contents($target_file, $raw_bytes);
    echo json_encode(['success' => true, 'pass_id' => $pass_id, 'bytes' => strlen($raw_bytes)]);
    exit;
}

// 2. Binary Download / PassKit Direct Delivery (Content-Disposition: inline to trigger iOS Apple Wallet modal sheet)
if (isset($_GET['download']) && $_GET['download'] === '1') {
    $target_file = $passes_dir . '/' . $pass_id . '.pkpass';
    if (empty($pass_id) || !file_exists($target_file)) {
        http_response_code(404);
        echo "Pass file not found.";
        exit;
    }
    
    // Clear any output buffers to guarantee raw binary delivery
    if (ob_get_level()) {
        ob_end_clean();
    }
    
    header('Content-Type: application/vnd.apple.pkpass');
    header('Content-Disposition: inline; filename="' . $pass_id . '.pkpass"');
    header('Content-Length: ' . filesize($target_file));
    header('Cache-Control: no-store, no-cache, must-revalidate, max-age=0');
    header('Pragma: no-cache');
    
    readfile($target_file);
    exit;
}

// 3. HTML Landing Page (Direct link without JavaScript e.preventDefault() so iOS Safari opens PassKit natively)
if (empty($pass_id)) {
    http_response_code(400);
    echo "Missing pass identifier.";
    exit;
}

$download_url = "upload_pass.php?pass_id=" . urlencode($pass_id) . "&download=1";
?>
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Real Life House — Digital Member Pass</title>
    <style>
        body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif; background: #f4f6f9; margin: 0; padding: 20px; display: flex; justify-content: center; align-items: center; min-height: 90vh; }
        .card { background: #ffffff; border-radius: 16px; padding: 32px; max-width: 480px; width: 100%; box-shadow: 0 10px 25px rgba(0,0,0,0.08); text-align: center; }
        .logo-text { font-size: 13px; font-weight: bold; color: #daa520; letter-spacing: 2px; text-transform: uppercase; margin-bottom: 8px; }
        h2 { color: #1a2b4c; margin: 0 0 12px 0; font-size: 22px; }
        p { color: #555; font-size: 15px; line-height: 1.5; margin: 0 0 24px 0; }
        .btn { display: inline-block; padding: 16px 28px; background: #000000; color: #ffffff; text-decoration: none; border-radius: 12px; font-weight: bold; font-size: 17px; box-shadow: 0 4px 14px rgba(0,0,0,0.2); margin-bottom: 16px; width: 85%; transition: all 0.3s ease; }
        .footer { font-size: 12px; color: #888; margin-top: 24px; border-top: 1px solid #eee; padding-top: 16px; }
    </style>
</head>
<body>
    <div class="card">
        <div class="logo-text">Real Life Study Center</div>
        <h2>Digital Member Pass</h2>
        <p>Tap the button below to add your official Real Life House Member Pass directly into your iPhone Apple Wallet.</p>
        
        <a href="<?php echo htmlspecialchars($download_url); ?>" class="btn">🍏 ADD TO APPLE WALLET</a>
        
        <div class="footer">
            Real Life Study Center & Hospitality House<br/>
            (864) 712-4446 | support@reallife-studycenter.org
        </div>
    </div>
</body>
</html>
