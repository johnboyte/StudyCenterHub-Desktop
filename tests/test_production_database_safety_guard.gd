extends SceneTree

## Dedicated Suite for Production Database Safety Guard & Read-Only Audit Verification

const SQLiteDatabaseScript = preload("res://src/infrastructure/database/sqlite_database.gd")

func _init() -> void:
	print("\n============================================================")
	print("  RUNNING PRODUCTION DATABASE SAFETY GUARD TEST SUITE")
	print("============================================================\n")

	call_deferred("run_all_tests")

func run_all_tests() -> void:
	# Test A: Mutating query operates normally on isolated test database
	var test_db_path = ProjectSettings.globalize_path("user://test_safety_guard_isolated.db")
	if FileAccess.file_exists(test_db_path):
		DirAccess.remove_absolute(test_db_path)

	var test_db = SQLiteDatabaseScript.new(test_db_path)
	var create_res = test_db.execute("CREATE TABLE IF NOT EXISTS safety_test (id INTEGER PRIMARY KEY, val TEXT);")
	assert(create_res["success"], "Failed CREATE on isolated test DB")
	
	var insert_res = test_db.execute("INSERT INTO safety_test (val) VALUES ('isolated_test_value');")
	assert(insert_res["success"], "Failed INSERT on isolated test DB")
	print("✓ PASS A: Mutating queries executed cleanly on isolated test DB.")

	# Test B: Mutating query REFUSED when pointed at Production database path
	var prod_db_path = ProjectSettings.globalize_path("user://studycenterhub_production.db")
	assert(FileAccess.file_exists(prod_db_path), "Production DB missing for safety test!")
	
	var prod_db = SQLiteDatabaseScript.new(prod_db_path)
	var refused_res = prod_db.execute("INSERT INTO people (person_uuid, first_name) VALUES ('test_fail_uuid', 'SafetyTest');")
	assert(not refused_res["success"], "Production mutating query was NOT refused!")
	assert(str(refused_res.get("error", "")).contains("HARD SAFETY GUARD"), "Expected HARD SAFETY GUARD error for Production mutation!")
	print("✓ PASS B: Hard safety guard successfully REFUSED mutating query on Production DB!")

	# Test C & D: Verify Production DB SHA-256 hash before & after running verify_production_deployment.gd
	var hash_before = _get_file_hash(prod_db_path)
	
	# Execute read-only verify_production_deployment logic
	var p_res = prod_db.execute("SELECT id FROM people LIMIT 1;")
	assert(p_res["success"], "Failed read query")
	var n_res = prod_db.execute("SELECT count(*) FROM person_notes;")
	assert(n_res["success"], "Failed read query")
	var t_res = prod_db.execute("SELECT count(*) FROM staff_tasks_index;")
	assert(t_res["success"], "Failed read query")
	
	var hash_after = _get_file_hash(prod_db_path)
	assert(hash_before == hash_after, "Production DB hash changed during read-only verification!")
	print("✓ PASS C & D: Read-Only verification performed zero writes and left Production DB SHA-256 hash 100% unchanged.")

	print("\n============================================================")
	print("  SUCCESS: ALL PRODUCTION DATABASE SAFETY GUARD TESTS PASSED (100%)")
	print("============================================================\n")
	quit(0)

func _get_file_hash(path: String) -> String:
	var f = FileAccess.open(path, FileAccess.READ)
	if not f:
		return ""
	var ctx = HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	while f.get_position() < f.get_length():
		var chunk = f.get_buffer(min(f.get_length() - f.get_position(), 65536))
		ctx.update(chunk)
	return ctx.finish().hex_encode()
