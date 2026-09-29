extends RefCounted

## Mobile SMS Relay Service for StudyCenterHub
## Relays constituent SMS messages to an authorized staff mobile phone and routes replies back cleanly.
## Preserves constituent privacy, enforces deterministic token routing, and logs all events.

const TwilioGatewayScript = preload("res://src/infrastructure/messaging/twilio_gateway_service.gd")

var db: RefCounted
var twilio_service: RefCounted
var mock_mode: bool = false

func _init(database: RefCounted) -> void:
	db = database
	twilio_service = TwilioGatewayScript.new(db)

func normalize_e164(phone_str: String) -> String:
	var raw = phone_str.strip_edges()
	if raw == "":
		return ""
	
	var digits = ""
	var has_plus = raw.begins_with("+")
	for i in range(raw.length()):
		var ch = raw[i]
		if ch >= '0' and ch <= '9':
			digits += ch

	if digits.length() == 0:
		return ""

	if has_plus:
		return "+" + digits

	if digits.length() == 10:
		return "+1" + digits
	elif digits.length() == 11 and digits.begins_with("1"):
		return "+" + digits

	return "+" + digits

func format_display_phone(phone_str: String) -> String:
	var norm = normalize_e164(phone_str)
	var digits = ""
	for i in range(norm.length()):
		var ch = norm[i]
		if ch >= '0' and ch <= '9':
			digits += ch

	if digits.length() == 11 and digits.begins_with("1"):
		digits = digits.substr(1)

	if digits.length() == 10:
		return "(%s) %s-%s" % [digits.substr(0, 3), digits.substr(3, 3), digits.substr(6, 4)]
	return phone_str

func get_relay_settings() -> Dictionary:
	var enabled = false
	var phone = ""

	var res_en = db.execute("SELECT setting_value FROM app_settings WHERE setting_key = 'SMS_RELAY_ENABLED' LIMIT 1;")
	if res_en["success"] and res_en["data"].size() > 0:
		enabled = str(res_en["data"][0]["setting_value"]).to_lower() == "true"

	var res_ph = db.execute("SELECT setting_value FROM app_settings WHERE setting_key = 'SMS_RELAY_PHONE' LIMIT 1;")
	if res_ph["success"] and res_ph["data"].size() > 0:
		phone = str(res_ph["data"][0]["setting_value"]).strip_edges()

	return {
		"enabled": enabled,
		"phone": normalize_e164(phone)
	}

func save_relay_settings(enabled: bool, phone_str: String) -> bool:
	var norm_phone = normalize_e164(phone_str)
	var en_str = "true" if enabled else "false"

	var res1 = db.execute("INSERT OR REPLACE INTO app_settings (setting_key, setting_value) VALUES ('SMS_RELAY_ENABLED', ?);", [en_str])
	var res2 = db.execute("INSERT OR REPLACE INTO app_settings (setting_key, setting_value) VALUES ('SMS_RELAY_PHONE', ?);", [norm_phone])

	return res1["success"] and res2["success"]

func is_relay_phone(phone_str: String) -> bool:
	var settings = get_relay_settings()
	if not settings["enabled"] or settings["phone"] == "":
		return false
	var norm_input = normalize_e164(phone_str)
	return norm_input != "" and norm_input == settings["phone"]

func generate_relay_token() -> String:
	const CHARS = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789" # Exclude O, 0, 1, I, L
	var attempts = 0
	while attempts < 100:
		var token = ""
		for i in range(4):
			var idx = randi() % CHARS.length()
			token += CHARS[idx]

		var check = db.execute("SELECT id FROM sms_relay_sessions WHERE relay_token = ? AND status = 'active' LIMIT 1;", [token])
		if not check["success"] or check["data"].size() == 0:
			return token
		attempts += 1

	return "R" + str(Time.get_ticks_msec()).substr(0, 3).to_upper()

func clean_expired_sessions() -> void:
	db.execute("UPDATE sms_relay_sessions SET status = 'expired' WHERE status = 'active' AND expires_at <= datetime('now');")

