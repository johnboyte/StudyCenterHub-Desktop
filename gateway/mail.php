<?php
/**
 * mail.php
 * Production SiteGround System Mail Relay Controller & Template Engine.
 * Serves app.reallife-studycenter.org/mail.php
 */
header('Content-Type: application/json; charset=utf-8');

$input = json_decode(file_get_contents('php://input'), true);
if (!$input || empty($input['to'])) {
    http_response_code(400);
    echo json_encode(['success' => false, 'error' => 'Missing recipient email']);
    exit;
}

// Sanitize inputs to protect against header injection
$to = str_replace(["\r", "\n"], '', trim($input['to']));
$subject = str_replace(["\r", "\n"], '', trim($input['subject'] ?? 'Real Life Study Center Communication'));

if (!filter_var($to, FILTER_VALIDATE_EMAIL)) {
    http_response_code(400);
    echo json_encode(['success' => false, 'error' => 'Invalid recipient email format']);
    exit;
}

// Determine Email HTML Content
$html_body = '';
if (!empty($input['html']) || !empty($input['html_body']) || !empty($input['body'])) {
    $raw_content = $input['html'] ?? $input['html_body'] ?? $input['body'];
    // Wrap plain text body in clean card layout if not already HTML
    if (strpos($raw_content, '<div') === false && strpos($raw_content, '<p') === false) {
        $html_body = '<div style="font-family: -apple-system, BlinkMacSystemFont, &quot;Segoe UI&quot;, Roboto, Helvetica, Arial, sans-serif; background-color: #ffffff; max-width: 540px; margin: 0 auto; border-radius: 12px; padding: 24px 20px; border: 1px solid #e2e8f0; color: #1a2536;">';
        $html_body .= '<p style="font-size: 15px; line-height: 1.6; whitespace: pre-wrap;">' . nl2br(htmlspecialchars($raw_content)) . '</p>';
        $html_body .= '<hr style="border: none; border-top: 1px solid #edf2f7; margin: 24px 0 16px 0;"/>';
        $html_body .= '<p style="font-size: 14px; margin: 0;"><strong>Real Life House</strong></p>';
        $html_body .= '<p style="font-size: 13px; color: #4a5568; margin: 2px 0 0 0;">A Study Center & Hospitality House</p>';
        $html_body .= '</div>';
    } else {
        $html_body = $raw_content;
    }
} else {
    // Default Digital Member Pass Template
    $pass_id = $input['pass_id'] ?? 'usr_6bd72efd-17c4-6f0e';
    $pass_url = "https://app.reallife-studycenter.org/upload_pass.php?pass_id=" . urlencode($pass_id);
    $new_anchor = '<a href="' . htmlspecialchars($pass_url) . '" target="_blank" style="display: inline-block; width: auto; max-width: 100%; height: auto; white-space: nowrap; background-color: #000000; color: #ffffff; text-decoration: none; padding: 12px 18px; border-radius: 8px; font-weight: bold; font-size: 13.5px; line-height: 1.2; box-sizing: border-box; text-align: center; border: 1px solid #333333; margin: 0 auto;">Add to Apple Wallet</a>';

    $html_body = '<div style="font-family: -apple-system, BlinkMacSystemFont, &quot;Segoe UI&quot;, Roboto, Helvetica, Arial, sans-serif; background-color: #ffffff; max-width: 440px; margin: 0 auto; border-radius: 12px; padding: 24px 16px; border: 1px solid #e2e8f0; color: #1a2536;">';
    $html_body .= '<p style="font-size: 15px; line-height: 1.5; margin-top: 0;">Hello Valued Member,</p>';
    $html_body .= '<p style="font-size: 15px; line-height: 1.5;">Your Real Life House Digital Member Pass is ready.</p>';
    $html_body .= '<p style="font-size: 15px; line-height: 1.5;">Use the link below to open and save your Digital Member Pass:</p>';
    $html_body .= '<div style="text-align: center; margin: 20px 0;">' . $new_anchor . '</div>';
    $html_body .= '<p style="font-size: 15px; line-height: 1.5;">Please keep your pass available for check-in at Real Life House.</p>';
    $html_body .= '<hr style="border: none; border-top: 1px solid #edf2f7; margin: 20px 0;"/>';
    $html_body .= '<p style="font-size: 14px; margin: 0;"><strong>Real Life House</strong></p>';
    $html_body .= '<p style="font-size: 13px; color: #4a5568; margin: 2px 0 0 0;">A Study Center & Hospitality House</p>';
    $html_body .= '<p style="font-size: 13px; color: #718096; font-style: italic; margin: 2px 0 0 0;">Real Lives. Real Struggles. Real Hope.</p>';
    $html_body .= '</div>';
}

$attachments = $input['attachments'] ?? [];
$mail_sent = false;

if (is_array($attachments) && count($attachments) > 0) {
    // MIME Multipart Email with Attachments
    $boundary = "==MP_BOUND_" . md5(time() . rand());

    $headers = "From: Real Life House <support@reallife-studycenter.org>\r\n";
    $headers .= "MIME-Version: 1.0\r\n";
    $headers .= "Content-Type: multipart/mixed; boundary=\"" . $boundary . "\"\r\n";

    $message = "--" . $boundary . "\r\n";
    $message .= "Content-Type: text/html; charset=UTF-8\r\n";
    $message .= "Content-Transfer-Encoding: 8bit\r\n\r\n";
    $message .= $html_body . "\r\n\r\n";

    foreach ($attachments as $att) {
        $filename = preg_replace('/[^a-zA-Z0-9_\-\.]/', '_', $att['filename'] ?? 'attachment.jpg');
        $mime_type = strtolower($att['mime_type'] ?? 'image/jpeg');
        $b64_data = $att['data'] ?? '';

        $allowed_mimes = ['image/jpeg', 'image/jpg', 'image/png', 'image/webp'];
        if (!in_array($mime_type, $allowed_mimes, true)) {
            continue;
        }

        if (!empty($b64_data)) {
            $chunked_data = chunk_split($b64_data);
            $message .= "--" . $boundary . "\r\n";
            $message .= "Content-Type: " . $mime_type . "; name=\"" . $filename . "\"\r\n";
            $message .= "Content-Disposition: attachment; filename=\"" . $filename . "\"\r\n";
            $message .= "Content-Transfer-Encoding: base64\r\n\r\n";
            $message .= $chunked_data . "\r\n\r\n";
        }
    }

    $message .= "--" . $boundary . "--";

    $mail_sent = @mail($to, $subject, $message, $headers, "-fsupport@reallife-studycenter.org");
} else {
    // Standard Single-Part HTML Email
    $headers = "From: Real Life House <support@reallife-studycenter.org>\r\n";
    $headers .= "MIME-Version: 1.0\r\n";
    $headers .= "Content-Type: text/html; charset=UTF-8\r\n";

    $mail_sent = @mail($to, $subject, $html_body, $headers, "-fsupport@reallife-studycenter.org");
}

echo json_encode(['success' => $mail_sent, 'recipient' => $to]);
