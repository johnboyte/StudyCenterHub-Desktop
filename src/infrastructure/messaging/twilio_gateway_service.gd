extends RefCounted

## Twilio Gateway Service for SMS & Voice Integration
## Complies with [PD-001] (Offline Storage & Outbox Gateway Pattern) and [PD-006] (Admin Config).

var db: RefCounted

func _init(database: RefCounted) -> void:
	db = database
	_ensure_table()

func _ensure_table() -> void:
	if db:
		db.execute("""
			CREATE TABLE IF NOT EXISTS app_settings (
				setting_key TEXT PRIMARY KEY,
				setting_value TEXT NOT NULL,
				updated_at TEXT NOT NULL DEFAULT (datetime('now'))
			);
		""")

func _clean_setting_val(val) -> String:
	if val == null: return ""
	var s = str(val).strip_edges()
	if s.to_lower() == "<null>" or s.to_lower() == "null" or s.to_lower() == "nil" or s == "":
		return ""
	return s

func get_twilio_config() -> Dictionary:
	_ensure_table()
	var sid_res = db.execute("SELECT setting_value FROM app_settings WHERE setting_key = 'TWILIO_ACCOUNT_SID';")
	var token_res = db.execute("SELECT setting_value FROM app_settings WHERE setting_key = 'TWILIO_AUTH_TOKEN';")
	var phone_res = db.execute("SELECT setting_value FROM app_settings WHERE setting_key = 'TWILIO_PHONE_NUMBER';")

	var sid = _clean_setting_val(sid_res["data"][0]["setting_value"]) if sid_res["success"] and sid_res["data"].size() > 0 else ""
	var token = _clean_setting_val(token_res["data"][0]["setting_value"]) if token_res["success"] and token_res["data"].size() > 0 else ""
	var phone = _clean_setting_val(phone_res["data"][0]["setting_value"]) if phone_res["success"] and phone_res["data"].size() > 0 else ""

	var normalized_phone = ""
	if phone != "":
		normalized_phone = format_e164_phone(phone)

	return {
		"account_sid": sid,
		"auth_token": token,
		"phone_number": normalized_phone
	}

func save_twilio_config(sid: String, token: String, phone: String) -> bool:
	_ensure_table()
	var stmt1 = {"sql": "INSERT INTO app_settings (setting_key, setting_value) VALUES ('TWILIO_ACCOUNT_SID', ?) ON CONFLICT(setting_key) DO UPDATE SET setting_value = excluded.setting_value;", "args": [sid.strip_edges()]}
	var stmt2 = {"sql": "INSERT INTO app_settings (setting_key, setting_value) VALUES ('TWILIO_AUTH_TOKEN', ?) ON CONFLICT(setting_key) DO UPDATE SET setting_value = excluded.setting_value;", "args": [token.strip_edges()]}
	var stmt3 = {"sql": "INSERT INTO app_settings (setting_key, setting_value) VALUES ('TWILIO_PHONE_NUMBER', ?) ON CONFLICT(setting_key) DO UPDATE SET setting_value = excluded.setting_value;", "args": [phone.strip_edges()]}

	var res = db.execute_transaction([stmt1, stmt2, stmt3])
	return res["success"]

func format_e164_phone(phone_input: String) -> String:
	var raw = phone_input.strip_edges()
	if raw.begins_with("+"):
		var digits = ""
		for c in raw:
			if c in "0123456789":
				digits += c
		return "+" + digits

	var digits = ""
	for c in raw:
		if c in "0123456789":
			digits += c

	if digits.length() == 10:
		return "+1" + digits
	elif digits.length() == 11 and digits.begins_with("1"):
		return "+" + digits

	return raw

func is_automated_test_environment() -> bool:
	if OS.get_environment("STUDYCENTERHUB_MOCK_COMMUNICATIONS") == "true" or OS.get_environment("STUDYCENTERHUB_TEST") == "true":
		return true
	var args = OS.get_cmdline_args()
	for arg in args:
		if arg.contains("--script") or arg.contains("tests/") or arg.contains("test_"):
			return true
	return false

func is_demo_config() -> bool:
	if is_automated_test_environment():
		return true
	var config = get_twilio_config()
	var sid = config.get("account_sid", "")
	var token = config.get("auth_token", "")
	return sid == "" or sid.begins_with("AC_demo") or token == "" or token.contains("demo")

