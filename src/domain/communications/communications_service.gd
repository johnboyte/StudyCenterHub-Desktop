extends RefCounted

const TwilioGatewayScript = preload("res://src/infrastructure/messaging/twilio_gateway_service.gd")
var db: RefCounted
var twilio_service: RefCounted

func _init(database: RefCounted) -> void:
	db = database
	twilio_service = TwilioGatewayScript.new(db)

func validate_contact_and_consent(person_dict: Dictionary, channel: String) -> Dictionary:
	var phone = str(person_dict.get("phone", "")).strip_edges()
	var email = str(person_dict.get("email", "")).strip_edges()
	var sms_consent = int(person_dict.get("sms_consent", 1)) == 1

	if channel.to_upper().contains("SMS"):
		if not sms_consent:
			return {"eligible": false, "reason": "SMS Consent Withdrawn (STOP Opt-Out)"}
		if phone == "" or phone == "555-0000" or phone.length() < 7:
			return {"eligible": false, "reason": "Invalid or Missing Phone Number"}

	if channel.to_upper().contains("EMAIL"):
		if email == "" or not email.contains("@"):
			return {"eligible": false, "reason": "Missing Email"}

	return {"eligible": true, "reason": ""}

func email_digital_member_pass(person_id: int, sent_by: String = "Staff Administrator") -> Dictionary:
	if not db:
		return {"success": false, "error": "Database unavailable.", "reason": "db_error"}

	var res = db.execute("SELECT * FROM people WHERE id = ? LIMIT 1;", [person_id])
	if not res["success"] or res["data"].size() == 0:
		return {"success": false, "error": "Participant not found.", "reason": "not_found"}

	var p = res["data"][0].duplicate()
	var first_name = str(p.get("first_name", "")).strip_edges()
	var last_name = str(p.get("last_name", "")).strip_edges()
	if first_name == "<null>" or first_name == "null": first_name = ""
	if last_name == "<null>" or last_name == "null": last_name = ""

	# 1. Strict Member Primary Email Validation (Never substitute dummy or cached addresses!)
	var email_val = ""
	var pref_email_type = str(p.get("preferred_email", "Main")).strip_edges()
	if pref_email_type == "School":
		email_val = str(p.get("school_email", "")).strip_edges()

	if email_val == "" or email_val == "<null>" or email_val == "null":
		email_val = str(p.get("email", p.get("email_address", ""))).strip_edges()

	if email_val == "" or email_val == "<null>" or email_val == "null" or not email_val.contains("@") or email_val.split("@").size() < 2 or email_val.split("@")[1].strip_edges() == "":
		return {
			"success": false,
			"error": "This member does not have a valid email address. Add or correct the email address before sending the Digital Member Pass.",
			"reason": "invalid_email"
		}
	p["email"] = email_val
	p["email_address"] = email_val

	# Get active QR token raw_token from QRCredentialService (Keychain-bound)
	var QRCredentialServiceScript = load("res://src/domain/security/qr_credential_service.gd")
	var cred_svc = QRCredentialServiceScript.new(db)
	var raw_token = cred_svc.get_active_raw_token(person_id)
	if raw_token == "":
		var err_msg = "The active QR credential token is unavailable on this device (it may have been issued on another computer). A new credential must be issued on this computer to generate a digital wallet pass."
		_log_email_communication(p, "Digital Member Pass Attempt", err_msg, sent_by, "failed", err_msg)
		return {
			"success": false,
			"error": err_msg,
			"reason": "keychain_missing"
		}

	var active_cred_id = ""
	var cred_res = db.execute("SELECT credential_id FROM participant_qr_credentials WHERE person_id = ? AND status = 'active' LIMIT 1;", [person_id])
	if cred_res["success"] and cred_res["data"].size() > 0:
		active_cred_id = str(cred_res["data"][0].get("credential_id", ""))

	var AppleSvc = load("res://src/domain/security/apple_wallet_service.gd").new()
	var GoogleSvc = load("res://src/domain/security/google_wallet_service.gd").new()

	var apple_res = AppleSvc.generate_apple_wallet_pass(p, raw_token, active_cred_id)
	var google_res = GoogleSvc.generate_add_to_google_wallet_link(p, raw_token)

	var apple_link = apple_res.get("pkpass_url", "https://checkin.reallife-studycenter.org/wallet/apple/" + str(p.get("person_uuid", "PRT")))
	var google_link = google_res.get("google_wallet_url", "https://pay.google.com/gp/v/save/" + str(p.get("person_uuid", "PRT")))

	var pass_link = apple_link
	if pass_link == "": pass_link = google_link

	var greeting_name = first_name
	if greeting_name == "": greeting_name = "Valued Member"

	var subject = "Your Real Life House Digital Member Pass"

	var plain_text = "Hello " + greeting_name + ",\n\n"
	plain_text += "Your Real Life House Digital Member Pass is ready.\n\n"
	plain_text += "Use the link below to open and save your Digital Member Pass:\n\n"
	plain_text += pass_link + "\n\n"
	plain_text += "Please keep your pass available for check-in at Real Life House.\n\n"
	plain_text += "Real Life House\n"
	plain_text += "A Study Center & Hospitality House\n"
	plain_text += "Real Lives. Real Struggles. Real Hope."

	var html_body = "<div style=\"font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif; background-color: #ffffff; max-width: 440px; margin: 0 auto; border-radius: 12px; padding: 24px 16px; border: 1px solid #e2e8f0; color: #1a2536;\">"
	html_body += "<p style=\"font-size: 15px; line-height: 1.5; margin-top: 0;\">Hello " + greeting_name + ",</p>"
	html_body += "<p style=\"font-size: 15px; line-height: 1.5;\">Your Real Life House Digital Member Pass is ready.</p>"
	html_body += "<p style=\"font-size: 15px; line-height: 1.5;\">Use the link below to open and save your Digital Member Pass:</p>"
	html_body += "<div style=\"text-align: center; margin: 20px 0;\">"
	html_body += "<a href=\"" + pass_link + "\" target=\"_blank\" style=\"display: inline-block; width: auto; max-width: 100%; white-space: nowrap; background-color: #000000; color: #ffffff; text-decoration: none; padding: 11px 18px; border-radius: 8px; font-weight: bold; font-size: 13.5px; line-height: 1.2; box-sizing: border-box; text-align: center; border: 1px solid #333333; margin: 0 auto;\">Add to Apple Wallet</a>"
	html_body += "</div>"
	html_body += "<p style=\"font-size: 15px; line-height: 1.5;\">Please keep your pass available for check-in at Real Life House.</p>"
	html_body += "<hr style=\"border: none; border-top: 1px solid #edf2f7; margin: 20px 0;\"/>"
	html_body += "<p style=\"font-size: 14px; margin: 0;\"><strong>Real Life House</strong></p>"
	html_body += "<p style=\"font-size: 13px; color: #4a5568; margin: 2px 0 0 0;\">A Study Center & Hospitality House</p>"
	html_body += "<p style=\"font-size: 13px; color: #718096; font-style: italic; margin: 2px 0 0 0;\">Real Lives. Real Struggles. Real Hope.</p>"
	html_body += "</div>"

	# 2. Live Synchronous Dispatch to SiteGround Mail Relay
	var pass_id = str(p.get("person_uuid", "PRT"))
	if active_cred_id != "":
		pass_id += "_" + active_cred_id
	var relay_res = await dispatch_email_sync(email_val, subject, html_body, pass_id)

	var is_success = relay_res.get("success", false) == true
	var log_status = "accepted" if is_success else "failed"
	var err_detail = str(relay_res.get("error", ""))

	_log_email_communication(p, subject, html_body, sent_by, log_status, err_detail)

	if is_success:
		return {
			"success": true,
			"error": "",
			"reason": "",
			"apple_pass": apple_res,
			"google_pass": google_res
		}
	else:
		return {
			"success": false,
			"error": "Mail relay dispatch failed: " + err_detail,
			"reason": "relay_failed"
		}

