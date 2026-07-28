extends RefCounted

## Inbound Event Processor for StudyCenterHub
## Processes raw inbound events (such as twilio.voicemail and twilio.sms) pulled from the relay,
## runs caller matching, handles SMS compliance, calls Gemini API for audio transcription,
## and logs records to SQLite and Google Sheets via the outbox.
## Complies with permanent design rules: all business logic, caller matching, and transcription live here.

const AttendanceServiceScript = preload("res://src/domain/attendance/attendance_service.gd")

var db: RefCounted
var parent_node: Node
var http_client: HTTPRequest

func _init(database: RefCounted, caller_node: Node) -> void:
	db = database
	parent_node = caller_node
	
	http_client = HTTPRequest.new()
	http_client.timeout = 10.0
	parent_node.add_child(http_client)

func get_gemini_api_key() -> String:
	var res = db.execute("SELECT setting_value FROM app_settings WHERE setting_key = 'GEMINI_API_KEY' LIMIT 1;")
	if res["success"] and res["data"].size() > 0:
		var k = str(res["data"][0]["setting_value"]).strip_edges()
		if k != "": return k
	return OS.get_environment("GEMINI_API_KEY")

func process_pending_events(callback: Callable) -> void:
	print("[Processor] Querying pending events...")
	var res = db.execute("SELECT * FROM inbound_event_queue WHERE processed = 0 ORDER BY id ASC;")
	if not res["success"] or res["data"].size() == 0:
		print("[Processor] No pending events found.")
		callback.call({"success": true, "processed_count": 0})
		return

	var events = res["data"]
	print("[Processor] Found ", events.size(), " pending events.")
	_process_next_event(events, 0, 0, callback)

func _process_next_event(events: Array, index: int, processed_count: int, callback: Callable) -> void:
	print("[Processor] Processing index: ", index)
	if index >= events.size():
		print("[Processor] Finished processing all events. Invoking callback.")
		callback.call({"success": true, "processed_count": processed_count})
		return

	var event = events[index]
	var event_id = int(event["id"])
	var event_type = str(event["event_type"])
	var payload_json = str(event["payload_json"])
	var payload = JSON.parse_string(payload_json)

	if typeof(payload) != TYPE_DICTIONARY:
		print("[Processor] Event ", event_id, " has invalid payload. Skipping.")
		db.execute("UPDATE inbound_event_queue SET processed = 1 WHERE id = ?;", [event_id])
		_process_next_event(events, index + 1, processed_count, callback)
		return

	if event_type == "portal.registration":
		print("[Processor] Processing portal.registration event ", event_id)
		_process_portal_registration(event_id, payload)
		_process_next_event(events, index + 1, processed_count + 1, callback)
	elif event_type == "portal.checkin":
		print("[Processor] Processing portal.checkin event ", event_id)
		_process_portal_checkin(event_id, payload)
		_process_next_event(events, index + 1, processed_count + 1, callback)
	elif event_type == "portal.signup":
		print("[Processor] Processing portal.signup event ", event_id)
		_process_portal_signup(event_id, payload)
		_process_next_event(events, index + 1, processed_count + 1, callback)
	elif event_type == "portal.cancel_signup":
		print("[Processor] Processing portal.cancel_signup event ", event_id)
		_process_portal_cancel_signup(event_id, payload)
		_process_next_event(events, index + 1, processed_count + 1, callback)
	elif event_type == "scanner.checkin":
		print("[Processor] Processing scanner.checkin event ", event_id)
		_process_scanner_checkin(event_id, payload)
		_process_next_event(events, index + 1, processed_count + 1, callback)
	elif event_type == "twilio.sms":
		print("[Processor] Processing SMS event ", event_id)
		_process_sms(event_id, payload)
		_process_next_event(events, index + 1, processed_count + 1, callback)
	elif event_type == "twilio.voicemail":
		print("[Processor] Processing Voicemail event ", event_id)
		_process_voicemail(event_id, payload, func():
			print("[Processor] Voicemail event ", event_id, " completion callback received.")
			_process_next_event(events, index + 1, processed_count + 1, callback)
		)
	else:
		print("[Processor] Generic event type: ", event_type)
		db.execute("UPDATE inbound_event_queue SET processed = 1 WHERE id = ?;", [event_id])
		_process_next_event(events, index + 1, processed_count, callback)

