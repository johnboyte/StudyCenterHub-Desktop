extends SceneTree

## Stage 5 Headless Automated Test Suite for Home Action Center Integration
## Verifies Action Center grid rendering, ActiveWorkTray, parameterized queue launching, count sync, and scope boundaries.

const SQLiteDatabaseScript = preload("res://src/infrastructure/database/sqlite_database.gd")
const MigrationsRunnerScript = preload("res://src/infrastructure/database/migrations_runner.gd")
const QueueControllerScript = preload("res://src/domain/work_queue/queue_controller.gd")

class MockAppShell extends Control:
	var db: RefCounted
	var switched_view: String = ""
	var switch_params: Dictionary = {}
	var switch_count: int = 0

	func switch_view(view_name: String, params: Dictionary = {}) -> bool:
		switched_view = view_name
		switch_params = params.duplicate(true)
		switch_count += 1
		return true

func _collect_nodes(node: Node, acc: Array) -> void:
	acc.append(node)
	for child in node.get_children():
		_collect_nodes(child, acc)

func _get_action_cards(root_node: Node) -> Array:
	var all_nodes = []
	_collect_nodes(root_node, all_nodes)
	var res = []
	for n in all_nodes:
		var scr = n.get_script()
		if scr and scr.resource_path.ends_with("action_center_card.gd"):
			res.append(n)
	return res

func _get_work_trays(root_node: Node) -> Array:
	var all_nodes = []
	_collect_nodes(root_node, all_nodes)
	var res = []
	for n in all_nodes:
		var scr = n.get_script()
		if scr and scr.resource_path.ends_with("active_work_tray.gd"):
			res.append(n)
	return res

func _init() -> void:
	print("==========================================================")
	print("STARTING STAGE 5 HOME ACTION CENTER TEST SUITE")
	print("==========================================================")
	call_deferred("run_tests")