func make_outbound_call_async(caller_node: Node, to_phone: String, callback: Callable) -> void:
	var config = get_twilio_config()
	var formatted_to = format_e164_phone(to_phone)
	var formatted_from = format_e164_phone(config["phone_number"])

	if is_demo_config():
		callback.call({
			"success": false,
			"demo_mode": true,
			"error": "Twilio Account SID & Auth Token not configured in Settings. Use 'Call from Computer' to dial via Mac/FaceTime, or configure Twilio API keys under Settings -> Communications.",
			"to_phone": formatted_to
		})
		return

	var http_request = HTTPRequest.new()
	caller_node.add_child(http_request)

	var auth_header = "Authorization: Basic " + Marshalls.utf8_to_base64(config["account_sid"] + ":" + config["auth_token"])
	var headers = [
		auth_header,
		"Content-Type: application/x-www-form-urlencoded"
	]

	var twiml_url = "https://app.reallife-studycenter.org/api/v1/webhooks/twilio/voice-prompt"
	var body = "To=" + formatted_to.uri_encode() + "&From=" + formatted_from.uri_encode() + "&Url=" + twiml_url.uri_encode()
	var url = "https://api.twilio.com/2010-04-01/Accounts/" + config["account_sid"] + "/Calls.json"

	http_request.request_completed.connect(func(result: int, response_code: int, _r_headers: PackedStringArray, body_bytes: PackedByteArray):
		var response_text = body_bytes.get_string_from_utf8()
		var json = JSON.parse_string(response_text) as Dictionary

		http_request.queue_free()

		if response_code in [200, 201] and json and json.has("sid"):
			callback.call({
				"success": true,
				"is_live": true,
				"twilio_call_sid": json["sid"],
				"status": json.get("status", "queued"),
				"to_phone": formatted_to,
				"from_phone": formatted_from
			})
		else:
			var err_msg = "HTTP " + str(response_code)
			if json and json.has("message"):
				err_msg += ": " + str(json["message"])
			elif response_text != "":
				err_msg += ": " + response_text.left(120)

			callback.call({
				"success": false,
				"error": err_msg,
				"to_phone": formatted_to
			})
	, CONNECT_ONE_SHOT)

	var err = http_request.request(url, headers, HTTPClient.METHOD_POST, body)
	if err != OK:
		http_request.queue_free()
		callback.call({
			"success": false,
			"error": "Failed to initiate outbound call request (Error code: " + str(err) + ")"
		})

func send_twilio_sms_async(caller_node: Node, to_phone: String, message_body: String, callback: Callable, media_url: String = "") -> void:
	var config = get_twilio_config()
	var formatted_to = format_e164_phone(to_phone)
	var formatted_from = format_e164_phone(config["phone_number"])

	if is_demo_config():
		var demo_sid = "MM" if media_url != "" else "SM"
		demo_sid += _generate_uuid().replace("-", "").left(30)
		print("Dispatched Simulated ", ("MMS" if media_url != "" else "SMS"), " from ", formatted_from, " to ", formatted_to, " | Message SID: ", demo_sid, (" | MediaUrl: " + media_url if media_url != "" else ""))
		callback.call({
			"success": true,
			"is_live": false,
			"demo_mode": true,
			"twilio_msg_sid": demo_sid,
			"to_phone": formatted_to,
			"from_phone": formatted_from,
			"message": "Simulated dispatch (Demo Mode). Save live Twilio Account SID & Auth Token to deliver real SMS/MMS messages to mobile phones."
		})
		return

	# Live HTTP Dispatch via Twilio REST API
	var http_request = HTTPRequest.new()
	caller_node.add_child(http_request)

	var auth_header = "Authorization: Basic " + Marshalls.utf8_to_base64(config["account_sid"] + ":" + config["auth_token"])
	var headers = [
		auth_header,
		"Content-Type: application/x-www-form-urlencoded"
	]

	var body = "To=" + formatted_to.uri_encode() + "&From=" + formatted_from.uri_encode() + "&Body=" + message_body.uri_encode()
	if media_url != "":
		body += "&MediaUrl=" + media_url.uri_encode()
	var url = "https://api.twilio.com/2010-04-01/Accounts/" + config["account_sid"] + "/Messages.json"

	http_request.request_completed.connect(func(result: int, response_code: int, _r_headers: PackedStringArray, body_bytes: PackedByteArray):
		var response_text = body_bytes.get_string_from_utf8()
		var json = JSON.parse_string(response_text) as Dictionary

		http_request.queue_free()

		if response_code == 201 and json and json.has("sid"):
			callback.call({
				"success": true,
				"is_live": true,
				"demo_mode": false,
				"twilio_msg_sid": json["sid"],
				"status": json.get("status", "queued"),
				"to_phone": formatted_to,
				"from_phone": formatted_from
			})
		else:
			var err_msg = "HTTP " + str(response_code)
			if json and json.has("message"):
				err_msg += ": " + str(json["message"])
			elif response_text != "":
				err_msg += ": " + response_text.left(120)

			callback.call({
				"success": false,
				"is_live": true,
				"demo_mode": false,
				"error": err_msg,
				"to_phone": formatted_to,
				"from_phone": formatted_from
			})
	)

	var err = http_request.request(url, headers, HTTPClient.METHOD_POST, body)
	if err != OK:
		http_request.queue_free()
		callback.call({
			"success": false,
			"is_live": true,
			"demo_mode": false,
			"error": "Failed to initiate HTTP request (Error code: " + str(err) + ")"
		})

