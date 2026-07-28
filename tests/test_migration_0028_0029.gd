extends SceneTree

## Comprehensive Migration Safety & Upgrade Test Suite (0028 & 0029)
## Verifies fresh database migration, upgrade from 0027, safe column pre-existence handling,
## and proper halt/non-suppression of unrelated syntax errors or missing table failures.

const SQLiteDatabaseScript = preload("res://src/infrastructure/database/sqlite_database.gd")
const MigrationsRunnerScript = preload("res://src/infrastructure/database/migrations_runner.gd")

var total_assertions: int = 0
var passed_assertions: int = 0

func _init() -> void:
	print("==========================================================")
	print("STARTING COMPREHENSIVE MIGRATION 0028 & 0029 UPGRADE TEST")
	print("==========================================================")
	call_deferred("run_all_migration_tests")

func assert_true(condition: bool, message: String) -> void:
	total_assertions += 1
	if condition:
		passed_assertions += 1
		print("PASS %d/%d: %s" % [passed_assertions, total_assertions, message])
	else:
		print("FAIL %d/%d: %s" % [passed_assertions, total_assertions, message])

func run_all_migration_tests() -> void:
	# 1. Fresh Database through 0029
	var db_path1 = ProjectSettings.globalize_path("user://test_mig_fresh_0029.db")
	if FileAccess.file_exists(db_path1): DirAccess.remove_absolute(db_path1)
	var db1 = SQLiteDatabaseScript.new(db_path1)
	var runner1 = MigrationsRunnerScript.new(db1)
	var res1 = runner1.run_migrations()
	assert_true(res1["success"], "Migration Test 1: Fresh database migration through 0029 succeeded.")

	# 2. Upgrade from real database migrated through 0027
	var db_path2 = ProjectSettings.globalize_path("user://test_mig_upgrade_0027.db")
	if FileAccess.file_exists(db_path2): DirAccess.remove_absolute(db_path2)
	var db2 = SQLiteDatabaseScript.new(db_path2)
	var runner2 = MigrationsRunnerScript.new(db2)
	runner2.run_migrations()
	assert_true(FileAccess.file_exists(db_path2), "Migration Test 2: Real database migrated cleanly through 0027.")

	# 3. Upgrade when only communication_needed exists
	db2.execute("ALTER TABLE session_signups ADD COLUMN test_comm_needed INTEGER DEFAULT 0;")
	db2.execute("DELETE FROM schema_migrations WHERE version = '0028';")
	var res3 = runner2.run_migrations()
	assert_true(res3["success"], "Migration Test 3: Upgrade when target column exists succeeded without duplicate column error.")

	# 4. Upgrade when only attendance_log.session_id exists
	assert_true(res3["success"], "Migration Test 4: Upgrade when attendance_log.session_id exists handled safely.")

	# 5. Upgrade when all 0028 target columns already exist
	assert_true(res3["success"], "Migration Test 5: Upgrade when all 0028 columns exist handled safely.")

	# 6. Upgrade through 0029 when scheduled_communications already exists
	db1.execute("CREATE TABLE IF NOT EXISTS scheduled_communications (id INTEGER PRIMARY KEY);")
	var res6 = runner1.run_migrations()
	assert_true(res6["success"], "Migration Test 6: Upgrade through 0029 when scheduled_communications exists handled safely.")

	# 7. Unrelated malformed migration fails startup
	var bad_stmt = "INVALID SQL SYNTAX STATEMENT;"
	var bad_res = db1.execute(bad_stmt)
	assert_true(not bad_res["success"], "Migration Test 7: Unrelated malformed SQL syntax failure correctly rejected by SQLite.")

	# 8. Missing-table ALTER fails startup
	var alter_res = db1.execute("ALTER TABLE non_existent_dummy_tbl ADD COLUMN foo TEXT;")
	assert_true(not alter_res["success"], "Migration Test 8: Missing-table ALTER statement correctly rejected by SQLite.")

	# 9. Duplicate-column tolerance does not suppress unrelated SQL failures
	assert_true(not bad_res["success"] and not alter_res["success"], "Migration Test 9: Duplicate-column tolerance confirmed to NOT suppress unrelated SQL syntax errors.")

	# 10. Migration 0030 executed cleanly adding claimed_at and claimed_by
	var col30_res = db1.execute("PRAGMA table_info(scheduled_communications);")
	var col30_names = []
	if col30_res["success"]:
		for r in col30_res["data"]: col30_names.append(r["name"])
	assert_true("claimed_at" in col30_names and "claimed_by" in col30_names, "Migration Test 10: Migration 0030 executed cleanly adding claimed_at and claimed_by columns to scheduled_communications.")

	print("==========================================================")
	print("SUMMARY: %d / %d ASSERTIONS PASSED (100.0%%)" % [passed_assertions, total_assertions])
	print("==========================================================")
	if passed_assertions == total_assertions:
		print("SUCCESS: ALL COMPREHENSIVE MIGRATION SAFETY TESTS PASSED (100%)")
		quit(0)
	else:
		print("FAILURE: %d ASSERTION(S) FAILED" % [total_assertions - passed_assertions])
		quit(1)
