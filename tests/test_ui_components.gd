extends SceneTree

## Stage 3 Headless Automated Test Suite for Reusable Work Queue UI Components
## Tests ActionCenterCard, ActiveWorkTray, and WorkQueueHeaderBar scenes and signal contracts.

const ActionCenterCardScene = preload("res://app/scenes/components/action_center_card.tscn")
const ActiveWorkTrayScene = preload("res://app/scenes/components/active_work_tray.tscn")
const WorkQueueHeaderBarScene = preload("res://app/scenes/components/work_queue_header_bar.tscn")

func _init() -> void:
	print("==========================================================")
	print("STARTING STAGE 3 WORK QUEUE UI COMPONENTS TEST SUITE")
	print("==========================================================")

	call_deferred("run_all_tests")

func run_all_tests() -> void:
	# 1. Test ActionCenterCard Instantiation & Configuration
	print("[Test 1] Testing ActionCenterCard configuration and property binding...")
	var card = ActionCenterCardScene.instantiate()
	root.add_child(card)
	
	card.configure_card({
		"queue_id": "pending_member_cards",
		"title": "Pending Member Cards",
		"count": 5,
		"supporting_detail": "Oldest: 10 mins ago",
		"urgency": "critical",
		"primary_button": "Issue Passes"
	})

	if card.title_label.text != "Pending Member Cards" or not card.count_badge.text.begins_with("5"):
		print("FAIL: ActionCenterCard title or count badge mismatch.")
		quit(1)
		return
	if card.urgency_label.text != "CRITICAL":
		print("FAIL: ActionCenterCard urgency label mismatch.")
		quit(1)
		return
	print("PASS 1/6: ActionCenterCard instantiated and configured correctly.")

	# 2. Test ActionCenterCard Signal Emission
	print("[Test 2] Testing ActionCenterCard action_requested signal...")
	var card_res = [""]
	card.action_requested.connect(func(qid):
		card_res[0] = qid
	)
	card._on_button_pressed()
	if card_res[0] != "pending_member_cards":
		print("FAIL: ActionCenterCard signal action_requested failed to emit payload.")
		quit(1)
		return
	print("PASS 2/6: ActionCenterCard action_requested signal emitted accurately.")
	card.queue_free()

	# 3. Test ActiveWorkTray Configuration
	print("[Test 3] Testing ActiveWorkTray configuration...")
	var tray = ActiveWorkTrayScene.instantiate()
	root.add_child(tray)

	tray.configure_tray({
		"queue_id": "overdue_callbacks",
		"title": "Overdue Callbacks",
		"current_index": 1,
		"total_count": 4
	})

	if not tray.title_label.text.contains("Overdue Callbacks") or not tray.progress_label.text.contains("Item 2 of 4"):
		print("FAIL: ActiveWorkTray title or progress text mismatch.")
		quit(1)
		return
	print("PASS 3/6: ActiveWorkTray configured and formatted progress correctly.")

	# 4. Test ActiveWorkTray Resume & End Signals
	print("[Test 4] Testing ActiveWorkTray signals...")
	var tray_res = [false, false]
	tray.resume_requested.connect(func(qid): tray_res[0] = (qid == "overdue_callbacks"))
	tray.end_requested.connect(func(qid): tray_res[1] = (qid == "overdue_callbacks"))
	tray._on_resume_pressed()
	tray._on_end_pressed()
	if not tray_res[0] or not tray_res[1]:
		print("FAIL: ActiveWorkTray resume or end signal failed.")
		quit(1)
		return
	print("PASS 4/6: ActiveWorkTray signals resume_requested and end_requested emitted accurately.")
	tray.queue_free()

	# 5. Test WorkQueueHeaderBar Configuration & Progress Updates
	print("[Test 5] Testing WorkQueueHeaderBar configuration and progress updates...")
	var header = WorkQueueHeaderBarScene.instantiate()
	root.add_child(header)

	header.configure_header("Uncovered Sessions", 0, 5)
	if not header.title_label.text.contains("Uncovered Sessions") or header.progress_bar.value != 20.0:
		print("FAIL: WorkQueueHeaderBar initial progress calculation mismatch.")
		quit(1)
		return

	header.update_progress(2, 5)
	if header.progress_bar.value != 60.0 or not header.count_label.text.contains("Item 3 of 5"):
		print("FAIL: WorkQueueHeaderBar progress update calculation mismatch.")
		quit(1)
		return
	print("PASS 5/6: WorkQueueHeaderBar progress bar and count label updated accurately.")

	# 6. Test WorkQueueHeaderBar Control Signals
	print("[Test 6] Testing WorkQueueHeaderBar pause and exit signals...")
	var header_res = [false, false]
	header.pause_requested.connect(func(): header_res[0] = true)
	header.exit_requested.connect(func(): header_res[1] = true)
	header.pause_requested.emit()
	header.exit_requested.emit()
	if not header_res[0] or not header_res[1]:
		print("FAIL: WorkQueueHeaderBar pause or exit signals failed.")
		quit(1)
		return
	print("PASS 6/6: WorkQueueHeaderBar signals pause_requested and exit_requested emitted accurately.")
	header.queue_free()

	print("==========================================================")
	print("ALL STAGE 3 WORK QUEUE UI COMPONENT TESTS PASSED!")
	print("==========================================================")
	quit(0)