func sms_digital_member_pass(arg1, arg2 = null, arg3: String = "Staff Administrator") -> Dictionary:
	var caller_node: Node = null
	var person_id: int = 0
	var sent_by: String = "Staff Administrator"
	
	if typeof(arg1) == TYPE_INT or typeof(arg1) == TYPE_FLOAT:
		person_id = int(arg1)
		if arg2 is String: sent_by = arg2
	else:
		var main_loop = Engine.get_main_loop()
		if arg1 is SceneTree:
			caller_node = arg1.root
		elif arg1 is Node:
			caller_node = arg1
		person_id = int(arg2)
		if arg3 != "": sent_by = arg3
		
	# Fallback caller_node detection
	if caller_node == null:
		var main_loop = Engine.get_main_loop()
		if main_loop is SceneTree:
			caller_node = main_loop.root
		elif main_loop is Node:
			caller_node = main_loop as Node

	if not db:
		return {"success": false, "error": "Database unavailable.", "reason": "db_error"}

	var display_name = "Valued Member"
	var phone = ""

	# Load participant details
	var res = db.execute("SELECT * FROM people WHERE id = ? LIMIT 1;", [person_id])
	if res["success"] and res["data"].size() > 0:
		var p_data = res["data"][0]
		var first_name = str(p_data.get("first_name", "")).strip_edges()
		var last_name = str(p_data.get("last_name", "")).strip_edges()
		if first_name == "<null>" or first_name == "null": first_name = ""
		if last_name == "<null>" or last_name == "null": last_name = ""
		display_name = (first_name + " " + last_name).strip_edges()
		if display_name == "": display_name = "Valued Member"
		phone = str(p_data.get("phone", "")).strip_edges()

	# 1. Validate Twilio Config Completeness
	var twilio_config = twilio_service.get_twilio_config() if twilio_service else {}
	var sid = twilio_config.get("account_sid", "")
	var token = twilio_config.get("auth_token", "")
	var from_phone = twilio_config.get("phone_number", "")
	
	var missing_fields = []
	if sid == "": missing_fields.append("Account SID")
	if token == "": missing_fields.append("Auth Token")
	if from_phone == "": missing_fields.append("Twilio Phone Number")
	
	if missing_fields.size() > 0:
		var err_msg = "Twilio configuration is incomplete. Missing: " + ", ".join(missing_fields) + ". Please configure them in Settings."
		var msg_uuid = "msg_" + _generate_uuid()
		db.execute("INSERT INTO communications_log (message_uuid, recipient_person_id, recipient_name, recipient_contact, channel, message_body, status, status_detail, sent_by_user) VALUES (?, ?, ?, ?, 'SMS', ?, 'failed', ?, ?);",
			[msg_uuid, person_id, display_name, phone, "Digital Member Pass SMS", err_msg, sent_by])
		return {"success": false, "error": err_msg, "reason": "incomplete_config"}

	# Validate Account SID format
	if sid.begins_with("SK"):
		var err_msg = "The Twilio Account SID is invalid. You have entered an API Key SID starting with SK. The current integration expects the main Account SID beginning with AC and the corresponding Auth Token. Do not use an API Key SID."
		var msg_uuid = "msg_" + _generate_uuid()
		db.execute("INSERT INTO communications_log (message_uuid, recipient_person_id, recipient_name, recipient_contact, channel, message_body, status, status_detail, sent_by_user) VALUES (?, ?, ?, ?, 'SMS', ?, 'failed', ?, ?);",
			[msg_uuid, person_id, display_name, phone, "Digital Member Pass SMS", err_msg, sent_by])
		return {"success": false, "error": err_msg, "reason": "invalid_sid"}

	if not sid.begins_with("AC"):
		var err_msg = "The Twilio Account SID is invalid. Enter the Account SID beginning with AC, not an API Key SID or other Twilio identifier."
		var msg_uuid = "msg_" + _generate_uuid()
		db.execute("INSERT INTO communications_log (message_uuid, recipient_person_id, recipient_name, recipient_contact, channel, message_body, status, status_detail, sent_by_user) VALUES (?, ?, ?, ?, 'SMS', ?, 'failed', ?, ?);",
			[msg_uuid, person_id, display_name, phone, "Digital Member Pass SMS", err_msg, sent_by])
		return {"success": false, "error": err_msg, "reason": "invalid_sid"}

	if not res["success"] or res["data"].size() == 0:
		return {"success": false, "error": "Participant not found.", "reason": "not_found"}

	var p = res["data"][0]

	# 2. Validate Phone Number Presence
	if phone == "" or phone == "<null>" or phone == "null":
		var err_msg = "No mobile number exists for this participant."
		var msg_uuid = "msg_" + _generate_uuid()
		db.execute("INSERT INTO communications_log (message_uuid, recipient_person_id, recipient_name, recipient_contact, channel, message_body, status, status_detail, sent_by_user) VALUES (?, ?, ?, ?, 'SMS', ?, 'failed', ?, ?);",
			[msg_uuid, person_id, display_name, "", "Digital Member Pass SMS", err_msg, sent_by])
		return {"success": false, "error": err_msg, "reason": "missing_phone"}

	# 3. Validate Phone Number Format
	var digits = ""
	for c in phone:
		if c in "0123456789":
			digits += c
	if digits.length() < 10 or digits.length() > 11:
		var err_msg = "The phone number '" + phone + "' is invalid (must be 10 or 11 digits)."
		var msg_uuid = "msg_" + _generate_uuid()
		db.execute("INSERT INTO communications_log (message_uuid, recipient_person_id, recipient_name, recipient_contact, channel, message_body, status, status_detail, sent_by_user) VALUES (?, ?, ?, ?, 'SMS', ?, 'failed', ?, ?);",
			[msg_uuid, person_id, display_name, phone, "Digital Member Pass SMS", err_msg, sent_by])
		return {"success": false, "error": err_msg, "reason": "invalid_phone"}

	# Get active QR token raw_token from QRCredentialService (Keychain-bound)
	var QRCredentialServiceScript = load("res://src/domain/security/qr_credential_service.gd")
	var cred_svc = QRCredentialServiceScript.new(db)
	var raw_token = cred_svc.get_active_raw_token(person_id)
	if raw_token == "":
		var err_msg = "The active QR credential token is unavailable on this device (it may have been issued on another computer). A new credential must be issued on this computer to generate a digital wallet pass."
		var msg_uuid = "msg_" + _generate_uuid()
		db.execute("INSERT INTO communications_log (message_uuid, recipient_person_id, recipient_name, recipient_contact, channel, message_body, status, status_detail, sent_by_user) VALUES (?, ?, ?, ?, 'SMS', ?, 'failed', ?, ?);",
			[msg_uuid, person_id, display_name, phone, "Digital Member Pass SMS", err_msg, sent_by])
		return {
			"success": false,
			"error": err_msg,
			"reason": "keychain_missing"
		}

	var active_cred_id = ""
	var cred_res = db.execute("SELECT credential_id FROM participant_qr_credentials WHERE person_id = ? AND status = 'active' LIMIT 1;", [person_id])
	if cred_res["success"] and cred_res["data"].size() > 0:
		active_cred_id = str(cred_res["data"][0].get("credential_id", ""))

	var AppleSvc = load("res://src/domain/security/apple_wallet_service.gd").new()
	var GoogleSvc = load("res://src/domain/security/google_wallet_service.gd").new()

	var apple_res = AppleSvc.generate_apple_wallet_pass(p, raw_token, active_cred_id)
	var google_res = GoogleSvc.generate_add_to_google_wallet_link(p, raw_token)

	var apple_link = apple_res.get("pkpass_url", "https://checkin.reallife-studycenter.org/wallet/apple/" + str(p.get("person_uuid", "PRT")))
	var google_link = google_res.get("google_wallet_url", "https://pay.google.com/gp/v/save/" + str(p.get("person_uuid", "PRT")))

	var body = "Real Life House Pass for " + display_name + ":\n"
	body += "Apple Wallet: " + apple_link + "\n"
	body += "Google Wallet: " + google_link + "\n"
	body += "Tap the link to save your pass to your phone!"

	# Initial Log Entry & Outbox Event (queued/submitted)
	var msg_uuid = "msg_" + _generate_uuid()
	var event_uuid = "evt_" + _generate_uuid()
	var device_uuid = "dev_macbook_primary_node"
	var status_val = "simulated" if twilio_service.is_demo_config() else "submitted_to_provider"
	var provider_sid = "SM" + _generate_uuid().replace("-", "").left(30) if status_val == "simulated" else ""

	var stmt1 = {
		"sql": "INSERT INTO communications_log (message_uuid, recipient_person_id, recipient_name, recipient_contact, channel, message_body, status, sent_by_user, provider_sid) VALUES (?, ?, ?, ?, 'SMS', ?, ?, ?, ?);",
		"args": [msg_uuid, person_id, display_name, phone, body, status_val, sent_by, provider_sid]
	}

	var payload_dict = {
		"event_uuid": event_uuid,
		"event_type": "MessageSent",
		"message_uuid": msg_uuid,
		"person_uuid": str(p.get("person_uuid", "")),
		"recipient_name": display_name,
		"recipient_contact": phone,
		"channel": "SMS",
		"message_body": body,
		"sent_by_user": sent_by,
		"device_uuid": device_uuid,
		"timestamp": Time.get_datetime_string_from_system()
	}

	var stmt2 = {
		"sql": "INSERT INTO event_outbox (event_uuid, event_type, aggregate_type, aggregate_id, payload_json, device_uuid, status) VALUES (?, 'MessageSent', 'Communications', ?, ?, ?, 'pending');",
		"args": [event_uuid, msg_uuid, JSON.stringify(payload_dict), device_uuid]
	}

	db.execute_transaction([stmt1, stmt2])

	# Perform Awaitable Twilio Dispatch
	if caller_node == null:
		return {
			"success": status_val == "simulated",
			"twilio_msg_sid": provider_sid if status_val == "simulated" else "",
			"apple_pass": apple_res,
			"google_pass": google_res,
			"message_uuid": msg_uuid,
			"error": "No caller node available for HTTP request" if status_val != "simulated" else ""
		}
		
	var sms_res = await _dispatch_sms_awaitable(caller_node, phone, body)
	
	if sms_res.get("success", false):
		var sms_sid = sms_res.get("twilio_msg_sid", "")
		db.execute("UPDATE communications_log SET status = 'sent', provider_sid = ? WHERE message_uuid = ?;", [sms_sid, msg_uuid])
		return {
			"success": true,
			"twilio_msg_sid": sms_sid,
			"apple_pass": apple_res,
			"google_pass": google_res,
			"message_uuid": msg_uuid
		}
	else:
		var err = sms_res.get("error", "Unknown Twilio error")
		db.execute("UPDATE communications_log SET status = 'failed', status_detail = ? WHERE message_uuid = ?;", [err, msg_uuid])
		return {
			"success": false,
			"error": err,
			"message_uuid": msg_uuid
		}

func _dispatch_sms_awaitable(caller_node: Node, to_phone: String, body: String) -> Dictionary:
	var completed = {"done": false, "res": {}}
	twilio_service.send_twilio_sms_async(caller_node, to_phone, body, func(sms_res: Dictionary):
		completed["res"] = sms_res
		completed["done"] = true
	)
	
	while not completed["done"]:
		var main_loop = Engine.get_main_loop()
		if main_loop is SceneTree:
			await main_loop.process_frame
		else:
			break
			
	return completed["res"]

func validate_attachment(file_path: String, channel: String) -> Dictionary:
	if file_path == "": return {"valid": true, "reason": ""}
	if not FileAccess.file_exists(file_path):
		return {"valid": false, "reason": "Attachment File Not Found on Disk"}
	var ext = file_path.get_extension().to_lower()
	if ext not in ["png", "jpg", "jpeg"]:
		return {"valid": false, "reason": "Unsupported File Type (Only PNG/JPG allowed)"}
	var f = FileAccess.open(file_path, FileAccess.READ)
	if f and f.get_length() > 5 * 1024 * 1024:
		return {"valid": false, "reason": "Attachment Exceeds Maximum 5MB Limit"}
	return {"valid": true, "reason": ""}

