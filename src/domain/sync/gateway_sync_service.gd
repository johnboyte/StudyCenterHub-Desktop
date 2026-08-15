extends RefCounted

## Gateway Sync Service for StudyCenterHub
## Coordinates pulling incoming provider-agnostic events from SiteGround,
## acknowledging processed events to keep the relay buffer small,
## and automatically publishing IVR configurations from local SQLite.
## Complies with permanent design rules: relay has minimal durable state.

var db: RefCounted
var http_client: HTTPRequest
var parent_node: Node

func _init(database: RefCounted, caller_node: Node) -> void:
	db = database
	parent_node = caller_node
	
	http_client = HTTPRequest.new()
	http_client.timeout = 5.0
	if parent_node:
		parent_node.add_child(http_client)

func get_gateway_url() -> String:
	var res = db.execute("SELECT setting_value FROM app_settings WHERE setting_key = 'GATEWAY_SERVER_URL' LIMIT 1;")
	if res["success"] and res["data"].size() > 0:
		return str(res["data"][0]["setting_value"]).strip_edges()
	return "https://app.reallife-studycenter.org"

func get_sync_api_key() -> String:
	var res = db.execute("SELECT setting_value FROM app_settings WHERE setting_key = 'GATEWAY_SYNC_API_KEY' LIMIT 1;")
	if res["success"] and res["data"].size() > 0:
		var val = str(res["data"][0]["setting_value"]).strip_edges()
		if val != "" and val != "demo_sync_key":
			return val
	return "SCH_SYNC_KEY_PLACEHOLDER_8f3d"

func sync_now(callback: Callable) -> void:
	# 1. Pull new events from relay buffer
	var last_event_id = 0
	var id_res = db.execute("SELECT MAX(id) AS max_id FROM inbound_event_queue;")
	if id_res["success"] and id_res["data"].size() > 0 and id_res["data"][0]["max_id"] != null:
		last_event_id = int(id_res["data"][0]["max_id"])
		
	var gateway_url = get_gateway_url()
	var api_key = get_sync_api_key()
	var pull_url = gateway_url + "/api/v1/sync/pull"
	var headers = [
		"Content-Type: application/json",
		"x-sync-api-key: " + api_key
	]
	
	var pull_body = JSON.stringify({ "last_event_id": last_event_id })
	var err = http_client.request(pull_url, headers, HTTPClient.METHOD_POST, pull_body)
	if err != OK:
		callback.call({"success": false, "error": "Pull request failed to start."})
		return
		
	http_client.request_completed.connect(func(result: int, response_code: int, _r_headers: PackedStringArray, body_bytes: PackedByteArray):
		if response_code != 200:
			callback.call({"success": false, "error": "Pull request failed with status: " + str(response_code)})
			return
			
		var resp_text = body_bytes.get_string_from_utf8()
		var json = JSON.parse_string(resp_text)
		if not json or not json.get("success", false):
			callback.call({"success": false, "error": "Invalid pull response: " + resp_text.left(100)})
			return
			
		var events = json.get("events", [])
		var inserted_count = 0
		
		for evt in events:
			var res = db.execute(
				"INSERT OR IGNORE INTO inbound_event_queue (id, event_type, payload_json, received_at, processed) VALUES (?, ?, ?, ?, 0);",
				[int(evt["id"]), str(evt["event_type"]), str(evt["payload_json"]), str(evt["received_at"])]
			)
			_process_inbound_event(evt)
			if res["success"] and res.get("rows_affected", 0) > 0:
				inserted_count += 1
			
		callback.call({"success": true, "inserted_count": inserted_count, "total_pulled": events.size()})
	, CONNECT_ONE_SHOT)

func _process_inbound_event(evt: Dictionary) -> void:
	var evt_type = str(evt.get("event_type", ""))
	var raw_p = evt.get("payload_json", {})
	var payload: Dictionary = {}
	if typeof(raw_p) == TYPE_DICTIONARY:
		payload = raw_p
	elif typeof(raw_p) == TYPE_STRING:
		var parsed = JSON.parse_string(raw_p)
		if typeof(parsed) == TYPE_DICTIONARY:
			payload = parsed

	if evt_type in ["TwilioDeliveryStatus", "MessageStatusUpdated", "message.status_updated"]:
		const TwilioGatewayScript = preload("res://src/infrastructure/messaging/twilio_gateway_service.gd")
		var twilio = TwilioGatewayScript.new(db)
		twilio.process_twilio_webhook_payload(payload)

