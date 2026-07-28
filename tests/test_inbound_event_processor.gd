extends SceneTree

const SQLiteDatabaseScript = preload("res://src/infrastructure/database/sqlite_database.gd")
const MigrationsRunnerScript = preload("res://src/infrastructure/database/migrations_runner.gd")
const InboundEventProcessorScript = preload("res://src/domain/sync/inbound_event_processor.gd")

func _init() -> void:
	print("==========================================================")
	print("STARTING INBOUND EVENT PROCESSOR TEST SUITE")
	print("==========================================================")

	var db_path = ProjectSettings.globalize_path("user://test_inbound_event_processor.db")
	if FileAccess.file_exists(db_path):
		DirAccess.remove_absolute(db_path)
		
	var db = SQLiteDatabaseScript.new(db_path)

	var runner = MigrationsRunnerScript.new(db)
	var run_res = runner.run_migrations()
	assert(run_res["success"], "Migrations failed to run: " + run_res.get("error", ""))
	
	# Seed a test person for caller matching
	var seed_res = db.execute(
		"INSERT INTO people (person_uuid, human_id, first_name, last_name, phone, status) VALUES ('p-uuid-999', 'H-999', 'Jane', 'Doe', '+15095551212', 'Clear');"
	)
	assert(seed_res["success"], "Failed to seed person: " + seed_res.get("error", ""))
	
	# Seed test device identity
	var dev_res = db.execute(
		"INSERT INTO device_identity (device_uuid, device_name, registered_at) VALUES ('dev-test-111', 'Mock Device', datetime('now'));"
	)
	assert(dev_res["success"], "Failed to seed device identity: " + dev_res.get("error", ""))

	# 1. Insert mock twilio.sms event
	var sms_payload = {
		"MessageSid": "SM-mock-111",
		"From": "+15095551212",
		"To": "+18647124446",
		"Body": "hello world"
	}
	db.execute(
		"INSERT INTO inbound_event_queue (id, event_type, payload_json, received_at, processed) VALUES (1, 'twilio.sms', ?, datetime('now'), 0);",
		[JSON.stringify(sms_payload)]
	)

	# 2. Insert mock STOP sms event (opt-out check)
	var stop_payload = {
		"MessageSid": "SM-mock-222",
		"From": "+15095551212",
		"To": "+18647124446",
		"Body": "STOP"
	}
	db.execute(
		"INSERT INTO inbound_event_queue (id, event_type, payload_json, received_at, processed) VALUES (2, 'twilio.sms', ?, datetime('now'), 0);",
		[JSON.stringify(stop_payload)]
	)

	# 3. Insert mock twilio.voicemail event
	var vm_payload = {
		"CallSid": "CA-mock-333",
		"From": "+15095551212",
		"RecordingUrl": "https://api.twilio.com/recordings/RE-mock",
		"RecordingDuration": 45,
		"TranscriptionText": "Please call me back"
	}
	db.execute(
		"INSERT INTO inbound_event_queue (id, event_type, payload_json, received_at, processed) VALUES (3, 'twilio.voicemail', ?, datetime('now'), 0);",
		[JSON.stringify(vm_payload)]
	)

	# Setup processor
	var root = Node.new()
	var processor = InboundEventProcessorScript.new(db, root)
	
	# Process
	var state = {"processed": false}
	processor.process_pending_events(func(result: Dictionary):
		assert(result["success"], "Processing failed: " + result.get("error", ""))
		assert(result["processed_count"] == 3, "Expected 3 processed events, got " + str(result["processed_count"]))
		state["processed"] = true
	)
	
	# Wait brief moment for any async / frame ticks
	var t = Time.get_ticks_msec()
	while not state["processed"] and Time.get_ticks_msec() - t < 1000:
		pass
		
	assert(state["processed"], "Processor callback timed out.")

	# Verify Inbound SMS Log
	var sms_log_res = db.execute("SELECT * FROM inbound_sms_log ORDER BY id ASC;")
	assert(sms_log_res["success"], "Failed to query SMS log")
	assert(sms_log_res["data"].size() == 2, "Expected 2 SMS log rows, got " + str(sms_log_res["data"].size()))
	
	var row1 = sms_log_res["data"][0]
	assert(row1["message_sid"] == "SM-mock-111", "Message SID mismatch")
	assert(row1["raw_body"] == "hello world", "Body mismatch")
	assert(int(row1["matched_person_id"]) > 0, "Expected matched constituent ID")

	# Verify STOP action and consent update
	var consent_res = db.execute("SELECT sms_consent FROM people WHERE phone = '+15095551212';")
	assert(int(consent_res["data"][0]["sms_consent"]) == 0, "Expected STOP keyword to opt-out SMS consent.")

	# Verify Voicemail Log
	var vm_log_res = db.execute("SELECT * FROM voicemails;")
	assert(vm_log_res["success"], "Failed to query voicemails")
	assert(vm_log_res["data"].size() == 2, "Expected 2 voicemail rows, got " + str(vm_log_res["data"].size()))
	
	var vm_row = vm_log_res["data"][1]
	assert(vm_row["caller_phone"] == "+15095551212", "Voicemail caller phone mismatch")
	assert(vm_row["transcription"] == "Please call me back", "Voicemail transcription mismatch")
	assert(int(vm_row["duration_sec"]) == 45, "Voicemail duration mismatch")

	# Verify event_outbox logs created to sync to Google Sheets
	var outbox_res = db.execute("SELECT event_type FROM event_outbox ORDER BY id ASC;")
	assert(outbox_res["success"], "Failed to query outbox")
	var types = []
	for r in outbox_res["data"]:
		types.append(r["event_type"])
	
	assert("SmsReceived" in types, "Expected SmsReceived in event outbox log")
	assert("PersonUpdated" in types, "Expected PersonUpdated in event outbox log")
	assert("VoicemailReceived" in types, "Expected VoicemailReceived in event outbox log")

	# Clean up Node
	root.free()

	print("==========================================================")
	print("SUCCESS: ALL INBOUND EVENT PROCESSOR TEST OBJECTIVES PASSED")
	print("==========================================================")
	quit()
