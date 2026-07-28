extends SceneTree

## Stage 1 Headless Test Suite for QueueRegistry and QueueController
## Verifies canonical queue registry definitions, SQL execution, item navigation, and state tracking.

const SQLiteDatabaseScript = preload("res://src/infrastructure/database/sqlite_database.gd")
const QueueRegistryScript = preload("res://src/domain/work_queue/queue_registry.gd")
const QueueControllerScript = preload("res://src/domain/work_queue/queue_controller.gd")

func _init() -> void:
	print("==========================================================")
	print("STARTING STAGE 1 WORK QUEUE CONTROLLER TEST SUITE")
	print("==========================================================")

	var db = SQLiteDatabaseScript.new("user://test_stage1_work_queue.db")

	# Seed required tables for testing
	db.execute("CREATE TABLE IF NOT EXISTS voicemails (id INTEGER PRIMARY KEY AUTOINCREMENT, voicemail_id TEXT, from_number TEXT, caller_name TEXT, message_text TEXT, due_date TEXT, status TEXT DEFAULT 'new', created_at TEXT DEFAULT (datetime('now')), updated_at TEXT);")
	db.execute("CREATE TABLE IF NOT EXISTS people (id INTEGER PRIMARY KEY AUTOINCREMENT, person_uuid TEXT, human_id TEXT, first_name TEXT, last_name TEXT, phone TEXT, email TEXT, primary_role TEXT, created_at TEXT DEFAULT (datetime('now')), updated_at TEXT);")
	db.execute("CREATE TABLE IF NOT EXISTS sessions (id INTEGER PRIMARY KEY AUTOINCREMENT, title TEXT, date_text TEXT, start_time TEXT, room_location TEXT, is_active INTEGER DEFAULT 1);")
	db.execute("CREATE TABLE IF NOT EXISTS schedule_entries (id INTEGER PRIMARY KEY AUTOINCREMENT, shift_date TEXT, shift_role TEXT, person_name TEXT, area TEXT);")
	db.execute("CREATE TABLE IF NOT EXISTS card_print_queue (id INTEGER PRIMARY KEY AUTOINCREMENT, queue_uuid TEXT, person_id INTEGER, person_uuid TEXT, status TEXT DEFAULT 'pending', added_at TEXT DEFAULT (datetime('now')), printed_at TEXT);")

	# Clear previous test data
	db.execute("DELETE FROM voicemails;")
	db.execute("DELETE FROM people;")
	db.execute("DELETE FROM sessions;")
	db.execute("DELETE FROM schedule_entries;")
	db.execute("DELETE FROM card_print_queue;")

	# 1. Verify QueueRegistry has all 5 Canonical Production V1 Queues
	var reg = QueueRegistryScript.get_registry()
	print("[Test 1] Verifying QueueRegistry contains 5 Production V1 Queues...")
	if reg.size() != 5:
		print("FAIL: Expected 5 canonical queues, got ", reg.size())
		quit(1)
		return
	
	var expected_ids = ["overdue_callbacks", "unanswered_messages", "registrations_awaiting_review", "uncovered_sessions", "pending_member_cards"]
	for qid in expected_ids:
		if not QueueRegistryScript.has_definition(qid):
			print("FAIL: Missing queue definition for ", qid)
			quit(1)
			return
	print("PASS 1/6: All 5 Production V1 queue definitions verified in QueueRegistry.")

	# 2. Seed test data for Pending Member Cards
	db.execute("INSERT INTO people (person_uuid, human_id, first_name, last_name, primary_role) VALUES ('uuid-101', 'P-101', 'John', 'Doe', 'Member');")
	var p_id = 1
	var q_p = db.execute("SELECT id FROM people WHERE human_id = 'P-101';")
	if q_p.get("success", false) and q_p.get("data", []).size() > 0:
		p_id = int(q_p["data"][0]["id"])

	db.execute("INSERT INTO card_print_queue (queue_uuid, person_id, person_uuid, status) VALUES ('cpq-001', " + str(p_id) + ", 'uuid-101', 'pending');")
	db.execute("INSERT INTO card_print_queue (queue_uuid, person_id, person_uuid, status) VALUES ('cpq-002', " + str(p_id) + ", 'uuid-101', 'pending');")

	# 3. Test QueueController Count & Record Fetching
	var controller = QueueControllerScript.new(db)
	var count = controller.get_queue_count("pending_member_cards")
	print("[Test 2] Pending Member Cards Count: ", count)
	if count != 2:
		print("FAIL: Expected count 2, got ", count)
		quit(1)
		return
	print("PASS 2/6: QueueController count query executed successfully.")

	var records = controller.fetch_queue_records("pending_member_cards")
	print("[Test 3] Fetched Records Count: ", records.size())
	if records.size() != 2 or str(records[0].get("first_name")) != "John":
		print("FAIL: Record fetch did not return joined record data accurately.")
		quit(1)
		return
	print("PASS 3/6: QueueController record query fetched joined dataset successfully.")

	# 4. Test Queue Navigation & Active State
	var started = controller.start_queue("pending_member_cards")
	if not started or controller.get_remaining_count() != 2:
		print("FAIL: start_queue failed or remaining count mismatch.")
		quit(1)
		return
	
	var current = controller.get_current_item()
	if str(current.get("queue_uuid")) != "cpq-001":
		print("FAIL: Current item index 0 mismatch.")
		quit(1)
		return
	
	var next_i = controller.next_item()
	if str(next_i.get("queue_uuid")) != "cpq-002":
		print("FAIL: Next item navigation mismatch.")
		quit(1)
		return
	
	print("PASS 4/6: Queue item navigation operates correctly.")

	# 5. Test Item Completion & Auto-Decrement
	var completed = controller.complete_current_item()
	if not completed:
		print("FAIL: complete_current_item returned false.")
		quit(1)
		return
	
	if controller.get_remaining_count() != 1:
		print("FAIL: Remaining count after completion expected 1, got ", controller.get_remaining_count())
		quit(1)
		return
	
	var new_cnt = controller.get_queue_count("pending_member_cards")
	if new_cnt != 1:
		print("FAIL: Database count after completion expected 1, got ", new_cnt)
		quit(1)
		return
	print("PASS 5/6: Item completion mutates database state and auto-decrements count.")

	# 6. Test Session Termination
	controller.end_session()
	if controller.active_queue_id != "" or controller.get_remaining_count() != 0:
		print("FAIL: end_session did not reset active session state.")
		quit(1)
		return
	print("PASS 6/6: end_session resets state cleanly.")

	print("==========================================================")
	print("ALL STAGE 1 WORK QUEUE TESTS PASSED SUCCESSFULLY!")
	print("==========================================================")
	quit(0)