func _process_portal_registration(event_id: int, payload: Dictionary) -> void:
	var human_id = str(payload.get("humanId", payload.get("human_id", ""))).strip_edges()
	var first_name = str(payload.get("firstName", payload.get("first_name", ""))).strip_edges()
	var last_name = str(payload.get("lastName", payload.get("last_name", ""))).strip_edges()
	var phone = str(payload.get("phone", "")).strip_edges()
	var email = str(payload.get("email", "")).strip_edges()
	var flag_status = str(payload.get("flagStatus", "To Be Confirmed")).strip_edges()

	if human_id != "":
		var existing = db.execute("SELECT id FROM people WHERE human_id = ? LIMIT 1;", [human_id])
		if existing["success"] and existing["data"].size() > 0:
			db.execute("UPDATE people SET flag_status = ? WHERE human_id = ?;", [flag_status, human_id])
			db.execute("UPDATE inbound_event_queue SET processed = 1 WHERE id = ?;", [event_id])
			return

	var next_id = 1001
	var max_res = db.execute("SELECT MAX(id) AS m FROM people;")
	if max_res["success"] and max_res["data"].size() > 0 and max_res["data"][0]["m"] != null:
		next_id = int(max_res["data"][0]["m"]) + 1
	if human_id == "":
		human_id = "PRT-" + str(next_id)

	db.execute(
		"INSERT INTO people (human_id, first_name, last_name, phone, email, flag_status, created_at) VALUES (?, ?, ?, ?, ?, ?, datetime('now'));",
		[human_id, first_name, last_name, phone, email, flag_status]
	)
	db.execute("UPDATE inbound_event_queue SET processed = 1 WHERE id = ?;", [event_id])

func _process_portal_checkin(event_id: int, payload: Dictionary) -> void:
	var human_id = str(payload.get("humanId", payload.get("human_id", ""))).strip_edges()
	var checkin_date = str(payload.get("checkInDate", Time.get_date_string_from_system())).strip_edges()
	var event_name = str(payload.get("eventName", "Daily Check-In")).strip_edges()

	var person_res = db.execute("SELECT id FROM people WHERE human_id = ? LIMIT 1;", [human_id])
	var person_id = 0
	if person_res["success"] and person_res["data"].size() > 0:
		person_id = int(person_res["data"][0]["id"])

	db.execute(
		"INSERT INTO attendance_log (person_id, date, type, created_at) VALUES (?, ?, ?, datetime('now'));",
		[person_id, checkin_date, event_name]
	)
	db.execute("UPDATE inbound_event_queue SET processed = 1 WHERE id = ?;", [event_id])

func _process_portal_signup(event_id: int, payload: Dictionary) -> void:
	var human_id = str(payload.get("humanId", "")).strip_edges()
	var status = str(payload.get("signupStatus", "Signed Up")).strip_edges()
	db.execute("UPDATE inbound_event_queue SET processed = 1 WHERE id = ?;", [event_id])

func _process_portal_cancel_signup(event_id: int, payload: Dictionary) -> void:
	db.execute("UPDATE inbound_event_queue SET processed = 1 WHERE id = ?;", [event_id])