func get_or_create_session(constituent_phone: String, relay_phone: String, person_id: Variant = null, source_msg_sid: String = "") -> Dictionary:
	clean_expired_sessions()
	var norm_c = normalize_e164(constituent_phone)
	var norm_r = normalize_e164(relay_phone)

	# Check for existing active session
	var res = db.execute(
		"SELECT * FROM sms_relay_sessions WHERE constituent_phone_e164 = ? AND relay_phone_e164 = ? AND status = 'active' AND expires_at > datetime('now') ORDER BY last_activity_at DESC LIMIT 1;",
		[norm_c, norm_r]
	)

	if res["success"] and res["data"].size() > 0:
		var sess = res["data"][0]
		var sess_id = int(sess["id"])
		db.execute(
			"UPDATE sms_relay_sessions SET last_activity_at = datetime('now'), expires_at = datetime('now', '+4 hours') WHERE id = ?;",
			[sess_id]
		)
		sess["last_activity_at"] = Time.get_datetime_string_from_system()
		return sess

	# Create new active session
	var token = generate_relay_token()
	var ins_res = db.execute(
		"INSERT INTO sms_relay_sessions (relay_token, relay_phone_e164, constituent_phone_e164, person_id, source_message_sid, status, created_at, last_activity_at, expires_at) VALUES (?, ?, ?, ?, ?, 'active', datetime('now'), datetime('now'), datetime('now', '+4 hours'));",
		[token, norm_r, norm_c, person_id, source_msg_sid]
	)

	if not ins_res["success"]:
		print("[SMS-RELAY] Failed to insert relay session: ", ins_res.get("error", ""))
		return {}

	var new_id = 0
	var id_q = db.execute("SELECT id FROM sms_relay_sessions WHERE relay_token = ? LIMIT 1;", [token])
	if id_q["success"] and id_q["data"].size() > 0:
		new_id = int(id_q["data"][0]["id"])

	_log_audit_event(new_id, token, "inbound_relay_created", norm_c, norm_r, JSON.stringify({"person_id": person_id, "source_sid": source_msg_sid}))

	return {
		"id": new_id,
		"relay_token": token,
		"relay_phone_e164": norm_r,
		"constituent_phone_e164": norm_c,
		"person_id": person_id,
		"status": "active"
	}

func forward_inbound_sms(caller_node: Node, constituent_phone: String, constituent_name: String, message_body: String, media_urls: Array = [], person_id: Variant = null, source_msg_sid: String = "") -> Dictionary:
	var settings = get_relay_settings()
	if not settings["enabled"] or settings["phone"] == "":
		return {"relayed": false, "reason": "relay_disabled"}

	var norm_c = normalize_e164(constituent_phone)
	var norm_r = settings["phone"]

	# Loop Prevention: Never forward if constituent phone matches authorized relay phone
	if norm_c == norm_r:
		print("[SMS-RELAY] Loop prevention: constituent phone matches relay phone. Forwarding suppressed.")
		return {"relayed": false, "reason": "loop_prevented"}

	# Idempotency check: If server gateway already forwarded this exact source_msg_sid, suppress duplicate desktop relay notification
	if source_msg_sid != "":
		var check_sid = db.execute("SELECT id, relay_token FROM sms_relay_sessions WHERE source_message_sid = ? LIMIT 1;", [source_msg_sid])
		if check_sid["success"] and check_sid["data"].size() > 0:
			print("[SMS-RELAY] Server gateway already forwarded source_msg_sid: ", source_msg_sid, ". Suppressing duplicate desktop relay notification.")
			return {"relayed": true, "reason": "already_relayed_by_server", "token": str(check_sid["data"][0].get("relay_token", ""))}

	var sess = get_or_create_session(norm_c, norm_r, person_id, source_msg_sid)
	if sess.is_empty():
		return {"relayed": false, "reason": "session_creation_failed"}

	var token = str(sess["relay_token"])

	# Count active sessions for this relay phone
	clean_expired_sessions()
	var cnt_res = db.execute("SELECT COUNT(*) as cnt FROM sms_relay_sessions WHERE relay_phone_e164 = ? AND status = 'active' AND expires_at > datetime('now');", [norm_r])
	var active_count = int(cnt_res["data"][0]["cnt"]) if (cnt_res["success"] and cnt_res["data"].size() > 0) else 1

	var disp_name = constituent_name.strip_edges()
	if disp_name == "" or disp_name == "<null>" or disp_name == "null":
		disp_name = "Unknown Constituent"
	var disp_phone = format_display_phone(norm_c)

	var text_content = message_body.strip_edges()
	if text_content == "" and media_urls.size() > 0:
		text_content = "[Image received — open StudyCenterHub to view]"
	elif media_urls.size() > 0:
		text_content += "\n[Image received — open StudyCenterHub to view]"

	var fwd_msg = "STUDY CENTER — %s\n%s\n%s\n\nRef: %s\nReply with:\n%s your reply" % [disp_name, disp_phone, text_content, token, token]

	_log_audit_event(int(sess.get("id", 0)), token, "notification_sent", norm_c, norm_r, JSON.stringify({"body": text_content}))

	# Dispatch SMS to authorized relay phone
	var dispatch_success = false
	var dispatch_error = ""

	if mock_mode or twilio_service.is_demo_config():
		dispatch_success = true
		print("[SMS-RELAY] MOCK DISPATCH: Forwarded SMS to relay phone ", norm_r, " with token ", token)
	elif caller_node and twilio_service:
		var completed = {"done": false, "res": {}}
		twilio_service.send_twilio_sms_async(caller_node, norm_r, fwd_msg, func(sms_res):
			completed["res"] = sms_res
			completed["done"] = true
		)
		while not completed["done"]:
			var main_loop = Engine.get_main_loop()
			if main_loop is SceneTree:
				await main_loop.process_frame
			else:
				break
		var res_dict = completed["res"]
		dispatch_success = res_dict.get("success", false) == true
		dispatch_error = str(res_dict.get("error", ""))

	if not dispatch_success:
		_log_audit_event(int(sess.get("id", 0)), token, "delivery_failed", norm_c, norm_r, JSON.stringify({"error": dispatch_error}))
		print("[SMS-RELAY] Failed to dispatch relay SMS: ", dispatch_error)

	return {"relayed": dispatch_success, "session": sess, "error": dispatch_error}

