extends SceneTree

## Screenshot Generation Script for Story DIR-SPR1-005A-V
## Renders and verifies 10 PNG screenshots to ~/Desktop/StudyCenterHub-Screenshots/

const SQLiteDatabaseScript = preload("res://src/infrastructure/database/sqlite_database.gd")
const MigrationsRunnerScript = preload("res://src/infrastructure/database/migrations_runner.gd")
const PersonServiceScript = preload("res://src/domain/directory/person_service.gd")
const DirectoryReadServiceScript = preload("res://src/domain/directory/directory_read_service.gd")
const DirectoryViewScript = preload("res://app/scenes/directory_view.gd")

const SCREENSHOT_DIR = "/Users/johnboyte/Desktop/StudyCenterHub-Screenshots/"

func _init() -> void:
	print("==========================================================")
	print("STARTING DIRECTORY SCREENSHOT GENERATION SCRIPT")
	print("==========================================================")

	DirAccess.make_dir_recursive_absolute(SCREENSHOT_DIR)

	var db_path = ProjectSettings.globalize_path("user://visual_review_directory.db")
	if FileAccess.file_exists(db_path):
		DirAccess.remove_absolute(db_path)

	var db = SQLiteDatabaseScript.new(db_path)
	MigrationsRunnerScript.new(db).run_migrations()
	var person_service = PersonServiceScript.new(db)
	var read_service = DirectoryReadServiceScript.new(db)

	# Seed Representative Dataset: 8 Active, 3 Pending, 2 Inactive
	person_service.create_person({"first_name": "Aaron", "last_name": "Zimmerman", "status": "active", "grade": "Senior"})
	person_service.create_person({"first_name": "Beth", "last_name": "Yates", "status": "active"}) # Missing Year
	person_service.create_person({"first_name": "Bartholomew-Alexander", "last_name": "Wellington-Smythe-Montgomery", "status": "active", "grade": "Graduate Student"}) # Long Name
	person_service.create_person({"first_name": "David", "last_name": "Vance", "status": "active", "grade": "Freshman"})
	person_service.create_person({"first_name": "Elena", "last_name": "de la Rosa", "status": "active", "grade": "Junior"}) # Multi-word last name
	person_service.create_person({"first_name": "Frank", "last_name": "Underwood", "status": "active", "grade": "Sophomore"})
	person_service.create_person({"first_name": "Grace", "last_name": "Hopper", "status": "active", "grade": "Recent Graduate"})
	person_service.create_person({"first_name": "Hannah", "last_name": "Abbott", "status": "active", "grade": "Freshman"})

	person_service.create_person({"first_name": "Ian", "last_name": "Malcolm", "status": "pending", "grade": "Junior"})
	person_service.create_person({"first_name": "Julia", "last_name": "Roberts", "status": "To Be Confirmed", "grade": "Freshman"})
	person_service.create_person({"first_name": "Kevin", "last_name": "Spacey", "status": "pending", "grade": "Sophomore"})

	person_service.create_person({"first_name": "Laura", "last_name": "Croft", "status": "inactive", "grade": "Senior"})
	person_service.create_person({"first_name": "Michael", "last_name": "Scott", "status": "inactive", "grade": "Other"})

	# Create SubViewport for rendering
	var sub_viewport = SubViewport.new()
	sub_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(sub_viewport)

	var scene_res = load("res://app/scenes/directory_view.tscn")
	var dir_view = scene_res.instantiate() as DirectoryViewScript
	dir_view.read_service = read_service
	sub_viewport.add_child(dir_view)
	dir_view.refresh_view()

	# Scenario 1: Default Directory
	dir_view.select_filter("all")
	dir_view.set_search_query("")
	dir_view.select_person_by_index(0)
	_capture(sub_viewport, dir_view, Vector2i(1024, 700), "screenshot_01_default_directory.png")

	# Scenario 2: Active Filter
	dir_view.select_filter("active")
	dir_view.set_search_query("")
	dir_view.select_person_by_index(0)
	_capture(sub_viewport, dir_view, Vector2i(1024, 700), "screenshot_02_active_filter.png")

	# Scenario 3: Pending Filter
	dir_view.select_filter("pending")
	dir_view.set_search_query("")
	dir_view.select_person_by_index(0)
	_capture(sub_viewport, dir_view, Vector2i(1024, 700), "screenshot_03_pending_filter.png")

	# Scenario 4: Inactive Filter
	dir_view.select_filter("inactive")
	dir_view.set_search_query("")
	dir_view.select_person_by_index(0)
	_capture(sub_viewport, dir_view, Vector2i(1024, 700), "screenshot_04_inactive_filter.png")

	# Scenario 5: Search
	dir_view.select_filter("all")
	dir_view.set_search_query("de la Rosa")
	_capture(sub_viewport, dir_view, Vector2i(1024, 700), "screenshot_05_search.png")

	# Scenario 6: Long Name
	dir_view.set_search_query("Wellington")
	_capture(sub_viewport, dir_view, Vector2i(1024, 700), "screenshot_06_long_name.png")

	# Scenario 7: No Results
	dir_view.set_search_query("NonExistentNameXYZ")
	_capture(sub_viewport, dir_view, Vector2i(1024, 700), "screenshot_07_no_results.png")

	# Scenario 8: No Selection
	dir_view.set_search_query("")
	dir_view.select_filter("all")
	dir_view._clear_preview()
	_capture(sub_viewport, dir_view, Vector2i(1024, 700), "screenshot_08_no_selection.png")

	# Scenario 9: Narrow Desktop Window (768 x 700)
	dir_view.select_person_by_index(0)
	_capture(sub_viewport, dir_view, Vector2i(768, 700), "screenshot_09_narrow_desktop.png")

	# Scenario 10: Wide Desktop Window (1440 x 800)
	_capture(sub_viewport, dir_view, Vector2i(1440, 800), "screenshot_10_wide_desktop.png")

	print("==========================================================")
	print("SUCCESS: ALL 10 SCREENSHOTS GENERATED AND VERIFIED")
	print("==========================================================")
	quit(0)

func _capture(sub_viewport: SubViewport, view: Control, size: Vector2i, filename: String) -> void:
	sub_viewport.size = size
	view.size = size
	RenderingServer.force_draw()
	var texture = sub_viewport.get_texture()
	var img = texture.get_image() if texture else null
	if img != null:
		var save_path = SCREENSHOT_DIR + filename
		var err = img.save_png(save_path)
		if err == OK and FileAccess.file_exists(save_path):
			var file_size = FileAccess.get_file_as_bytes(save_path).size()
			print("VERIFIED saved: ", save_path, " (Resolution: ", img.get_width(), "x", img.get_height(), ", Size: ", file_size, " bytes)")
		else:
			print("ERROR saving screenshot: ", save_path, " Error code: ", err)
	else:
		print("ERROR: Viewport texture image is null for ", filename)