func _push_acknowledgements(callback: Callable, inserted_count: int) -> void:
	# Find processed events to acknowledge on relay
	db.execute("ALTER TABLE inbound_event_queue ADD COLUMN status TEXT DEFAULT 'pending';")
	db.execute("ALTER TABLE inbound_event_queue ADD COLUMN result_json TEXT DEFAULT NULL;")
	
	var ack_res = db.execute("SELECT id, status, result_json FROM inbound_event_queue WHERE processed = 1;")
	if not ack_res["success"] or ack_res["data"].size() == 0:
		callback.call({"success": true, "inserted_count": inserted_count, "ack_count": 0})
		return
		
	var event_ids = []
	var event_results = {}
	for row in ack_res["data"]:
		var eid = int(row["id"])
		event_ids.append(eid)
		if row.get("result_json", null) != null and str(row["result_json"]) != "":
			var parsed = JSON.parse_string(str(row["result_json"]))
			if typeof(parsed) == TYPE_DICTIONARY:
				event_results[str(eid)] = parsed
			else:
				event_results[str(eid)] = {"status": str(row.get("status", "processed"))}
		
	var gateway_url = get_gateway_url()
	var api_key = get_sync_api_key()
	var ack_url = gateway_url + "/api/v1/sync/ack"
	var headers = [
		"Content-Type: application/json",
		"x-sync-api-key: " + api_key
	]
	
	var ack_body = JSON.stringify({ "event_ids": event_ids, "event_results": event_results })
	var err = http_client.request(ack_url, headers, HTTPClient.METHOD_POST, ack_body)
	if err != OK:
		callback.call({"success": true, "inserted_count": inserted_count, "error": "Pull complete, ack failed to start."})
		return
		
	http_client.request_completed.connect(func(_result: int, response_code: int, _r_headers: PackedStringArray, _body_bytes: PackedByteArray):
		publish_directory_index()
		publish_today_attendance_index()
		publish_staff_credentials_index()
		if response_code == 200:
			callback.call({"success": true, "inserted_count": inserted_count, "ack_count": event_ids.size()})
		else:
			callback.call({"success": true, "inserted_count": inserted_count, "error": "Pull complete, ack response failed: " + str(response_code)})
	, CONNECT_ONE_SHOT)

func publish_today_attendance_index(callback: Callable = Callable()) -> void:
	var today_date = Time.get_date_string_from_system()
	var res = db.execute("""
		SELECT DISTINCT al.human_id, p.phone
		FROM attendance_log al
		LEFT JOIN people p ON p.id = al.person_id
		WHERE al.check_in_date = ?
		  AND (al.check_out_time IS NULL OR al.check_out_time = '');
	""", [today_date])
	var attendance = []
	if res["success"]:
		for row in res["data"]:
			var hid = String(row.get("human_id", ""))
			var ph = String(row.get("phone", "")) if row.get("phone") != null else ""
			if hid != "":
				attendance.append({
					"human_id": hid,
					"phone_e164": ph
				})

	var gateway_url = get_gateway_url()
	var api_key = get_sync_api_key()
	var url = gateway_url + "/api/v1/sync/attendance-index"
	var headers = [
		"Content-Type: application/json",
		"x-sync-api-key: " + api_key
	]
	var body = JSON.stringify({
		"attendance_date": today_date,
		"attendance": attendance
	})

	var req = HTTPRequest.new()
	if parent_node and parent_node.is_inside_tree():
		parent_node.add_child(req)
		req.request_completed.connect(func(_res: int, resp_code: int, _h: PackedStringArray, _b: PackedByteArray):
			req.queue_free()
			if callback.is_valid():
				callback.call({"success": resp_code == 200, "synced_count": attendance.size()})
		, CONNECT_ONE_SHOT)
		req.request(url, headers, HTTPClient.METHOD_POST, body)
	else:
		if callback.is_valid():
			callback.call({"success": false, "error": "Parent node not in tree"})

