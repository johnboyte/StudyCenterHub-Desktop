extends SceneTree

## Headless Test Suite for Campus & Community UI Toggle and Reordering

const SQLiteDatabaseScript = preload("res://src/infrastructure/database/sqlite_database.gd")
const MigrationsRunnerScript = preload("res://src/infrastructure/database/migrations_runner.gd")
const DirectoryViewScript = preload("res://app/scenes/directory_view.gd")

func _init() -> void:
	print("==========================================================")
	print("STARTING CAMPUS & COMMUNITY TOGGLE AND REORDERING TESTS")
	print("==========================================================")
	_run_tests()

func _run_tests() -> void:
	await create_timer(0.05).timeout

	var db_path = "user://test_campus_community_toggle.db"
	var global_path = ProjectSettings.globalize_path(db_path)
	if FileAccess.file_exists(global_path):
		DirAccess.remove_absolute(global_path)

	var db = SQLiteDatabaseScript.new(db_path)
	var mig_runner = MigrationsRunnerScript.new(db)
	var mig_res = mig_runner.run_migrations()
	assert(mig_res["success"], "Migrations must succeed")

	# Insert a test person
	var p_uuid = "usr_toggle_test_1"
	db.execute("""
		INSERT INTO people (
			person_uuid, human_id, first_name, last_name, email,
			institution_id, relationship, academic_year, major, residence,
			expected_grad_term, expected_grad_year, campus_community_applies
		) VALUES (
			?, 'P-TEST-001', 'Testy', 'McTesterson', 'testy@school.edu',
			1, 'Student', 'Junior', 'Math', 'Commuter', 'Fall', 2027, 1
		);
	""", [p_uuid])

	# Create Directory View and bind database
	var view = DirectoryViewScript.new()
	view.db = db
	
	# --------------------------------------------------------
	# Test 1: Verify Section/Tab Reordering
	# --------------------------------------------------------
	print("[Test 1] Verifying tab order...")
	# Exact target order:
	# 1. Overview
	# 2. Profile
	# 3. Communication
	# 4. Participation
	# 5. Notes
	# 6. History
	
	# Check order of children inside SectionTabBar in the scene tree structure
	# Since it is a PackedScene, we can instantiate it and check
	var view_instance = load("res://app/scenes/directory_view.tscn").instantiate()
	var tab_bar = view_instance.get_node("MarginContainer/VBoxContainer/MainSplit/WorkspacePanel/WorkspaceMargin/SelectedWorkspaceVBox/SectionTabBar")
	assert(tab_bar != null, "SectionTabBar node must exist")
	
	var expected_tabs = ["TabOverview", "TabProfile", "TabCommunications", "TabParticipation", "TabNotes", "TabHistory"]
	assert(tab_bar.get_child_count() == expected_tabs.size(), "Tab count mismatch")
	for idx in range(expected_tabs.size()):
		var child = tab_bar.get_child(idx)
		assert(child.name == expected_tabs[idx], "Tab order mismatch at index " + str(idx) + ": expected " + expected_tabs[idx] + " got " + child.name)
	
	# Check order of children inside SectionStack
	var section_stack = view_instance.get_node("MarginContainer/VBoxContainer/MainSplit/WorkspacePanel/WorkspaceMargin/SelectedWorkspaceVBox/WorkspaceScroll/SectionStack")
	assert(section_stack != null, "SectionStack node must exist")
	var expected_sections = ["OverviewSection", "ProfileSection", "CommunicationsSection", "ParticipationSection", "NotesSection", "HistorySection"]
	assert(section_stack.get_child_count() == expected_sections.size(), "Section count mismatch")
	for idx in range(expected_sections.size()):
		var child = section_stack.get_child(idx)
		assert(child.name == expected_sections[idx], "Section order mismatch at index " + str(idx) + ": expected " + expected_sections[idx] + " got " + child.name)
	print("PASS 1: Tab and section stack order matches the exact specification.")

	# --------------------------------------------------------
	# Test 2: Card rendering and default toggle to ON
	# --------------------------------------------------------
	print("[Test 2] Rendering card with toggle ON...")
	var person_data_q = db.execute("SELECT * FROM people WHERE person_uuid = ? LIMIT 1;", [p_uuid])
	var p_data = person_data_q["data"][0]
	
	var card = view._create_campus_community_card(p_data, p_uuid)
	var cc_card_vbox = card.get_child(0).get_child(1) as VBoxContainer
	var toggle = cc_card_vbox.get_child(0) as CheckButton
	assert(toggle != null and toggle.text == "Campus & Community Applies", "Toggle must be the first child of cc_card_vbox with correct label")
	assert(toggle.button_pressed == true, "Toggle must default to ON when campus_community_applies is 1")
	
	var form_grid = cc_card_vbox.get_child(1) as GridContainer
	assert(form_grid.visible == true, "Form fields must be visible when toggle is ON")
	print("PASS 2: Toggle correctly rendered and initialized to ON.")

	# --------------------------------------------------------
	# Test 3: Expected Graduation Term "Not Applicable" Option
	# --------------------------------------------------------
	print("[Test 3] Verifying Expected Graduation Term options...")
	# Find the Expected Graduation Term dropdown in the form grid
	# 8th vbox is the Expected Graduation Term container
	var gt_vbox = form_grid.get_child(7) as VBoxContainer
	var gt_dropdown = gt_vbox.get_child(1) as OptionButton
	
	var gt_options = []
	for i in range(gt_dropdown.item_count):
		gt_options.append(gt_dropdown.get_item_text(i))
	assert("Not Applicable" in gt_options, "'Not Applicable' must be a selectable option in Expected Graduation Term")
	print("PASS 3: 'Not Applicable' is available in expected graduation term options.")

	# --------------------------------------------------------
	# Test 4: Removal of raw "<null>" display in expected graduation year
	# --------------------------------------------------------
	print("[Test 4] Verifying no raw '<null>' string displays...")
	# Insert a person record with NULL/empty grad year and term
	var p_uuid_null = "usr_toggle_test_null"
	db.execute("""
		INSERT INTO people (
			person_uuid, human_id, first_name, last_name, email,
			expected_grad_term, expected_grad_year
		) VALUES (
			?, 'P-TEST-002', 'Null', 'McNull', 'null@school.edu',
			NULL, NULL
		);
	""", [p_uuid_null])
	
	var p_null_data = db.execute("SELECT * FROM people WHERE person_uuid = ? LIMIT 1;", [p_uuid_null])["data"][0]
	var null_card = view._create_campus_community_card(p_null_data, p_uuid_null)
	var null_cc_card_vbox = null_card.get_child(0).get_child(1) as VBoxContainer
	var null_form_grid = null_cc_card_vbox.get_child(1) as GridContainer
	
	# Expected Graduation Year LineEdit (9th child / index 8)
	var gy_vbox = null_form_grid.get_child(8) as VBoxContainer
	var gy_edit = gy_vbox.get_child(1) as LineEdit
	assert(gy_edit.text == "", "Graduation year must display empty string, not '<null>'")
	
	# Expected Graduation Term Dropdown (8th child / index 7)
	var null_gt_vbox = null_form_grid.get_child(7) as VBoxContainer
	var null_gt_dropdown = null_gt_vbox.get_child(1) as OptionButton
	var selected_term_text = null_gt_dropdown.get_item_text(null_gt_dropdown.selected)
	assert(selected_term_text == "Not Applicable", "Graduation term must default to 'Not Applicable' when NULL")
	print("PASS 4: Raw '<null>' values are cleared and fallback to blank/'Not Applicable'.")

	# --------------------------------------------------------
	# Test 5: Toggle persistence & Preservation of Hidden Data
	# --------------------------------------------------------
	print("[Test 5] Verifying toggle persistence & data preservation...")
	# Toggle the applies button to OFF
	toggle.button_pressed = false
	assert(form_grid.visible == false, "Form fields must collapse/hide when toggle is OFF")
	
	# Simulate clicking save on the card
	var save_button = cc_card_vbox.get_child(2) as Button
	save_button.pressed.emit()
	
	# Fetch updated record from DB
	var updated_data_q = db.execute("SELECT * FROM people WHERE person_uuid = ? LIMIT 1;", [p_uuid])
	var updated_data = updated_data_q["data"][0]
	
	assert(int(updated_data["campus_community_applies"]) == 0, "Toggle state must be saved to database as 0")
	# Hidden values must be preserved, not wiped/erased
	assert(updated_data["major"] == "Math", "Hidden data 'major' must be preserved")
	assert(updated_data["expected_grad_year"] == 2027, "Hidden data 'expected_grad_year' must be preserved")
	assert(updated_data["expected_grad_term"] == "Fall", "Hidden data 'expected_grad_term' must be preserved")
	print("PASS 5: Toggle state persists and hidden values are preserved successfully.")

	# Clean up test project resources
	view_instance.queue_free()
	db = null
	if FileAccess.file_exists(global_path):
		DirAccess.remove_absolute(global_path)

	print("==========================================================")
	print("ALL CAMPUS & COMMUNITY TOGGLE AND REORDERING TESTS PASSED!")
	print("==========================================================")
	quit(0)
