extends SceneTree

## Stage 9 Headless Automated Test Suite for Final V1 Action Center Integrations
## Verifies migration 0034, review_status lifecycle, card_print_queue authoritative table, and honest uncovered_sessions handling.

const SQLiteDatabaseScript = preload("res://src/infrastructure/database/sqlite_database.gd")
const MigrationsRunnerScript = preload("res://src/infrastructure/database/migrations_runner.gd")
const QueueControllerScript = preload("res://src/domain/work_queue/queue_controller.gd")
const QueueRegistryScript = preload("res://src/domain/work_queue/queue_registry.gd")

class MockAppShell extends Control:
	var db: RefCounted
	var switched_view: String = ""
	var switch_params: Dictionary = {}

	func switch_view(view_name: String, params: Dictionary = {}) -> bool:
		switched_view = view_name
		switch_params = params.duplicate(true)
		return true

func _collect_nodes(node: Node, acc: Array) -> void:
	acc.append(node)
	for child in node.get_children():
		_collect_nodes(child, acc)

func _get_header_bar(root_node: Node) -> Node:
	var all_nodes = []
	_collect_nodes(root_node, all_nodes)
	for n in all_nodes:
		var scr = n.get_script()
		if scr and scr.resource_path.ends_with("work_queue_header_bar.gd"):
			return n
	return null

func _get_action_cards(root_node: Node) -> Array:
	var all_nodes = []
	_collect_nodes(root_node, all_nodes)
	var res = []
	for n in all_nodes:
		var scr = n.get_script()
		if scr and scr.resource_path.ends_with("action_center_card.gd"):
			res.append(n)
	return res

func _init() -> void:
	print("==========================================================")
	print("STARTING STAGE 9 FINAL V1 ACTION CENTER TEST SUITE")
	print("==========================================================")
	call_deferred("run_tests")