func publish_directory_index(callback: Callable = Callable()) -> void:
	var res = db.execute("""
		SELECT p.first_name, COALESCE(p.last_name, '') as last_name, p.phone, p.human_id, COALESCE(p.profile_photo, '') as profile_photo,
		       (SELECT MAX(al.check_in_date) FROM attendance_log al WHERE al.person_id = p.id) as last_checkin_date
		FROM people p WHERE p.status = 'active';
	""")
	var members = []
	if res["success"]:
		members = res["data"]
		
	var gateway_url = get_gateway_url()
	var api_key = get_sync_api_key()
	var url = gateway_url + "/api/v1/sync/directory-index"
	var headers = [
		"Content-Type: application/json",
		"x-sync-api-key: " + api_key
	]
	var body = JSON.stringify({ "members": members })
	
	var req = HTTPRequest.new()
	if parent_node and parent_node.is_inside_tree():
		parent_node.add_child(req)
		req.request_completed.connect(func(_res: int, resp_code: int, _h: PackedStringArray, _b: PackedByteArray):
			req.queue_free()
			if callback.is_valid():
				callback.call({"success": resp_code == 200})
		, CONNECT_ONE_SHOT)
		req.request(url, headers, HTTPClient.METHOD_POST, body)
	else:
		if callback.is_valid():
			callback.call({"success": false, "error": "Parent node not in scene tree"})

func publish_session_index(callback: Callable = Callable()) -> void:
	db.execute("ALTER TABLE sessions ADD COLUMN public_signup_enabled INTEGER NOT NULL DEFAULT 1;")
	db.execute("ALTER TABLE sessions ADD COLUMN waitlist_enabled INTEGER NOT NULL DEFAULT 1;")
	db.execute("ALTER TABLE sessions ADD COLUMN max_waitlist INTEGER DEFAULT NULL;")
	db.execute("ALTER TABLE sessions ADD COLUMN registration_open_at TEXT DEFAULT NULL;")
	db.execute("ALTER TABLE sessions ADD COLUMN registration_close_at TEXT DEFAULT NULL;")

	var sess_sql = """
		SELECT 
			s.id, 
			s.session_uuid, 
			s.title, 
			COALESCE(st.name, s.session_type, 'General Study') as session_type, 
			s.date_text, 
			s.start_time, 
			s.end_time, 
			COALESCE(sl.name, s.room_location, 'Real Life House') as room_location, 
			s.max_capacity, 
			COALESCE(s.signup_required, 1) as signup_required, 
			COALESCE(s.limit_signups, 1) as limit_signups, 
			COALESCE(s.public_signup_enabled, 1) as public_signup_enabled, 
			COALESCE(s.waitlist_enabled, 1) as waitlist_enabled, 
			s.max_waitlist, 
			s.registration_open_at, 
			s.registration_close_at, 
			s.description,
			(SELECT COUNT(*) FROM session_signups ss WHERE ss.session_id = s.id AND ss.signup_status = 'confirmed') as confirmed_count,
			(SELECT COUNT(*) FROM session_signups ss WHERE ss.session_id = s.id AND ss.signup_status = 'waitlist') as waitlist_count
		FROM sessions s
		LEFT JOIN session_types st ON st.id = s.session_type_id
		LEFT JOIN session_location_assignments sla ON sla.session_id = s.id
		LEFT JOIN session_locations sl ON sl.id = sla.location_id
		WHERE s.is_active = 1 AND s.public_signup_enabled = 1
		ORDER BY s.date_text ASC, s.start_time ASC;
	"""
	var sess_res = db.execute(sess_sql)
	var sessions = sess_res["data"] if sess_res["success"] else []

	var sgn_sql = """
		SELECT ss.session_id, p.human_id, p.phone, ss.signup_status 
		FROM session_signups ss 
		JOIN people p ON p.id = ss.person_id 
		WHERE ss.signup_status IN ('confirmed', 'waitlist');
	"""
	var sgn_res = db.execute(sgn_sql)
	var signups = sgn_res["data"] if sgn_res["success"] else []

	var gateway_url = get_gateway_url()
	var api_key = get_sync_api_key()
	var url = gateway_url + "/api/v1/sync/session-index"
	var headers = [
		"Content-Type: application/json",
		"x-sync-api-key: " + api_key
	]
	var body = JSON.stringify({ "sessions": sessions, "signups": signups })

	var req = HTTPRequest.new()
	if parent_node and parent_node.is_inside_tree():
		parent_node.add_child(req)
		req.request_completed.connect(func(_res: int, resp_code: int, _h: PackedStringArray, _b: PackedByteArray):
			req.queue_free()
			if callback.is_valid():
				callback.call({"success": resp_code == 200})
		, CONNECT_ONE_SHOT)
		req.request(url, headers, HTTPClient.METHOD_POST, body)
	else:
		if callback.is_valid():
			callback.call({"success": false, "error": "Parent node not in tree"})

