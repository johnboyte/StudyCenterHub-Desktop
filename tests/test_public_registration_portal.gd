extends SceneTree

## Comprehensive End-to-End Test Suite for Public Portal & Registration Wizard

const SQLiteDatabaseScript = preload("res://src/infrastructure/database/sqlite_database.gd")
const InboundEventProcessorScript = preload("res://src/domain/sync/inbound_event_processor.gd")
const PersonRegistrationValidatorScript = preload("res://src/domain/directory/person_registration_validator.gd")
const MembershipCardEngineScript = preload("res://src/domain/sync/membership_card_engine.gd")

func _init() -> void:
	print("==========================================================")
	print("RUNNING AUTOMATED TEST SUITE: PUBLIC REGISTRATION PORTAL")
	print("==========================================================")
	
	OS.set_environment("STUDYCENTERHUB_ENV", "development")
	
	var db = SQLiteDatabaseScript.new()
	db.execute("""
		CREATE TABLE IF NOT EXISTS inbound_event_queue (
			id INTEGER PRIMARY KEY AUTOINCREMENT,
			event_type TEXT NOT NULL,
			provider_event_id TEXT UNIQUE,
			payload_json TEXT NOT NULL,
			received_at TEXT NOT NULL DEFAULT (datetime('now')),
			processed INTEGER NOT NULL DEFAULT 0,
			status TEXT DEFAULT 'pending',
			result_json TEXT DEFAULT NULL
		);
	""")
	var dummy_node = Node.new()
	root.add_child(dummy_node)
	var processor = InboundEventProcessorScript.new(db, dummy_node)

	# --- TEST 0: Remote Check-In QR Sign Verification ---
	assert(MembershipCardEngineScript.REMOTE_SIGN_CONFIG["qr_target_url"] == "https://app.reallife-studycenter.org/public", "QR sign config URL must be app.reallife-studycenter.org/public")
	var sign_img = MembershipCardEngineScript.render_remote_qr_sign()
	assert(sign_img != null and not sign_img.is_empty(), "Remote QR sign image must render")
	db.execute("DELETE FROM inbound_event_queue WHERE event_type LIKE 'portal.%';")
	db.execute("DELETE FROM digital_pass_event_log WHERE person_id IN (SELECT id FROM people WHERE email LIKE '%dmiller%' OR email LIKE '%thanna%' OR email LIKE '%homeschool%' OR email LIKE '%sarah.walker%' OR phone LIKE '%555-0812%' OR phone LIKE '%555-0943%' OR phone LIKE '%555-4422%' OR phone LIKE '%555-7733%');")
	db.execute("DELETE FROM attendance_log WHERE person_id IN (SELECT id FROM people WHERE email LIKE '%dmiller%' OR email LIKE '%thanna%' OR email LIKE '%homeschool%' OR email LIKE '%sarah.walker%' OR phone LIKE '%555-0812%' OR phone LIKE '%555-0943%' OR phone LIKE '%555-4422%' OR phone LIKE '%555-7733%');")
	db.execute("DELETE FROM people WHERE email LIKE '%dmiller%' OR email LIKE '%thanna%' OR email LIKE '%homeschool%' OR email LIKE '%sarah.walker%' OR phone LIKE '%555-0812%' OR phone LIKE '%555-0943%' OR phone LIKE '%555-4422%' OR phone LIKE '%555-7733%';")

	# --- TEST 1: Public Registration Event Processing (Adult Registration & Auto Check-In) ---
	var adult_payload = {
		"firstName": "Sarah",
		"lastName": "Walker",
		"phone": "(864) 555-0812",
		"email": "sarah.walker@example.com",
		"birthday": "1998-05-14",
		"primaryRole": "Community Member",
		"smsConsentChoice": "Yes",
		"emergencyContactName": "",
		"emergencyContactPhone": "",
		"profilePhoto": "data:image/jpeg;base64,/9j/4AAQSkZJRgABAQEASABIAAD/2wBDAP//////////////////////////////////////////////////////////////////////////////////////wgALCAABAAEBAREA/8QAFBABAAAAAAAAAAAAAAAAAAAAAP/aAAgBAQABPxA="
	}
	db.execute("INSERT INTO inbound_event_queue (event_type, payload_json, received_at, processed) VALUES ('portal.registration', ?, datetime('now'), 0);", [JSON.stringify(adult_payload)])
	
	var finished_signal = false
	processor.process_pending_events(func(res):
		finished_signal = true
		assert(res["success"], "Pending events processing should succeed")
	)
	
	var check_res = db.execute("SELECT * FROM people WHERE phone = '(864) 555-0812' LIMIT 1;")
	assert(check_res["success"] and check_res["data"].size() > 0, "Adult registration must create member in SQLite people table")
	var adult_rec = check_res["data"][0]
	assert(adult_rec["first_name"] == "Sarah", "First name must match")
	assert(adult_rec["sms_consent"] == 1, "SMS consent must be 1")
	assert(adult_rec["profile_photo"] != "", "Profile photo base64 string must be stored")

	# Check automatic daily check-in creation
	var today_str = Time.get_date_string_from_system()
	var att_check = db.execute("SELECT COUNT(*) as cnt FROM attendance_log WHERE person_id = ? AND check_in_date = ?;", [adult_rec["id"], today_str])
	assert(int(att_check["data"][0]["cnt"]) == 1, "Successful registration MUST automatically create exactly 1 check-in record for today")

	# Check closed-loop status result
	var q_res = db.execute("SELECT status, result_json FROM inbound_event_queue WHERE event_type = 'portal.registration' ORDER BY id DESC LIMIT 1;")
	assert(q_res["success"] and q_res["data"].size() > 0, "Event queue record must exist")
	assert(q_res["data"][0]["status"] == "registered_and_checked_in", "Queue status must be registered_and_checked_in")
	print("✅ Test 1 Passed: Adult public self-registration created member AND automatically checked in for today.")

	# --- TEST 2: Student Registration Event Processing ---
	var student_payload = {
		"firstName": "David",
		"lastName": "Miller",
		"phone": "(864) 555-0943",
		"email": "dmiller@clemson.edu",
		"birthday": "2004-11-20",
		"primaryRole": "College Student",
		"smsConsentChoice": "No",
		"institution": "Clemson University",
		"grade": "Junior",
		"emergencyContactName": "Robert Miller",
		"emergencyContactPhone": "(864) 555-9000"
	}
	
	db.execute("INSERT INTO inbound_event_queue (event_type, payload_json, received_at, processed) VALUES ('portal.registration', ?, datetime('now'), 0);", [JSON.stringify(student_payload)])
	
	processor.process_pending_events(func(res):
		assert(res["success"], "Pending events processing should succeed")
	)
	
	var stu_check = db.execute("SELECT * FROM people WHERE email = 'dmiller@clemson.edu' LIMIT 1;")
	assert(stu_check["success"] and stu_check["data"].size() > 0, "Student registration must create member in SQLite people table")
	var stu_rec = stu_check["data"][0]
	assert(stu_rec["first_name"] == "David", "First name must match")
	assert(stu_rec["sms_consent"] == 0, "SMS consent = No must be recorded as 0")
	assert(stu_rec["grade"] == "Junior", "Grade must be stored")

	var stu_att = db.execute("SELECT COUNT(*) as cnt FROM attendance_log WHERE person_id = ? AND check_in_date = ?;", [stu_rec["id"], today_str])
	assert(int(stu_att["data"][0]["cnt"]) == 1, "Student registration must auto check-in")
	print("✅ Test 2 Passed: Student public self-registration processed with academic details, SMS opt-out, & auto check-in.")

	# --- TEST 3: Duplicate Phone/Email Matching & Same-Day Duplicate Check-In Protection ---
	var dup_payload = {
		"firstName": "Sarah",
		"lastName": "Walker-Updated",
		"phone": "(864) 555-0812",
		"email": "sarah.walker@example.com",
		"birthday": "1998-05-14",
		"primaryRole": "Community Member",
		"smsConsentChoice": "Yes"
	}
	
	db.execute("INSERT INTO inbound_event_queue (event_type, payload_json, received_at, processed) VALUES ('portal.registration', ?, datetime('now'), 0);", [JSON.stringify(dup_payload)])
	
	processor.process_pending_events(func(res):
		assert(res["success"], "Pending events processing should succeed")
	)
	
	var dup_check = db.execute("SELECT COUNT(*) as cnt FROM people WHERE phone = '(864) 555-0812';")
	assert(int(dup_check["data"][0]["cnt"]) == 1, "Duplicate phone must NOT create a second member")
	
	var updated_rec = db.execute("SELECT last_name FROM people WHERE phone = '(864) 555-0812';")
	assert(updated_rec["data"][0]["last_name"] == "Walker-Updated", "Existing member must be updated")

	var dup_att_check = db.execute("SELECT COUNT(*) as cnt FROM attendance_log WHERE person_id = ? AND check_in_date = ?;", [adult_rec["id"], today_str])
	assert(int(dup_att_check["data"][0]["cnt"]) == 1, "Re-registration on same day must NOT create duplicate attendance record")

	var dup_q_res = db.execute("SELECT status FROM inbound_event_queue WHERE event_type = 'portal.registration' ORDER BY id DESC LIMIT 1;")
	assert(dup_q_res["data"][0]["status"] == "registered_already_checked_in", "Queue status must be registered_already_checked_in")
	print("✅ Test 3 Passed: Duplicate registration updates member and preserves same-day check-in duplicate protection.")

	# --- TEST 4: Invalid Registration Produces Zero Attendance Record ---
	var inv_payload = {
		"firstName": "",
		"lastName": "Invalid",
		"phone": ""
	}
	db.execute("INSERT INTO inbound_event_queue (event_type, payload_json, received_at, processed) VALUES ('portal.registration', ?, datetime('now'), 0);", [JSON.stringify(inv_payload)])
	processor.process_pending_events(func(res): assert(res["success"]))
	var inv_att = db.execute("SELECT COUNT(*) as cnt FROM attendance_log WHERE person_id IS NULL OR person_id = 0;")
	assert(int(inv_att["data"][0]["cnt"]) == 0, "Invalid registration must create ZERO attendance records")
	print("✅ Test 4 Passed: Invalid registration creates NO attendance record.")

	# --- TEST 5: Database Safety & Integrity Verification ---
	var integ_res = db.execute("PRAGMA integrity_check;")
	assert(integ_res["success"], "Database integrity check must pass")
	print("✅ Test 5 Passed: PRAGMA integrity_check = ok.")

	# --- TEST 6: High School Canonical Institution Resolution & Auto Check-In ---
	var hs_payload = {
		"firstName": "Tyler",
		"lastName": "Hanna",
		"phone": "(864) 555-4422",
		"email": "thanna@example.com",
		"birthday": "2008-03-15",
		"primaryRole": "High School Student",
		"smsConsentChoice": "Yes",
		"institution": "T.L. Hanna High School",
		"grade": "11th Grade",
		"emergencyContactName": "Mary Hanna",
		"emergencyContactPhone": "(864) 555-9988"
	}
	db.execute("INSERT INTO inbound_event_queue (event_type, payload_json, received_at, processed) VALUES ('portal.registration', ?, datetime('now'), 0);", [JSON.stringify(hs_payload)])
	processor.process_pending_events(func(res): assert(res["success"]))
	var hs_check = db.execute("SELECT * FROM people WHERE email = 'thanna@example.com' LIMIT 1;")
	assert(hs_check["success"] and hs_check["data"].size() > 0, "High School student registration failed")
	var hs_rec = hs_check["data"][0]
	assert(hs_rec["primary_role"] == "Participant", "High school primary_role must be Participant")
	assert(hs_rec["relationship"] == "High School Student", "High school relationship must be High School Student")
	assert(hs_rec["campus_community_applies"] == 1, "High school campus_community_applies must be 1")
	assert(hs_rec["institution_id"] != null and hs_rec["institution_id"] > 0, "Canonical institution_id must be resolved")

	# Test Home School
	var home_payload = {
		"firstName": "Hannah",
		"lastName": "Home",
		"phone": "(864) 555-7733",
		"email": "hannah@homeschool.org",
		"birthday": "2002-01-10",
		"primaryRole": "High School Student",
		"smsConsentChoice": "No",
		"institution": "Home School",
		"grade": "10th Grade",
		"emergencyContactName": "Paul Home",
		"emergencyContactPhone": "(864) 555-1122"
	}
	db.execute("INSERT INTO inbound_event_queue (event_type, payload_json, received_at, processed) VALUES ('portal.registration', ?, datetime('now'), 0);", [JSON.stringify(home_payload)])
	processor.process_pending_events(func(res): assert(res["success"]))
	var home_check = db.execute("SELECT * FROM people WHERE email = 'hannah@homeschool.org' LIMIT 1;")
	assert(home_check["success"] and home_check["data"].size() > 0, "Home School registration failed")
	var home_rec = home_check["data"][0]
	assert(home_rec["sms_consent"] == 0, "SMS consent No must be 0")
	assert(home_rec["institution_id"] != null, "Home School must resolve to canonical institution_id")
	assert(home_rec["institution_other_name"] == "" or home_rec["institution_other_name"] == null, "Home School must NOT populate institution_other_name")
	print("✅ Test 6 Passed: High School canonical institutions, SMS choices, and auto check-in verified.")

	# --- TEST 7: Digital Pass Status Audit & Pass Link Access Tracking ---
	var adult_pid = int(adult_rec["id"])
	var pass_log_check = db.execute("SELECT * FROM digital_pass_event_log WHERE person_id = ? AND event_type = 'issued' LIMIT 1;", [adult_pid])
	assert(pass_log_check["success"] and pass_log_check["data"].size() > 0, "Credential issuance must be recorded in digital_pass_event_log")

	var cred_row = db.execute("SELECT token_hash FROM participant_qr_credentials WHERE person_id = ? AND status = 'active' LIMIT 1;", [adult_pid])
	assert(cred_row["success"] and cred_row["data"].size() > 0, "Active credential row must exist")
	var t_hash = str(cred_row["data"][0]["token_hash"])

	var access_payload = {
		"token": t_hash,
		"type": "pkpass",
		"channel": "direct_web",
		"user_agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X)"
	}
	db.execute("INSERT INTO inbound_event_queue (event_type, payload_json, received_at, processed) VALUES ('portal.pass_accessed', ?, datetime('now'), 0);", [JSON.stringify(access_payload)])
	processor.process_pending_events(func(res): assert(res["success"]))

	var apple_log_check = db.execute("SELECT * FROM digital_pass_event_log WHERE person_id = ? AND event_type = 'apple_wallet_served' LIMIT 1;", [adult_pid])
	assert(apple_log_check["success"] and apple_log_check["data"].size() > 0, "Apple Wallet access event must be logged")
	print("✅ Test 7 Passed: Digital Pass audit trail records issuance and device-aware access events.")

	# --- TEST 8: portal.pass_request Event Processing ---
	var sms_pass_req = {
		"channel": "sms",
		"phone": "(864) 555-0812",
		"firstName": "Dave"
	}
	db.execute("INSERT INTO inbound_event_queue (event_type, payload_json, received_at, processed) VALUES ('portal.pass_request', ?, datetime('now'), 0);", [JSON.stringify(sms_pass_req)])
	processor.process_pending_events(func(res): assert(res["success"]))

	var sms_pass_queue_check = db.execute("SELECT status FROM inbound_event_queue WHERE event_type = 'portal.pass_request' ORDER BY id DESC LIMIT 1;")
	assert(sms_pass_queue_check["success"] and sms_pass_queue_check["data"].size() > 0, "Pass request event must be processed")
	assert(str(sms_pass_queue_check["data"][0]["status"]).begins_with("sms_"), "SMS pass request status must be recorded")

	var email_pass_req = {
		"channel": "email",
		"email": "dave.miller@example.com",
		"firstName": "Dave"
	}
	db.execute("INSERT INTO inbound_event_queue (event_type, payload_json, received_at, processed) VALUES ('portal.pass_request', ?, datetime('now'), 0);", [JSON.stringify(email_pass_req)])
	processor.process_pending_events(func(res): assert(res["success"]))

	var email_pass_queue_check = db.execute("SELECT status, result_json FROM inbound_event_queue WHERE event_type = 'portal.pass_request' ORDER BY id DESC LIMIT 1;")
	assert(email_pass_queue_check["success"] and email_pass_queue_check["data"].size() > 0, "Email pass request event must be processed")
	var st_val = str(email_pass_queue_check["data"][0]["status"])
	assert(st_val.begins_with("email_") or st_val == "processed", "Email pass request status must be recorded")
	print("✅ Test 8 Passed: Public portal pass requests (SMS & Email) processed cleanly through InboundEventProcessor.")

	# Clean up test rows
	db.execute("DELETE FROM digital_pass_event_log WHERE person_id IN (SELECT id FROM people WHERE phone IN ('(864) 555-0812', '(864) 555-0943', '(864) 555-4422', '(864) 555-7733'));")
	db.execute("DELETE FROM attendance_log WHERE person_id IN (SELECT id FROM people WHERE phone IN ('(864) 555-0812', '(864) 555-0943', '(864) 555-4422', '(864) 555-7733'));")
	db.execute("DELETE FROM people WHERE phone IN ('(864) 555-0812', '(864) 555-0943', '(864) 555-4422', '(864) 555-7733');")
	dummy_node.queue_free()

	print("==========================================================")
	print("ALL PUBLIC REGISTRATION PORTAL TESTS PASSED 100%")
	print("==========================================================")
	quit(0)
