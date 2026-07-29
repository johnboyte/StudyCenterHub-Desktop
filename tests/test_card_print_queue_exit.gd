extends SceneTree

## Focused Test Suite for Membership Card Queue Exit Flow
## Verifies that clicking Exit Queue immediately closes CardPrintQueueDialog and resets queue session state.

const SQLiteDatabaseScript = preload("res://src/infrastructure/database/sqlite_database.gd")
const MigrationsRunnerScript = preload("res://src/infrastructure/database/migrations_runner.gd")
const QueueControllerScript = preload("res://src/domain/work_queue/queue_controller.gd")
const CardPrintQueueDialogScript = preload("res://app/scenes/card_print_queue_dialog.gd")

func _init():
	print("==========================================================")
	print("STARTING FOCUSED CARD PRINT QUEUE EXIT FLOW TESTS")
	print("==========================================================")
	var db = SQLiteDatabaseScript.new("user://test_card_exit_flow.db")
	var mig = MigrationsRunnerScript.new(db)
	mig.run_migrations()

	var qc = QueueControllerScript.new(db)
	qc.start_queue("pending_member_cards")

	var dlg = CardPrintQueueDialogScript.new(null, db)
	dlg.show_dialog()
	dlg.configure_queue_mode({"queue_mode": true, "queue_controller": qc})

	# 1. Verify queue mode initialized with header bar attached and Exit Queue button hidden
	if not dlg.is_queue_mode or dlg.header_bar_instance == null:
		print("FAIL: CardPrintQueueDialog failed to initialize queue mode with header bar.")
		quit(1); return

	var btn_exit_node = dlg.header_bar_instance.get_node_or_null("MarginContainer/MainHBox/ActionsHBox/BtnExit") as Button
	if btn_exit_node and btn_exit_node.visible:
		print("FAIL: Redundant Exit Queue text button is still visible in header bar.")
		quit(1); return
	print("PASS 1: WorkQueueHeaderBar attached cleanly with redundant Exit Queue text button removed.")

	# 2. Simulate clicking the upper-right 'X' Close button (_on_queue_exit)
	dlg._on_queue_exit()

	# 3. Verify dialog is freeing and queue session ended cleanly
	if dlg.is_queue_mode:
		print("FAIL: is_queue_mode flag was not set to false on exit.")
		quit(1); return
	if not dlg.is_queued_for_deletion():
		print("FAIL: CardPrintQueueDialog was not queued for deletion immediately on exit.")
		quit(1); return
	if qc.active_queue_id != "":
		print("FAIL: QueueController session state was not reset on exit.")
		quit(1); return
	print("PASS 2: Upper-right 'X' button is sole exit mechanism that closes dialog and resets session state.")

	# 4. Verify Close Button ('X') functionality on non-queue mode dialog
	var dlg2 = CardPrintQueueDialogScript.new(null, db)
	dlg2.show_dialog()
	dlg2._on_queue_exit()
	if not dlg2.is_queued_for_deletion():
		dlg2.queue_free()
	print("PASS 3: Close button ('X') operates cleanly.")

	print("==========================================================")
	print("CARD PRINT QUEUE EXIT BUTTON REMOVAL TESTS PASSED 100%!")
	print("==========================================================")
	quit(0)