func run_tests() -> void:
	var db_path = ProjectSettings.globalize_path("user://test_stage5_home_action_center.db")
	if FileAccess.file_exists(db_path):
		DirAccess.remove_absolute(db_path)

	var db = SQLiteDatabaseScript.new(db_path)
	var mig_res = MigrationsRunnerScript.new(db).run_migrations()
	if not mig_res.get("success", false):
		print("FAIL: Database migrations failed.")
		quit(1)
		return

	# Clear migration seed & insert controlled seed data
	db.execute("DELETE FROM card_print_queue;")
	db.execute("INSERT OR REPLACE INTO people (id, person_uuid, first_name, last_name, human_id) VALUES (10, 'p-uuid-10', 'Carol', 'Danvers', 'M110');")
	db.execute("INSERT OR REPLACE INTO card_print_queue (id, queue_uuid, person_id, person_uuid, status, added_at) VALUES (100, 'uuid-100', 10, 'p-uuid-10', 'pending', datetime('now'));")

	var shell = MockAppShell.new()
	shell.db = db
	root.add_child(shell)

	# 1. Test HomeView Instantiation & Action Center Card Grid Rendering
	print("[Test 1] Testing HomeView instantiation and ActionCenterCard rendering...")
	var home = load("res://app/scenes/home_view.tscn").instantiate()
	home.set_app_shell(shell)
	root.add_child(home)
	await process_frame

	var cards = _get_action_cards(home)
	if cards.size() != 5:
		print("FAIL: Expected 5 ActionCenterCard instances for 5 V1 queues, got: ", cards.size())
		quit(1)
		return
	print("PASS 1/7: Home Action Center rendered all 5 Production V1 queue cards simultaneously.")

	# 2. Verify Card Metadata & Counts from Queue Architecture
	print("[Test 2] Verifying card metadata and count sources...")
	var member_cards_found = false
	var pending_card_count = -1
	for card in cards:
		if card.queue_id == "pending_member_cards":
			member_cards_found = true
			var badge_lbl = card.count_badge if card.count_badge else (card.find_child("CountBadge", true, false) as Label)
			if badge_lbl:
				pending_card_count = badge_lbl.text.to_int()
			break

	if not member_cards_found or pending_card_count != 1:
		print("FAIL: pending_member_cards card metadata or count mismatch. Found: ", member_cards_found, " count: ", pending_card_count)
		quit(1)
		return
	print("PASS 2/7: Card metadata and count derived accurately from QueueRegistry and QueueController.")

	# 3. Test Selecting pending_member_cards Card Launches Stage 4 Slice via Stage 2 Navigation
	print("[Test 3] Testing pending_member_cards launch via Stage 2 navigation contract...")
	shell.switched_view = ""
	shell.switch_params = {}
	home._on_card_action("pending_member_cards")

	if shell.switched_view != "card_print_queue" or shell.switch_params.get("queue_mode") != true or shell.switch_params.get("queue_id") != "pending_member_cards":
		print("FAIL: Navigation contract mismatch on launch. Target: ", shell.switched_view, " Params: ", shell.switch_params)
		quit(1)
		return
	print("PASS 3/7: Selecting pending_member_cards card invoked Stage 2 navigation contract correctly.")

	# 4. Test ActiveWorkTray Rendering for Paused Session
	print("[Test 4] Testing ActiveWorkTray rendering when paused session exists...")
	var qc = home._get_queue_controller()
	qc.start_queue("pending_member_cards")
	home._setup_middle_cards()

	var trays = _get_work_trays(home)
	if trays.size() != 1:
		print("FAIL: ActiveWorkTray did not render when active session existed. Found count: ", trays.size())
		quit(1)
		return
	print("PASS 4/7: ActiveWorkTray rendered cleanly for active paused work session.")

	# 5. Test ActiveWorkTray [End Session] Button Clearing Tray State
	print("[Test 5] Testing ActiveWorkTray [End Session] button handler...")
	home._on_tray_end("pending_member_cards")
	trays = _get_work_trays(home)
	if trays.size() != 0 or qc.active_queue_id != "":
		print("FAIL: End session failed to clear active queue session or remove tray.")
		quit(1)
		return
	print("PASS 5/7: ActiveWorkTray [End Session] cleared session and updated Home Action Center.")

	# 6. Test Count Synchronization After Item Completion
	print("[Test 6] Testing count synchronization after item completion...")
	qc.start_queue("pending_member_cards")
	qc.complete_current_item([100]) # Complete the item
	home.receive_navigation_context({}) # Simulate return to Home

	cards = _get_action_cards(home)
	for card in cards:
		if card.queue_id == "pending_member_cards":
			var badge_lbl = card.count_badge if card.count_badge else (card.find_child("CountBadge", true, false) as Label)
			if not badge_lbl or not badge_lbl.text.begins_with("0"):
				print("FAIL: Count did not update to 0 after item completion. Text: ", (badge_lbl.text if badge_lbl else "null"))
				quit(1)
				return
			break
	print("PASS 6/7: Counts refreshed and synchronized after queue item completion.")

	# 7. Verify All 5 Production V1 Cards Are Functional & Supported
	print("[Test 7] Verifying all 5 Production V1 cards are functional and supported...")
	for card in cards:
		var btn = card.primary_button if card.primary_button else (card.find_child("PrimaryButton", true, false) as Button)
		if btn and btn.text.contains("(Unavailable)"):
			print("FAIL: All 5 Production V1 cards should be active. Found unavailable card: ", card.queue_id)
			quit(1)
			return

	shell.switched_view = ""
	home._on_card_action("uncovered_sessions")
	if shell.switched_view != "schedules":
		print("FAIL: Selecting uncovered_sessions should switch to schedules view, got: ", shell.switched_view)
		quit(1)
		return
	print("PASS 7/7: All 5 Production V1 Action Center queues are fully operational.")

	home.queue_free()
	shell.queue_free()

	print("==========================================================")
	print("ALL STAGE 5 HOME ACTION CENTER TESTS PASSED SUCCESSFULLY!")
	print("==========================================================")
	quit(0)