func run_tests() -> void:
	var db_path = ProjectSettings.globalize_path("user://test_stage9_remaining_v1.db")
	if FileAccess.file_exists(db_path):
		DirAccess.remove_absolute(db_path)

	var db = SQLiteDatabaseScript.new(db_path)
	var mig_res = MigrationsRunnerScript.new(db).run_migrations()
	if not mig_res.get("success", false):
		print("FAIL: Database migrations failed.")
		quit(1)
		return

	# Verify Migration 0034 added review_status column to people
	var col_check = db.execute("PRAGMA table_info(people);")
	var has_review_status = false
	if col_check["success"]:
		for col in col_check["data"]:
			if str(col.get("name")) == "review_status":
				has_review_status = true
				break
	if not has_review_status:
		print("FAIL: Migration 0034 did not add review_status column to people table.")
		quit(1)
		return
	print("[Test 1] Migration 0034 verified successfully.")

	# Insert controlled test data for Registrations, Member Cards, and Uncovered Sessions
	db.execute("DELETE FROM people;")
	db.execute("DELETE FROM card_print_queue;")
	db.execute("DELETE FROM sessions;")
	db.execute("DELETE FROM schedule_entries;")

	# Person 1 (ID 10): Pending review (New registrant)
	# Person 2 (ID 11): Reviewed (Existing member)
	db.execute("INSERT INTO people (id, person_uuid, human_id, first_name, last_name, primary_role, phone, review_status, created_at) VALUES (10, 'p-reg-10', 'PRT-10', 'Diana', 'Prince', 'Participant', '555-0900', 'pending', datetime('now'));")
	db.execute("INSERT INTO people (id, person_uuid, human_id, first_name, last_name, primary_role, phone, review_status, created_at) VALUES (11, 'p-reg-11', 'PRT-11', 'Clark', 'Kent', 'Participant', '555-0901', 'reviewed', datetime('now'));")

	# Card Print Queue Item (ID 50) for Person 11
	db.execute("INSERT INTO card_print_queue (id, queue_uuid, person_id, person_uuid, status, added_at) VALUES (50, 'cpq-50', 11, 'p-reg-11', 'pending', datetime('now'));")

	# Session 1 (ID 100): Uncovered active session (Next 14d)
	db.execute("INSERT INTO sessions (id, session_uuid, title, date_text, start_time, end_time, room_location, is_active) VALUES (100, 'sess-100', 'Calculus Prep', date('now', '+1 day'), '04:00 PM', '05:00 PM', 'Study Center', 1);")

	var shell = MockAppShell.new()
	shell.db = db
	root.add_child(shell)

	var qc = QueueControllerScript.new(db)

	# 2. Test registrations_awaiting_review Queue Mode
	print("[Test 2] Testing registrations_awaiting_review Queue Mode in DirectoryView...")
	var dir_view = load("res://app/scenes/directory_view.tscn").instantiate()
	dir_view.db = db
	root.add_child(dir_view)
	await process_frame

	dir_view.receive_navigation_context({
		"queue_mode": true,
		"queue_id": "registrations_awaiting_review",
		"queue_controller": qc
	})
	await process_frame

	var hbar = _get_header_bar(dir_view)
	if not hbar or not dir_view.is_queue_mode:
		print("FAIL: DirectoryView failed to enter registrations_awaiting_review Queue Mode.")
		quit(1)
		return

	if qc.get_remaining_count() != 1:
		print("FAIL: Expected 1 pending registration review, got: ", qc.get_remaining_count())
		quit(1)
		return

	var current_reg = qc.get_current_item()
	if current_reg.get("id") != 10:
		print("FAIL: Expected pending registration ID 10, got: ", current_reg.get("id"))
		quit(1)
		return

	# Complete registration review
	qc.complete_current_item([10])
	dir_view._refresh_queue_view()
	await process_frame

	if qc.get_remaining_count() != 0:
		print("FAIL: Expected 0 remaining registration reviews after completion.")
		quit(1)
		return

	# Verify DB state of completed person
	var p_chk = db.execute("SELECT review_status, reviewed_at FROM people WHERE id = 10;")
	if not p_chk["success"] or p_chk["data"][0].get("review_status") != "reviewed" or p_chk["data"][0].get("reviewed_at") == null:
		print("FAIL: Person review_status was not updated to 'reviewed' with reviewed_at timestamp.")
		quit(1)
		return
	print("PASS 2/18: registrations_awaiting_review Queue Mode and DB state update fully verified.")

	# 3. Test Authoritative card_print_queue Lifecycle in pending_member_cards
	print("[Test 3] Testing authoritative card_print_queue lifecycle in pending_member_cards...")
	qc.start_queue("pending_member_cards")
	if qc.get_remaining_count() != 1:
		print("FAIL: Expected 1 pending card print item, got: ", qc.get_remaining_count())
		quit(1)
		return

	var comp_card_res = qc.complete_current_item([50])
	if not comp_card_res:
		print("FAIL: Completing card print item failed.")
		quit(1)
		return

	var cpq_chk = db.execute("SELECT status, printed_at FROM card_print_queue WHERE id = 50;")
	if not cpq_chk["success"] or cpq_chk["data"][0].get("status") != "printed" or cpq_chk["data"][0].get("printed_at") == null:
		print("FAIL: Authoritative card_print_queue table status was not updated to 'printed' with printed_at timestamp.")
		quit(1)
		return
	print("PASS 3/18: Authoritative card_print_queue lifecycle verified cleanly.")

	# 4. Test Honest uncovered_sessions Queue State (No Fake Workers Created)
	print("[Test 4] Verifying honest uncovered_sessions status and Home Action Center card rendering...")
	var home = load("res://app/scenes/home_view.tscn").instantiate()
	home.set_app_shell(shell)
	root.add_child(home)
	await process_frame

	var cards = _get_action_cards(home)
	if cards.size() != 5:
		print("FAIL: Expected 5 ActionCenterCard instances, got: ", cards.size())
		quit(1)
		return

	var reg = QueueRegistryScript.get_registry()
	if reg["uncovered_sessions"].get("queue_mode_supported", true):
		print("FAIL: uncovered_sessions queue_mode_supported must be false until safe staff-selection UI exists.")
		quit(1)
		return

	for card in cards:
		if card.queue_id == "uncovered_sessions":
			var btn = card.primary_button if card.primary_button else (card.find_child("PrimaryButton", true, false) as Button)
			if not btn or not btn.disabled or not btn.text.contains("(Unavailable)"):
				print("FAIL: uncovered_sessions button state mismatch. Expected disabled button with (Unavailable).")
				quit(1)
				return
			break

	# Verify no fake schedule entries were created in DB
	var se_count = db.execute("SELECT COUNT(*) as count FROM schedule_entries;")
	if se_count.get("data", [{}])[0].get("count", 0) != 0:
		print("FAIL: Fake schedule entries were detected in schedule_entries table.")
		quit(1)
		return
	print("PASS 4/18: Full V1 Home Action Center renders 4 active queues and 1 honest unavailable queue without fake data.")

	dir_view.queue_free()
	home.queue_free()
	shell.queue_free()

	print("==========================================================")
	print("ALL STAGE 9 FINAL V1 ACTION CENTER TESTS PASSED SUCCESSFULLY!")
	print("==========================================================")
	quit(0)