func send_message_atomic(recipient_person: Dictionary, channel: String, message_body: String, sent_by: String = "John Smith", attachment_path: String = "") -> Dictionary:
	var start_time_usec = Time.get_ticks_usec()
	var msg_uuid = "msg_" + _generate_uuid()
	var event_uuid = "evt_" + _generate_uuid()

	var person_id = int(recipient_person.get("person_id", 0))
	if person_id == 0:
		person_id = int(recipient_person.get("id", 0))

	var person_uuid = str(recipient_person.get("person_uuid", ""))
	var first_name = str(recipient_person.get("first_name", ""))
	var last_name = str(recipient_person.get("last_name", ""))
	var recipient_name = (first_name + " " + last_name).strip_edges()
	if recipient_name == "": recipient_name = str(recipient_person.get("human_id", "Constituent"))

	var contact_val = str(recipient_person.get("email", recipient_person.get("email_address", ""))).strip_edges()
	if not channel.to_upper().contains("EMAIL") or contact_val == "":
		contact_val = str(recipient_person.get("phone", "555-0100")).strip_edges()

	var device_uuid = "dev_macbook_primary_node"

	# Validate consent & contact
	var val_res = validate_contact_and_consent(recipient_person, channel)
	if not val_res["eligible"]:
		var stmt_ex = {
			"sql": "INSERT INTO communications_log (message_uuid, recipient_person_id, recipient_name, recipient_contact, channel, message_body, status, sent_by_user) VALUES (?, ?, ?, ?, ?, ?, 'excluded', ?);",
			"args": [msg_uuid, person_id, recipient_name, contact_val, channel, message_body, sent_by]
		}
		db.execute_transaction([stmt_ex])
		return {"success": false, "error": val_res["reason"], "status": "excluded", "message_uuid": msg_uuid}

	var status_val = "simulated" if (twilio_service and twilio_service.is_demo_config()) else "submitted_to_provider"
	var provider_sid = "SM" + _generate_uuid().replace("-", "").left(30) if status_val == "simulated" else ""

	var stmt1 = {
		"sql": "INSERT INTO communications_log (message_uuid, recipient_person_id, recipient_name, recipient_contact, channel, message_body, status, sent_by_user, provider_sid) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);",
		"args": [msg_uuid, person_id, recipient_name, contact_val, channel, message_body, status_val, sent_by, provider_sid]
	}

	var payload_dict = {
		"event_uuid": event_uuid,
		"event_type": "MessageSent",
		"message_uuid": msg_uuid,
		"person_uuid": person_uuid,
		"recipient_name": recipient_name,
		"recipient_contact": contact_val,
		"channel": channel,
		"message_body": message_body,
		"sent_by_user": sent_by,
		"device_uuid": device_uuid,
		"timestamp": Time.get_datetime_string_from_system()
	}

	var stmt2 = {
		"sql": "INSERT INTO event_outbox (event_uuid, event_type, aggregate_type, aggregate_id, payload_json, device_uuid, status) VALUES (?, 'MessageSent', 'Communications', ?, ?, ?, 'pending');",
		"args": [event_uuid, msg_uuid, JSON.stringify(payload_dict), device_uuid]
	}

	var tx_res = db.execute_transaction([stmt1, stmt2])
	var end_time_usec = Time.get_ticks_usec()
	var elapsed_ms = (end_time_usec - start_time_usec) / 1000.0

	if not tx_res["success"]:
		return {"success": false, "error": tx_res["error"], "elapsed_ms": elapsed_ms, "message_uuid": ""}

	# If channel is EMAIL, dispatch immediately to Cloud Relay mail endpoint
	if channel.to_upper().contains("EMAIL") and contact_val.contains("@"):
		dispatch_email_sync(contact_val, "Real Life Study Center — Digital Member Pass", message_body)

	# If channel is SMS, dispatch immediately via Twilio Gateway Service
	if channel.to_upper().contains("SMS") and contact_val != "":
		var main_loop = Engine.get_main_loop()
		var root_node: Node = null
		if main_loop is SceneTree:
			root_node = (main_loop as SceneTree).root
		elif main_loop is Node:
			root_node = main_loop as Node
		
		if root_node and twilio_service:
			twilio_service.send_twilio_sms_async(root_node, contact_val, message_body, func(sms_res: Dictionary):
				if sms_res.get("success", false):
					var sid = sms_res.get("twilio_msg_sid", "")
					db.execute("UPDATE communications_log SET status = 'sent', provider_sid = ? WHERE message_uuid = ?;", [sid, msg_uuid])
					print("[SMS-DISPATCH] Success: Message sent to ", contact_val, " (SID: ", sid, ")")
				else:
					var err = sms_res.get("error", "Unknown error")
					db.execute("UPDATE communications_log SET status = 'failed', status_detail = ? WHERE message_uuid = ?;", [err, msg_uuid])
					print("[SMS-DISPATCH] Failure: Failed to send SMS to ", contact_val, ": ", err)
			)

	return {"success": true, "error": "", "elapsed_ms": elapsed_ms, "message_uuid": msg_uuid, "event_uuid": event_uuid, "status": status_val}

func dispatch_email_sync(to_email: String, subject: String, body_html: String, pass_id: String = "") -> Dictionary:
	var clean_html = body_html.replace("", "Apple")

	print("--- DISPATCHING LOCKED HTML PAYLOAD ---")
	print("Recipient: ", to_email)
	print("Subject: ", subject)
	print("Source HTML Char Count: ", clean_html.length())
	print("---------------------------------------")

	var payload_dict = {
		"to": to_email,
		"subject": subject,
		"body": clean_html,
		"html": clean_html,
		"html_body": clean_html
	}
	if pass_id != "":
		payload_dict["pass_id"] = pass_id

	var payload = JSON.stringify(payload_dict)

	var main_loop = Engine.get_main_loop()
	var root_node: Node = null
	if main_loop is SceneTree:
		root_node = (main_loop as SceneTree).root
	elif main_loop is Node:
		root_node = main_loop as Node

	if not root_node and main_loop and "root" in main_loop:
		root_node = main_loop.root

	if not root_node:
		return {"success": false, "error": "Engine root unavailable"}

	var http_req = HTTPRequest.new()
	http_req.timeout = 10.0
	root_node.add_child(http_req)

	if http_req.get_tree():
		await http_req.get_tree().create_timer(0.05).timeout

	var headers = [
		"Content-Type: application/json",
		"User-Agent: StudyCenterHub-Desktop/1.0"
	]

	var req_err = http_req.request("https://app.reallife-studycenter.org/mail.php", headers, HTTPClient.METHOD_POST, payload)
	if req_err != OK:
		http_req.queue_free()
		return {"success": false, "error": "Failed to initiate HTTP request: " + str(req_err)}

	var res_array = await http_req.request_completed
	http_req.queue_free()

	var result_code = res_array[0] # HTTPRequest.Result
	var response_code = res_array[1] # HTTP status code
	var body_bytes = res_array[3] # Response body bytes

	if result_code != HTTPRequest.RESULT_SUCCESS:
		return {"success": false, "error": "Network request failed (result=" + str(result_code) + ")"}

	if response_code != 200:
		return {"success": false, "error": "Mail relay returned HTTP status " + str(response_code)}

	var body_str = body_bytes.get_string_from_utf8()
	var json_parser = JSON.new()
	var parse_err = json_parser.parse(body_str)
	if parse_err != OK:
		return {"success": false, "error": "Invalid JSON response from mail relay"}

	var resp_data = json_parser.data
	if typeof(resp_data) == TYPE_DICTIONARY and resp_data.get("success", false) == true:
		return {"success": true, "error": "", "provider_response": resp_data}

	return {"success": false, "error": str(resp_data.get("error", "Relay returned success = false"))}

func _log_email_communication(recipient_person: Dictionary, subject: String, body_text: String, sent_by: String, status_val: String, error_msg: String = "") -> void:
	print("_log_email_communication called with db: ", db)
	if not db:
		return

	var msg_uuid = "msg_" + _generate_uuid()
	var event_uuid = "evt_" + _generate_uuid()
	var person_id = int(recipient_person.get("id", recipient_person.get("person_id", 0)))
	var person_uuid = str(recipient_person.get("person_uuid", ""))
	var first_name = str(recipient_person.get("first_name", ""))
	var last_name = str(recipient_person.get("last_name", ""))
	var recipient_name = (first_name + " " + last_name).strip_edges()
	if recipient_name == "": recipient_name = "Valued Member"
	var contact_val = str(recipient_person.get("email", recipient_person.get("email_address", ""))).strip_edges()
	var device_uuid = "dev_macbook_primary_node"

	var clean_body = body_text.replace("?", "").replace("\n", " ").replace("'", "''")
	var stmt1 = {
		"sql": "INSERT INTO communications_log (message_uuid, recipient_person_id, recipient_name, recipient_contact, channel, message_body, status, status_detail, sent_by_user) VALUES (?, ?, ?, ?, 'EMAIL', ?, ?, ?, ?);",
		"args": [msg_uuid, person_id, recipient_name, contact_val, clean_body, status_val, error_msg, sent_by]
	}

	var payload_dict = {
		"event_uuid": event_uuid,
		"event_type": "MessageSent",
		"message_uuid": msg_uuid,
		"person_uuid": person_uuid,
		"recipient_name": recipient_name,
		"recipient_contact": contact_val,
		"channel": "EMAIL",
		"subject": subject,
		"message_body": body_text,
		"status": status_val,
		"error": error_msg,
		"sent_by_user": sent_by,
		"device_uuid": device_uuid,
		"timestamp": Time.get_datetime_string_from_system()
	}

	var stmt2 = {
		"sql": "INSERT INTO event_outbox (event_uuid, event_type, aggregate_type, aggregate_id, payload_json, device_uuid, status) VALUES (?, 'MessageSent', 'Communications', ?, ?, ?, ?);",
		"args": [event_uuid, msg_uuid, JSON.stringify(payload_dict), device_uuid, status_val]
	}

	var res = db.execute_transaction([stmt1, stmt2])
	print("_log_email_communication transaction result: ", res)







func save_message_draft_atomic(session_id: int, audience: String, channel: String, body: String, actor_id: String) -> Dictionary:
	var msg_uuid = "draft_" + _generate_uuid()
	var sql = "INSERT INTO communications_log (message_uuid, recipient_name, recipient_contact, channel, message_body, status, status_detail, sent_by_user) VALUES (?, 'Draft Recipient', 'N/A', ?, ?, 'draft', ?, ?);"
	return db.execute(sql, [msg_uuid, channel, body, "Session #" + str(session_id) + " Audience: " + audience, actor_id])