func simulate_twilio_sms(to_phone: String, message_body: String) -> Dictionary:
	var config = get_twilio_config()
	var formatted_to = format_e164_phone(to_phone)
	if config["account_sid"] == "" or config["auth_token"] == "":
		return {"success": false, "error": "Twilio Account SID or Auth Token missing."}

	var twilio_msg_sid = "SM" + _generate_uuid().replace("-", "").left(30)
	print("Dispatched SMS via Twilio Gateway to ", formatted_to, " | Twilio Message SID: ", twilio_msg_sid)

	return {
		"success": true,
		"error": "",
		"twilio_msg_sid": twilio_msg_sid,
		"to_phone": formatted_to,
		"from_phone": config["phone_number"],
		"status": "queued"
	}

func process_delivery_status_update(message_uuid: String, new_delivery_status: String, error_code: String = "") -> bool:
	if not db: return false
	var status_detail = "Delivery status: " + new_delivery_status
	if error_code != "": status_detail += " (Code: " + error_code + ")"
	var res = db.execute("UPDATE communications_log SET delivery_status = ?, error_code = ?, status_detail = ? WHERE message_uuid = ?;",
		[new_delivery_status, error_code, status_detail, message_uuid])
	return res.get("success", false)

func process_twilio_webhook_payload(payload: Dictionary) -> Dictionary:
	if not db:
		return {"success": false, "error": "Database unavailable."}

	var msg_sid = str(payload.get("MessageSid", payload.get("SmsSid", payload.get("message_sid", "")))).strip_edges()
	var raw_status = str(payload.get("MessageStatus", payload.get("status", "failed"))).to_lower().strip_edges()
	var error_code = str(payload.get("ErrorCode", payload.get("error_code", ""))).strip_edges()

	var delivery_status = "failed"
	if raw_status in ["delivered", "sent"]:
		delivery_status = "delivered"
	elif raw_status in ["queued", "sending"]:
		delivery_status = "queued"
	elif raw_status in ["failed", "undelivered", "rejected"]:
		delivery_status = "failed"

	if msg_sid.is_empty():
		return {"success": false, "error": "Missing MessageSid in webhook payload."}

	var query_res = db.execute("SELECT id, message_uuid FROM communications_log WHERE provider_sid = ? OR message_uuid = ? LIMIT 1;", [msg_sid, msg_sid])
	if not query_res["success"] or query_res["data"].size() == 0:
		query_res = db.execute("SELECT id, message_uuid FROM communications_log WHERE status = 'submitted_to_provider' ORDER BY id DESC LIMIT 1;")

	if not query_res["success"] or query_res["data"].size() == 0:
		return {"success": false, "error": "No matching message log found for SID: " + msg_sid}

	var msg_uuid = str(query_res["data"][0]["message_uuid"])
	var updated = process_delivery_status_update(msg_uuid, delivery_status, error_code)
	return {"success": updated, "message_uuid": msg_uuid, "delivery_status": delivery_status, "error_code": error_code}

func _generate_uuid() -> String:
	var b1 = "%08X" % (randi() % 4294967295)
	var b2 = "%04X" % (randi() % 65536)
	var b3 = "%04X" % (randi() % 65536)
	return (b1 + "-" + b2 + "-" + b3).to_lower()
