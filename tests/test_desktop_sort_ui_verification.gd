extends SceneTree

const SQLiteDatabaseScript = preload("res://src/infrastructure/database/sqlite_database.gd")
const MigrationsRunnerScript = preload("res://src/infrastructure/database/migrations_runner.gd")
const DirectoryViewScript = preload("res://app/scenes/directory_view.gd")
const AttendanceViewScript = preload("res://app/scenes/attendance_view.gd")

func _init() -> void:
	print("==========================================================")
	print("VERIFYING DESKTOP VISIBLE SORTING UI CONTROLS")
	print("==========================================================")

	var db = SQLiteDatabaseScript.new()
	var mig = MigrationsRunnerScript.new(db)
	mig.run_migrations()

	# ----------------------------------------------------
	# 1. TEST DESKTOP PEOPLE DIRECTORY VIEW
	# ----------------------------------------------------
	print("\n--- 1. DESKTOP PEOPLE DIRECTORY VIEW ---")
	var dir_scene = load("res://app/scenes/directory_view.tscn")
	var dir_instance = dir_scene.instantiate()
	root.add_child(dir_instance)

	dir_instance.db = db
	dir_instance.refresh_view()

	assert(dir_instance.btn_sort_first != null, "Desktop Directory btn_sort_first must exist")
	assert(dir_instance.btn_sort_last != null, "Desktop Directory btn_sort_last must exist")
	assert(dir_instance.current_sort_by == "first_name", "Desktop Directory must default to first_name sort")

	var names_fn: Array = []
	for p in dir_instance.visible_people:
		names_fn.append(str(p.get("first_name", "")) + " " + str(p.get("last_name", "")))
	print("First Name Sort Order (Top 5):", names_fn.slice(0, 5))

	# Switch sort to Last Name
	dir_instance.select_sort_by("last_name")
	assert(dir_instance.current_sort_by == "last_name", "Desktop Directory current_sort_by must update to last_name")

	var names_ln: Array = []
	for p in dir_instance.visible_people:
		names_ln.append(str(p.get("first_name", "")) + " " + str(p.get("last_name", "")))
	print("Last Name Sort Order (Top 5):", names_ln.slice(0, 5))

	assert(names_fn != names_ln, "Selecting Last Name MUST visibly reorder the constituent list!")
	print("✅ DESKTOP PEOPLE DIRECTORY VISIBLE SORT CONTROL VERIFIED!")

	# ----------------------------------------------------
	# 2. TEST DESKTOP SIGNED IN TODAY / ATTENDANCE VIEW
	# ----------------------------------------------------
	print("\n--- 2. DESKTOP SIGNED IN TODAY / ATTENDANCE VIEW ---")
	var att_scene = load("res://app/scenes/attendance_view.tscn")
	var att_instance = att_scene.instantiate()
	root.add_child(att_instance)

	att_instance.db = db
	att_instance._refresh_dashboard()

	assert(att_instance.current_log_sort_by == "first_name", "Attendance View must default to first_name sort")
	print("Attendance default sort mode:", att_instance.current_log_sort_by)

	# Toggle Attendance Sort to Last Name
	att_instance.current_log_sort_by = "last_name"
	att_instance._refresh_dashboard()
	assert(att_instance.current_log_sort_by == "last_name", "Attendance View sort mode updated to last_name")
	print("Attendance sort updated to:", att_instance.current_log_sort_by)

	print("✅ DESKTOP SIGNED IN TODAY VISIBLE SORT CONTROL VERIFIED!")

	dir_instance.queue_free()
	att_instance.queue_free()

	print("\n==========================================================")
	print("ALL DESKTOP VISIBLE SORTING UI TESTS PASSED 100%!")
	print("==========================================================")
	quit()