func _process_scanner_checkin(event_id: int, payload: Dictionary) -> void:
	var raw_scanned = str(payload.get("raw_scanned_content", "")).strip_edges()
	var scanner_id = str(payload.get("scanner_id", "DS2800")).strip_edges()
	var mode_val = str(payload.get("mode", "Study Center Daily")).strip_edges()

	if raw_scanned == "":
		db.execute("UPDATE inbound_event_queue SET processed = 1 WHERE id = ?;", [event_id])
		return

	# Extract opaque token if raw content is a full URL: https://checkin.reallife-studycenter.org/public-returning?credential={OPAQUE_TOKEN}
	var token_candidate = raw_scanned
	if "credential=" in raw_scanned:
		var parts = raw_scanned.split("credential=")
		if parts.size() > 1:
			token_candidate = parts[1].split("&")[0].strip_edges()

	var token_hash = token_candidate.sha256_text().to_lower()

	# 1. Resolve participant via active QR credential
	var pid = 0
	var cred_res = db.execute("SELECT person_id FROM participant_qr_credentials WHERE (token_hash = ? OR token_hash = ?) AND status = 'active' LIMIT 1;", [token_hash, token_candidate.to_lower()])
	if cred_res["success"] and cred_res["data"].size() > 0:
		pid = int(cred_res["data"][0]["person_id"])

	if pid == 0:
		# Fallback check legacy qr_code_value column in people table
		var legacy_res = db.execute("SELECT id FROM people WHERE qr_code_value = ? OR qr_code_value = ? LIMIT 1;", [token_hash, token_candidate])
		if legacy_res["success"] and legacy_res["data"].size() > 0:
			pid = int(legacy_res["data"][0]["id"])

	if pid == 0:
		print("[Processor] Warning: DS2800 scanner QR token not recognized or revoked: ", raw_scanned.left(25))
		db.execute("UPDATE inbound_event_queue SET processed = 1 WHERE id = ?;", [event_id])
		return

	var p_res = db.execute("SELECT * FROM people WHERE id = ? LIMIT 1;", [pid])
	if not p_res["success"] or p_res["data"].size() == 0:
		db.execute("UPDATE inbound_event_queue SET processed = 1 WHERE id = ?;", [event_id])
		return

	var person_dict = p_res["data"][0]

	# 2. Duplicate protection check for current date
	var today_str = Time.get_date_string_from_system()
	var dup_res = db.execute("SELECT COUNT(*) as cnt FROM attendance_log WHERE person_id = ? AND check_in_date = ? AND (mode = ? OR mode = 'Study Center Daily');", [pid, today_str, mode_val])
	if dup_res["success"] and dup_res["data"].size() > 0 and int(dup_res["data"][0]["cnt"]) > 0:
		print("[Processor] Participant ", pid, " already checked in today. Suppressing duplicate scan.")
		db.execute("UPDATE inbound_event_queue SET processed = 1 WHERE id = ?;", [event_id])
		return

	# 3. Record attendance check-in atomically using AttendanceService
	var att_svc = AttendanceServiceScript.new(db)
	att_svc.record_check_in_atomic(person_dict, "NETUM DS2800 Scanner", scanner_id, null, mode_val, "John Boyte")

	db.execute("UPDATE inbound_event_queue SET processed = 1 WHERE id = ?;", [event_id])


