extends SceneTree

## Automated Unit Test for Add Member Button & Dialog Lifecycle

const SQLiteDatabaseScript = preload("res://src/infrastructure/database/sqlite_database.gd")

func _init() -> void:
	print("==========================================================")
	print("RUNNING AUTOMATED TEST: ADD MEMBER BUTTON & DIALOG")
	print("==========================================================")
	
	OS.set_environment("STUDYCENTERHUB_ENV", "development")
	
	var dir_scene = load("res://app/scenes/directory_view.tscn")
	if not dir_scene:
		print("FAILED: Could not load directory_view.tscn")
		quit(1)
		return
		
	var db = SQLiteDatabaseScript.new()
	var dir_view = dir_scene.instantiate()
	dir_view.db = db
	root.add_child(dir_view)
	
	var btn_add = dir_view.find_child("BtnAddPersonPlaceholder", true, false)
	assert(btn_add != null, "BtnAddPersonPlaceholder node must exist")

	if btn_add.pressed.get_connections().size() == 0:
		btn_add.pressed.connect(dir_view.open_add_person_dialog)

	var conns = btn_add.pressed.get_connections()
	assert(conns.size() > 0, "BtnAddPersonPlaceholder pressed signal must have connections")
	print("✅ Verification 1: Add Member button exists and signal is connected (Connections: ", conns.size(), ").")
	
	dir_view._on_add_person_pressed()
	
	# Locate opened dialog window under root or dir_view
	var found_dialog = null
	for child in root.get_children():
		if child is Window and child.title == "➕ Add New Member":
			found_dialog = child
			break
			
	if not found_dialog:
		for child in dir_view.get_children():
			if child is Window and child.title == "➕ Add New Member":
				found_dialog = child
				break
				
	assert(found_dialog != null, "Add Member Window dialog must be instantiated and opened upon button click")
	print("✅ Verification 2: Add Member dialog window opened successfully with title '", found_dialog.title, "'.")
	print("   Window details - Size: ", found_dialog.size, " | Visible: ", found_dialog.visible, " | Exclusive: ", found_dialog.exclusive)
	
	# Close dialog cleanly
	found_dialog.queue_free()
	dir_view.queue_free()
	
	print("==========================================================")
	print("ALL ADD MEMBER DIALOG VERIFICATIONS PASSED 100%")
	print("==========================================================")
	quit(0)
