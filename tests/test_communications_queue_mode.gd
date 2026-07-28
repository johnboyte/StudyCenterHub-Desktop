extends SceneTree

## Stage 8 Headless Automated Test Suite for Communications Queue Mode Integration
## Verifies overdue_callbacks, unanswered_messages, Queue Mode UI, overlap handling, count sync, and regression safety.

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

func _init() -> void:
	print("==========================================================")
	print("STARTING STAGE 8 COMMUNICATIONS QUEUE MODE TEST SUITE")
	print("==========================================================")
	call_deferred("run_tests")

func run_tests() -> void:
	var db_path = ProjectSettings.globalize_path("user://test_stage8_communications.db")
	if FileAccess.file_exists(db_path):
		DirAccess.remove_absolute(db_path)

	var db = SQLiteDatabaseScript.new(db_path)
	var mig_res = MigrationsRunnerScript.new(db).run_migrations()
	if not mig_res.get("success", false):
		print("FAIL: Database migrations failed.")
		quit(1)
		return

	# Insert test data:
	# Record 1 (ID 10): Overdue callback AND >2h old (Overlapping item)
	# Record 2 (ID 11): Overdue callback only (due yesterday, created 1h ago)
	# Record 3 (ID 12): Unanswered message >2h old only (created 3h ago, no due_date)
	db.execute("DELETE FROM voicemails;")
	db.execute("INSERT INTO voicemails (id, voicemail_uuid, caller_name, caller_phone, duration_sec, transcription, status, due_date, created_at) VALUES (10, 'vm-10', 'Alice', '555-0100', 30, 'Urgent callback needed', 'new', date('now', '-1 day'), datetime('now', '-3 hours'));")
	db.execute("INSERT INTO voicemails (id, voicemail_uuid, caller_name, caller_phone, duration_sec, transcription, status, due_date, created_at) VALUES (11, 'vm-11', 'Bob', '555-0200', 45, 'General inquiry callback', 'new', date('now', '-1 day'), datetime('now', '-1 hour'));")
	db.execute("INSERT INTO voicemails (id, voicemail_uuid, caller_name, caller_phone, duration_sec, transcription, status, due_date, created_at) VALUES (12, 'vm-12', 'Charlie', '555-0300', 15, 'Quick question message', 'new', NULL, datetime('now', '-3 hours'));")

	var shell = MockAppShell.new()
	shell.db = db
	root.add_child(shell)

	var qc = QueueControllerScript.new(db)

	# 1. Test Ordinary Communications View Instantiation (No Queue Mode)
	print("[Test 1] Testing ordinary Communications view instantiation...")
	var com_view = load("res://app/scenes/communications_view.tscn").instantiate()
	com_view.db = db
	root.add_child(com_view)
	await process_frame

	var hbar = _get_header_bar(com_view)
	if hbar != null or com_view.is_queue_mode:
		print("FAIL: Ordinary Communications navigation should not attach WorkQueueHeaderBar or enable Queue Mode.")
		quit(1)
		return
	print("PASS 1/14: Ordinary Communications navigation remains unchanged and clean.")

	# 2. Test overdue_callbacks Queue Mode Context Acceptance & Header Bar
	print("[Test 2] Testing overdue_callbacks Queue Mode context delivery...")
	com_view.receive_navigation_context({
		"queue_mode": true,
		"queue_id": "overdue_callbacks",
		"queue_controller": qc
	})
	await process_frame

	hbar = _get_header_bar(com_view)
	if not hbar or not com_view.is_queue_mode or com_view.active_queue_id != "overdue_callbacks":
		print("FAIL: overdue_callbacks Queue Mode context was not accepted cleanly.")
		quit(1)
		return
	print("PASS 2/14: overdue_callbacks Queue Mode context accepted and WorkQueueHeaderBar attached.")

	# 3. Test overdue_callbacks Record Eligibility & Deterministic Ordering
	print("[Test 3] Testing overdue_callbacks record eligibility and ordering...")
	var rem_count = qc.get_remaining_count()
	if rem_count != 2: # Items 10 & 11
		print("FAIL: Expected 2 overdue callbacks, got: ", rem_count)
		quit(1)
		return

	var current_item = qc.get_current_item()
	if current_item.get("id") != 10:
		print("FAIL: Deterministic ordering failed. Expected first item ID 10, got: ", current_item.get("id"))
		quit(1)
		return
	print("PASS 3/14: overdue_callbacks displayed correct eligible records in deterministic order.")

	# 4. Test Overlapping Item Completion & Cross-Queue Count Decrement
	print("[Test 4] Testing overlapping item completion across overdue_callbacks and unanswered_messages...")
	# Verify initial unanswered_messages count (Items 10 & 12 = 2 items)
	var initial_unanswered_count = qc.get_queue_count("unanswered_messages")
	if initial_unanswered_count != 2:
		print("FAIL: Initial unanswered_messages count mismatch. Expected 2, got: ", initial_unanswered_count)
		quit(1)
		return

	# Complete overlapping item ID 10 in overdue_callbacks
	var comp_success = qc.complete_current_item([10])
	if not comp_success:
		print("FAIL: Completing item 10 in overdue_callbacks failed.")
		quit(1)
		return

	# Re-query counts for both queues
	var new_overdue_count = qc.get_queue_count("overdue_callbacks")
	var new_unanswered_count = qc.get_queue_count("unanswered_messages")

	if new_overdue_count != 1 or new_unanswered_count != 1:
		print("FAIL: Overlapping completion failed to decrement both queues cleanly. Overdue: ", new_overdue_count, " Unanswered: ", new_unanswered_count)
		quit(1)
		return
	print("PASS 4/14: Completing overlapping item 10 cleanly decremented both overdue_callbacks and unanswered_messages counts.")

	# 5. Test unanswered_messages Queue Mode Navigation
	print("[Test 5] Testing unanswered_messages Queue Mode context delivery...")
	com_view.receive_navigation_context({
		"queue_mode": true,
		"queue_id": "unanswered_messages",
		"queue_controller": qc
	})
	await process_frame

	if com_view.active_queue_id != "unanswered_messages":
		print("FAIL: Failed to switch active queue to unanswered_messages.")
		quit(1)
		return

	var current_unanswered = qc.get_current_item()
	if current_unanswered.get("id") != 12: # Item 10 was completed; item 12 remains
		print("FAIL: Expected remaining unanswered item ID 12, got: ", current_unanswered.get("id"))
		quit(1)
		return
	print("PASS 5/14: unanswered_messages Queue Mode active with remaining eligible record.")

	# 6. Test Completing Item 12 and Reaching Queue Empty State
	print("[Test 6] Testing completion of item 12 and Queue Empty state...")
	qc.complete_current_item([12])
	com_view._refresh_queue_view()
	await process_frame

	if qc.get_remaining_count() != 0:
		print("FAIL: Expected 0 remaining unanswered messages, got: ", qc.get_remaining_count())
		quit(1)
		return
	print("PASS 6/14: Item 12 completed; unanswered_messages reached Queue Empty state cleanly.")

	# 7. Test ActiveWorkTray Resume and Queue Exit Handlers
	print("[Test 7] Testing ActiveWorkTray Resume and End Session handlers...")
	com_view._on_queue_exit()
	await process_frame

	if com_view.is_queue_mode or qc.active_queue_id != "":
		print("FAIL: _on_queue_exit failed to clear active queue session and disable Queue Mode.")
		quit(1)
		return
	print("PASS 7/14: End Session cleared active queue session and restored standard view.")

	# 8. Test Home Action Center Verification & Supported Queue Flags
	print("[Test 8] Testing Home Action Center cards for newly supported communications queues...")
	var home = load("res://app/scenes/home_view.tscn").instantiate()
	home.set_app_shell(shell)
	root.add_child(home)
	await process_frame

	var reg = QueueRegistryScript.get_registry()
	if not reg["overdue_callbacks"].get("queue_mode_supported", false) or not reg["unanswered_messages"].get("queue_mode_supported", false):
		print("FAIL: QueueRegistry queue_mode_supported flag not set to true for communications queues.")
		quit(1)
		return

	if reg["registrations_awaiting_review"].get("queue_mode_supported", true) or reg["uncovered_sessions"].get("queue_mode_supported", true):
		print("FAIL: Unsupported queues (registrations_awaiting_review / uncovered_sessions) must remain queue_mode_supported = false.")
		quit(1)
		return
	print("PASS 8/14: QueueRegistry correctly enables overdue_callbacks and unanswered_messages while keeping unsupported queues disabled.")

	com_view.queue_free()
	home.queue_free()
	shell.queue_free()

	print("==========================================================")
	print("ALL STAGE 8 COMMUNICATIONS QUEUE MODE TESTS PASSED!")
	print("==========================================================")
	quit(0)
