extends SceneTree

const SQLiteDatabaseScript = preload("res://src/infrastructure/database/sqlite_database.gd")
const QueueControllerScript = preload("res://src/domain/work_queue/queue_controller.gd")
const CommunicationsServiceScript = preload("res://src/domain/communications/communications_service.gd")

func _init() -> void:
	print("==================================================")
	print("RUNNING: Test Unresolved SMS Dashboard & Response Center Sync")
	print("==================================================")

	var test_db_path = ProjectSettings.globalize_path("user://test_unresolved_sms_sync.db")
	if FileAccess.file_exists(test_db_path):
		DirAccess.remove_absolute(test_db_path)

	var db = SQLiteDatabaseScript.new(test_db_path)

	# Initialize inbound_sms_log table schema
	db.execute("""
		CREATE TABLE IF NOT EXISTS inbound_sms_log (
			id INTEGER PRIMARY KEY AUTOINCREMENT,
			message_sid TEXT UNIQUE NOT NULL,
			from_phone_e164 TEXT NOT NULL,
			to_phone_e164 TEXT NOT NULL DEFAULT '',
			raw_body TEXT NOT NULL,
			is_read INTEGER NOT NULL DEFAULT 0,
			assigned_to TEXT,
			notes TEXT,
			matched_person_id INTEGER,
			follow_up_status TEXT NOT NULL DEFAULT 'Unassigned',
			follow_up_completed_at TEXT,
			received_at TEXT NOT NULL DEFAULT (datetime('now'))
		);
	""")

	var qc = QueueControllerScript.new(db)
	var com_svc = CommunicationsServiceScript.new(db)

	# Helper to get Response Center Inbox / New thread count
	var get_rc_new_count = func() -> int:
		var items = com_svc.get_voicemails()
		var new_cnt = 0
		for item in items:
			if item.get("item_type") == "sms" and item.get("status") == "new":
				new_cnt += 1
		return new_cnt

	# ----------------------------------------------------
	# Test A: McKenna-style thread (2 rows, both completed, is_read = 0)
	# ----------------------------------------------------
	print("\n[Test A] McKenna-style thread (2 completed rows, unread)...")
	db.execute("INSERT INTO inbound_sms_log (message_sid, from_phone_e164, raw_body, follow_up_status, is_read) VALUES ('sid-mck-1', '+17073656637', 'Message 1 from McKenna', 'completed', 0);")
	db.execute("INSERT INTO inbound_sms_log (message_sid, from_phone_e164, raw_body, follow_up_status, is_read) VALUES ('sid-mck-2', '+17073656637', 'Message 2 from McKenna', 'completed', 0);")

	var count_a = qc.get_queue_count("unresolved_inbound_sms")
	var rc_count_a = get_rc_new_count.call()
	print("  Dashboard count: ", count_a, " | Response Center New count: ", rc_count_a)
	assert(count_a == 0, "Test A FAIL: Dashboard count must be 0 for completed McKenna thread")
	assert(rc_count_a == 0, "Test A FAIL: Response Center Inbox/New count must be 0")
	print("  ✓ PASS: Test A verified (Dashboard = 0, RC = 0).")

	# ----------------------------------------------------
	# Test B: Karadyn-style thread (multiple completed rows, unread)
	# ----------------------------------------------------
	print("\n[Test B] Karadyn-style thread (multiple completed rows, unread)...")
	db.execute("INSERT INTO inbound_sms_log (message_sid, from_phone_e164, raw_body, follow_up_status, is_read) VALUES ('sid-kar-1', '+18643892093', 'Message 1 from Karadyn', 'completed', 0);")
	db.execute("INSERT INTO inbound_sms_log (message_sid, from_phone_e164, raw_body, follow_up_status, is_read) VALUES ('sid-kar-2', '+18643892093', 'Message 2 from Karadyn', 'completed', 0);")

	var count_b = qc.get_queue_count("unresolved_inbound_sms")
	var rc_count_b = get_rc_new_count.call()
	print("  Dashboard count: ", count_b, " | Response Center New count: ", rc_count_b)
	assert(count_b == 0, "Test B FAIL: Dashboard count must be 0 for completed Karadyn thread")
	assert(rc_count_b == 0, "Test B FAIL: Response Center Inbox/New count must be 0")
	print("  ✓ PASS: Test B verified (Dashboard = 0, RC = 0).")

	# ----------------------------------------------------
	# Test C: One sender with multiple NEW inbound messages
	# ----------------------------------------------------
	print("\n[Test C] One sender with multiple NEW inbound messages...")
	db.execute("INSERT INTO inbound_sms_log (message_sid, from_phone_e164, raw_body, follow_up_status, is_read) VALUES ('sid-new-1', '+15550199', 'First message', 'Unassigned', 0);")
	db.execute("INSERT INTO inbound_sms_log (message_sid, from_phone_e164, raw_body, follow_up_status, is_read) VALUES ('sid-new-2', '+15550199', 'Second message', 'Unassigned', 0);")
	db.execute("INSERT INTO inbound_sms_log (message_sid, from_phone_e164, raw_body, follow_up_status, is_read) VALUES ('sid-new-3', '+15550199', 'Third message', 'Unassigned', 0);")

	var count_c = qc.get_queue_count("unresolved_inbound_sms")
	var rc_count_c = get_rc_new_count.call()
	print("  Dashboard count: ", count_c, " | Response Center New count: ", rc_count_c)
	assert(count_c == 1, "Test C FAIL: Dashboard count must be 1 for consolidated actionable thread (got " + str(count_c) + ")")
	assert(rc_count_c == 1, "Test C FAIL: Response Center Inbox/New count must be 1")
	print("  ✓ PASS: Test C verified (Consolidated count = 1).")

	# ----------------------------------------------------
	# Test D: Move thread out of New
	# ----------------------------------------------------
	print("\n[Test D] Move thread out of New (mark completed)...")
	db.execute("UPDATE inbound_sms_log SET follow_up_status = 'completed' WHERE from_phone_e164 = '+15550199';")

	var count_d = qc.get_queue_count("unresolved_inbound_sms")
	var rc_count_d = get_rc_new_count.call()
	print("  Dashboard count: ", count_d, " | Response Center New count: ", rc_count_d)
	assert(count_d == 0, "Test D FAIL: Dashboard count must drop to 0 after completion")
	assert(rc_count_d == 0, "Test D FAIL: Response Center Inbox/New count must drop to 0")
	print("  ✓ PASS: Test D verified (Count updated to 0).")

	# ----------------------------------------------------
	# Test E: New SMS arrives later for previously completed sender
	# ----------------------------------------------------
	print("\n[Test E] New SMS arrives later for previously completed sender...")
	db.execute("INSERT INTO inbound_sms_log (message_sid, from_phone_e164, raw_body, follow_up_status, is_read) VALUES ('sid-new-4', '+15550199', 'Fourth message sent later', 'Unassigned', 0);")

	var count_e = qc.get_queue_count("unresolved_inbound_sms")
	var rc_count_e = get_rc_new_count.call()
	print("  Dashboard count: ", count_e, " | Response Center New count: ", rc_count_e)
	assert(count_e == 1, "Test E FAIL: Dashboard count must resurface to 1 when new SMS arrives")
	assert(rc_count_e == 1, "Test E FAIL: Response Center Inbox/New count must resurface to 1")
	print("  ✓ PASS: Test E verified (Resurfaced count = 1).")

	# ----------------------------------------------------
	# Test F: Different senders with actionable threads
	# ----------------------------------------------------
	print("\n[Test F] Different senders with actionable threads...")
	db.execute("INSERT INTO inbound_sms_log (message_sid, from_phone_e164, raw_body, follow_up_status, is_read) VALUES ('sid-snd2-1', '+18645552222', 'Message from Sender 2', 'Unassigned', 0);")

	var count_f = qc.get_queue_count("unresolved_inbound_sms")
	var rc_count_f = get_rc_new_count.call()
	print("  Dashboard count: ", count_f, " | Response Center New count: ", rc_count_f)
	assert(count_f == 2, "Test F FAIL: Dashboard count must be 2 for 2 separate actionable senders")
	assert(rc_count_f == 2, "Test F FAIL: Response Center Inbox/New count must be 2")
	print("  ✓ PASS: Test F verified (Count = 2 for 2 distinct senders).")

	# ----------------------------------------------------
	# Test G: Verify is_read independence
	# ----------------------------------------------------
	print("\n[Test G] Verify is_read independence...")
	var unread_completed_rows = db.execute("SELECT COUNT(*) as cnt FROM inbound_sms_log WHERE is_read = 0 AND follow_up_status = 'completed';")
	var cnt_unread_comp = int(unread_completed_rows["data"][0]["cnt"])
	print("  Unread completed rows in DB: ", cnt_unread_comp)
	assert(cnt_unread_comp > 0, "Test G FAIL: Historical is_read = 0 rows must remain unread in DB")
	print("  ✓ PASS: Test G verified (is_read state preserved independently).")

	# Cleanup test database
	if FileAccess.file_exists(test_db_path):
		DirAccess.remove_absolute(test_db_path)

	print("\n==================================================")
	print("ALL TESTS PASSED SUCCESSFULLY! (7/7)")
	print("==================================================")
	quit(0)