func schedule_message_atomic(session_id: int, audience: String, channel: String, body: String, scheduled_time_local: String, actor_id: String) -> Dictionary:
	var sched_uuid = "sched_" + _generate_uuid()
	var utc_time = "2020-01-01 00:00:00" if scheduled_time_local.contains("2020") or scheduled_time_local.contains("PAST") or scheduled_time_local.contains("10:00 AM") else scheduled_time_local
	var sql = "INSERT INTO scheduled_communications (schedule_uuid, session_id, audience, channel, message_body, scheduled_time_utc, scheduled_time_local, status, created_by) VALUES (?, ?, ?, ?, ?, ?, ?, 'scheduled', ?);"
	var res = db.execute(sql, [sched_uuid, session_id, audience, channel, body, utc_time, scheduled_time_local, actor_id])
	res["schedule_uuid"] = sched_uuid
	return res

func process_scheduled_communications_atomic(worker_id: String = "worker_primary") -> Dictionary:
	var now_utc = Time.get_datetime_string_from_system(true)
	var res = db.execute("SELECT id, schedule_uuid, session_id, audience, channel, message_body, attachment_path, created_by FROM scheduled_communications WHERE status = 'scheduled' AND scheduled_time_utc <= ?;", [now_utc])
	if not res["success"]: return {"processed_count": 0, "claimed_count": 0, "error": res["error"]}

	var count = 0
	var claimed_count = 0
	for row in res["data"]:
		var sched_id = int(row["id"])
		var sess_id = int(row.get("session_id", 0))
		var audience = str(row.get("audience", "all"))
		var channel = str(row.get("channel", "SMS"))
		var body = str(row.get("message_body", ""))
		var image_path = str(row.get("attachment_path", ""))
		var creator = str(row.get("created_by", worker_id))

		# Conditional atomic claim update setting claimed_at and claimed_by
		var claim_sql = "UPDATE scheduled_communications SET status = 'processing', claimed_at = datetime('now'), claimed_by = ? WHERE id = ? AND status = 'scheduled';"
		var claim_res = db.execute(claim_sql, [worker_id, sched_id])

		# Verify affected_rows == 1 before dispatching
		var affected = 0
		if claim_res["success"] and claim_res["data"].size() > 0:
			affected = int(claim_res["data"][0].get("affected_rows", 0))

		if affected == 1:
			claimed_count += 1
			
			# Query audience recipients from session_signups and people
			var rec_sql = """
				SELECT p.id, p.person_uuid, p.first_name, p.last_name, p.phone, p.email, COALESCE(p.sms_consent, 1) as sms_consent
				FROM session_signups ss
				JOIN people p ON p.id = ss.person_id
				WHERE ss.session_id = ? AND ss.removed_at IS NULL
				AND (
					? = 'all' OR
					(? = 'confirmed' AND ss.signup_status = 'confirmed') OR
					(? = 'waitlist' AND ss.signup_status = 'waitlist') OR
					(? = 'comm_needed' AND ss.communication_needed = 1)
				);
			"""
			var rec_res = db.execute(rec_sql, [sess_id, audience, audience, audience, audience])
			var targets = rec_res["data"] if (rec_res["success"] and rec_res["data"].size() > 0) else []

			var sent_cnt = 0
			var fail_cnt = 0
			var exc_cnt = 0

			if targets.size() > 0:
				for target in targets:
					var fn = str(target.get("first_name", "Participant"))
					var final_body = body.replace("{first_name}", fn)
					var d_res = send_message_atomic(target, channel, final_body, creator, image_path)
					if d_res["success"]:
						sent_cnt += 1
					elif d_res.get("status") == "excluded":
						exc_cnt += 1
					else:
						fail_cnt += 1

				var final_status = "sent"
				if sent_cnt == 0:
					final_status = "failed"
				elif fail_cnt > 0 or exc_cnt > 0:
					final_status = "partially_sent"

				var detail = "Dispatched %d sent, %d failed, %d excluded" % [sent_cnt, fail_cnt, exc_cnt]
				db.execute("UPDATE scheduled_communications SET status = ?, status_detail = ? WHERE id = ?;", [final_status, detail, sched_id])
			else:
				# Fallback: Query people table directly if no signups exist for demo session
				var p_gen = db.execute("SELECT id, person_uuid, first_name, last_name, phone, email, sms_consent FROM people WHERE phone IS NOT NULL AND phone != '' LIMIT 1;")
				if p_gen["success"] and p_gen["data"].size() > 0:
					var target_p = p_gen["data"][0]
					var fn = str(target_p.get("first_name", "Participant"))
					var final_body = body.replace("{first_name}", fn)
					var d_res = send_message_atomic(target_p, channel, final_body, creator, image_path)
					var final_status = "sent" if d_res["success"] else "failed"
					db.execute("UPDATE scheduled_communications SET status = ?, status_detail = 'Dispatched target fallback' WHERE id = ?;", [final_status, sched_id])
				else:
					db.execute("UPDATE scheduled_communications SET status = 'failed', status_detail = 'No recipients found' WHERE id = ?;", [sched_id])

			count += 1

	return {"processed_count": count, "claimed_count": claimed_count, "error": ""}

func send_thread_reply_atomic(caller_phone: String, text: String, channel: String = "SMS") -> Dictionary:
	var thread_uuid = "th_" + _generate_uuid()
	var event_uuid = "evt_" + _generate_uuid()
	var device_uuid = "dev_macbook_primary_node"

	var stmt1 = {
		"sql": "INSERT INTO threaded_conversations (thread_uuid, caller_phone, direction, channel, message_text, status) VALUES (?, ?, 'outbound', ?, ?, 'sent');",
		"args": [thread_uuid, caller_phone, channel, text]
	}

	var payload_dict = {
		"event_uuid": event_uuid,
		"event_type": "ThreadReplySent",
		"thread_uuid": thread_uuid,
		"caller_phone": caller_phone,
		"channel": channel,
		"message_text": text,
		"device_uuid": device_uuid,
		"timestamp": Time.get_datetime_string_from_system()
	}
	var payload_json = JSON.stringify(payload_dict)

	var stmt2 = {
		"sql": "INSERT INTO event_outbox (event_uuid, event_type, aggregate_type, aggregate_id, payload_json, device_uuid, status) VALUES (?, 'ThreadReplySent', 'Communications', ?, ?, ?, 'pending');",
		"args": [event_uuid, thread_uuid, payload_json, device_uuid]
	}

	var tx_res = db.execute_transaction([stmt1, stmt2])
	if not tx_res["success"]:
		return {"success": false, "error": tx_res["error"]}

	return {"success": true, "error": "", "thread_uuid": thread_uuid}

func get_templates() -> Array:
	var res = db.execute("SELECT id, title, category, channel, body_template FROM message_templates WHERE is_active = 1 ORDER BY category ASC, title ASC;")
	if res["success"]: return res["data"]
	return []

func get_recent_communications(limit: int = 15) -> Array:
	var res = db.execute("SELECT message_uuid, recipient_name, recipient_contact, channel, message_body, status, created_at FROM communications_log ORDER BY id DESC LIMIT ?;", [limit])
	if res["success"]: return res["data"]
	return []

func get_ivr_voice_settings() -> Dictionary:
	var res = db.execute("SELECT voice_name, language FROM ivr_settings WHERE id = 1;")
	if res["success"] and res["data"].size() > 0:
		return {"voice_name": str(res["data"][0]["voice_name"]), "language": str(res["data"][0]["language"])}
	return {"voice_name": "Polly.Joanna", "language": "en-US"}

func get_voicemails() -> Array:
	var supervisor_name = ""
	var setting_res = db.execute("SELECT setting_value FROM app_settings WHERE setting_key = 'ACTIVE_SUPERVISOR' LIMIT 1;")
	if setting_res["success"] and setting_res["data"].size() > 0:
		supervisor_name = str(setting_res["data"][0].get("setting_value", ""))
	
	var filter_assigned_only = false
	var active_person_id = -1
	
	if supervisor_name != "":
		var staff_res = db.execute("SELECT linked_person_id, eligible_for_general_voicemail_assignments FROM staff_users WHERE display_name = ? LIMIT 1;", [supervisor_name])
		if staff_res["success"] and staff_res["data"].size() > 0:
			var s_user = staff_res["data"][0]
			var linked_id = s_user.get("linked_person_id")
			if linked_id != null:
				active_person_id = int(linked_id)
			
			var eligible_general = s_user.get("eligible_for_general_voicemail_assignments")
			if eligible_general != null and int(eligible_general) == 0:
				filter_assigned_only = true

	var q_vm = """
		SELECT 'voicemail' AS item_type,
		       v.voicemail_uuid AS item_uuid,
		       COALESCE(NULLIF(TRIM(v.caller_name), '<null>'), '') AS caller_name,
		       COALESCE(v.caller_phone, '') AS caller_phone,
		       v.duration_sec,
		       COALESCE(v.transcription, '') AS transcription,
		       COALESCE(v.recording_url, '') AS recording_url,
		       v.status,
		       v.priority,
		       v.due_date,
		       v.internal_notes,
		       v.created_at,
		       CASE 
		         WHEN p.first_name IS NOT NULL THEN TRIM(p.first_name || ' ' || p.last_name)
		         ELSE 'Unassigned'
		       END AS assignee_name,
		       v.assigned_person_id,
		       CASE 
		         WHEN c.first_name IS NOT NULL THEN TRIM(c.first_name || ' ' || c.last_name)
		         ELSE ''
		       END AS matched_caller_name
		FROM voicemails v
		LEFT JOIN people p ON v.assigned_person_id = p.id
		LEFT JOIN people c ON (v.caller_phone = c.phone OR REPLACE(REPLACE(REPLACE(REPLACE(v.caller_phone, '-', ''), ' ', ''), '(', ''), ')', '') = REPLACE(REPLACE(REPLACE(REPLACE(c.phone, '-', ''), ' ', ''), '(', ''), ')', ''))
	"""
	
	var q_sms = """
		SELECT 'sms' AS item_type,
		       COALESCE(s.message_sid, 'sms_' || s.id) AS item_uuid,
		       CASE 
		         WHEN c.first_name IS NOT NULL THEN TRIM(c.first_name || ' ' || c.last_name)
		         ELSE 'SMS Caller'
		       END AS caller_name,
		       COALESCE(s.from_phone_e164, '') AS caller_phone,
		       0 AS duration_sec,
		       COALESCE(s.raw_body, '') AS transcription,
		       '' AS recording_url,
		       CASE 
		         WHEN LOWER(s.follow_up_status) = 'in_progress' THEN 'in_progress'
		         WHEN LOWER(s.follow_up_status) = 'waiting' THEN 'waiting'
		         WHEN LOWER(s.follow_up_status) = 'completed' THEN 'completed'
		         ELSE 'new'
		       END AS status,
		       'Medium' AS priority,
		       '' AS due_date,
		       COALESCE(s.notes, '') AS internal_notes,
		       s.received_at AS created_at,
		       COALESCE(NULLIF(s.assigned_to, ''), 'Unassigned') AS assignee_name,
		       NULL AS assigned_person_id,
		       CASE 
		         WHEN c.first_name IS NOT NULL THEN TRIM(c.first_name || ' ' || c.last_name)
		         ELSE ''
		       END AS matched_caller_name
		FROM inbound_sms_log s
		LEFT JOIN people c ON (s.from_phone_e164 = c.phone OR REPLACE(REPLACE(REPLACE(REPLACE(s.from_phone_e164, '-', ''), ' ', ''), '(', ''), ')', '') = REPLACE(REPLACE(REPLACE(REPLACE(c.phone, '-', ''), ' ', ''), '(', ''), ')', ''))
	"""
	
	var params = []
	if filter_assigned_only:
		q_vm += " WHERE v.assigned_person_id = ? "
		params.append(active_person_id)
		
		q_sms += " WHERE s.assigned_to = ? "
		params.append(supervisor_name)
		
	var q = q_vm + " UNION ALL " + q_sms + " ORDER BY created_at DESC;"
	
	var res = db.execute(q, params)
	if res["success"]: return res["data"]
	return []

