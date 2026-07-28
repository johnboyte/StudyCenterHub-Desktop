extends SceneTree

## Stage 4 Headless Automated Test Suite for Pending Member Cards Vertical Slice
## Verifies QueueController, WorkQueueHeaderBar integration, item completion, count decrement, and session exit.

const SQLiteDatabaseScript = preload("res://src/infrastructure/database/sqlite_database.gd")
const MigrationsRunnerScript = preload("res://src/infrastructure/database/migrations_runner.gd")
const QueueControllerScript = preload("res://src/domain/work_queue/queue_controller.gd")
const CardPrintQueueDialogScript = preload("res://app/scenes/card_print_queue_dialog.gd")

func _init() -> void:
	print("==========================================================")
	print("STARTING STAGE 4 VERTICAL SLICE TEST SUITE (MEMBER CARDS)")
	print("==========================================================")

	var db_path = ProjectSettings.globalize_path("user://test_stage4_member_cards.db")
	if FileAccess.file_exists(db_path):
		DirAccess.remove_absolute(db_path)

	var db = SQLiteDatabaseScript.new(db_path)
	var mig_res = MigrationsRunnerScript.new(db).run_migrations()
	if not mig_res.get("success", false):
		print("FAIL: Database migrations failed.")
		quit(1)
		return

	# Clear any migration seed data & seed exactly 2 pending passes in card_print_queue
	db.execute("DELETE FROM card_print_queue;")
	db.execute("INSERT OR REPLACE INTO people (id, person_uuid, first_name, last_name, human_id) VALUES (1, 'p-uuid-1', 'Alice', 'Smith', 'M101');")
	db.execute("INSERT OR REPLACE INTO people (id, person_uuid, first_name, last_name, human_id) VALUES (2, 'p-uuid-2', 'Bob', 'Jones', 'M102');")
	db.execute("INSERT OR REPLACE INTO card_print_queue (id, queue_uuid, person_id, person_uuid, status, added_at) VALUES (1, 'uuid-1', 1, 'p-uuid-1', 'pending', datetime('now'));")
	db.execute("INSERT OR REPLACE INTO card_print_queue (id, queue_uuid, person_id, person_uuid, status, added_at) VALUES (2, 'uuid-2', 2, 'p-uuid-2', 'pending', datetime('now'));")

	# 1. Verify Initial Count via QueueController
	print("[Test 1] Verifying initial pending_member_cards count...")
	var controller = QueueControllerScript.new(db)
	controller.start_queue("pending_member_cards")
	var init_count = controller.get_remaining_count()
	if init_count != 2:
		print("FAIL: Expected initial count 2, got: ", init_count)
		quit(1)
		return
	print("PASS 1/6: Initial pending_member_cards count verified (2 items).")

	# 2. Test Dialog Instantiation & Queue Mode Context Delivery
	print("[Test 2] Testing dialog instantiation and Queue Mode context delivery...")
	var dialog = CardPrintQueueDialogScript.new(null, db)
	root.add_child(dialog)

	dialog.receive_navigation_context({
		"queue_mode": true,
		"queue_id": "pending_member_cards",
		"queue_controller": controller
	})
	dialog.show_dialog()

	if not dialog.is_queue_mode or dialog.header_bar_instance == null:
		print("FAIL: Dialog failed to initialize in Queue Mode or attach header bar.")
		quit(1)
		return
	print("PASS 2/6: Dialog instantiated in Queue Mode with active WorkQueueHeaderBar.")

	# 3. Verify Header Bar Progress Initial State via Node Traversal
	print("[Test 3] Verifying WorkQueueHeaderBar progress state via node traversal...")
	var count_lbl = dialog.header_bar_instance.get_node_or_null("MarginContainer/MainHBox/ProgressHBox/CountLabel") as Label
	if count_lbl == null or not count_lbl.text.contains("Item 1 of 2"):
		print("FAIL: Header count text expected 'Item 1 of 2', got: ", (count_lbl.text if count_lbl else "null"))
		quit(1)
		return
	print("PASS 3/6: WorkQueueHeaderBar initialized with correct progress (Item 1 of 2).")

	# 4. Test Card Printing Completion Delegation
	print("[Test 4] Executing card print item completion delegation...")
	controller.complete_current_item([1]) # Complete card_print_queue.id = 1
	dialog.header_bar_instance.update_progress(controller.current_index, controller.get_remaining_count())

	var check_db = db.execute("SELECT status FROM card_print_queue WHERE id = 1;")
	if not check_db.get("success", false) or check_db["data"][0]["status"] != "printed":
		print("FAIL: Database row status was not updated to 'printed'.")
		quit(1)
		return
	print("PASS 4/6: Card completion mutated SQLite status to 'printed' successfully.")

	# 5. Verify Remaining Count Decrement
	print("[Test 5] Verifying remaining count decrement...")
	var rem_count = controller.get_remaining_count()
	if rem_count != 1:
		print("FAIL: Expected remaining count 1, got: ", rem_count)
		quit(1)
		return
	print("PASS 5/6: QueueController auto-decremented remaining count to 1.")

	# 6. Test Queue Session Exit
	print("[Test 6] Testing Queue Mode session exit...")
	dialog._on_queue_exit()
	if dialog.is_queue_mode or dialog.header_bar_instance != null:
		print("FAIL: Session exit failed to clean up header bar or reset queue_mode flag.")
		quit(1)
		return
	print("PASS 6/6: Queue Mode session exited cleanly.")

	dialog.queue_free()

	print("==========================================================")
	print("ALL STAGE 4 VERTICAL SLICE TESTS PASSED SUCCESSFULLY!")
	print("==========================================================")
	quit(0)