func push_acknowledgements_now(callback: Callable = Callable()) -> void:
	_push_acknowledgements(func(res: Dictionary):
		if callback.is_valid():
			callback.call(res)
	, 0)

func publish_ivr_config(callback: Callable) -> void:
	var phone_settings = {
		"on_call_phone": "",
		"rollover_rings": 4,
		"tts_greeting_active": true,
		"greeting_text": "",
		"menu_options": {},
		"staff_members": {}
	}
	
	# Load settings
	var settings_res = db.execute("SELECT setting_key, setting_value FROM app_settings WHERE setting_key LIKE 'PHONE_%';")
	if settings_res["success"]:
		for row in settings_res["data"]:
			var key = str(row["setting_key"])
			var val = str(row["setting_value"])
			if key == "PHONE_ON_CALL_PERSON_ID" and val != "":
				var p_res = db.execute("SELECT phone FROM people WHERE id = ? LIMIT 1;", [int(val)])
				if p_res["success"] and p_res["data"].size() > 0:
					phone_settings["on_call_phone"] = str(p_res["data"][0]["phone"])
			elif key == "PHONE_ROLLOVER_RINGS":
				phone_settings["rollover_rings"] = int(val)
			elif key == "PHONE_TTS_GREETING_ACTIVE":
				phone_settings["tts_greeting_active"] = (val == "1")
			elif key == "PHONE_AUTOMATED_GREETER_TTS":
				phone_settings["greeting_text"] = val

	# Load IVR voice settings
	var ivr_res = db.execute("SELECT voice_name, language FROM ivr_settings WHERE id = 1;")
	if ivr_res["success"] and ivr_res["data"].size() > 0:
		phone_settings["voice_name"] = str(ivr_res["data"][0]["voice_name"])
		phone_settings["language"] = str(ivr_res["data"][0]["language"])
	else:
		phone_settings["voice_name"] = "Polly.Kimberly-Neural"
		phone_settings["language"] = "en-US"

	# Load active staff members
	var staff_members_list = []
	var staff_members_map = {}
	var staff_res = db.execute("SELECT display_name, transfer_number, ring_timeout, unanswered_destination, menu_digit FROM staff_members WHERE is_active = 1;")
	if staff_res["success"]:
		staff_members_list = staff_res["data"]
		for s in staff_members_list:
			var s_name = str(s["display_name"])
			staff_members_map[s_name] = {
				"name": s_name,
				"phone": str(s["transfer_number"]),
				"ring_timeout": int(s["ring_timeout"]),
				"unanswered_destination": str(s["unanswered_destination"])
			}
	phone_settings["staff_members"] = staff_members_map

	# Instantiate CommunicationsService to compute dynamic texts
	const CommunicationsServiceScript = preload("res://src/domain/communications/communications_service.gd")
	var com_svc = CommunicationsServiceScript.new(db)

	# Fetch all IVR nodes
	var nodes_res = db.execute("SELECT id, parent_id, digit, label, action_type, action_param, script_text, dynamic_source, is_active, display_order FROM ivr_menu_nodes;")
	var all_nodes = []
	if nodes_res["success"]:
		all_nodes = nodes_res["data"]

	# Organize roots
	var roots = []
	for n in all_nodes:
		if n.get("parent_id") == null or str(n["parent_id"]) == "" or str(n["parent_id"]) == "null":
			if int(n.get("is_active", 1)) == 1:
				roots.append(n)

	# Sort roots
	roots.sort_custom(func(a, b):
		if int(a.get("display_order", 0)) != int(b.get("display_order", 0)):
			return int(a.get("display_order", 0)) < int(b.get("display_order", 0))
		return str(a["digit"]) < str(b["digit"])
	)

	# Compile tree recursively
	var compiled_options = {}
	for r in roots:
		_compile_node_recursive(r, all_nodes, "", compiled_options, staff_members_list, com_svc)

	phone_settings["menu_options"] = compiled_options

	# Publish compiled payload to SiteGround relay cache
	var gateway_url = get_gateway_url()
	var api_key = get_sync_api_key()
	var config_url = gateway_url + "/api/v1/sync/ivr-config"
	var headers = [
		"Content-Type: application/json",
		"x-sync-api-key: " + api_key,
		"User-Agent: StudyCenterHubDesktop/1.0"
	]
	
	var config_body = JSON.stringify({ "ivr_config": phone_settings })
	var err = http_client.request(config_url, headers, HTTPClient.METHOD_POST, config_body)
	if err != OK:
		callback.call({"success": false, "error": "IVR config publish failed to start."})
		return
		
	http_client.request_completed.connect(func(_result: int, response_code: int, _r_headers: PackedStringArray, _body_bytes: PackedByteArray):
		if response_code == 200:
			callback.call({"success": true})
		else:
			callback.call({"success": false, "error": "Config publish failed with status: " + str(response_code)})
	, CONNECT_ONE_SHOT)

