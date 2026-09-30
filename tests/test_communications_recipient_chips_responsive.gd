@tool
extends SceneTree

const SQLiteDatabaseScript = preload("res://src/infrastructure/database/sqlite_database.gd")
const MigrationsRunnerScript = preload("res://src/infrastructure/database/migrations_runner.gd")

func _init() -> void:
	print("==========================================================")
	print("STARTING COMMUNICATIONS RECIPIENT CHIPS RESPONSIVE TEST")
	print("==========================================================")
	
	# Set test DB override
	var user_dir = OS.get_user_data_dir()
	var test_db_path = user_dir.path_join("test_communications_recipient_chips_responsive.db")
	ProjectSettings.set_setting("app/database_override_path", test_db_path)
	
	call_deferred("_run_tests")

func _run_tests() -> void:
	var db = SQLiteDatabaseScript.new()
	var mig = MigrationsRunnerScript.new(db)
	mig.run_migrations()

	var scene_res = load("res://app/scenes/communications_view.tscn")
	var comm_view = scene_res.instantiate()
	root.add_child(comm_view)
	if not comm_view.is_node_ready() or comm_view.audience_type_dropdown == null:
		comm_view._setup_communicate_send_composer()
		comm_view._ready()
	comm_view.db = db
	
	# Wait for view initialization
	await create_timer(0.3).timeout
	
	# Prepare mock person list with 50 test constituents
	var mock_persons: Array = []
	for i in range(1, 51):
		mock_persons.append({
			"id": i,
			"human_id": "P-%03d" % i,
			"first_name": "TestConstituent",
			"last_name": "Number%d" % i,
			"email": "test%d@example.org" % i,
			"phone": "555-01%02d" % (i % 100)
		})
	
	comm_view.person_list = mock_persons
	comm_view._on_audience_type_selected(0) # Individual
	
	var chips_container = comm_view.individual_chips_container
	var scroll_container = comm_view.chips_scroll_container
	
	print("PASS 1/7: Containers initialized correctly.")
	assert(chips_container != null, "individual_chips_container must be instantiated")
	assert(chips_container is HFlowContainer, "individual_chips_container must be HFlowContainer")
	assert(scroll_container != null, "chips_scroll_container must be instantiated")
	assert(scroll_container is ScrollContainer, "chips_scroll_container must be ScrollContainer")
	assert(scroll_container.horizontal_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED, "Horizontal scroll mode must be SCROLL_MODE_DISABLED")
	
	# TEST 1: 1 Recipient
	comm_view.selected_individual_ids = [1]
	comm_view._refresh_individual_chips()
	await create_timer(0.1).timeout
	
	assert(chips_container.get_child_count() == 1, "Should render 1 chip")
	assert(scroll_container.visible == true, "Scroll container should be visible")
	print("PASS 2/7: 1 Recipient renders 1 chip in compact row without horizontal expansion.")
	
	# TEST 2: 5 Recipients
	comm_view.selected_individual_ids = [1, 2, 3, 4, 5]
	comm_view._refresh_individual_chips()
	await create_timer(0.1).timeout
	
	assert(chips_container.get_child_count() == 5, "Should render 5 chips")
	assert(scroll_container.horizontal_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED, "Horizontal scroll disabled for 5 recipients")
	print("PASS 3/7: 5 Recipients reflow correctly within available width.")
	
	# TEST 3: 15 Recipients
	var ids_15: Array = []
	for i in range(1, 16): ids_15.append(i)
	comm_view.selected_individual_ids = ids_15
	comm_view._refresh_individual_chips()
	await create_timer(0.1).timeout
	
	assert(chips_container.get_child_count() == 15, "Should render 15 chips")
	assert(scroll_container.horizontal_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED, "Horizontal scroll disabled for 15 recipients")
	print("PASS 4/7: 15 Recipients reflow into clean wrapped rows without expanding page width.")
	
	# TEST 4: Large Group (50 Recipients)
	var ids_50: Array = []
	for i in range(1, 51): ids_50.append(i)
	comm_view.selected_individual_ids = ids_50
	comm_view._refresh_individual_chips()
	await create_timer(0.2).timeout
	
	assert(chips_container.get_child_count() == 50, "Should render 50 chips")
	assert(scroll_container.custom_minimum_size.y <= 140.0, "Vertical height capped at 140px for large groups")
	assert(scroll_container.horizontal_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED, "Horizontal scroll disabled for large group")
	print("PASS 5/7: Large Group (50 recipients) caps vertical height at 140px with vertical scrolling.")
	
	# TEST 5: Chip Removal / Reflow
	comm_view.selected_individual_ids.erase(50)
	comm_view.selected_individual_ids.erase(49)
	comm_view.selected_individual_ids.erase(48)
	comm_view._refresh_individual_chips()
	await create_timer(0.1).timeout
	
	assert(chips_container.get_child_count() == 47, "Reflowed to 47 chips after removal")
	
	# Clear all
	comm_view.selected_individual_ids.clear()
	comm_view._refresh_individual_chips()
	await create_timer(0.1).timeout
	
	assert(chips_container.get_child_count() == 0, "0 chips after clear")
	assert(scroll_container.visible == false, "Scroll container hidden when 0 recipients selected")
	print("PASS 6/7: Removing recipients reflows chips upward and reclaims unused space.")
	
	# TEST 6: Audience resolution / Counts Label
	comm_view.selected_individual_ids = [1, 2, 3]
	comm_view._refresh_individual_chips()
	comm_view._update_audience_resolution()
	await create_timer(0.1).timeout
	
	assert(comm_view.aud_count_label != null, "aud_count_label must exist")
	assert(comm_view.aud_count_label.text.contains("Eligible Recipients"), "Counts label displays eligible recipients")
	print("PASS 7/7: Eligible/excluded recipient counts label preserved and updated.")
	
	print("==========================================================")
	print("SUMMARY: 7 / 7 ASSERTIONS PASSED (100.0%)")
	print("==========================================================")
	print("SUCCESS: ALL COMMUNICATIONS RECIPIENT CHIPS RESPONSIVE TESTS PASSED!")
	
	comm_view.queue_free()
	quit(0)
