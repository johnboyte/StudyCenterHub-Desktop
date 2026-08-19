extends SceneTree

## Diagnostic Script to Reproduce & Identify Root Cause of Blank Notes & Tasks Tab

const SQLiteDatabaseScript = preload("res://src/infrastructure/database/sqlite_database.gd")

func _init() -> void:
	print("\n============================================================")
	print("  DIAGNOSING BLANK NOTES & TASKS TAB RENDER PATH")
	print("============================================================\n")

	call_deferred("diagnose")

func diagnose() -> void:
	var db_path = ProjectSettings.globalize_path("user://studycenterhub_development.db")
	if not FileAccess.file_exists(db_path):
		db_path = ProjectSettings.globalize_path("user://test_spelling_and_sync.db")

	var db = SQLiteDatabaseScript.new(db_path)

	print("Preloading spelling_assistance_helper.gd directly...")
	var helper_script = load("res://src/ui/components/spelling_assistance_helper.gd")
	print("Loaded helper_script: ", helper_script)
	if helper_script:
		var inst = helper_script.new()
		print("Instantiated helper script cleanly: ", inst)

	# Instantiate directory_view.tscn
	var scene = load("res://app/scenes/directory_view.tscn")
	assert(scene != null, "directory_view.tscn failed to load")
	var view = scene.instantiate()
	root.add_child(view)
	view.db = db

	# Fetch person
	var p_res = db.execute("SELECT * FROM people LIMIT 1;")
	assert(p_res["success"] and p_res["data"].size() > 0, "No person in DB")
	var p = p_res["data"][0]

	print("Testing constituent: %s %s (UUID: %s)" % [p.get("first_name", ""), p.get("last_name", ""), p.get("person_uuid", "")])

	# Assign notes_section container
	var notes_container = VBoxContainer.new()
	view.notes_section = notes_container

	print("Calling view._populate_notes_section(p)...")
	view._populate_notes_section(p)

	print("Children added to notes_section: ", notes_container.get_child_count())
	for i in range(notes_container.get_child_count()):
		var child = notes_container.get_child(i)
		print("  Child %d: %s (Class: %s, Name: %s)" % [i, child.to_string(), child.get_class(), child.name])

	assert(notes_container.get_child_count() > 0, "ERROR: notes_section HAS 0 CHILDREN! IT IS COMPLETELY BLANK!")

	print("\n============================================================")
	print("  DIAGNOSTIC PASSED: notes_section rendered %d cards cleanly." % notes_container.get_child_count())
	print("============================================================\n")
	quit(0)