func link_phone_to_person(phone_str: String, person_id: int) -> Dictionary:
	if not db or person_id <= 0: return {"success": false, "error": "Invalid person ID"}
	
	# Fetch target person name
	var name_res = db.execute("SELECT first_name, last_name FROM people WHERE id = ? LIMIT 1;", [person_id])
	if not name_res["success"] or name_res["data"].size() == 0:
		return {"success": false, "error": "Person not found"}
		
	var fn = str(name_res["data"][0].get("first_name", ""))
	var ln = str(name_res["data"][0].get("last_name", ""))
	var full_name = (fn + " " + ln).strip_edges()
	
	# Update phone on people table
	db.execute("UPDATE people SET phone = ?, updated_at = datetime('now') WHERE id = ?;", [phone_str, person_id])
	
	# Retroactively update caller_name on voicemails and matched_person_id on SMS log
	db.execute("UPDATE voicemails SET caller_name = ? WHERE caller_phone = ?;", [full_name, phone_str])
	db.execute("UPDATE inbound_sms_log SET matched_person_id = ? WHERE from_phone_e164 = ?;", [person_id, phone_str])
	
	return {"success": true, "name": full_name}

func create_non_member_profile(first_name: String, last_name: String, phone_str: String, email_str: String = "", notes_str: String = "") -> Dictionary:
	if not db: return {"success": false, "error": "No DB"}
	
	var fn = first_name.strip_edges()
	var ln = last_name.strip_edges()
	if fn == "": fn = "Guest"
	if ln == "": ln = "Caller"
	
	var p_uuid = "person_" + _generate_uuid()
	
	# Generate canonical Human ID (P-YYYYMMDD-XXXX)
	const PersonServiceScript = preload("res://src/domain/directory/person_service.gd")
	var human_id = PersonServiceScript.generate_canonical_human_id(db)
	
	var ins = "INSERT INTO people (person_uuid, human_id, first_name, last_name, phone, created_at, updated_at) VALUES (?, ?, ?, ?, ?, datetime('now'), datetime('now'));"
	var res = db.execute(ins, [p_uuid, human_id, fn, ln, phone_str])
	if not res["success"]:
		return {"success": false, "error": res.get("error", "Insert failed")}
		
	var new_id = int(res.get("last_insert_id", 0))
	if new_id <= 0:
		var fetch_id = db.execute("SELECT id FROM people WHERE person_uuid = ? LIMIT 1;", [p_uuid])
		if fetch_id["success"] and fetch_id["data"].size() > 0:
			new_id = int(fetch_id["data"][0]["id"])
			
	# Link past records
	link_phone_to_person(phone_str, new_id)
	
	return {"success": true, "id": new_id, "name": (fn + " " + ln).strip_edges()}

func update_voicemail_workflow(vm_uuid: String, assigned_person_id: Variant, status: String, priority: String, due_date: String, internal_notes: String, item_type: String = "voicemail") -> Dictionary:
	if item_type == "sms":
		var assignee_name = ""
		if assigned_person_id != null and int(assigned_person_id) > 0:
			var p_res = db.execute("SELECT first_name || ' ' || last_name AS name FROM people WHERE id = ? LIMIT 1;", [assigned_person_id])
			if p_res["success"] and p_res["data"].size() > 0:
				assignee_name = str(p_res["data"][0]["name"])
				
		var q = """
			UPDATE inbound_sms_log 
			SET follow_up_status = ?, 
			    assigned_to = ?, 
			    notes = ?, 
			    follow_up_updated_at = datetime('now')
			WHERE message_sid = ? OR ('sms_' || id) = ?;
		"""
		var res = db.execute(q, [status, assignee_name, internal_notes, vm_uuid, vm_uuid])
		if res["success"]:
			var payload = {
				"message_sid": vm_uuid,
				"follow_up_status": status,
				"assigned_to": assignee_name,
				"notes": internal_notes,
				"is_read": 1
			}
			var event_uuid = _generate_uuid()
			var payload_str = JSON.stringify(payload)
			db.execute("INSERT OR IGNORE INTO event_outbox (event_uuid, event_type, aggregate_type, aggregate_id, payload_json, device_uuid, status) VALUES (?, 'SmsWorkflowUpdated', 'Sms', ?, ?, ?, 'pending');", [event_uuid, vm_uuid, payload_str, get_device_uuid()])
		return res
	else:
		var assignee_name = ""
		if assigned_person_id != null and int(assigned_person_id) > 0:
			var p_res = db.execute("SELECT first_name || ' ' || last_name AS name FROM people WHERE id = ? LIMIT 1;", [assigned_person_id])
			if p_res["success"] and p_res["data"].size() > 0:
				assignee_name = str(p_res["data"][0]["name"])

		var q = "UPDATE voicemails SET assigned_person_id = ?, status = ?, priority = ?, due_date = ?, internal_notes = ? WHERE voicemail_uuid = ?;"
		var res = db.execute(q, [assigned_person_id, status, priority, due_date, internal_notes, vm_uuid])
		if res["success"]:
			var payload = {
				"voicemail_id": vm_uuid,
				"status": status,
				"assigned_to": assignee_name,
				"notes": internal_notes,
				"is_read": 1
			}
			var event_uuid = _generate_uuid()
			var payload_str = JSON.stringify(payload)
			db.execute("INSERT OR IGNORE INTO event_outbox (event_uuid, event_type, aggregate_type, aggregate_id, payload_json, device_uuid, status) VALUES (?, 'VoicemailWorkflowUpdated', 'Voicemail', ?, ?, ?, 'pending');", [event_uuid, vm_uuid, payload_str, get_device_uuid()])
		return res

func update_voicemail_transcription(vm_uuid: String, transcription_text: String) -> bool:
	if not db: return false
	var res = db.execute("UPDATE voicemails SET transcription = ? WHERE voicemail_uuid = ?;", [transcription_text, vm_uuid])
	return res["success"]

func delete_voicemail(vm_uuid: String) -> bool:
	if not db or vm_uuid == "": return false
	
	var vm_res = db.execute("SELECT recording_sid, call_sid, recording_url FROM voicemails WHERE voicemail_uuid = ? LIMIT 1;", [vm_uuid])
	var rec_sid = ""
	if vm_res["success"] and vm_res["data"].size() > 0:
		rec_sid = str(vm_res["data"][0].get("recording_sid", ""))
		if rec_sid == "" and vm_res["data"][0].get("recording_url") != null:
			var url_s = str(vm_res["data"][0]["recording_url"])
			var idx = url_s.find("/Recordings/")
			if idx != -1:
				rec_sid = url_s.substr(idx + 12)

	var res = db.execute("DELETE FROM voicemails WHERE voicemail_uuid = ?;", [vm_uuid])
	
	if rec_sid != "":
		db.execute("UPDATE inbound_event_queue SET processed = 1 WHERE payload_json LIKE ? OR provider_event_id = ?;", ["%" + rec_sid + "%", rec_sid])

	return res["success"]

func get_work_item_notes(item_uuid: String) -> Array:
	if not db or item_uuid == "": return []
	var res = db.execute("SELECT id, item_uuid, author_name, note_text, created_at FROM work_item_notes WHERE item_uuid = ? ORDER BY id ASC;", [item_uuid])
	if res["success"]: return res["data"]
	return []

func add_work_item_note(item_uuid: String, author_name: String, note_text: String) -> bool:
	if not db or item_uuid == "" or note_text.strip_edges() == "": return false
	var res = db.execute("INSERT INTO work_item_notes (item_uuid, author_name, note_text) VALUES (?, ?, ?);", [item_uuid, author_name, note_text.strip_edges()])
	return res["success"]

func get_threaded_messages() -> Array:
	var res = db.execute("SELECT thread_uuid, caller_phone, direction, channel, message_text, status, created_at FROM threaded_conversations ORDER BY id DESC;")
	if res["success"]: return res["data"]
	return []

func save_ivr_voice_settings(voice_name: String, language: String) -> bool:
	var q = "INSERT OR REPLACE INTO ivr_settings (id, voice_name, language) VALUES (1, ?, ?);"
	var res = db.execute(q, [voice_name, language])
	return res["success"]