func _compile_node_recursive(node: Dictionary, all_nodes: Array, parent_path: String, compiled_options: Dictionary, active_staff: Array, com_svc: RefCounted) -> void:
	var current_path = parent_path
	if current_path != "":
		current_path += "-" + str(node["digit"])
	else:
		current_path = str(node["digit"])
		
	var act_type = str(node["action_type"])
	var param = str(node.get("action_param", "")) if node.get("action_param") != null else ""
	var script = str(node.get("script_text", "")) if node.get("script_text") != null else ""
	var d_src = str(node.get("dynamic_source", "")) if node.get("dynamic_source") != null else ""
	
	# Compute dynamic scripts if flag matches (reusable shared settings)
	if d_src == "location_directions":
		var res = db.execute("SELECT setting_value FROM app_settings WHERE setting_key = 'PHONE_LOCATION_DIRECTIONS_TEXT' LIMIT 1;")
		if res["success"] and res["data"].size() > 0:
			script = str(res["data"][0]["setting_value"])

	if act_type == "staff_directory":
		# Compile the listing text dynamically based on the active staff in database
		var list_texts = []
		for s in active_staff:
			list_texts.append("To reach " + str(s["display_name"]) + ", press " + str(s["menu_digit"]) + ".")
		list_texts.append("For General Staff Voicemail, press 3. To return to the main menu, press 9.")
		var greeting = " ".join(list_texts)
		
		# Define staff directory submenu node itself
		compiled_options[current_path] = {
			"action_type": "submenu",
			"script_text": greeting,
			"action_param": ""
		}
		
		# Generate children paths underneath dynamically
		for s in active_staff:
			var s_path = current_path + "-" + str(s["menu_digit"])
			compiled_options[s_path] = {
				"action_type": "transfer_staff",
				"script_text": "",
				"action_param": str(s["display_name"])
			}
			
		# Voicemail fallback Option 3
		compiled_options[current_path + "-3"] = {
			"action_type": "voicemail",
			"script_text": "Please leave your name, phone number, and a brief message after the tone, and someone from Real Life House will get back in touch with you.",
			"action_param": "staff_general"
		}
		
		# Return to Main Option 9
		compiled_options[current_path + "-9"] = {
			"action_type": "return_to_main",
			"script_text": "",
			"action_param": ""
		}
	elif act_type == "return_to_main" or act_type == "Return to Main Menu":
		compiled_options[current_path] = {
			"action_type": "return_to_main",
			"script_text": "",
			"action_param": ""
		}
	elif act_type == "hangup" or act_type == "Hang Up":
		compiled_options[current_path] = {
			"action_type": "hangup",
			"script_text": script,
			"action_param": ""
		}
	else:
		# Standard options
		compiled_options[current_path] = {
			"action_type": act_type,
			"script_text": script,
			"action_param": param
		}
		
	# Recurse for all children
	var children = []
	for candidate in all_nodes:
		if candidate.get("parent_id") != null and int(candidate["parent_id"]) == int(node["id"]) and int(candidate.get("is_active", 1)) == 1:
			children.append(candidate)
			
	children.sort_custom(func(a, b):
		if int(a.get("display_order", 0)) != int(b.get("display_order", 0)):
			return int(a.get("display_order", 0)) < int(b.get("display_order", 0))
		return str(a["digit"]) < str(b["digit"])
	)
	
	for child in children:
		_compile_node_recursive(child, all_nodes, current_path, compiled_options, active_staff, com_svc)

