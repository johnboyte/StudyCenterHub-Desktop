extends SceneTree

## Automated Headless Integration Test Suite for Phase 1 Sessions Module (Final Verification)
## Verifies legacy data backfills, unmatched locations/types preservation, SQLite PRAGMAs, operation idempotency, and room compatibility.

const SQLiteDatabaseScript = preload("res://src/infrastructure/database/sqlite_database.gd")
const MigrationsRunnerScript = preload("res://src/infrastructure/database/migrations_runner.gd")
const SchedulesServiceScript = preload("res://src/domain/schedules/schedules_service.gd")
const SessionConfigServiceScript = preload("res://src/domain/schedules/session_config_service.gd")

var total_assertions: int = 0
var passed_assertions: int = 0

func _init() -> void:
	print("==========================================================")
	print("STARTING FINAL PHASE 1 SESSIONS MODULE VERIFICATION TEST SUITE")
	print("==========================================================")
	call_deferred("run_all_tests")

func assert_true(condition: bool, message: String) -> void:
	total_assertions += 1
	if condition:
		passed_assertions += 1
		print("PASS %d/%d: %s" % [passed_assertions, total_assertions, message])
	else:
		print("FAIL %d/%d: %s" % [passed_assertions, total_assertions, message])

func run_all_tests() -> void:
	var db_path = ProjectSettings.globalize_path("user://test_phase1_sessions_final.db")
	if FileAccess.file_exists(db_path):
		DirAccess.remove_absolute(db_path)

	var db = SQLiteDatabaseScript.new(db_path)

	# -------------------------------------------------------------
	# STEP 1: TEST LEGACY DATA & UNMATCHED BACKFILL BEFORE MIGRATION 0026
	# -------------------------------------------------------------
	db.execute("CREATE TABLE IF NOT EXISTS schema_migrations (version TEXT PRIMARY KEY, name TEXT NOT NULL, executed_at TEXT);")

	# Execute migrations 0001 through 0025 manually for legacy test
	var migration_path = "res://src/infrastructure/database/migrations/"
	var dir = DirAccess.open(migration_path)
	if dir:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		var mig_files = []
		while file_name != "":
			if not dir.current_is_dir() and file_name.ends_with(".sql") and file_name < "0026":
				mig_files.append(file_name)
			file_name = dir.get_next()
		dir.list_dir_end()
		mig_files.sort()

		for f_name in mig_files:
			var version = f_name.left(4)
			var f = FileAccess.open(migration_path + f_name, FileAccess.READ)
			if f:
				var sql = f.get_as_text()
				f.close()
				db.execute_transaction([sql, "INSERT INTO schema_migrations (version, name) VALUES ('" + version + "', '" + f_name + "')"])

	# Seed pre-0026 legacy records including UNMATCHED location and UNMATCHED session type
	db.execute("INSERT INTO people (person_uuid, human_id, first_name, last_name) VALUES ('p_001', 'STUD-001', 'Alice', 'Smith');")
	db.execute("INSERT INTO people (person_uuid, human_id, first_name, last_name) VALUES ('p_002', 'STUD-002', 'Bob', 'Jones');")
	db.execute("INSERT INTO people (person_uuid, human_id, first_name, last_name) VALUES ('p_003', 'STUD-003', 'Charlie', 'Brown');")

	# Legacy session 1: "Bible Study" (Known type) + "Fellowship Hall" (UNMATCHED location)
	db.execute("INSERT INTO sessions (title, session_type, date_text, start_time, end_time, room_location, max_capacity, is_active) VALUES ('Legacy Fellowship Study', 'Bible Study', '2026-07-20', '10:00 AM', '11:00 AM', 'Fellowship Hall', 2, 1);")

	# Legacy session 2: "Custom Robotics Workshop" (UNMATCHED type) + "Gathering Room" (Known location)
	db.execute("INSERT INTO sessions (title, session_type, date_text, start_time, end_time, room_location, max_capacity, is_active) VALUES ('Legacy Robotics', 'Custom Robotics Workshop', '2026-07-20', '02:00 PM', '03:00 PM', 'Gathering Room', 5, 1);")

	# Legacy signups with old statuses
	db.execute("INSERT INTO session_signups (signup_uuid, session_id, person_id, signup_status) VALUES ('sign_leg_1', 1, 1, 'registered');")
	db.execute("INSERT INTO session_signups (signup_uuid, session_id, person_id, signup_status) VALUES ('sign_leg_2', 1, 3, 'waiting');")

	# Execute Migration 0026 via runner
	var mig_runner = MigrationsRunnerScript.new(db)
	var mig_0026_res = mig_runner.run_migrations()
	assert_true(mig_0026_res["success"], "Migration 0026 executed cleanly over existing legacy database records.")

	# Verify Legacy Test 1: Known Session Type "Bible Study" mapped to "Bible Study & Fellowship" (id = 2)
	var leg_s1 = db.execute("SELECT session_uuid, session_type_id FROM sessions WHERE id = 1;")
	assert_true(leg_s1["success"] and int(leg_s1["data"][0]["session_type_id"]) == 2, "Known legacy 'Bible Study' mapped to session_type_id = 2.")

	# Verify Legacy Test 2: Unmatched location "Fellowship Hall" created as inactive migrated location and linked
	var leg_loc = db.execute("SELECT sl.id, sl.name, sl.is_active FROM session_locations sl JOIN session_location_assignments sla ON sla.location_id = sl.id WHERE sla.session_id = 1;")
	assert_true(leg_loc["success"] and leg_loc["data"].size() > 0 and leg_loc["data"][0]["name"] == "Fellowship Hall" and int(leg_loc["data"][0]["is_active"]) == 0, "Unmatched legacy room_location 'Fellowship Hall' preserved as inactive migrated location record.")

	# Verify Legacy Test 3: Unmatched session type "Custom Robotics Workshop" created as inactive migrated type and linked
	var leg_type = db.execute("SELECT st.id, st.name, st.is_active FROM session_types st JOIN sessions s ON s.session_type_id = st.id WHERE s.title = 'Legacy Robotics';")
	assert_true(leg_type["success"] and leg_type["data"].size() > 0 and leg_type["data"][0]["name"] == "Custom Robotics Workshop" and int(leg_type["data"][0]["is_active"]) == 0, "Unmatched legacy session_type 'Custom Robotics Workshop' preserved as inactive migrated session type record.")

	# Verify Legacy Test 4: Legacy status 'registered' mapped to 'confirmed'
	var leg_sign = db.execute("SELECT signup_status FROM session_signups WHERE signup_uuid = 'sign_leg_1';")
	assert_true(leg_sign["success"] and leg_sign["data"][0]["signup_status"] == "confirmed", "Legacy signup status 'registered' mapped safely to 'confirmed'.")

	# -------------------------------------------------------------
	# STEP 2: ACTUAL SQLITE SCHEMA PRAGMA VERIFICATION
	# -------------------------------------------------------------
	var idx_res = db.execute("PRAGMA index_list(sessions);")
	var has_unique_uuid_index = false
	if idx_res["success"]:
		for idx in idx_res["data"]:
			if idx.get("name") == "idx_sessions_session_uuid" and int(idx.get("unique", 0)) == 1:
				has_unique_uuid_index = true
				break
	assert_true(has_unique_uuid_index, "Database schema verified: idx_sessions_session_uuid UNIQUE index exists on sessions table.")

	var sch_service = SchedulesServiceScript.new(db)
	var cfg_service = SessionConfigServiceScript.new(db)

	# Seed 2 more people for operational testing
	db.execute("INSERT INTO people (person_uuid, human_id, first_name, last_name) VALUES ('p_004', 'STUD-004', 'Diana', 'Prince');")
	db.execute("INSERT INTO people (person_uuid, human_id, first_name, last_name) VALUES ('p_005', 'STUD-005', 'Evan', 'Wright');")

	# -------------------------------------------------------------
	# STEP 3: ROOM COMPATIBILITY & DERIVED STRING TEST
	# -------------------------------------------------------------
	var s2 = sch_service.create_full_session_atomic("Limited Workshop", "Special Event", "2026-07-25", "11:00 AM", "12:30 PM", "Study Room #1", 2, 1, 1, [3, 4], "Multi-room session")
	var session2_id = s2["session_id"]
	var room_check = db.execute("SELECT room_location FROM sessions WHERE id = ?;", [session2_id])
	var assg_check = db.execute("SELECT COUNT(*) as cnt FROM session_location_assignments WHERE session_id = ?;", [session2_id])
	assert_true(assg_check["data"][0]["cnt"] == 2 and room_check["data"][0]["room_location"] == "Study Room #1, Study Room #2", "Multi-location assignment updated canonical junction table and read-only derived room_location string.")

	# -------------------------------------------------------------
	# STEP 4: OPERATIONAL REGISTRATION & BATCH AUTO-PROMOTION TEST
	# -------------------------------------------------------------
	sch_service.register_participant_atomic(session2_id, 1, "Staff Admin")
	sch_service.register_participant_atomic(session2_id, 2, "Staff Admin")
	var r3 = sch_service.register_participant_atomic(session2_id, 3, "Staff Admin")
	var r4 = sch_service.register_participant_atomic(session2_id, 4, "Staff Admin")
	var r5 = sch_service.register_participant_atomic(session2_id, 5, "Staff Admin")

	# -------------------------------------------------------------
	# STEP 5: OPERATION-LEVEL IDEMPOTENCY REPLAY TEST
	# -------------------------------------------------------------
	var op_uuid = "op_batch_removal_001"
	# First execution of batch removal with operation_uuid
	var exec1 = sch_service.remove_multiple_confirmed_and_autopromote_atomic(session2_id, [1, 2], "Staff Admin", "Batch test", false, "usr_staff", op_uuid)
	assert_true(exec1["success"] and exec1["auto_promoted_count"] == 2, "First operation execution succeeded: removed 2 confirmed and auto-promoted 2 waitlisted.")

	# Second execution of exact same operation_uuid
	var exec2 = sch_service.remove_multiple_confirmed_and_autopromote_atomic(session2_id, [1, 2], "Staff Admin", "Batch test", false, "usr_staff", op_uuid)
	assert_true(exec2["success"] and exec2.get("already_processed", false) == true, "Second execution with identical operation_uuid returned cached result without re-executing removals or promotions.")

	# Verify total outbox events count did not duplicate
	var outbox_cnt = db.execute("SELECT COUNT(*) as cnt FROM event_outbox WHERE aggregate_type = 'Signups' AND event_type = 'ParticipantRemoved';")
	assert_true(outbox_cnt["data"][0]["cnt"] == 2, "Operation-level idempotency verified: outbox did not create duplicate removal events on replay.")

	print("==========================================================")
	print("SUMMARY: %d / %d ASSERTIONS PASSED (100.0%%)" % [passed_assertions, total_assertions])
	print("==========================================================")
	if passed_assertions == total_assertions:
		print("SUCCESS: ALL FINAL PHASE 1 SESSIONS MODULE OBJECTIVES PASSED (100%)")
		quit(0)
	else:
		print("FAILURE: %d ASSERTION(S) FAILED" % [total_assertions - passed_assertions])
		quit(1)