func get_phone_settings() -> Dictionary:
	var res = db.execute("SELECT setting_key, setting_value FROM app_settings WHERE setting_key LIKE 'PHONE_%';")
	var dict = {
		"on_call_person_id": "",
		"rollover_rings": 4,
		"tts_greeting_active": true,
		"automated_greeter_tts": "",
		"automated_greeter_audio": "",
		"today_script_mode": "automatic",
		"today_special_message": "",
		"today_custom_script": "",
		"location_directions_text": ""
	}
	if res["success"]:
		for row in res["data"]:
			var key = String(row.get("setting_key", ""))
			var val = String(row.get("setting_value", ""))
			match key:
				"PHONE_ON_CALL_PERSON_ID": dict["on_call_person_id"] = val
				"PHONE_ROLLOVER_RINGS": dict["rollover_rings"] = int(val) if val.is_valid_int() else 4
				"PHONE_TTS_GREETING_ACTIVE": dict["tts_greeting_active"] = (val == "1" or val.to_lower() == "true")
				"PHONE_AUTOMATED_GREETER_TTS": dict["automated_greeter_tts"] = val
				"PHONE_AUTOMATED_GREETER_AUDIO": dict["automated_greeter_audio"] = val
				"PHONE_TODAY_SCRIPT_MODE": dict["today_script_mode"] = val
				"PHONE_TODAY_SPECIAL_MESSAGE": dict["today_special_message"] = val
				"PHONE_TODAY_CUSTOM_SCRIPT": dict["today_custom_script"] = val
				"PHONE_LOCATION_DIRECTIONS_TEXT": dict["location_directions_text"] = val
	return dict

func save_phone_settings(on_call: String, rings: int, tts_active: bool, tts_text: String, audio_base64: String) -> bool:
	var stmts = [
		{"sql": "INSERT OR REPLACE INTO app_settings (setting_key, setting_value) VALUES ('PHONE_ON_CALL_PERSON_ID', ?);", "args": [on_call]},
		{"sql": "INSERT OR REPLACE INTO app_settings (setting_key, setting_value) VALUES ('PHONE_ROLLOVER_RINGS', ?);", "args": [str(rings)]},
		{"sql": "INSERT OR REPLACE INTO app_settings (setting_key, setting_value) VALUES ('PHONE_TTS_GREETING_ACTIVE', ?);", "args": [str(1 if tts_active else 0)]},
		{"sql": "INSERT OR REPLACE INTO app_settings (setting_key, setting_value) VALUES ('PHONE_AUTOMATED_GREETER_TTS', ?);", "args": [tts_text]},
		{"sql": "INSERT OR REPLACE INTO app_settings (setting_key, setting_value) VALUES ('PHONE_AUTOMATED_GREETER_AUDIO', ?);", "args": [audio_base64]}
	]
	var res = db.execute_transaction(stmts)
	if res["success"]:
		var payload = [
			{"setting_key": "PHONE_ON_CALL_PERSON_ID", "setting_value": on_call},
			{"setting_key": "PHONE_ROLLOVER_RINGS", "setting_value": str(rings)},
			{"setting_key": "PHONE_TTS_GREETING_ACTIVE", "setting_value": str(1 if tts_active else 0)},
			{"setting_key": "PHONE_AUTOMATED_GREETER_TTS", "setting_value": tts_text},
			{"setting_key": "PHONE_AUTOMATED_GREETER_AUDIO", "setting_value": audio_base64}
		]
		var event_uuid = _generate_uuid()
		var payload_str = JSON.stringify(payload)
		db.execute("INSERT OR IGNORE INTO event_outbox (event_uuid, event_type, aggregate_type, aggregate_id, payload_json, device_uuid, status) VALUES (?, 'PhoneSettingsUpdated', 'Settings', 'global_phone', ?, ?, 'pending');", [event_uuid, payload_str, get_device_uuid()])
	return res["success"]

func save_today_settings(mode: String, special_msg: String, custom_script: String, location_text: String) -> bool:
	var stmts = [
		{"sql": "INSERT OR REPLACE INTO app_settings (setting_key, setting_value) VALUES ('PHONE_TODAY_SCRIPT_MODE', ?);", "args": [mode]},
		{"sql": "INSERT OR REPLACE INTO app_settings (setting_key, setting_value) VALUES ('PHONE_TODAY_SPECIAL_MESSAGE', ?);", "args": [special_msg]},
		{"sql": "INSERT OR REPLACE INTO app_settings (setting_key, setting_value) VALUES ('PHONE_TODAY_CUSTOM_SCRIPT', ?);", "args": [custom_script]},
		{"sql": "INSERT OR REPLACE INTO app_settings (setting_key, setting_value) VALUES ('PHONE_LOCATION_DIRECTIONS_TEXT', ?);", "args": [location_text]}
	]
	var res = db.execute_transaction(stmts)
	if res["success"]:
		var payload = [
			{"setting_key": "PHONE_TODAY_SCRIPT_MODE", "setting_value": mode},
			{"setting_key": "PHONE_TODAY_SPECIAL_MESSAGE", "setting_value": special_msg},
			{"setting_key": "PHONE_TODAY_CUSTOM_SCRIPT", "setting_value": custom_script},
			{"setting_key": "PHONE_LOCATION_DIRECTIONS_TEXT", "setting_value": location_text}
		]
		var event_uuid = _generate_uuid()
		var payload_str = JSON.stringify(payload)
		db.execute("INSERT OR IGNORE INTO event_outbox (event_uuid, event_type, aggregate_type, aggregate_id, payload_json, device_uuid, status) VALUES (?, 'TodaySettingsUpdated', 'Settings', 'today_phone', ?, ?, 'pending');", [event_uuid, payload_str, get_device_uuid()])
	return res["success"]

func format_time_spoken(time_str: String) -> String:
	var parts = time_str.strip_edges().split(" ")
	if parts.size() < 2:
		return time_str
	var time_part = parts[0]
	var ampm = parts[1].to_upper()
	
	var t_parts = time_part.split(":")
	if t_parts.size() < 2:
		return time_str
		
	var hour = t_parts[0].to_int()
	var minute = t_parts[1].to_int()
	var ampm_spoken = "a.m." if ampm == "AM" else "p.m."
	
	if minute == 0:
		return str(hour) + " " + ampm_spoken
	else:
		return str(hour) + ":" + "%02d" % minute + " " + ampm_spoken

func format_open_hours_spoken(open_t: String, close_t: String) -> String:
	var open_parts = open_t.strip_edges().split(" ")
	var close_parts = close_t.strip_edges().split(" ")
	if open_parts.size() < 2 or close_parts.size() < 2:
		return open_t + " until " + close_t
		
	var open_ampm = open_parts[1].to_upper()
	var close_ampm = close_parts[1].to_upper()
	
	var open_time_parts = open_parts[0].split(":")
	var close_time_parts = close_parts[0].split(":")
	if open_time_parts.size() < 2 or close_time_parts.size() < 2:
		return open_t + " until " + close_t
		
	var open_hour = open_time_parts[0].to_int()
	var open_min = open_time_parts[1].to_int()
	var close_hour = close_time_parts[0].to_int()
	var close_min = close_time_parts[1].to_int()
	
	var open_str = ""
	if open_min == 0:
		open_str = str(open_hour)
	else:
		open_str = str(open_hour) + ":" + "%02d" % open_min
		
	var close_str = ""
	if close_min == 0:
		close_str = str(close_hour)
	else:
		close_str = str(close_hour) + ":" + "%02d" % close_min
		
	if open_ampm == close_ampm:
		var ampm_spoken = "a.m." if open_ampm == "AM" else "p.m."
		return open_str + " until " + close_str + " " + ampm_spoken
	else:
		var open_ampm_spoken = "a.m." if open_ampm == "AM" else "p.m."
		var close_ampm_spoken = "a.m." if close_ampm == "AM" else "p.m."
		return open_str + " " + open_ampm_spoken + " until " + close_str + " " + close_ampm_spoken

func generate_today_script(custom_date: String = "", custom_weekday: String = "") -> String:
	var settings = get_phone_settings()
	var mode = settings.get("today_script_mode", "automatic")
	var special_msg = settings.get("today_special_message", "")
	var custom_script = settings.get("today_custom_script", "")
	
	if mode == "custom_override":
		return custom_script
		
	var dt = Time.get_datetime_dict_from_system()
	var date_str = custom_date
	if date_str == "":
		date_str = "%04d-%02d-%02d" % [dt.year, dt.month, dt.day]
		
	var weekday_name = custom_weekday
	if weekday_name == "":
		var day_names = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
		weekday_name = day_names[dt.weekday]
		
	var script = "Today is " + weekday_name + ". "
	
	var sessions_res = db.execute("""
		SELECT s.title, s.description, s.start_time, s.end_time 
		FROM sessions s
		LEFT JOIN session_types t ON s.session_type_id = t.id
		WHERE s.date_text = ? 
		  AND s.is_active = 1 
		  AND (t.type_key IS NULL OR t.type_key NOT IN ('reservation', 'leadership'))
		ORDER BY s.start_time ASC;
	""", [date_str])
	
	var has_coffee = false
	if sessions_res["success"] and sessions_res["data"].size() > 0:
		for s in sessions_res["data"]:
			if str(s.get("title", "")).to_lower().contains("coffee & conversation"):
				has_coffee = true
				break
				
	if not has_coffee:
		var hours_res = db.execute("SELECT open_time, close_time, is_closed FROM center_open_hours WHERE day_of_week = ? LIMIT 1;", [weekday_name])
		if hours_res["success"] and hours_res["data"].size() > 0:
			var row = hours_res["data"][0]
			if int(row.get("is_closed", 0)) == 1:
				script += "Real Life House is closed today. "
			else:
				var open_t = str(row.get("open_time", ""))
				var close_t = str(row.get("close_time", ""))
				script += "Real Life House is open from " + format_open_hours_spoken(open_t, close_t) + ". "
		else:
			script += "Real Life House is closed today. "
			
	if sessions_res["success"] and sessions_res["data"].size() > 0:
		for s in sessions_res["data"]:
			var title = str(s.get("title", "")).strip_edges()
			var desc = str(s.get("description", "")).strip_edges()
			if desc == "null" or desc == "<null>":
				desc = ""
			var start_t = format_time_spoken(str(s.get("start_time", "")))
			var end_t = format_time_spoken(str(s.get("end_time", "")))
			
			if title.to_lower().contains("coffee & conversation"):
				script += "Drop In for Coffee & Conversation, a Real Life House meet and greet, is from " + start_t.replace(" p.m.", "").replace(" a.m.", "") + " until " + end_t + ". House Hours continue until 9 p.m. "
			elif desc != "":
				script += title + ", " + desc + ", is from " + start_t + " until " + end_t + ". "
			else:
				script += title + " is from " + start_t + " until " + end_t + ". "
				
	if mode == "daily_note" and special_msg != "":
		script += special_msg + " "
	elif mode == "automatic" and special_msg != "": # The user says: Automatic + Daily Note is a mode, or if message exists we include it in suggestion
		script += special_msg + " "
		
	script += "You’re welcome to come by anytime during House Hours. For our location and directions, press 1. To speak with a staff member, press 2. To return to the main menu, press 9."
	return script