func handle_relay_reply(caller_node: Node, relay_phone: String, reply_text: String, message_sid: String = "") -> Dictionary:
	var norm_r = normalize_e164(relay_phone)
	if not is_relay_phone(norm_r):
		return {"handled": false, "reason": "unauthorized_phone"}

	_log_audit_event(0, "UNRESOLVED", "reply_received", norm_r, "", JSON.stringify({"raw_reply": reply_text, "sid": message_sid}))
	clean_expired_sessions()

	var raw_body = reply_text.strip_edges()
	var extracted_token = ""
	var clean_msg = raw_body

	# Parse token prefix: e.g. "A7K4 Yes we will", "Ref: A7K4: Yes", "A7K4: Yes"
	var words = raw_body.split(" ", false)
	if words.size() > 0:
		var w0 = words[0].replace("Ref:", "").replace(":", "").strip_edges().to_upper()
		if w0.length() == 4:
			# Verify if w0 is an active session token for this relay phone
			var tok_check = db.execute("SELECT id FROM sms_relay_sessions WHERE relay_token = ? AND relay_phone_e164 = ? AND status = 'active' AND expires_at > datetime('now') LIMIT 1;", [w0, norm_r])
			if tok_check["success"] and tok_check["data"].size() > 0:
				extracted_token = w0
				# Strip prefix token from clean_msg
				var rest_idx = raw_body.find(words[0]) + words[0].length()
				clean_msg = raw_body.substr(rest_idx).strip_edges()
				if clean_msg.begins_with(":"):
					clean_msg = clean_msg.substr(1).strip_edges()

	var target_session: Dictionary = {}

	if extracted_token != "":
		# Token explicit & matched
		var s_q = db.execute("SELECT * FROM sms_relay_sessions WHERE relay_token = ? AND relay_phone_e164 = ? AND status = 'active' AND expires_at > datetime('now') LIMIT 1;", [extracted_token, norm_r])
		if s_q["success"] and s_q["data"].size() > 0:
			target_session = s_q["data"][0]
		else:
			# Check if token exists but is expired
			var exp_q = db.execute("SELECT id FROM sms_relay_sessions WHERE relay_token = ? AND relay_phone_e164 = ? AND status = 'expired' LIMIT 1;", [extracted_token, norm_r])
			var is_expired = exp_q["success"] and exp_q["data"].size() > 0
			var err_msg = ("Study Center Relay: %s has expired. No message was sent." % extracted_token) if is_expired else ("Study Center Relay: %s wasn't recognized. No message was sent." % extracted_token)
			_log_audit_event(0, extracted_token, "reply_rejected", norm_r, "", JSON.stringify({"reason": "expired_token" if is_expired else "invalid_token"}))
			_notify_relay_phone(caller_node, norm_r, err_msg)
			return {"handled": true, "success": false, "reason": "expired_token" if is_expired else "invalid_token", "error": err_msg}
	else:
		# V1 MANDATORY TOKEN RULE: Never guess or auto-route unprefixed replies even if 1 conversation is active!
		_log_audit_event(0, "UNMATCHED", "missing_token", norm_r, "", JSON.stringify({"raw_reply": reply_text}))
		var missing_tok_msg = "Study Center Relay: I couldn't match that reply. Start your message with the active reference code, for example:\n\nK9R2 your message"
		_notify_relay_phone(caller_node, norm_r, missing_tok_msg)
		return {"handled": true, "success": false, "reason": "missing_token", "error": missing_tok_msg}

	if target_session.is_empty():
		return {"handled": true, "success": false, "reason": "unresolved_session"}

	var sess_id = int(target_session["id"])
	var token = str(target_session["relay_token"])
	var constituent_phone = str(target_session["constituent_phone_e164"])
	var person_id = target_session.get("person_id")

	# Dispatch reply to constituent FROM Study Center Twilio number!
	const CommunicationsServiceScript = preload("res://src/domain/communications/communications_service.gd")
	var comm_svc = CommunicationsServiceScript.new(db)
	comm_svc.mock_relay_mode = mock_mode

	var person_dict = {"phone": constituent_phone, "id": person_id}
	if person_id != null and int(person_id) > 0:
		var p_res = db.execute("SELECT * FROM people WHERE id = ? LIMIT 1;", [int(person_id)])
		if p_res["success"] and p_res["data"].size() > 0:
			person_dict = p_res["data"][0]

	var send_res = comm_svc.send_message_atomic(person_dict, "SMS", clean_msg, "Mobile Relay")
	var is_sent = bool(send_res.get("success", false))

	if is_sent:
		# Update session activity
		db.execute("UPDATE sms_relay_sessions SET last_activity_at = datetime('now'), expires_at = datetime('now', '+4 hours') WHERE id = ?;", [sess_id])

		# Update Response Center status so thread is marked answered/handled
		db.execute("UPDATE inbound_sms_log SET follow_up_status = 'completed' WHERE from_phone_e164 = ? AND follow_up_status != 'completed';", [constituent_phone])

		# Update status_detail in communications_log to show "sent_via_mobile_relay"
		var msg_uuid = str(send_res.get("message_uuid", ""))
		if msg_uuid != "":
			db.execute("UPDATE communications_log SET status_detail = 'sent_via_mobile_relay' WHERE message_uuid = ?;", [msg_uuid])

		_log_audit_event(sess_id, token, "reply_sent_to_constituent", norm_r, constituent_phone, JSON.stringify({"clean_msg": clean_msg}))
		return {"handled": true, "success": true, "session": target_session, "clean_msg": clean_msg}
	else:
		_log_audit_event(sess_id, token, "delivery_failed", norm_r, constituent_phone, JSON.stringify({"error": send_res.get("error", "")}))
		_notify_relay_phone(caller_node, norm_r, "Failed to send your reply to the constituent: " + str(send_res.get("error", "Unknown error")))
		return {"handled": true, "success": false, "reason": "constituent_send_failed", "error": send_res.get("error", "")}

