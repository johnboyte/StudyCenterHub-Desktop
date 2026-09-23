extends SceneTree

## Automated Verification Test for Multi-Message SMS Thread Drag and Status Update Fix
## Verifies that moving a consolidated SMS thread card (like McKenna Boykin's multi-message card)
## updates all messages in the thread and persists the card status across column moves and feed refreshes.

func _init() -> void:
	print("=== Starting Test: Multi-Message SMS Thread Drag & Status Update Fix ===")
	
	var SQLiteDatabase = load("res://src/infrastructure/database/sqlite_database.gd")
	var CommunicationsService = load("res://src/domain/communications/communications_service.gd")
	
	var test_db_path = "user://test_mckenna_thread_fix.db"
	var global_path = ProjectSettings.globalize_path(test_db_path)
	if FileAccess.file_exists(global_path):
		DirAccess.remove_absolute(global_path)
		
	var db = SQLiteDatabase.new(test_db_path)
	assert(db != null, "Failed to initialize SQLiteDatabase adapter.")
	
	# Apply necessary migrations / schema setup
	db.execute("""
		CREATE TABLE IF NOT EXISTS people (
			id INTEGER PRIMARY KEY AUTOINCREMENT,
			human_id TEXT,
			first_name TEXT,
			last_name TEXT,
			phone TEXT,
			status TEXT DEFAULT 'active'
		);
	""")
	
	db.execute("""
		CREATE TABLE IF NOT EXISTS voicemails (
			id INTEGER PRIMARY KEY AUTOINCREMENT,
			voicemail_uuid TEXT UNIQUE,
			caller_name TEXT,
			caller_phone TEXT,
			duration_sec INTEGER DEFAULT 0,
			recording_url TEXT,
			transcription TEXT,
			status TEXT DEFAULT 'new',
			priority TEXT DEFAULT 'Medium',
			due_date TEXT,
			internal_notes TEXT,
			created_at TEXT DEFAULT (datetime('now')),
			assigned_person_id INTEGER,
			recording_sid TEXT,
			call_sid TEXT
		);
	""")
	
	db.execute("""
		CREATE TABLE IF NOT EXISTS inbound_sms_log (
			id INTEGER PRIMARY KEY AUTOINCREMENT,
			message_sid TEXT,
			from_phone_e164 TEXT,
			to_phone_e164 TEXT,
			raw_body TEXT,
			follow_up_status TEXT DEFAULT 'new',
			follow_up_updated_at TEXT,
			assigned_to TEXT,
			notes TEXT,
			is_read INTEGER DEFAULT 0,
			received_at TEXT DEFAULT (datetime('now')),
			matched_person_id INTEGER
		);
	""")
	
	db.execute("""
		CREATE TABLE IF NOT EXISTS event_outbox (
			id INTEGER PRIMARY KEY AUTOINCREMENT,
			event_uuid TEXT UNIQUE,
			event_type TEXT,
			aggregate_type TEXT,
			aggregate_id TEXT,
			payload_json TEXT,
			device_uuid TEXT,
			status TEXT DEFAULT 'pending',
			created_at TEXT DEFAULT (datetime('now'))
		);
	""")
	
	# Insert Person record for McKenna Boykin
	db.execute("INSERT INTO people (id, human_id, first_name, last_name, phone) VALUES (9, 'P-0009', 'McKenna', 'Boykin', '+17073656637');")
	
	# Insert 2 inbound SMS records for McKenna with DIFFERENT initial follow_up_status values!
	# Record 1: follow_up_status = 'new'
	# Record 2: follow_up_status = 'in_progress'
	db.execute("""
		INSERT INTO inbound_sms_log (id, message_sid, from_phone_e164, to_phone_e164, raw_body, follow_up_status, received_at, matched_person_id)
		VALUES (1, 'MM50bffd342c997894a9ef8ac7d283f985', '+17073656637', '+18647124446', 'Message 1 from McKenna', 'new', '2026-09-15 22:49:10', 9);
	""")
	db.execute("""
		INSERT INTO inbound_sms_log (id, message_sid, from_phone_e164, to_phone_e164, raw_body, follow_up_status, received_at, matched_person_id)
		VALUES (2, 'SMb2bd7ab1c8c9739acd282867c752a14f', '+17073656637', '+18647124446', 'Message 2 from McKenna', 'in_progress', '2026-09-15 22:50:31', 9);
	""")

	var com_service = CommunicationsService.new(db)
	
	# 1. Initial State Check
	print("--- Step 1: Initial Card State ---")
	var initial_cards = com_service.get_voicemails()
	assert(initial_cards.size() == 1, "Expected exactly 1 consolidated thread card for McKenna.")
	var card = initial_cards[0]
	print("Initial card status:", card.get("status"))
	print("Initial item_uuid:", card.get("item_uuid"))
	# Because Record 1 is 'new', status evaluates to 'new' initially
	assert(card.get("status") == "new", "Initial card status should be 'new' due to message 1.")
	
	# 2. Simulate Drag Move to 'in_progress'
	print("--- Step 2: Drag Card to 'in_progress' ---")
	var target_uuid = str(card.get("item_uuid"))
	var update_res = com_service.update_voicemail_workflow(target_uuid, null, "in_progress", "Medium", "", "", "sms")
	assert(update_res.get("success", false), "Workflow update query failed.")
	
	# Verify that BOTH records in inbound_sms_log were updated!
	var db_check1 = db.execute("SELECT id, follow_up_status FROM inbound_sms_log WHERE from_phone_e164 = '+17073656637';")
	assert(db_check1["success"] and db_check1["data"].size() == 2, "DB check failed.")
	for r in db_check1["data"]:
		print("Row ID", r["id"], "follow_up_status:", r["follow_up_status"])
		assert(str(r["follow_up_status"]) == "in_progress", "All rows in thread must be 'in_progress'.")
		
	# Re-fetch cards to simulate feed refresh (_refresh_all_feeds)
	var refreshed_cards1 = com_service.get_voicemails()
	assert(refreshed_cards1.size() == 1, "Expected 1 card after refresh.")
	print("Refreshed card status:", refreshed_cards1[0].get("status"))
	assert(refreshed_cards1[0].get("status") == "in_progress", "Card MUST remain in 'in_progress' after refresh!")

	# 3. Simulate Drag Move to 'completed'
	print("--- Step 3: Drag Card to 'completed' ---")
	var update_res2 = com_service.update_voicemail_workflow(target_uuid, null, "completed", "Medium", "", "", "sms")
	assert(update_res2.get("success", false), "Workflow update to completed failed.")
	
	var db_check2 = db.execute("SELECT id, follow_up_status FROM inbound_sms_log WHERE from_phone_e164 = '+17073656637';")
	for r in db_check2["data"]:
		print("Row ID", r["id"], "follow_up_status:", r["follow_up_status"])
		assert(str(r["follow_up_status"]) == "completed", "All rows in thread must be 'completed'.")
		
	var refreshed_cards2 = com_service.get_voicemails()
	print("Refreshed card status:", refreshed_cards2[0].get("status"))
	assert(refreshed_cards2[0].get("status") == "completed", "Card MUST remain in 'completed' after refresh!")
	
	print("\n✅ SUCCESS: All tests passed! McKenna's multi-message SMS thread card moves freely and persists status across column moves and feed refreshes.")
	
	quit(0)