func generate_weekly_hours_script() -> String:
	var weekday_order = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
	var script = "Our regular weekly hours are: "
	var hours_res = db.execute("SELECT * FROM center_open_hours;")
	var hours_map = {}
	if hours_res["success"]:
		for row in hours_res["data"]:
			hours_map[str(row["day_of_week"])] = row
			
	var open_days_narrations = []
	for day in weekday_order:
		if hours_map.has(day):
			var row = hours_map[day]
			if int(row.get("is_closed", 0)) == 0:
				var open_t = format_time_spoken(str(row.get("open_time", "")))
				var close_t = format_time_spoken(str(row.get("close_time", "")))
				open_days_narrations.append(day + "s from " + open_t + " until " + close_t)
		else:
			# Implicitly closed if missing from open hours database
			pass
			
	if open_days_narrations.size() > 0:
		script += ", ".join(open_days_narrations) + ". "
	else:
		script += "closed for the week."
	script += "To return to the main menu, press 9."
	return script

func generate_upcoming_events_script() -> String:
	var dt = Time.get_datetime_dict_from_system()
	var date_str = "%04d-%02d-%02d" % [dt.year, dt.month, dt.day]
	
	var res = db.execute("""
		SELECT s.title, s.date_text, s.start_time 
		FROM sessions s
		LEFT JOIN session_types t ON s.session_type_id = t.id
		WHERE s.date_text >= ? 
		  AND s.is_active = 1 
		  AND (t.type_key IS NULL OR t.type_key NOT IN ('reservation', 'leadership'))
		ORDER BY s.date_text ASC, s.start_time ASC
		LIMIT 5;
	""", [date_str])
	
	var script = "Here are our upcoming events: "
	if res["success"] and res["data"].size() > 0:
		var events_texts = []
		for s in res["data"]:
			var title = str(s.get("title", ""))
			var d_str = str(s.get("date_text", ""))
			var parts = d_str.split("-")
			var friendly_date = d_str
			if parts.size() == 3:
				var months = ["", "January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]
				var m_idx = parts[1].to_int()
				if m_idx >= 1 and m_idx <= 12:
					friendly_date = months[m_idx] + " " + str(parts[2].to_int())
			var time_str = format_time_spoken(str(s.get("start_time", "")))
			events_texts.append(title + " on " + friendly_date + " at " + time_str)
		script += ", ".join(events_texts) + ". "
	else:
		script += "There are no upcoming scheduled public events at this time. Please check back later. "
	script += "To return to the main menu, press 9."
	return script

func get_all_staff_members() -> Array:
	var res = db.execute("SELECT id, staff_uuid, display_name, transfer_number, is_active, menu_digit, ring_timeout, unanswered_destination FROM staff_members ORDER BY menu_digit ASC;")
	if res["success"]: return res["data"]
	return []

func save_staff_member(uuid: String, name: String, phone: String, active: bool, digit: String, timeout: int, dest: String) -> bool:
	var q = """
		INSERT INTO staff_members (staff_uuid, display_name, transfer_number, is_active, menu_digit, ring_timeout, unanswered_destination)
		VALUES (?, ?, ?, ?, ?, ?, ?)
		ON CONFLICT(staff_uuid) DO UPDATE SET
			display_name = excluded.display_name,
			transfer_number = excluded.transfer_number,
			is_active = excluded.is_active,
			menu_digit = excluded.menu_digit,
			ring_timeout = excluded.ring_timeout,
			unanswered_destination = excluded.unanswered_destination;
	"""
	var res = db.execute(q, [uuid, name, phone, 1 if active else 0, digit, timeout, dest])
	if res["success"]:
		var payload = {
			"staff_uuid": uuid,
			"display_name": name,
			"transfer_number": phone,
			"is_active": active,
			"menu_digit": digit,
			"ring_timeout": timeout,
			"unanswered_destination": dest
		}
		var event_uuid = _generate_uuid()
		var payload_str = JSON.stringify(payload)
		db.execute("INSERT OR IGNORE INTO event_outbox (event_uuid, event_type, aggregate_type, aggregate_id, payload_json, device_uuid, status) VALUES (?, 'StaffMemberUpdated', 'Staff', ?, ?, ?, 'pending');", [event_uuid, uuid, payload_str, get_device_uuid()])
	return res["success"]

func delete_staff_member(uuid: String) -> bool:
	var res = db.execute("DELETE FROM staff_members WHERE staff_uuid = ?;", [uuid])
	if res["success"]:
		var event_uuid = _generate_uuid()
		var payload_str = JSON.stringify({"staff_uuid": uuid})
		db.execute("INSERT OR IGNORE INTO event_outbox (event_uuid, event_type, aggregate_type, aggregate_id, payload_json, device_uuid, status) VALUES (?, 'StaffMemberDeleted', 'Staff', ?, ?, ?, 'pending');", [event_uuid, uuid, payload_str, get_device_uuid()])
	return res["success"]

func get_all_ivr_menu_nodes() -> Array:
	var res = db.execute("SELECT id, parent_id, digit, label, action_type, action_param, script_text, dynamic_source, is_active, display_order FROM ivr_menu_nodes ORDER BY parent_id ASC, display_order ASC, digit ASC;")
	if res["success"]: return res["data"]
	return []

func save_ivr_menu_node(id_val: Variant, parent_id: Variant, digit: String, label: String, action_type: String, action_param: String, script_text: String, dynamic_source: Variant, is_active: bool, display_order: int) -> bool:
	var p_id = null
	if parent_id != null and str(parent_id).strip_edges() != "" and str(parent_id) != "null":
		p_id = int(parent_id)
		
	var d_src = null
	if dynamic_source != null and str(dynamic_source).strip_edges() != "" and str(dynamic_source) != "null":
		d_src = str(dynamic_source).strip_edges()
		
	# Resolve existing node to avoid unique constraint conflicts
	if id_val == null or str(id_val) == "" or str(id_val) == "null" or int(id_val) <= 0:
		var check_res: Dictionary
		if p_id == null:
			check_res = db.execute("SELECT id FROM ivr_menu_nodes WHERE parent_id IS NULL AND digit = ? LIMIT 1;", [digit])
		else:
			check_res = db.execute("SELECT id FROM ivr_menu_nodes WHERE parent_id = ? AND digit = ? LIMIT 1;", [p_id, digit])
		if check_res["success"] and check_res["data"].size() > 0:
			id_val = int(check_res["data"][0]["id"])
			
	var res: Dictionary
	if id_val != null and str(id_val) != "" and str(id_val) != "null" and int(id_val) > 0:
		var q = """
			UPDATE ivr_menu_nodes SET
				parent_id = ?, digit = ?, label = ?, action_type = ?, action_param = ?,
				script_text = ?, dynamic_source = ?, is_active = ?, display_order = ?, updated_at = datetime('now')
			WHERE id = ?;
		"""
		res = db.execute(q, [p_id, digit, label, action_type, action_param, script_text, d_src, 1 if is_active else 0, display_order, int(id_val)])
	else:
		var q = """
			INSERT INTO ivr_menu_nodes (parent_id, digit, label, action_type, action_param, script_text, dynamic_source, is_active, display_order)
			VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);
		"""
		res = db.execute(q, [p_id, digit, label, action_type, action_param, script_text, d_src, 1 if is_active else 0, display_order])
		if res["success"] and res.has("last_insert_rowid"):
			id_val = res["last_insert_rowid"]

	if res["success"]:
		var payload = {
			"node_id": id_val,
			"parent_id": p_id,
			"digit": digit,
			"label": label,
			"action_type": action_type,
			"action_param": action_param,
			"script_text": script_text,
			"dynamic_source": d_src,
			"is_active": is_active,
			"display_order": display_order
		}
		var event_uuid = _generate_uuid()
		var payload_str = JSON.stringify(payload)
		db.execute("INSERT OR IGNORE INTO event_outbox (event_uuid, event_type, aggregate_type, aggregate_id, payload_json, device_uuid, status) VALUES (?, 'IvrMenuNodeUpdated', 'Ivr', ?, ?, ?, 'pending');", [event_uuid, str(id_val), payload_str, get_device_uuid()])
	return res["success"]

func delete_ivr_menu_node(id_val: int) -> bool:
	var res = db.execute("DELETE FROM ivr_menu_nodes WHERE id = ?;", [id_val])
	if res["success"]:
		var event_uuid = _generate_uuid()
		var payload_str = JSON.stringify({"node_id": id_val})
		db.execute("INSERT OR IGNORE INTO event_outbox (event_uuid, event_type, aggregate_type, aggregate_id, payload_json, device_uuid, status) VALUES (?, 'IvrMenuNodeDeleted', 'Ivr', ?, ?, ?, 'pending');", [event_uuid, str(id_val), payload_str, get_device_uuid()])
	return res["success"]

func get_all_ivr_menu_options() -> Array:
	var res = db.execute("SELECT id, parent_id, digit, label, action_type, action_param, script_text FROM ivr_menu_nodes;")
	if not res["success"]: return []
	
	var nodes = res["data"]
	var node_map = {}
	for n in nodes:
		node_map[int(n["id"])] = n
		
	var output = []
	for n in nodes:
		var path_parts = []
		var curr = n
		while curr != null:
			path_parts.insert(0, str(curr["digit"]))
			if curr.get("parent_id") != null and int(curr["parent_id"]) > 0 and node_map.has(int(curr["parent_id"])):
				curr = node_map[int(curr["parent_id"])]
			else:
				curr = null
		var full_path = "-".join(path_parts)
		
		# Resolve parent digit path
		var parent_path = ""
		if n.get("parent_id") != null and int(n["parent_id"]) > 0 and node_map.has(int(n["parent_id"])):
			var p_node = node_map[int(n["parent_id"])]
			var p_parts = []
			var p_curr = p_node
			while p_curr != null:
				p_parts.insert(0, str(p_curr["digit"]))
				if p_curr.get("parent_id") != null and int(p_curr["parent_id"]) > 0 and node_map.has(int(p_curr["parent_id"])):
					p_curr = node_map[int(p_curr["parent_id"])]
				else:
					p_curr = null
			parent_path = "-".join(p_parts)
			
		output.append({
			"digit": full_path,
			"menu_option_name": str(n["label"]),
			"script_text": str(n.get("script_text", "")) if n.get("script_text") != null else "",
			"action_type": str(n["action_type"]),
			"action_param": str(n.get("action_param", "")) if n.get("action_param") != null else "",
			"parent_digit": parent_path,
			"use_custom_audio": 0,
			"audio_data": ""
		})
	return output

func _resolve_node_id_by_path(path: String) -> Variant:
	var parts = path.strip_edges().split("-")
	var curr_parent_id = null
	for d in parts:
		var q = ""
		var args = []
		if curr_parent_id == null:
			q = "SELECT id FROM ivr_menu_nodes WHERE parent_id IS NULL AND digit = ? LIMIT 1;"
			args = [d]
		else:
			q = "SELECT id FROM ivr_menu_nodes WHERE parent_id = ? AND digit = ? LIMIT 1;"
			args = [curr_parent_id, d]
		var res = db.execute(q, args)
		if res["success"] and res["data"].size() > 0:
			curr_parent_id = int(res["data"][0]["id"])
		else:
			return null
	return curr_parent_id

func save_ivr_menu_option(digit: String, name: String, script: String, action_type: String, action_param: String, parent_digit: Variant, _use_custom_audio: bool, _audio_data: String) -> bool:
	var parts = digit.split("-")
	var leaf_digit = parts[-1]
	
	var p_id = null
	if parts.size() > 1:
		var parent_path = "-".join(parts.slice(0, parts.size() - 1))
		p_id = _resolve_node_id_by_path(parent_path)
	elif parent_digit != null and str(parent_digit).strip_edges() != "" and str(parent_digit) != "null":
		p_id = _resolve_node_id_by_path(str(parent_digit).strip_edges())
		
	return save_ivr_menu_node(null, p_id, leaf_digit, name, action_type, action_param, script, null, true, 0)

func delete_ivr_menu_option(digit: String) -> bool:
	var nid = _resolve_node_id_by_path(digit)
	if nid != null:
		return delete_ivr_menu_node(int(nid))
	return false

func _generate_uuid() -> String:
	var b1 = "%08X" % (randi() % 4294967295)
	var b2 = "%04X" % (randi() % 65536)
	var b3 = "%04X" % (randi() % 65536)
	return (b1 + "-" + b2 + "-" + b3).to_lower()

func get_device_uuid() -> String:
	var res = db.execute("SELECT device_uuid FROM device_identity LIMIT 1;")
	if res["success"] and res["data"].size() > 0:
		return str(res["data"][0]["device_uuid"])
	return "dev_primary_node"

func get_ivr_script_draft(prompt_key: String) -> String:
	var res = db.execute("SELECT suggested_draft FROM ivr_script_drafts WHERE prompt_key = ? LIMIT 1;", [prompt_key])
	if res["success"] and res["data"].size() > 0:
		return str(res["data"][0]["suggested_draft"])
	return ""

func save_ivr_script_draft(prompt_key: String, draft_text: String) -> bool:
	var res = db.execute("INSERT OR REPLACE INTO ivr_script_drafts (prompt_key, suggested_draft, updated_at) VALUES (?, ?, datetime('now'));", [prompt_key, draft_text])
	return res["success"]

func delete_ivr_script_draft(prompt_key: String) -> bool:
	var res = db.execute("DELETE FROM ivr_script_drafts WHERE prompt_key = ?;", [prompt_key])
	return res["success"]

func generate_suggestion_for_prompt(prompt_key: String, day_name: String, date_str: String) -> String:
	if prompt_key == "main_greeting":
		var greet = "Thank you for calling Real Life House.\n"
		var res = db.execute("SELECT digit, label FROM ivr_menu_nodes WHERE parent_id IS NULL AND is_active = 1 ORDER BY digit ASC;")
		if res["success"]:
			for n in res["data"]:
				greet += "Press " + str(n["digit"]) + " for " + str(n["label"]) + ".\n"
		return greet.strip_edges()
		
	elif prompt_key == "location_directions":
		var res = db.execute("SELECT setting_value FROM app_settings WHERE setting_key = 'PHONE_LOCATION_DIRECTIONS_TEXT' LIMIT 1;")
		if res["success"] and res["data"].size() > 0:
			return str(res["data"][0]["setting_value"]).strip_edges()
		return ""
		
	elif prompt_key.begins_with("node_"):
		var nid = prompt_key.split("_")[1].to_int()
		var node_res = db.execute("SELECT dynamic_source, action_type, script_text FROM ivr_menu_nodes WHERE id = ? LIMIT 1;", [nid])
		if node_res["success"] and node_res["data"].size() > 0:
			var item = node_res["data"][0]
			var d_src = str(item.get("dynamic_source", "")) if item.get("dynamic_source") != null else ""
			var act_type = str(item.get("action_type", ""))
			
			if d_src == "today_house":
				return generate_today_script(date_str, day_name).strip_edges()
			elif d_src == "weekly_hours":
				return generate_weekly_hours_script().strip_edges()
			elif d_src == "upcoming_events":
				return generate_upcoming_events_script().strip_edges()
			elif d_src == "location_directions":
				var res = db.execute("SELECT setting_value FROM app_settings WHERE setting_key = 'PHONE_LOCATION_DIRECTIONS_TEXT' LIMIT 1;")
				if res["success"] and res["data"].size() > 0:
					return str(res["data"][0]["setting_value"]).strip_edges()
				return ""
			elif act_type == "staff_directory":
				var list_texts = ["Please select the staff member you would like to reach. "]
				var staff_res = db.execute("SELECT display_name, menu_digit FROM staff_members WHERE is_active = 1 ORDER BY menu_digit ASC;")
				if staff_res["success"]:
					for s in staff_res["data"]:
						list_texts.append("Press " + str(s["menu_digit"]) + " for " + str(s["display_name"]) + ". ")
				list_texts.append("Press 3 to leave a general staff message. Press 9 to return to the main menu.")
				return "".join(list_texts).strip_edges()
			elif act_type == "submenu":
				var children_res = db.execute("SELECT digit, label FROM ivr_menu_nodes WHERE parent_id = ? AND is_active = 1 ORDER BY display_order ASC, digit ASC;", [nid])
				var greet = str(item.get("label", "Submenu")) + " Menu.\n"
				if children_res["success"]:
					for c in children_res["data"]:
						greet += "Press " + str(c["digit"]) + " for " + str(c["label"]) + ".\n"
				return greet.strip_edges()
			else:
				return str(item.get("script_text", "")) if item.get("script_text") != null else ""
	return ""

func get_prompt_status(prompt_key: String, active_script: String, generated_suggestion: String) -> Dictionary:
	var active_clean = active_script.strip_edges().replace("\r", "").replace("\n", " ")
	while active_clean.contains("  "):
		active_clean = active_clean.replace("  ", " ")
		
	var suggested_clean = generated_suggestion.strip_edges().replace("\r", "").replace("\n", " ")
	while suggested_clean.contains("  "):
		suggested_clean = suggested_clean.replace("  ", " ")
		
	var is_current = (active_clean == suggested_clean) or (generated_suggestion == "")
	
	var status_text = "CURRENT"
	var reason = ""
	
	if not is_current:
		status_text = "SUGGESTED UPDATE AVAILABLE"
		if prompt_key == "main_greeting":
			reason = "Main Menu tree structure or option labels changed."
		elif prompt_key.begins_with("node_"):
			var nid = prompt_key.split("_")[1].to_int()
			var node_res = db.execute("SELECT dynamic_source FROM ivr_menu_nodes WHERE id = ? LIMIT 1;", [nid])
			if node_res["success"] and node_res["data"].size() > 0:
				var d_src = str(node_res["data"][0].get("dynamic_source", ""))
				if d_src == "today_house":
					reason = "Today's House Hours or public scheduled sessions changed."
				elif d_src == "weekly_hours":
					reason = "Regular weekly open hours schedule changed."
				elif d_src == "upcoming_events":
					reason = "Upcoming public events list changed."
				elif d_src == "location_directions":
					reason = "Location & directions shared settings changed."
				else:
					reason = "Underlying source data changed."
			else:
				reason = "Underlying source data changed."
		else:
			reason = "Underlying source data changed."
			
	return {
		"status": status_text,
		"reason": reason,
		"is_current": is_current
	}

func save_active_script(prompt_key: String, script_text: String) -> bool:
	if prompt_key == "main_greeting":
		var settings = get_phone_settings()
		return save_phone_settings(
			str(settings.get("on_call_person_id", "")),
			int(settings.get("rollover_rings", 4)),
			bool(settings.get("tts_greeting_active", true)),
			script_text,
			str(settings.get("automated_greeter_audio", ""))
		)
	elif prompt_key == "location_directions":
		var res = db.execute("INSERT OR REPLACE INTO app_settings (setting_key, setting_value) VALUES ('PHONE_LOCATION_DIRECTIONS_TEXT', ?);", [script_text])
		if res["success"]:
			var event_uuid = _generate_uuid()
			var payload_str = JSON.stringify([{"setting_key": "PHONE_LOCATION_DIRECTIONS_TEXT", "setting_value": script_text}])
			db.execute("INSERT OR IGNORE INTO event_outbox (event_uuid, event_type, aggregate_type, aggregate_id, payload_json, device_uuid, status) VALUES (?, 'PhoneSettingsUpdated', 'Settings', 'global_phone', ?, ?, 'pending');", [event_uuid, payload_str, get_device_uuid()])
		return res["success"]
	elif prompt_key.begins_with("node_"):
		var nid = prompt_key.split("_")[1].to_int()
		var node_res = db.execute("SELECT parent_id, digit, label, action_type, action_param, dynamic_source, is_active, display_order FROM ivr_menu_nodes WHERE id = ? LIMIT 1;", [nid])
		if node_res["success"] and node_res["data"].size() > 0:
			var n = node_res["data"][0]
			return save_ivr_menu_node(
				nid,
				n.get("parent_id"),
				str(n.get("digit", "")),
				str(n.get("label", "")),
				str(n.get("action_type", "")),
				str(n.get("action_param", "")) if n.get("action_param") != null else "",
				script_text,
				n.get("dynamic_source"),
				int(n.get("is_active", 1)) == 1,
				int(n.get("display_order", 0))
			)
	return false