func _process_sms(event_id: int, payload: Dictionary) -> void:
	var from_phone = str(payload.get("From", "")).strip_edges()
	var to_phone = str(payload.get("To", "")).strip_edges()
	var body = str(payload.get("Body", "")).strip_edges()
	var message_sid = str(payload.get("MessageSid", "")).strip_edges()
	
	var matched_person_id = null
	if from_phone != "":
		var p_info = _find_person_by_phone(from_phone)
		if not p_info.is_empty():
			matched_person_id = p_info["id"]

	var keyword = body.to_upper().strip_edges()
	var action = ""
	if keyword == "STOP":
		action = "Opt-Out (STOP)"
		if matched_person_id != null:
			db.execute("UPDATE people SET sms_consent = 0 WHERE id = ?;", [matched_person_id])
			var sync_evt_uuid = _generate_uuid()
			var sync_payload = {
				"person_uuid": _get_person_uuid_by_id(matched_person_id),
				"sms_consent": 0,
				"updated_at": Time.get_datetime_string_from_system()
			}
			db.execute("INSERT OR IGNORE INTO event_outbox (event_uuid, event_type, aggregate_type, aggregate_id, payload_json, device_uuid, status) VALUES (?, 'PersonUpdated', 'Person', ?, ?, ?, 'pending');", [sync_evt_uuid, sync_payload["person_uuid"], JSON.stringify(sync_payload), get_device_uuid()])

	var insert_sms = """
		INSERT INTO inbound_sms_log (
			message_sid, from_phone_e164, to_phone_e164, raw_body, normalized_keyword,
			action_taken, source, processing_status, matched_person_id, is_read, received_at
		) VALUES (?, ?, ?, ?, ?, ?, ?, 'processed', ?, 0, datetime('now'));
	"""
	var db_res = db.execute(insert_sms, [
		message_sid,
		from_phone,
		to_phone,
		body,
		keyword,
		action,
		"Twilio Inbound",
		matched_person_id
	])
	if not db_res["success"]:
		print("[Processor] Failed to insert SMS: ", db_res["error"])

	var outbox_uuid = _generate_uuid()
	var outbox_payload = {
		"message_sid": message_sid,
		"from_phone": from_phone,
		"to_phone": to_phone,
		"body": body,
		"keyword": keyword,
		"action_taken": action,
		"matched_person_id": matched_person_id,
		"received_at": Time.get_datetime_string_from_system()
	}
	db.execute("INSERT OR IGNORE INTO event_outbox (event_uuid, event_type, aggregate_type, aggregate_id, payload_json, device_uuid, status) VALUES (?, 'SmsReceived', 'Sms', ?, ?, ?, 'pending');", [outbox_uuid, message_sid, JSON.stringify(outbox_payload), get_device_uuid()])

	db.execute("UPDATE inbound_event_queue SET processed = 1 WHERE id = ?;", [event_id])

func _process_voicemail(event_id: int, payload: Dictionary, completion_callback: Callable) -> void:
	var caller_phone = str(payload.get("From", "")).strip_edges()
	var call_sid = str(payload.get("CallSid", "")).strip_edges()
	var recording_url = str(payload.get("RecordingUrl", "")).strip_edges()
	var duration_sec = int(payload.get("RecordingDuration", 30))
	var transcription = str(payload.get("TranscriptionText", "")).strip_edges()
	
	var matched_person_id = null
	var caller_name = "Unknown Caller"
	if caller_phone != "":
		var p_info = _find_person_by_phone(caller_phone)
		if not p_info.is_empty():
			matched_person_id = p_info["id"]
			caller_name = p_info["name"]

	if transcription == "" and recording_url != "":
		var api_key = get_gemini_api_key()
		if api_key != "":
			print("[Processor] Voicemail has no transcript. Calling Gemini...")
			_call_gemini_transcribe(api_key, recording_url, func(gemini_trans: String):
				_save_voicemail_record(event_id, call_sid, caller_name, caller_phone, duration_sec, recording_url, gemini_trans, matched_person_id)
				completion_callback.call()
			)
			return
			
	_save_voicemail_record(event_id, call_sid, caller_name, caller_phone, duration_sec, recording_url, transcription, matched_person_id)
	completion_callback.call()

func _normalize_phone_digits(phone_str: String) -> String:
	var digits = ""
	for c in phone_str:
		if c >= '0' and c <= '9':
			digits += c
	if digits.length() == 11 and digits.begins_with("1"):
		digits = digits.substr(1)
	return digits

func _find_person_by_phone(phone_str: String) -> Dictionary:
	if not db or phone_str == "": return {}
	var target_digits = _normalize_phone_digits(phone_str)
	if target_digits == "": return {}
	
	var res = db.execute("SELECT id, first_name, last_name, phone FROM people;")
	if res["success"] and res["data"].size() > 0:
		for p in res["data"]:
			var p_phone = str(p.get("phone", ""))
			if _normalize_phone_digits(p_phone) == target_digits:
				var fn = str(p.get("first_name", "")) if p.get("first_name") != null else ""
				var ln = str(p.get("last_name", "")) if p.get("last_name") != null else ""
				var full_name = (fn + " " + ln).strip_edges()
				if full_name == "" or full_name == "<null>": full_name = "Unknown Contact"
				return {"id": int(p["id"]), "name": full_name}
	return {}

