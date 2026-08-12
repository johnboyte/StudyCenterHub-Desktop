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

$to = trim($input['to']);
$subject = trim($input['subject'] ?? 'Your Real Life House Digital Member Pass');
$pass_id = $input['pass_id'] ?? 'usr_6bd72efd-17c4-6f0e';
$pass_url = "https://app.reallife-studycenter.org/upload_pass.php?pass_id=" . urlencode($pass_id);

// Updated Single-Line Anchor Markup (Add to Apple Wallet)
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

$headers = "From: Real Life House <support@reallife-studycenter.org>\r\n";
$headers .= "MIME-Version: 1.0\r\n";
$headers .= "Content-Type: text/html; charset=UTF-8\r\n";

$mail_sent = @mail($to, $subject, $html_body, $headers, "-fsupport@reallife-studycenter.org");

echo json_encode(['success' => $mail_sent, 'recipient' => $to]);