func send_test_relay(caller_node: Node, test_phone_str: String, is_manual_user_action: bool = false) -> Dictionary:
	var norm = normalize_e164(test_phone_str)
	if norm == "":
		return {
			"success": false,
			"is_live": false,
			"demo_mode": false,
			"error": "Invalid relay phone number. Please enter a valid 10-digit or E.164 phone number."
		}

	return {
		"success": true,
		"is_live": false,
		"demo_mode": true,
		"server_relay": true,
		"to_phone": norm,
		"message": "Mobile SMS Relay runs 24/7 on the live gateway server. Settings saved cleanly."
	}

func _notify_relay_phone(caller_node: Node, relay_phone: String, message_text: String) -> void:
	if mock_mode or twilio_service.is_demo_config():
		print("[SMS-RELAY] MOCK NOTIFY TO RELAY PHONE (", relay_phone, "): ", message_text)
		return

	if caller_node and twilio_service:
		twilio_service.send_twilio_sms_async(caller_node, relay_phone, message_text, func(res): pass)

func _log_audit_event(session_id: int, token: String, event_type: String, from_ph: String, to_ph: String, details_json: String) -> void:
	var s_id = session_id if session_id > 0 else null
	db.execute(
		"INSERT INTO sms_relay_events (session_id, relay_token, event_type, from_phone_e164, to_phone_e164, details_json, created_at) VALUES (?, ?, ?, ?, ?, ?, datetime('now'));",
		[s_id, token, event_type, from_ph, to_ph, details_json]
	)
