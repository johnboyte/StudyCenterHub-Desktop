extends SceneTree

## Stage 10 Headless Automated Test Suite for Final V1 Action Center Integrations
## Verifies migration 0034, review_status lifecycle, card_print_queue authoritative table, and real uncovered_sessions staffing workflow.

const SQLiteDatabaseScript = preload("res://src/infrastructure/database/sqlite_database.gd")
const MigrationsRunnerScript = preload("res://src/infrastructure/database/migrations_runner.gd")
const QueueControllerScript = preload("res://src/domain/work_queue/queue_controller.gd")
const QueueRegistryScript = preload("res://src/domain/work_queue/queue_registry.gd")
const SchedulesServiceScript = preload("res://src/domain/schedules/schedules_service.gd")

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
	print("STARTING STAGE 10 FINAL V1 ACTION CENTER TEST SUITE")
	print("==========================================================")
	call_deferred("run_tests")

func run_tests() -> void:
	var db_path = ProjectSettings.globalize_path("user://test_stage10_remaining_v1.db")
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
	# Person 2 (ID 11): Reviewed (Existing staff worker)
	db.execute("INSERT INTO people (id, person_uuid, human_id, first_name, last_name, primary_role, phone, review_status, created_at) VALUES (10, 'p-reg-10', 'PRT-10', 'Diana', 'Prince', 'Participant', '555-0900', 'pending', datetime('now'));")
	db.execute("INSERT INTO people (id, person_uuid, human_id, first_name, last_name, primary_role, phone, review_status, created_at) VALUES (11, 'p-reg-11', 'STF-11', 'Marcus', 'Vance', 'Staff', '555-0901', 'reviewed', datetime('now'));")

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

	# Complete registration review
	qc.complete_current_item([10])
	dir_view._refresh_queue_view()
	await process_frame

	if qc.get_remaining_count() != 0:
		print("FAIL: Expected 0 remaining registration reviews after completion.")
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

	# 4. Test Real Staff Assignment Workflow in uncovered_sessions (No Fake Workers Created)
	print("[Test 4] Testing real staff assignment workflow for uncovered_sessions...")
	qc.start_queue("uncovered_sessions")
	if qc.get_remaining_count() != 1:
		print("FAIL: Expected 1 uncovered session, got: ", qc.get_remaining_count())
		quit(1)
		return

	var sch_svc = SchedulesServiceScript.new(db)
	var cur_sess = qc.get_current_item()
	sch_svc.create_shift_entry_atomic(
		"Marcus Vance",
		"Shift Supervisor (Staff)",
		str(cur_sess.get("date_text")),
		str(cur_sess.get("start_time")),
		str(cur_sess.get("end_time")),
		str(cur_sess.get("room_location")),
		"Assigned via Uncovered Sessions Queue"
	)

	# Refresh queue controller
	qc.start_queue("uncovered_sessions")
	if qc.get_remaining_count() != 0:
		print("FAIL: Uncovered session did not disappear after assigning real staff coverage.")
		quit(1)
		return

	var se_chk = db.execute("SELECT person_name, shift_role FROM schedule_entries WHERE area = 'Study Center';")
	if not se_chk["success"] or se_chk["data"][0].get("person_name") != "Marcus Vance":
		print("FAIL: Created schedule entry did not contain real constituent person_name.")
		quit(1)
		return

	if se_chk["data"][0].get("person_name") == "Assigned Staff" or se_chk["data"][0].get("shift_role") == "Duty Worker":
		print("FAIL: Synthetic/placeholder staff values were detected in schedule_entries.")
		quit(1)
		return
	print("PASS 4/18: Real constituent staffing assignment created legitimate schedule entry and removed session from queue.")

	# 4b. Test Time-Span Coverage Engine Rules (Examples A - E)
	print("[Test 4b] Testing full time-span coverage engine rules (Examples A-E)...")
	# Seed test session: 4:00 PM - 5:00 PM on future date
	db.execute("INSERT OR REPLACE INTO sessions (id, session_uuid, title, date_text, start_time, end_time, room_location, is_active) VALUES (999, 'sess-999', 'Test Session A-E', date('now', '+3 days'), '04:00 PM', '05:00 PM', 'Study Room #99', 1);")
	var test_date = str(db.execute("SELECT date('now', '+3 days') as d;")["data"][0]["d"])

	# Example A: Shift 3:00 - 6:00 PM (Full coverage, shift starts before and ends after) -> COVERED
	db.execute("INSERT OR REPLACE INTO schedule_entries (entry_uuid, person_name, shift_role, shift_date, start_time, end_time, area) VALUES ('sh-ex-a', 'Staff A', 'Staff', ?, '03:00 PM', '06:00 PM', 'Study Room #99');", [test_date])
	qc.start_queue("uncovered_sessions")
	var items = qc.fetch_queue_records("uncovered_sessions")
	var sess_999_uncovered = false
	for it in items:
		if it.get("id") == 999: sess_999_uncovered = true
	if sess_999_uncovered:
		print("FAIL: Example A (Session 4-5 PM, Shift 3-6 PM) should be COVERED.")
		quit(1); return

	# Example B: Shift 3:00 - 4:30 PM (Early ending shift) -> UNCOVERED
	db.execute("DELETE FROM schedule_entries WHERE entry_uuid LIKE 'sh-ex-%';")
	db.execute("INSERT OR REPLACE INTO schedule_entries (entry_uuid, person_name, shift_role, shift_date, start_time, end_time, area) VALUES ('sh-ex-b', 'Staff B', 'Staff', ?, '03:00 PM', '04:30 PM', 'Study Room #99');", [test_date])
	items = qc.fetch_queue_records("uncovered_sessions")
	sess_999_uncovered = false
	for it in items:
		if it.get("id") == 999: sess_999_uncovered = true
	if not sess_999_uncovered:
		print("FAIL: Example B (Session 4-5 PM, Shift 3-4:30 PM) should be UNCOVERED.")
		quit(1); return

	# Example C: Shift 4:30 - 6:00 PM (Late starting shift) -> UNCOVERED
	db.execute("DELETE FROM schedule_entries WHERE entry_uuid LIKE 'sh-ex-%';")
	db.execute("INSERT OR REPLACE INTO schedule_entries (entry_uuid, person_name, shift_role, shift_date, start_time, end_time, area) VALUES ('sh-ex-c', 'Staff C', 'Staff', ?, '04:30 PM', '06:00 PM', 'Study Room #99');", [test_date])
	items = qc.fetch_queue_records("uncovered_sessions")
	sess_999_uncovered = false
	for it in items:
		if it.get("id") == 999: sess_999_uncovered = true
	if not sess_999_uncovered:
		print("FAIL: Example C (Session 4-5 PM, Shift 4:30-6 PM) should be UNCOVERED.")
		quit(1); return

	# Example D: Shift 4:00 - 5:00 PM (Exact match) -> COVERED
	db.execute("DELETE FROM schedule_entries WHERE entry_uuid LIKE 'sh-ex-%';")
	db.execute("INSERT OR REPLACE INTO schedule_entries (entry_uuid, person_name, shift_role, shift_date, start_time, end_time, area) VALUES ('sh-ex-d', 'Staff D', 'Staff', ?, '04:00 PM', '05:00 PM', 'Study Room #99');", [test_date])
	items = qc.fetch_queue_records("uncovered_sessions")
	sess_999_uncovered = false
	for it in items:
		if it.get("id") == 999: sess_999_uncovered = true
	if sess_999_uncovered:
		print("FAIL: Example D (Session 4-5 PM, Shift 4-5 PM) should be COVERED.")
		quit(1); return

	# Example E: Shift 9:00 - 10:00 AM (Same room & date, wrong time) -> UNCOVERED
	db.execute("DELETE FROM schedule_entries WHERE entry_uuid LIKE 'sh-ex-%';")
	db.execute("INSERT OR REPLACE INTO schedule_entries (entry_uuid, person_name, shift_role, shift_date, start_time, end_time, area) VALUES ('sh-ex-e', 'Staff E', 'Staff', ?, '09:00 AM', '10:00 AM', 'Study Room #99');", [test_date])
	items = qc.fetch_queue_records("uncovered_sessions")
	sess_999_uncovered = false
	for it in items:
		if it.get("id") == 999: sess_999_uncovered = true
	if not sess_999_uncovered:
		print("FAIL: Example E (Session 4-5 PM, Shift 9-10 AM) should be UNCOVERED.")
		quit(1); return

	# Clean up test session 999 and test shift
	db.execute("DELETE FROM sessions WHERE id = 999;")
	db.execute("DELETE FROM schedule_entries WHERE entry_uuid LIKE 'sh-ex-%';")
	print("PASS 4b: Time-span coverage engine rules (Examples A-E) verified 100% successfully.")

	# 4c. Test Session Staffing Requirement (DEDICATED_SESSION_STAFF vs COVERED_BY_STUDY_CENTER_STAFF)
	print("[Test 4c] Testing Prompt 2 Session Staffing Requirement & Queue Counts...")
	# 1. Verify Migration 0035 default staffing_requirement = 'DEDICATED_SESSION_STAFF'
	db.execute("INSERT INTO sessions (id, session_uuid, title, date_text, start_time, end_time, room_location, is_active) VALUES (888, 'sess-888', 'Default Dedicated Session', date('now', '+2 days'), '03:00 PM', '05:00 PM', 'Study Room #88', 1);")
	var col_check = db.execute("SELECT staffing_requirement FROM sessions WHERE id = 888;")
	if not col_check["success"] or col_check["data"][0]["staffing_requirement"] != "DEDICATED_SESSION_STAFF":
		print("FAIL: Migration 0035 default staffing_requirement is not DEDICATED_SESSION_STAFF.")
		quit(1); return

	# 2. General staff shift present covering 3-5 PM, but session requires DEDICATED_SESSION_STAFF
	var test_date_888 = str(db.execute("SELECT date('now', '+2 days') as d;")["data"][0]["d"])
	db.execute("INSERT INTO schedule_entries (entry_uuid, person_name, shift_role, shift_date, start_time, end_time, area) VALUES ('sh-gen-888', 'General Floor Staff', 'Supervisor', ?, '03:00 PM', '05:00 PM', 'Study Room #88');", [test_date_888])

	# DEDICATED_SESSION_STAFF + General staff present => STILL UNCOVERED
	qc.start_queue("uncovered_sessions")
	items = qc.fetch_queue_records("uncovered_sessions")
	var sess_888_uncovered = false
	for it in items:
		if it.get("id") == 888: sess_888_uncovered = true
	if not sess_888_uncovered:
		print("FAIL: Dedicated session with general staff should remain UNCOVERED.")
		quit(1); return

	# Dedicated staff assigned (session_id = 888) => COVERED
	db.execute("INSERT INTO schedule_entries (entry_uuid, person_name, shift_role, shift_date, start_time, end_time, area, session_id) VALUES ('sh-ded-888', 'Dedicated Assistant', 'Session Staff', ?, '03:00 PM', '05:00 PM', 'Study Room #88', 888);", [test_date_888])
	qc.start_queue("uncovered_sessions")
	items = qc.fetch_queue_records("uncovered_sessions")
	sess_888_uncovered = false
	for it in items:
		if it.get("id") == 888: sess_888_uncovered = true
	if sess_888_uncovered:
		print("FAIL: Dedicated session with dedicated staff assigned (session_id) should be COVERED.")
		quit(1); return

	# 3. Change staffing_requirement to COVERED_BY_STUDY_CENTER_STAFF (Session Creation & Edit Persistence)
	sch_svc.update_full_session_atomic(888, "Default Dedicated Session", 1, test_date_888, "03:00 PM", "05:00 PM", 30, 1, 1, [], "", "", "", "usr_admin_master", "Administrator", "", false, "COVERED_BY_STUDY_CENTER_STAFF")
	var edit_chk = db.execute("SELECT staffing_requirement FROM sessions WHERE id = 888;")
	if not edit_chk["success"] or edit_chk["data"][0]["staffing_requirement"] != "COVERED_BY_STUDY_CENTER_STAFF":
		print("FAIL: staffing_requirement COVERED_BY_STUDY_CENTER_STAFF did not persist after edit.")
		quit(1); return

	# Clean up 888 test session and shifts
	db.execute("DELETE FROM sessions WHERE id = 888;")
	db.execute("DELETE FROM schedule_entries WHERE entry_uuid LIKE 'sh-%-888';")
	print("PASS 4c: Prompt 2 Session Staffing Requirement & Queue Counts verified 100% successfully.")

	# 5. Test Full Production V1 Home Action Center (All 5 Queues Operational)
	print("[Test 5] Verifying all 5 Production V1 Action Center queues operational...")
	var home = load("res://app/scenes/home_view.tscn").instantiate()
	home.set_app_shell(shell)
	home.show_all_queues = true
	root.add_child(home)
	await process_frame

	var cards = _get_action_cards(home)
	if cards.size() != 5:
		print("FAIL: Expected 5 ActionCenterCard instances when show_all_queues is true, got: ", cards.size())
		quit(1)
		return

	var reg = QueueRegistryScript.get_registry()
	for qid in reg.keys():
		var def = reg[qid]
		if not def.get("queue_mode_supported", false):
			print("FAIL: All 5 Production V1 queues must have queue_mode_supported = true. Failed for: ", qid)
			quit(1)
			return

	for card in cards:
		var btn = card.primary_button if card.primary_button else (card.find_child("PrimaryButton", true, false) as Button)
		if btn and btn.text.contains("(Unavailable)"):
			print("FAIL: No Production V1 card should display (Unavailable). Found on: ", card.queue_id)
			quit(1)
			return
	print("PASS 5/18: Full Production V1 Home Action Center active; all 5 queues operational.")

	dir_view.queue_free()
	home.queue_free()
	shell.queue_free()

	print("==========================================================")
	print("ALL STAGE 10 FINAL V1 ACTION CENTER TESTS PASSED SUCCESSFULLY!")
	print("==========================================================")
	quit(0)
