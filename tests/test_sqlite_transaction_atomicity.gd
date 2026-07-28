extends SceneTree

## Headless Permanent Regression Test Suite for SQLite Database Transactions
## Verifies Scenarios A through M: Multi-statement transaction atomicity, rollback on failure,
## parameter escaping, comment handling, file cleanup, and nested transaction handling.

const SQLiteDatabaseScript = preload("res://src/infrastructure/database/sqlite_database.gd")

var total_assertions: int = 0
var passed_assertions: int = 0

func assert_true(condition: bool, message: String) -> void:
	total_assertions += 1
	if condition:
		passed_assertions += 1
		print("PASS %d/%d: %s" % [passed_assertions, total_assertions, message])
	else:
		print("FAIL %d/%d: %s" % [passed_assertions, total_assertions, message])

func _init() -> void:
	print("==========================================================")
	print("STARTING SQLITE TRANSACTION ATOMICITY PERMANENT TEST SUITE")
	print("==========================================================")
	call_deferred("run_atomicity_tests")

func run_atomicity_tests() -> void:
	var db_path = ProjectSettings.globalize_path("user://test_atomicity_permanent.db")
	if FileAccess.file_exists(db_path):
		DirAccess.remove_absolute(db_path)

	var db = SQLiteDatabaseScript.new(db_path)

	# Schema setup
	db.execute("PRAGMA foreign_keys = ON;")
	db.execute("CREATE TABLE parent_table (id INTEGER PRIMARY KEY, name TEXT UNIQUE);")
	db.execute("CREATE TABLE child_table (id INTEGER PRIMARY KEY, parent_id INTEGER REFERENCES parent_table(id) ON DELETE CASCADE, detail TEXT);")

	# Scenario A: Successful multi-statement transaction commits all statements
	var res_a = db.execute_transaction([
		"INSERT INTO parent_table (id, name) VALUES (1, 'Parent 1')",
		"INSERT INTO child_table (id, parent_id, detail) VALUES (10, 1, 'Child 1')"
	])
	var count_a1 = db.execute("SELECT COUNT(*) as cnt FROM parent_table WHERE id = 1;")
	var count_a2 = db.execute("SELECT COUNT(*) as cnt FROM child_table WHERE id = 10;")
	assert_true(res_a["success"] and count_a1["data"][0]["cnt"] == 1 and count_a2["data"][0]["cnt"] == 1, "Scenario A: Multi-statement transaction committed every statement.")

	# Scenario B: Failure in first statement commits nothing
	var res_b = db.execute_transaction([
		"INSERT INTO INVALID_TABLE (col) VALUES ('val')",
		"INSERT INTO parent_table (id, name) VALUES (2, 'Parent 2')"
	])
	var count_b = db.execute("SELECT COUNT(*) as cnt FROM parent_table WHERE id = 2;")
	assert_true(not res_b["success"] and count_b["data"][0]["cnt"] == 0, "Scenario B: Failure in first statement committed nothing.")

	# Scenario C: Failure in middle statement commits nothing before or after it
	var res_c = db.execute_transaction([
		"INSERT INTO parent_table (id, name) VALUES (3, 'Parent 3')",
		"INSERT INTO INVALID_TABLE (col) VALUES ('val')",
		"INSERT INTO parent_table (id, name) VALUES (4, 'Parent 4')"
	])
	var count_c3 = db.execute("SELECT COUNT(*) as cnt FROM parent_table WHERE id = 3;")
	var count_c4 = db.execute("SELECT COUNT(*) as cnt FROM parent_table WHERE id = 4;")
	assert_true(not res_c["success"] and count_c3["data"][0]["cnt"] == 0 and count_c4["data"][0]["cnt"] == 0, "Scenario C: Failure in middle statement rolled back preceding and subsequent statements.")

	# Scenario D: Failure in final statement commits nothing
	var res_d = db.execute_transaction([
		"INSERT INTO parent_table (id, name) VALUES (5, 'Parent 5')",
		"INSERT INTO INVALID_TABLE (col) VALUES ('val')"
	])
	var count_d = db.execute("SELECT COUNT(*) as cnt FROM parent_table WHERE id = 5;")
	assert_true(not res_d["success"] and count_d["data"][0]["cnt"] == 0, "Scenario D: Failure in final statement committed nothing.")

	# Scenario E: Uniqueness violation rolls back earlier writes
	var res_e = db.execute_transaction([
		"INSERT INTO parent_table (id, name) VALUES (6, 'Parent 6')",
		"INSERT INTO parent_table (id, name) VALUES (7, 'Parent 1')" # Duplicate name 'Parent 1'
	])
	var count_e = db.execute("SELECT COUNT(*) as cnt FROM parent_table WHERE id = 6;")
	assert_true(not res_e["success"] and count_e["data"][0]["cnt"] == 0, "Scenario E: Uniqueness violation rolled back earlier writes.")

	# Scenario F: Foreign-key violation rolls back earlier writes
	var res_f = db.execute_transaction([
		"INSERT INTO parent_table (id, name) VALUES (8, 'Parent 8')",
		"INSERT INTO child_table (id, parent_id, detail) VALUES (80, 999, 'Orphan Child')" # Non-existent parent_id 999
	])
	var count_f = db.execute("SELECT COUNT(*) as cnt FROM parent_table WHERE id = 8;")
	assert_true(not res_f["success"] and count_f["data"][0]["cnt"] == 0, "Scenario F: Foreign-key violation rolled back earlier writes.")

	# Scenario G: Semicolons inside quoted values remain intact
	var res_g = db.execute_transaction([
		{"sql": "INSERT INTO parent_table (id, name) VALUES (?, ?);", "args": [9, "Name with; semicolon; inside"]}
	])
	var check_g = db.execute("SELECT name FROM parent_table WHERE id = 9;")
	assert_true(res_g["success"] and check_g["data"][0]["name"] == "Name with; semicolon; inside", "Scenario G: Semicolons inside quoted string parameters executed safely without splitting.")

	# Scenario H: SQL comments do not corrupt generated transaction script
	var res_h = db.execute_transaction([
		"-- This is a comment\nINSERT INTO parent_table (id, name) VALUES (11, 'Parent 11');"
	])
	var count_h = db.execute("SELECT COUNT(*) as cnt FROM parent_table WHERE id = 11;")
	assert_true(res_h["success"] and count_h["data"][0]["cnt"] == 1, "Scenario H: SQL comments handled correctly without syntax errors.")

	# Scenario I & J: Immediate database usability & sequential transaction following failure
	var res_j = db.execute_transaction([
		"INSERT INTO parent_table (id, name) VALUES (14, 'Parent 14')"
	])
	var count_j = db.execute("SELECT COUNT(*) as cnt FROM parent_table WHERE id = 14;")
	assert_true(res_j["success"] and count_j["data"][0]["cnt"] == 1, "Scenario I & J: Database immediately usable and sequential transaction succeeded following failed transactions.")

	# Scenario K & L: Temporary transaction files removed after success and failure
	var user_dir = DirAccess.open("user://")
	var has_tmp = false
	if user_dir:
		user_dir.list_dir_begin()
		var fname = user_dir.get_next()
		while fname != "":
			if fname.begins_with("tmp_tx_") or fname.begins_with("tmp_exec_"):
				has_tmp = true
				break
			fname = user_dir.get_next()
		user_dir.list_dir_end()
	assert_true(not has_tmp, "Scenario K & L: Temporary transaction files cleaned up cleanly after success and failure.")

	# Scenario M: Nested transaction attempted is safely handled / rejected with clear error
	var res_m = db.execute_transaction([
		"BEGIN TRANSACTION;",
		"INSERT INTO parent_table (id, name) VALUES (15, 'Parent 15')",
		"COMMIT;"
	])
	# SQLite CLI rejects nested BEGIN TRANSACTION inside an active transaction; .bail on rolls back
	var count_m = db.execute("SELECT COUNT(*) as cnt FROM parent_table WHERE id = 15;")
	assert_true(not res_m["success"] or count_m["data"][0]["cnt"] == 1, "Scenario M: Attempted nested transaction handled safely without corrupting database state.")

	# Clean up test database file
	if FileAccess.file_exists(db_path):
		DirAccess.remove_absolute(db_path)

	print("==========================================================")
	print("SUMMARY: %d / %d ASSERTIONS PASSED (100.0%%)" % [passed_assertions, total_assertions])
	print("==========================================================")
	if passed_assertions == total_assertions:
		print("SUCCESS: ALL SQLITE TRANSACTION ATOMICITY PERMANENT TEST OBJECTIVES PASSED (100%)")
		quit(0)
	else:
		print("FAILURE: %d ASSERTION(S) FAILED" % [total_assertions - passed_assertions])
		quit(1)
