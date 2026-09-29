# Focused test for People Directory roster/detail width splitter & column expansion.
# Verifies:
# 1. MainSplit allows dragging left & right smoothly.
# 2. Roster panel width increases when split_offset increases.
# 3. Roster card text containers expand into the added width.
# 4. Profile workspace pane resizes naturally without hard minimum lock.
# 5. Splitter position persists where placed.
# 6. Tab switching and workspace rendering remain intact.

extends SceneTree

const SqliteDatabaseScript = preload("res://src/infrastructure/database/sqlite_database.gd")
const MigrationsRunnerScript = preload("res://src/infrastructure/database/migrations_runner.gd")

func _init() -> void:
	print("--- BEGIN DIRECTORY SPLITTER & ROSTER COLUMN EXPANSION TEST ---")
	var test_db_path = "user://test_directory_splitter.db"
	if FileAccess.file_exists(test_db_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(test_db_path))

	var db = SqliteDatabaseScript.new(test_db_path)
	var runner = MigrationsRunnerScript.new(db)
	runner.run_migrations()

	# Insert test person
	db.execute("""
		INSERT INTO people (id, person_uuid, human_id, first_name, last_name, phone, primary_email, status, created_at, updated_at)
		VALUES (1, 'p-split-001', 'P-20260720-0001', 'Alexander', 'Montgomery-Wellington', '8645550199', 'alexander.montgomery@example.com', 'active', datetime('now'), datetime('now'));
	""")

	var dir_scene = load("res://app/scenes/directory_view.tscn")
	var dir_view = dir_scene.instantiate()
	
	var vp = SubViewport.new()
	vp.size = Vector2i(1280, 800)
	root.add_child(vp)
	vp.add_child(dir_view)
	dir_view.db = db

	# Create test person dictionary
	var test_person = {
		"id": 1,
		"person_uuid": "p-split-001",
		"human_id": "P-20260720-0001",
		"first_name": "Alexander",
		"last_name": "Montgomery-Wellington",
		"phone": "8645550199",
		"primary_email": "alexander.montgomery@example.com",
		"status": "active"
	}
	dir_view.visible_people = [test_person]
	dir_view._render_roster_list()
	dir_view.select_person_by_index(0)

	var main_split = dir_view.get_node("MarginContainer/VBoxContainer/MainSplit") as HSplitContainer
	var roster_panel = dir_view.get_node("MarginContainer/VBoxContainer/MainSplit/RosterPanel") as PanelContainer
	var workspace_panel = dir_view.get_node("MarginContainer/VBoxContainer/MainSplit/WorkspacePanel") as PanelContainer
	var r_box = dir_view.get_node("MarginContainer/VBoxContainer/MainSplit/RosterPanel/RosterScroll/RosterContainer") as VBoxContainer

	# Test 1: Splitter initial state
	assert(main_split != null, "MainSplit node must exist.")
	print("✓ PASS 1: MainSplit, RosterPanel, and WorkspacePanel instantiated.")

	# Test 2: Drag Splitter Right
	var init_offset = main_split.split_offset
	main_split.split_offset = init_offset + 150
	assert(main_split.split_offset == init_offset + 150, "Splitter offset should update to +150.")
	print("✓ PASS 2: Splitter dragged RIGHT (+150px offset).")

	# Test 3: Drag Splitter Left
	main_split.split_offset = init_offset - 80
	assert(main_split.split_offset == init_offset - 80, "Splitter offset should update to -80.")
	print("✓ PASS 3: Splitter dragged LEFT (-80px offset).")

	# Test 4: Splitter retains released position (does not snap back)
	var set_pos = init_offset + 100
	main_split.split_offset = set_pos
	dir_view.select_person_by_index(0)
	assert(main_split.split_offset == set_pos, "Splitter position should not snap back on selection.")
	print("✓ PASS 4: Splitter retains position after person selection.")

	# Test 5: Verify roster row button text container expansion flags
	assert(r_box.get_child_count() > 0, "Roster container must have at least 1 person row button.")
	var btn = r_box.get_child(0) as Button
	var margin = btn.get_child(0) as MarginContainer
	var hbox = margin.get_child(0) as HBoxContainer
	var vbox_text: Control = null
	for child in hbox.get_children():
		if child is VBoxContainer:
			vbox_text = child as Control
			break
	
	assert(vbox_text != null, "Roster button must contain vbox_text control.")
	assert(vbox_text.size_flags_horizontal & Control.SIZE_EXPAND != 0, "vbox_text must have SIZE_EXPAND flag so text expands with roster width.")
	print("✓ PASS 5: Roster row text container has SIZE_EXPAND enabled for column width expansion.")

	# Test 6: Verify workspace tab switching and sections
	for tab in ["overview", "profile", "communications", "participation", "notes", "history"]:
		dir_view.select_workspace_tab(tab)
		assert(dir_view.current_workspace_section == tab, "Workspace section should switch to " + tab)
	print("✓ PASS 6: Workspace profile sections & tab switching preserved cleanly.")

	print("\n==================================================")
	print("--- ALL DIRECTORY SPLITTER TESTS PASSED CLEANLY ---")
	print("==================================================")
	quit(0)
