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
	parent_node.add_child(http_client)

func get_gateway_url() -> String:
	var res = db.execute("SELECT setting_value FROM app_settings WHERE setting_key = 'GATEWAY_SERVER_URL' LIMIT 1;")
	if res["success"] and res["data"].size() > 0:
		return str(res["data"][0]["setting_value"]).strip_edges()
	return "https://app.reallife-studycenter.org"

func get_sync_api_key() -> String:
	var res = db.execute("SELECT setting_value FROM app_settings WHERE setting_key = 'GATEWAY_SYNC_API_KEY' LIMIT 1;")
	if res["success"] and res["data"].size() > 0:
		return str(res["data"][0]["setting_value"]).strip_edges()
	return "demo_sync_key"

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
		
		# Insert un-processed raw events into Godot's local buffer
		for evt in events:
			db.execute(
				"INSERT OR IGNORE INTO inbound_event_queue (id, event_type, payload_json, received_at, processed) VALUES (?, ?, ?, ?, 0);",
				[int(evt["id"]), str(evt["event_type"]), str(evt["payload_json"]), str(evt["received_at"])]
			)
			inserted_count += 1
			
		# Proceed to push/acknowledgements
		_push_acknowledgements(callback, inserted_count)
	, CONNECT_ONE_SHOT)

func _push_acknowledgements(callback: Callable, inserted_count: int) -> void:
	# Find processed events to acknowledge on relay
	var ack_res = db.execute("SELECT id FROM inbound_event_queue WHERE processed = 1;")
	if not ack_res["success"] or ack_res["data"].size() == 0:
		callback.call({"success": true, "inserted_count": inserted_count, "ack_count": 0})
		return
		
	var event_ids = []
	for row in ack_res["data"]:
		event_ids.append(int(row["id"]))
		
	var gateway_url = get_gateway_url()
	var api_key = get_sync_api_key()
	var ack_url = gateway_url + "/api/v1/sync/ack"
	var headers = [
		"Content-Type: application/json",
		"x-sync-api-key: " + api_key
	]
	
	var ack_body = JSON.stringify({ "event_ids": event_ids })
	var err = http_client.request(ack_url, headers, HTTPClient.METHOD_POST, ack_body)
	if err != OK:
		callback.call({"success": true, "inserted_count": inserted_count, "error": "Pull complete, ack failed to start."})
		return
		
	http_client.request_completed.connect(func(result: int, response_code: int, _r_headers: PackedStringArray, body_bytes: PackedByteArray):
		if response_code == 200:
			# Acknowledged on relay; safe to clean up local buffer
			var placeholders = []
			for id in event_ids: placeholders.append("?")
			var q = "DELETE FROM inbound_event_queue WHERE id IN (" + ",".join(placeholders) + ");"
			db.execute(q, event_ids)
			callback.call({"success": true, "inserted_count": inserted_count, "ack_count": event_ids.size()})
		else:
			callback.call({"success": true, "inserted_count": inserted_count, "error": "Pull complete, ack response failed: " + str(response_code)})
	, CONNECT_ONE_SHOT)

func publish_ivr_config(callback: Callable) -> void:
	# Compile active settings and options from SQLite
	var phone_settings = {
		"on_call_phone": "",
		"rollover_rings": 4,
		"tts_greeting_active": true,
		"greeting_text": "",
		"menu_options": {}
	}
	
	# Load settings
	var settings_res = db.execute("SELECT setting_key, setting_value FROM app_settings WHERE setting_key LIKE 'PHONE_%';")
	if settings_res["success"]:
		for row in settings_res["data"]:
			var key = str(row["setting_key"])
			var val = str(row["setting_value"])
			if key == "PHONE_ON_CALL_PERSON_ID" and val != "":
				# Resolve actual phone number from person ID
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
		phone_settings["voice_name"] = "Polly.Joanna"
		phone_settings["language"] = "en-US"

	# Load menu options
	var options_res = db.execute("SELECT digit, menu_option_name, script_text, action_type, action_param FROM ivr_menu_options;")
	if options_res["success"]:
		for row in options_res["data"]:
			var digit = str(row["digit"])
			phone_settings["menu_options"][digit] = {
				"action_type": str(row["action_type"]),
				"script_text": str(row["script_text"]),
				"action_param": str(row["action_param"]) if row["action_param"] != null else ""
			}

	# Publish compiled payload to SiteGround relay cache
	var gateway_url = get_gateway_url()
	var api_key = get_sync_api_key()
	var config_url = gateway_url + "/api/v1/sync/ivr-config"
	var headers = [
		"Content-Type: application/json",
		"x-sync-api-key: " + api_key
	]
	
	var config_body = JSON.stringify({ "ivr_config": phone_settings })
	var err = http_client.request(config_url, headers, HTTPClient.METHOD_POST, config_body)
	if err != OK:
		callback.call({"success": false, "error": "IVR config publish failed to start."})
		return
		
	http_client.request_completed.connect(func(result: int, response_code: int, _r_headers: PackedStringArray, body_bytes: PackedByteArray):
		if response_code == 200:
			callback.call({"success": true})
		else:
			callback.call({"success": false, "error": "Config publish failed with status: " + str(response_code)})
	, CONNECT_ONE_SHOT)
