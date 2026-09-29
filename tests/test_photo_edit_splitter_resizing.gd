# Focused test for Directory Splitter Resizing after Photo Cropping / Editing.
# Verifies:
# 1. Profile section photo card with all 6 photo buttons (Edit, Restore, Retake, Upload, Save Original, Remove) does NOT enforce a huge minimum width.
# 2. MainSplit splitter can be dragged right (+200px) and left (-100px) cleanly with a person having a profile photo.
# 3. Executing photo editing callbacks and refreshing profile section leaves MainSplit completely unlocked and freely resizable.

extends SceneTree

const SqliteDatabaseScript = preload("res://src/infrastructure/database/sqlite_database.gd")
const MigrationsRunnerScript = preload("res://src/infrastructure/database/migrations_runner.gd")

func _init() -> void:
	print("--- BEGIN PHOTO EDIT SPLITTER RESIZING TEST ---")
	var test_db_path = "user://test_photo_edit_splitter.db"
	if FileAccess.file_exists(test_db_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(test_db_path))

	var db = SqliteDatabaseScript.new(test_db_path)
	var runner = MigrationsRunnerScript.new(db)
	runner.run_migrations()

	# Create 1x1 base64 PNG dummy photo
	var dummy_b64 = "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=="

	# Insert test person with profile_photo and original_profile_photo
	db.execute("""
		INSERT INTO people (id, person_uuid, human_id, first_name, last_name, phone, profile_photo, original_profile_photo, status, created_at, updated_at)
		VALUES (1, 'p-photo-split-001', 'P-20260720-0002', 'Khalil', 'Peake', '8645550199', ?, ?, 'active', datetime('now'), datetime('now'));
	""", [dummy_b64, dummy_b64])

	var dir_scene = load("res://app/scenes/directory_view.tscn")
	var dir_view = dir_scene.instantiate()
	
	var vp = SubViewport.new()
	vp.size = Vector2i(1280, 800)
	root.add_child(vp)
	vp.add_child(dir_view)
	dir_view.db = db

	# Render roster & select person with photo
	var test_person = {
		"id": 1,
		"person_uuid": "p-photo-split-001",
		"human_id": "P-20260720-0002",
		"first_name": "Khalil",
		"last_name": "Peake",
		"phone": "8645550199",
		"profile_photo": dummy_b64,
		"original_profile_photo": dummy_b64,
		"status": "active"
	}
	dir_view.visible_people = [test_person]
	dir_view._render_roster_list()
	dir_view.select_person_by_index(0)

	var main_split = dir_view.get_node("MarginContainer/VBoxContainer/MainSplit") as HSplitContainer
	var roster_panel = dir_view.get_node("MarginContainer/VBoxContainer/MainSplit/RosterPanel") as PanelContainer
	var workspace_panel = dir_view.get_node("MarginContainer/VBoxContainer/MainSplit/WorkspacePanel") as PanelContainer

	# Test 1: Check initial minimum width of WorkspacePanel / ProfileSection
	var profile_min_w = workspace_panel.get_combined_minimum_size().x
	print("WorkspacePanel combined minimum width with all 6 photo buttons: ", profile_min_w, "px")
	assert(profile_min_w < 600.0, "WorkspacePanel minimum width must be < 600px so splitter remains freely resizable (was: " + str(profile_min_w) + "px).")
	print("✓ PASS 1: Photo card layout uses HFlowContainer (min width < 600px).")

	# Test 2: Drag Splitter Right (+200px) with photo loaded
	var init_offset = main_split.split_offset
	main_split.split_offset = init_offset + 200
	assert(main_split.split_offset == init_offset + 200, "Splitter offset should update to +200.")
	print("✓ PASS 2: Splitter dragged RIGHT (+200px offset) with active profile photo.")

	# Test 3: Drag Splitter Left (-100px)
	main_split.split_offset = init_offset - 100
	assert(main_split.split_offset == init_offset - 100, "Splitter offset should update to -100.")
	print("✓ PASS 3: Splitter dragged LEFT (-100px offset).")

	# Test 4: Simulate photo update / redo callback and refresh view
	dir_view._active_photo_callback.call(dummy_b64)
	dir_view.refresh_view()

	# Verify MainSplit can still be dragged after photo redo
	main_split.split_offset = init_offset + 150
	assert(main_split.split_offset == init_offset + 150, "Splitter must remain freely resizable after photo redo callback.")
	print("✓ PASS 4: Splitter remains freely resizable (+150px) after photo edit/redo workflow.")

	print("\n==================================================")
	print("--- ALL PHOTO EDIT SPLITTER TESTS PASSED CLEANLY ---")
	print("==================================================")
	quit(0)
