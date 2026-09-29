extends SceneTree

const SqliteDatabase = preload("res://src/infrastructure/database/sqlite_database.gd")
const CommunicationsService = preload("res://src/domain/communications/communications_service.gd")
const TwilioGatewayService = preload("res://src/infrastructure/messaging/twilio_gateway_service.gd")

func _init() -> void:
	print("==========================================================")
	print("RUNNING MMS MEDIA UPLOAD & FAIL-CLOSED WORKFLOW TEST")
	print("==========================================================")

	var test_db_path = "user://test_mms_media_workflow.db"
	if FileAccess.file_exists(test_db_path):
		DirAccess.remove_absolute(test_db_path)

	var db = SqliteDatabase.new(test_db_path)

	# Setup tables
	db.execute("""
		CREATE TABLE IF NOT EXISTS people (
			id INTEGER PRIMARY KEY AUTOINCREMENT,
			person_uuid TEXT UNIQUE NOT NULL,
			human_id TEXT NOT NULL,
			first_name TEXT NOT NULL,
			last_name TEXT NOT NULL,
			phone TEXT,
			primary_email TEXT,
			sms_consent INTEGER DEFAULT 1,
			email_consent INTEGER DEFAULT 1,
			status TEXT DEFAULT 'active'
		);
	""")
	db.execute("""
		CREATE TABLE IF NOT EXISTS communications_log (
			id INTEGER PRIMARY KEY AUTOINCREMENT,
			message_uuid TEXT UNIQUE NOT NULL,
			recipient_person_id INTEGER,
			recipient_name TEXT NOT NULL,
			recipient_contact TEXT NOT NULL,
			channel TEXT NOT NULL DEFAULT 'SMS',
			message_body TEXT NOT NULL,
			status TEXT NOT NULL DEFAULT 'sent',
			sent_by_user TEXT NOT NULL DEFAULT 'John Smith',
			created_at TEXT NOT NULL DEFAULT (datetime('now')),
			provider_sid TEXT DEFAULT NULL,
			attachment_path TEXT DEFAULT NULL,
			status_detail TEXT DEFAULT NULL,
			scheduled_at TEXT DEFAULT NULL,
			delivery_status TEXT NOT NULL DEFAULT 'delivered',
			error_code TEXT
		);
	""")
	db.execute("""
		CREATE TABLE IF NOT EXISTS event_outbox (
			id INTEGER PRIMARY KEY AUTOINCREMENT,
			event_uuid TEXT UNIQUE NOT NULL,
			event_type TEXT NOT NULL,
			aggregate_type TEXT NOT NULL,
			aggregate_id TEXT NOT NULL,
			payload_json TEXT NOT NULL,
			device_uuid TEXT NOT NULL,
			status TEXT NOT NULL DEFAULT 'pending',
			created_at TEXT NOT NULL DEFAULT (datetime('now'))
		);
	""")

	# Insert test person
	db.execute("INSERT INTO people (person_uuid, human_id, first_name, last_name, phone, primary_email) VALUES ('p_001', 'H1001', 'Test', 'Person', '8649344080', 'test@example.org');")

	var comms = CommunicationsService.new(db)
	var twilio = comms.twilio_service

	var root_node = Node.new()
	root.add_child(root_node)

	# Create temporary test image
	var test_img_path = "user://test_sample_image.png"
	var f_img = FileAccess.open(test_img_path, FileAccess.WRITE)
	# 1x1 PNG pixel bytes
	var png_bytes = PackedByteArray([
		0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
		0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
		0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
		0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
		0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41,
		0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
		0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00,
		0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,
		0x42, 0x60, 0x82
	])
	f_img.store_buffer(png_bytes)
	f_img.close()

	print("✅ Test 1: Local test image created at ", test_img_path, " (Size: ", png_bytes.size(), " bytes)")

	var person = {"id": 1, "person_uuid": "p_001", "first_name": "Test", "last_name": "Person", "phone": "8649344080", "sms_consent": 1}

	# Test demo async upload
	twilio.upload_mms_media_async(root_node, test_img_path, func(res: Dictionary):
		if res.get("success", false) and res.has("public_url"):
			print("✅ Test 2: upload_mms_media_async demo response successful. Public URL: ", res["public_url"])
		else:
			print("❌ Test 2 failed: ", res.get("error", "Unknown upload error"))
			quit(1)

		# Test Fail-Closed behavior when local file is missing
		twilio.upload_mms_media_async(root_node, "user://non_existent_file.png", func(fail_res: Dictionary):
			if not fail_res.get("success", false) and fail_res.get("error", "").contains("does not exist"):
				print("✅ Test 3: Fail-closed behavior verified for non-existent file.")
			else:
				print("❌ Test 3 failed: Expected error for non-existent file.")
				quit(1)

			# Test send_message_atomic with MMS attachment
			var msg_res = comms.send_message_atomic(person, "SMS Text", "Test MMS body message", "John Smith", test_img_path)
			if msg_res.get("success", false):
				print("✅ Test 4: send_message_atomic with MMS attachment processed cleanly.")
			else:
				print("❌ Test 4 failed: ", msg_res.get("error", "Failed send_message_atomic"))
				quit(1)

			# Verify log status in SQLite
			var log_res = db.execute("SELECT status, delivery_status, provider_sid, attachment_path FROM communications_log ORDER BY id DESC LIMIT 1;")
			if log_res["success"] and log_res["data"].size() > 0:
				var row = log_res["data"][0]
				var d_stat = str(row.get("delivery_status", ""))
				if d_stat == "submitted" or d_stat == "delivered":
					print("✅ Test 5: SQLite log updated correctly. delivery_status: ", d_stat, " | SID: ", row.get("provider_sid", ""))
				else:
					print("❌ Test 5 failed: Incorrect delivery status ", d_stat)
					quit(1)

			print("\n🎉 ALL MMS MEDIA UPLOAD & FAIL-CLOSED TESTS PASSED CLEANLY!")
			quit(0)
		)
	)
