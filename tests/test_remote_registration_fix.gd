extends SceneTree

## Automated Regression Test: Remote Self-Registration Bug Fix Verification
## Verifies that brand-new public self-registrations with camelCase emergency contact fields (minors < 18)
## properly validate, create people records, auto-check-in, and record confirmed status/result_json.

const InboundEventProcessorScript = preload("res://src/domain/sync/inbound_event_processor.gd")
const PersonRegistrationValidatorScript = preload("res://src/domain/directory/person_registration_validator.gd")

func _init() -> void:
	print("==========================================================")
	print("RUNNING AUTOMATED TEST: REMOTE SELF-REGISTRATION FIX")
	print("==========================================================")

	var db = load("res://src/infrastructure/database/sqlite_database.gd").new()
	var test_db_path = OS.get_user_data_dir() + "/test_remote_reg_fix.db"
	
	# Reset test db
	if FileAccess.file_exists(test_db_path):
		DirAccess.remove_absolute(test_db_path)
	
	db.open_db(test_db_path)
	
	# Run migrations
	var migrator = load("res://src/infrastructure/database/database_migrator.gd").new(db)
	migrator.run_migrations()

	# 1. Test payload with camelCase emergency contact keys for minor < 18
	var test_payload = {
		"firstName": "NewMinor",
		"lastName": "TestUser",
		"phone": "(864) 555-9876",
		"email": "newminor.test@example.org",
		"birthday": "2010-05-15", # Minor age 16
		"primaryRole": "High School Student",
		"institution": "T.L. Hanna High School",
		"grade": "11th Grade",
		"smsConsentChoice": "Yes",
		"sms_consent": 1,
		"emergencyContactName": "Parent SafetyContact",
		"emergencyContactPhone": "(864) 555-1122"
	}

	# 2. Test validator directly
	var val_res = PersonRegistrationValidatorScript.validate_registration(test_payload)
	print("🔍 Validator result is_valid:", val_res["is_valid"], " errors:", val_res["errors"])
	assert(val_res["is_valid"] == true, "Validator MUST pass for minor with emergencyContactName / emergencyContactPhone")

	# 3. Queue event in inbound_event_queue
	var ins_ev = db.execute(
		"INSERT INTO inbound_event_queue (provider, provider_event_id, event_type, payload_json, processed, created_at) VALUES ('web_portal', 'evt_test_reg_99', 'portal.registration', ?, 0, datetime('now'));",
		[JSON.stringify(test_payload)]
	)
	assert(ins_ev["success"] == true, "Queueing event must succeed")
	var event_id = ins_ev["last_insert_id"]

	# 4. Process event via InboundEventProcessor
	var dummy_node = Node.new()
	var processor = InboundEventProcessorScript.new(db, dummy_node)
	
	var processed_done = false
	processor.process_pending_events(func(res):
		processed_done = true
		print("✅ InboundEventProcessor finished. Result:", res)
	)
	
	assert(processed_done == true, "Processor callback must be invoked synchronously")

	# 5. Assert person row created
	var p_res = db.execute("SELECT * FROM people WHERE email = 'newminor.test@example.org' LIMIT 1;")
	assert(p_res["success"] and p_res["data"].size() == 1, "New person row MUST exist in database")
	var person = p_res["data"][0]
	print("✅ Person created - ID:", person["id"], " Name:", person["first_name"], person["last_name"], " EmergencyContact:", person.get("emergency_contact_name"))
	assert(str(person["first_name"]) == "NewMinor", "First name must match")
	assert(str(person["emergency_contact_name"]) == "Parent SafetyContact", "Emergency contact name must be saved")

	# 6. Assert attendance_log row created for today
	var today_str = Time.get_date_string_from_system()
	var att_res = db.execute("SELECT * FROM attendance_log WHERE person_id = ? AND check_in_date = ? LIMIT 1;", [person["id"], today_str])
	assert(att_res["success"] and att_res["data"].size() == 1, "Exactly 1 attendance_log row MUST exist for today")
	print("✅ Attendance record created - Log ID:", att_res["data"][0]["id"], " Date:", att_res["data"][0]["check_in_date"])

	# 7. Assert event queue result status and result_json
	var q_res = db.execute("SELECT * FROM inbound_event_queue WHERE id = ?;", [event_id])
	assert(q_res["success"] and q_res["data"].size() == 1, "Queue row must exist")
	var ev_row = q_res["data"][0]
	assert(int(ev_row["processed"]) == 1, "Event must be marked processed = 1")
	assert(str(ev_row.get("status", "")) == "registered_and_checked_in", "Event status must be registered_and_checked_in")
	
	var res_dict = JSON.parse_string(str(ev_row.get("result_json", "{}")))
	print("✅ Event Result JSON:", res_dict)
	assert(res_dict.get("checked_in") == true, "result_json must confirm checked_in = true")
	assert(res_dict.get("status") == "registered_and_checked_in", "result_json status must match")

	dummy_node.queue_free()

	print("==========================================================")
	print("ALL REGISTRATION FIX TESTS PASSED 100%")
	print("==========================================================")
	quit()
