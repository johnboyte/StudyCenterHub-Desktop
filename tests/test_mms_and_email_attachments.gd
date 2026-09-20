extends SceneTree

## Unit & Integration Tests for MMS & Email Flyer Attachments

const SQLiteDatabaseScript = preload("res://src/infrastructure/database/sqlite_database.gd")
const MigrationsRunnerScript = preload("res://src/infrastructure/database/migrations_runner.gd")
const CommunicationsServiceScript = preload("res://src/domain/communications/communications_service.gd")

func _init() -> void:
	print("--- STARTING TEST: MMS & Email Flyer Attachments ---")

	var db_path = "user://test_attachments_" + str(Time.get_ticks_usec()) + ".db"
	var db = SQLiteDatabaseScript.new(db_path)

	var runner = MigrationsRunnerScript.new(db)
	var m_res = runner.run_migrations()
	assert(m_res.get("success", false) == true, "Failed to run migrations: " + str(m_res.get("error", "")))

	var com_service = CommunicationsServiceScript.new(db)
	assert(com_service != null, "Failed to instantiate CommunicationsService")

	# Create temporary test image files
	var tmp_dir = OS.get_user_data_dir()
	DirAccess.make_dir_recursive_absolute(tmp_dir)

	var test_jpg_path = tmp_dir + "/test_flyer.jpg"
	var img = Image.create(800, 600, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.2, 0.5, 0.8, 1.0))
	var save_err = img.save_jpg(test_jpg_path, 0.9)
	assert(save_err == OK, "Failed to create test JPG image")

	var test_txt_path = tmp_dir + "/test_script.sh"
	var f_txt = FileAccess.open(test_txt_path, FileAccess.WRITE)
	if f_txt:
		f_txt.store_string("#!/bin/bash\necho hello")
		f_txt.close()

	# Test 1: Attachment Validation
	print("\n[TEST 1] Testing Attachment Validation...")
	var val_ok = com_service.validate_attachment(test_jpg_path, "SMS Text")
	assert(val_ok.get("valid", false) == true, "Valid JPG should pass validation")
	print("  PASS: JPG validation passed")

	var val_bad = com_service.validate_attachment(test_txt_path, "SMS Text")
	assert(val_bad.get("valid", false) == false, "Script file should be rejected")
	print("  PASS: Unsupported file rejected cleanly: ", val_bad.get("reason", ""))

	var val_nonexistent = com_service.validate_attachment(tmp_dir + "/missing.jpg", "SMS Text")
	assert(val_nonexistent.get("valid", false) == false, "Missing file should be rejected")
	print("  PASS: Missing file rejected cleanly: ", val_nonexistent.get("reason", ""))

	# Insert test constituent into people table
	var p_stmt = {
		"sql": "INSERT INTO people (id, person_uuid, human_id, first_name, last_name, phone, email, sms_consent) VALUES (?, ?, ?, ?, ?, ?, ?, ?);",
		"args": [101, "usr_test_mms_001", "P-0101", "Flyer", "Recipient", "555-0199", "flyer.test@example.com", 1]
	}
	db.execute_transaction([p_stmt])

	var person = {
		"id": 101,
		"person_uuid": "usr_test_mms_001",
		"first_name": "Flyer",
		"last_name": "Recipient",
		"phone": "555-0199",
		"email": "flyer.test@example.com",
		"sms_consent": 1
	}

	# Test 2: SMS Image-Only (MMS)
	print("\n[TEST 2] Testing SMS Image-Only Dispatch...")
	var res_mms_only = com_service.send_message_atomic(person, "SMS Text", "", "John Smith", test_jpg_path)
	print("  res_mms_only: ", res_mms_only)
	assert(res_mms_only.get("success", false) == true, "SMS Image-Only should succeed: " + str(res_mms_only))
	var msg_uuid1 = res_mms_only.get("message_uuid", "")
	var log_res1 = db.execute("SELECT attachment_path, message_body, provider_sid FROM communications_log WHERE message_uuid = ? LIMIT 1;", [msg_uuid1])
	assert(log_res1["success"] and log_res1["data"].size() > 0, "Log entry should exist")
	assert(log_res1["data"][0]["attachment_path"] == test_jpg_path, "attachment_path should be persisted in log")
	assert(str(log_res1["data"][0]["provider_sid"]).begins_with("MM"), "Provider SID for MMS should begin with MM")
	print("  PASS: SMS Image-Only logged with attachment_path and MMS SID")

	# Test 3: SMS Image + Text (MMS)
	print("\n[TEST 3] Testing SMS Image + Text Dispatch...")
	var res_mms_text = com_service.send_message_atomic(person, "SMS Text", "Fall Fellowship Flyer attached!", "John Smith", test_jpg_path)
	assert(res_mms_text.get("success", false) == true, "SMS Image + Text should succeed")
	print("  PASS: SMS Image + Text dispatched successfully")

	# Test 4: Email Image-Only
	print("\n[TEST 4] Testing Email Image-Only Dispatch...")
	var res_email_only = com_service.send_message_atomic(person, "Email", "", "John Smith", test_jpg_path)
	assert(res_email_only.get("success", false) == true, "Email Image-Only should succeed")
	print("  PASS: Email Image-Only dispatched successfully")

	# Test 5: Email Image + Text
	print("\n[TEST 5] Testing Email Image + Text Dispatch...")
	var res_email_text = com_service.send_message_atomic(person, "Email", "Check out our latest event flyer!", "John Smith", test_jpg_path)
	assert(res_email_text.get("success", false) == true, "Email Image + Text should succeed")
	print("  PASS: Email Image + Text dispatched successfully")

	# Test 6: Scheduled Communication with Attachment
	print("\n[TEST 6] Testing Scheduled Communication with Attachment...")
	var sched_res = com_service.schedule_message_atomic(0, "555-0199", "SMS Text", "Scheduled Flyer Message", "2020-01-01 10:00 AM", "John Smith", test_jpg_path)
	assert(sched_res.get("success", false) == true or sched_res.get("schedule_uuid", "") != "", "Scheduling should succeed")
	var sched_uuid = sched_res.get("schedule_uuid", "")
	var s_row = db.execute("SELECT attachment_path FROM scheduled_communications WHERE schedule_uuid = ? LIMIT 1;", [sched_uuid])
	assert(s_row["success"] and s_row["data"].size() > 0, "Scheduled row should exist")
	assert(s_row["data"][0]["attachment_path"] == test_jpg_path, "Scheduled communication should save attachment_path")
	print("  PASS: Scheduled communication saved attachment_path in scheduled_communications table")

	# Test 7: Process Scheduled Communication with Attachment
	print("\n[TEST 7] Testing Processing of Scheduled Communication with Attachment...")
	var proc_res = com_service.process_scheduled_communications_atomic("test_worker")
	assert(proc_res.get("processed_count", 0) >= 1, "Scheduled communication should be processed")
	print("  PASS: Scheduled flyer communication processed and dispatched cleanly")

	# Cleanup test files
	DirAccess.remove_absolute(test_jpg_path)
	DirAccess.remove_absolute(test_txt_path)
	DirAccess.remove_absolute(db_path)

	print("\n=== ALL MMS & EMAIL ATTACHMENT TESTS PASSED SUCCESSFULLY ===")
	quit(0)