func _save_voicemail_record(event_id: int, call_sid: String, caller_name: String, caller_phone: String, duration_sec: int, recording_url: String, transcription: String, matched_person_id: Variant) -> void:
	var vm_uuid = _generate_uuid()
	var insert_vm = """
		INSERT INTO voicemails (
			voicemail_uuid, caller_name, caller_phone, duration_sec, recording_url,
			transcription, status, created_at, assigned_person_id, priority
		) VALUES (?, ?, ?, ?, ?, ?, 'new', datetime('now'), ?, 'Medium');
	"""
	var db_res = db.execute(insert_vm, [
		vm_uuid,
		caller_name,
		caller_phone,
		duration_sec,
		recording_url,
		transcription,
		matched_person_id
	])
	if not db_res["success"]:
		print("[Processor] Failed to insert voicemail: ", db_res["error"])

	var outbox_uuid = _generate_uuid()
	var outbox_payload = {
		"voicemail_uuid": vm_uuid,
		"caller_name": caller_name,
		"caller_phone": caller_phone,
		"duration_sec": duration_sec,
		"recording_url": recording_url,
		"transcription": transcription,
		"matched_person_id": matched_person_id,
		"created_at": Time.get_datetime_string_from_system()
	}
	db.execute("INSERT OR IGNORE INTO event_outbox (event_uuid, event_type, aggregate_type, aggregate_id, payload_json, device_uuid, status) VALUES (?, 'VoicemailReceived', 'Voicemail', ?, ?, ?, 'pending');", [outbox_uuid, vm_uuid, JSON.stringify(outbox_payload), get_device_uuid()])

	db.execute("UPDATE inbound_event_queue SET processed = 1 WHERE id = ?;", [event_id])

func _call_gemini_transcribe(api_key: String, recording_url: String, callback: Callable) -> void:
	var gateway_url = "https://app.reallife-studycenter.org"
	var sync_key = "SCH_7wY9Pq4LmX8Nz2RbV5Kd1Hs6Mf3Jc9QaTp8Ux"
	var proxy_url = gateway_url + "/api/v1/proxy/recording?sync_api_key=" + sync_key + "&url=" + recording_url.uri_encode()
	
	var url = "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key=" + api_key
	var headers = ["Content-Type: application/json"]
	var body = JSON.stringify({
		"contents": [
			{
				"parts": [
					{ "text": "Please provide an accurate text transcription of the voicemail audio file at this URL. Return ONLY the transcription text: " + proxy_url }
				]
			}
		]
	})
	
	var err = http_client.request(url, headers, HTTPClient.METHOD_POST, body)
	if err != OK:
		callback.call("[Transcription failed to start]")
		return
		
	http_client.request_completed.connect(func(_result: int, response_code: int, _r_headers: PackedStringArray, body_bytes: PackedByteArray):
		if response_code == 200:
			var resp_text = body_bytes.get_string_from_utf8()
			var json = JSON.parse_string(resp_text)
			if json and json.has("candidates") and json["candidates"].size() > 0:
				var candidate = json["candidates"][0]
				if candidate.has("content") and candidate["content"].has("parts") and candidate["content"]["parts"].size() > 0:
					var trans_text = str(candidate["content"]["parts"][0].get("text", "")).strip_edges()
					callback.call(trans_text)
					return
		callback.call("[Gemini transcription unavailable]")
	, CONNECT_ONE_SHOT)

func _get_person_uuid_by_id(person_id: int) -> String:
	var res = db.execute("SELECT person_uuid FROM people WHERE id = ? LIMIT 1;", [person_id])
	if res["success"] and res["data"].size() > 0:
		return str(res["data"][0]["person_uuid"])
	return ""

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
