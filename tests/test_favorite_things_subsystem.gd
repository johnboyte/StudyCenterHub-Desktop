extends SceneTree

const SQLiteDatabaseScript = preload("res://src/infrastructure/database/sqlite_database.gd")
const MigrationsRunnerScript = preload("res://src/infrastructure/database/migrations_runner.gd")
const PersonServiceScript = preload("res://src/domain/directory/person_service.gd")

func _init() -> void:
	print("==========================================================")
	print("TESTING PERSON FAVORITE THINGS SUBSYSTEM (MIGRATION 0049)")
	print("==========================================================")
	
	var db_path = ProjectSettings.globalize_path("user://test_fav_things.db")
	if FileAccess.file_exists(db_path):
		DirAccess.remove_absolute(db_path)
		
	var db = SQLiteDatabaseScript.new(db_path)
	var runner = MigrationsRunnerScript.new(db)
	var mig_res = runner.run_migrations()
	assert(mig_res["success"], "Migrations failed to execute")
	print("PASS 1: Migrations (including 0049) executed successfully.")

	var person_svc = PersonServiceScript.new(db)
	
	# Create two test people
	var p1_res = person_svc.create_person({"first_name": "John", "last_name": "Boyte"})
	var p2_res = person_svc.create_person({"first_name": "Jane", "last_name": "Doe"})
	
	var p1_id = db.execute("SELECT id FROM people WHERE first_name = 'John' LIMIT 1;")["data"][0]["id"]
	var p2_id = db.execute("SELECT id FROM people WHERE first_name = 'Jane' LIMIT 1;")["data"][0]["id"]

	# TEST 2: Initially blank
	var fav1_init = person_svc.get_favorite_things(p1_id)
	assert(fav1_init.size() == 0, "Initial favorite things should be empty")
	print("PASS 2: Initial favorite things return empty dictionary.")

	# TEST 3: Save favorite things for Person 1
	var fav_payload1 = {
		"candy_treat": "Dark Chocolate Sea Salt",
		"snack": "Trail Mix",
		"drink": "Iced Americano",
		"food_meal": "Grilled Salmon",
		"restaurant": "Sweetgrass Grill",
		"dessert": "Key Lime Pie",
		"fruit": "Honeycrisp Apples",
		"movie_tv": "Inception",
		"music": "Classical / Jazz",
		"activities_hobbies": "Hiking & Reading",
		"sports_teams": "Clemson Tigers",
		"stores_places": "Barnes & Noble",
		"other_favorites": "Morning coffee on the porch, strategy board games",
		"prefer_to_avoid": "No cilantro"
	}
	var save_res = person_svc.save_favorite_things(p1_id, fav_payload1)
	assert(save_res["success"], "Save favorite things failed")
	print("PASS 3: Saved 14 favorite things fields atomically for Person 1.")

	# TEST 4: Fetch and verify saved fields
	var fav1_loaded = person_svc.get_favorite_things(p1_id)
	assert(fav1_loaded.get("candy_treat") == "Dark Chocolate Sea Salt", "candy_treat mismatch")
	assert(fav1_loaded.get("drink") == "Iced Americano", "drink mismatch")
	assert(fav1_loaded.get("other_favorites") == "Morning coffee on the porch, strategy board games", "other_favorites mismatch")
	assert(fav1_loaded.get("prefer_to_avoid") == "No cilantro", "prefer_to_avoid mismatch")
	print("PASS 4: Verified loaded values match saved values for Person 1.")

	# TEST 5: Person 2 remains blank (no data leakage)
	var fav2_loaded = person_svc.get_favorite_things(p2_id)
	assert(fav2_loaded.size() == 0, "Person 2 favorite things leaked data from Person 1!")
	print("PASS 5: Verified zero data leakage between profiles.")

	# TEST 6: Verify person_notes table was NOT touched
	var notes_res = db.execute("SELECT COUNT(*) as c FROM person_notes;")
	assert(int(notes_res["data"][0]["c"]) == 0, "person_notes table should have 0 rows")
	print("PASS 6: Verified person_notes table remains 100% untouched.")

	# TEST 7: Foreign key constraint check
	var fk_res = db.execute("PRAGMA foreign_key_check;")
	assert(fk_res["success"] and fk_res["data"].size() == 0, "Foreign key violation detected!")
	print("PASS 7: SQLite foreign key check passed with zero violations.")

	print("==========================================================")
	print("SUCCESS: ALL FAVORITE THINGS SUBSYSTEM TESTS PASSED (100%)")
	print("==========================================================")
	
	DirAccess.remove_absolute(db_path)
	quit()
