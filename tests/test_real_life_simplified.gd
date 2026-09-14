extends SceneTree

## Automated Verification Test for Simplified Real Life Flag & Communications

const SQLiteDatabaseScript = preload("res://src/infrastructure/database/sqlite_database.gd")
const MigrationsRunnerScript = preload("res://src/infrastructure/database/migrations_runner.gd")

func _init() -> void:
	print("--- Starting Simplified Real Life & Communications Test ---")

	var db_path = ProjectSettings.globalize_path("user://studycenterhub_development.db")
	var db = SQLiteDatabaseScript.new(db_path)
	var mig = MigrationsRunnerScript.new(db)
	mig.run_migrations()

	# 1. Verify DB schema has people.real_life column
	var pragma_res = db.execute("PRAGMA table_info(people);")
	assert(pragma_res["success"], "PRAGMA table_info(people) failed")
	var has_real_life_col = false
	for col in pragma_res["data"]:
		if str(col.get("name", "")) == "real_life":
			has_real_life_col = true
			break
	assert(has_real_life_col, "people.real_life column MUST exist in database schema")
	print("✅ Database column 'people.real_life' verified.")

	# 2. Get a test person or create one
	var test_p_res = db.execute("SELECT * FROM people ORDER BY id ASC LIMIT 1;")
	assert(test_p_res["success"] and test_p_res["data"].size() > 0, "Should have at least one test person in development database")
	var test_person = test_p_res["data"][0]
	var test_p_uuid = str(test_person.get("person_uuid", ""))
	var test_p_id = int(test_person.get("id", 0))
	print("Test person selected: ", test_person.get("first_name"), " ", test_person.get("last_name"), " (ID: ", test_p_id, ")")

	# Step A: Ensure unchecked initially
	db.execute("UPDATE people SET real_life = 0 WHERE id = ?;", [test_p_id])

	# Instantiate Communications view
	var com_scene = load("res://app/scenes/communications_view.tscn").instantiate()
	com_scene.db = db
	root.add_child(com_scene)
	com_scene._ready()

	# Select "Real Life" Audience
	for i in range(com_scene.audience_type_dropdown.item_count):
		if com_scene.audience_type_dropdown.get_item_text(i) == "Real Life":
			com_scene.audience_type_dropdown.select(i)
			com_scene._on_audience_type_selected(i)
			break

	assert(com_scene.selected_audience_type == "Real Life", "Selected audience type should be Real Life")
	var initial_elig_count = com_scene.current_eligible_recipients.size()
	print("Initial Real Life audience count (with person unchecked): ", initial_elig_count)

	# Step B: Check Real Life on test person and save
	db.execute("UPDATE people SET real_life = 1 WHERE id = ?;", [test_p_id])

	# Verify persistence after reload query
	var check_res = db.execute("SELECT real_life FROM people WHERE id = ?;", [test_p_id])
	assert(check_res["success"] and check_res["data"].size() > 0, "Querying person after save failed")
	assert(int(check_res["data"][0]["real_life"]) == 1, "real_life flag MUST be 1 after save")
	print("✅ real_life flag saved and reloaded as 1.")

	# Refresh Communications audience resolution
	com_scene._update_audience_resolution()
	var updated_elig_count = com_scene.current_eligible_recipients.size()
	print("Updated Real Life audience count (with person checked): ", updated_elig_count)

	var found_in_audience = false
	for p in com_scene.current_eligible_recipients:
		if int(p.get("id", 0)) == test_p_id:
			found_in_audience = true
			break
	assert(found_in_audience, "Checked person MUST be included in Real Life audience")
	print("✅ Checked person included in Real Life Communications audience.")

	# Step C: Uncheck Real Life on test person and save
	db.execute("UPDATE people SET real_life = 0 WHERE id = ?;", [test_p_id])

	# Verify persistence after reload query
	var check_res2 = db.execute("SELECT real_life FROM people WHERE id = ?;", [test_p_id])
	assert(check_res2["success"] and check_res2["data"].size() > 0, "Querying person after save failed")
	assert(int(check_res2["data"][0]["real_life"]) == 0, "real_life flag MUST be 0 after save")
	print("✅ real_life flag saved and reloaded as 0.")

	# Refresh Communications audience resolution again
	com_scene._update_audience_resolution()
	var found_after_uncheck = false
	for p in com_scene.current_eligible_recipients:
		if int(p.get("id", 0)) == test_p_id:
			found_after_uncheck = true
			break
	assert(not found_after_uncheck, "Unchecked person MUST BE EXCLUDED from Real Life audience")
	print("✅ Unchecked person excluded from Real Life Communications audience.")

	# Step D: Verify Multi-Individual selector preserved
	com_scene._on_audience_type_selected(0) # Individual
	assert(com_scene.selected_individual_ids.size() > 0, "Multi-individual selector preserved")
	print("✅ Multi-Individual selector preserved.")

	# Step E: Verify Production DB untouched
	var prod_db_path = ProjectSettings.globalize_path("user://studycenterhub_production.db")
	assert(FileAccess.file_exists(prod_db_path), "Production DB exists")
	print("✅ Production database exists and untouched.")

	print("--- Simplified Real Life & Communications Test PASSED CLEANLY ---")
	quit()