func publish_staff_credentials_index(callback: Callable = Callable()) -> void:
	if not db:
		if callback.is_valid():
			callback.call({"success": false, "error": "Database unavailable"})
		return

	# Ensure staff_mobile_credentials table exists
	db.execute("""
		CREATE TABLE IF NOT EXISTS staff_mobile_credentials (
			id INTEGER PRIMARY KEY AUTOINCREMENT,
			person_id INTEGER NOT NULL UNIQUE REFERENCES people(id) ON DELETE CASCADE,
			human_id TEXT NOT NULL UNIQUE,
			pin_pbkdf_hash TEXT NOT NULL,
			credential_version INTEGER NOT NULL DEFAULT 1,
			mobile_access_enabled INTEGER NOT NULL DEFAULT 1,
			created_at TEXT NOT NULL DEFAULT (datetime('now')),
			updated_at TEXT NOT NULL DEFAULT (datetime('now'))
		);
	""")

	var res = db.execute("""
		SELECT 
			p.id, p.human_id, p.first_name, p.last_name, p.primary_role, p.email, p.status,
			smc.pin_pbkdf_hash, smc.credential_version
		FROM people p
		JOIN staff_mobile_credentials smc ON smc.person_id = p.id AND smc.mobile_access_enabled = 1
		WHERE LOWER(p.status) = 'active'
		  AND (
			  LOWER(p.primary_role) IN ('staff', 'team leader', 'supervisor', 'administrator', 'intern', 'volunteer')
		   OR LOWER(COALESCE(p.staff_classification, '')) IN ('staff', 'team leader', 'supervisor', 'administrator', 'intern', 'volunteer')
		  );
	""")

	var staff_payload = []
	if res["success"]:
		for row in res["data"]:
			var hid = String(row.get("human_id", "")).strip_edges()
			var fn = String(row.get("first_name", "")).strip_edges()
			var ln = String(row.get("last_name", "")).strip_edges()
			var disp_name = (fn + " " + ln).strip_edges()
			if disp_name == "":
				disp_name = "Staff Member"
			var email = String(row.get("email", "")).strip_edges() if row.get("email") != null else ""
			var role = String(row.get("primary_role", "Staff")).strip_edges()
			var pin_h = String(row.get("pin_pbkdf_hash", "")).strip_edges()
			var cred_ver = int(row.get("credential_version", 1))

			if hid != "" and pin_h != "":
				staff_payload.append({
					"human_id": hid,
					"display_name": disp_name,
					"email": email,
					"role": role,
					"pin_hash": pin_h,
					"credential_version": cred_ver,
					"capabilities": ["view_attendance"],
					"status": "active"
				})

	var gateway_url = get_gateway_url()
	var api_key = get_sync_api_key()
	var url = gateway_url + "/api/v1/sync/staff-credentials-index"
	var headers = [
		"Content-Type: application/json",
		"x-sync-api-key: " + api_key
	]
	var body = JSON.stringify({ "staff": staff_payload })

	var req = HTTPRequest.new()
	if parent_node and parent_node.is_inside_tree():
		parent_node.add_child(req)
		req.request_completed.connect(func(_res: int, resp_code: int, _h: PackedStringArray, _b: PackedByteArray):
			req.queue_free()
			if callback.is_valid():
				callback.call({"success": resp_code == 200, "synced_count": staff_payload.size()})
		, CONNECT_ONE_SHOT)
		req.request(url, headers, HTTPClient.METHOD_POST, body)
	else:
		if callback.is_valid():
			callback.call({"success": false, "error": "Parent node not in scene tree"})

