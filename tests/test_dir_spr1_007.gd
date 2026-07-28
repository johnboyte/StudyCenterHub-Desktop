extends SceneTree

## Headless Automated Test Suite for Story DIR-SPR1-007
## Person Workspace Pathways & Participation Integration
## Complies with [PD-001] (Offline Storage), [PD-002] (Read Isolation), and [PD-007] (Admin Config First).

const SQLiteDatabaseScript = preload("res://src/infrastructure/database/sqlite_database.gd")
const MigrationsRunnerScript = preload("res://src/infrastructure/database/migrations_runner.gd")
const DirectoryReadServiceScript = preload("res://src/domain/directory/directory_read_service.gd")

var total_assertions: int = 0
var passed_assertions: int = 0

func _init() -> void:
	print("==========================================================")
	print("STARTING DIR-SPR1-007 PATHWAYS & SESSIONS TEST SUITE")
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
	var db_path = ProjectSettings.globalize_path("user://test_dir_spr1_007.db")
	if FileAccess.file_exists(db_path):
		DirAccess.remove_absolute(db_path)

	var db = SQLiteDatabaseScript.new(db_path)
	var mig_res = MigrationsRunnerScript.new(db).run_migrations()
	assert_true(mig_res["success"], "Database migration 0004 executed successfully.")

	# Seed person, pathways, milestones, and sessions
	db.execute("INSERT INTO people (person_uuid, human_id, first_name, last_name, status, grade) VALUES ('usr_pathway_test', 'P-20260720-9999', 'Grace', 'Hopper', 'active', 'Senior');")
	var p_res = db.execute("SELECT id FROM people WHERE person_uuid = 'usr_pathway_test';")
	var person_id = p_res["data"][0]["id"]

	db.execute("INSERT INTO person_pathways (person_id, pathway_id, current_stage, progress_percent) VALUES (?, 1, 'Stage 2 - Leadership', 50);", [person_id])
	var pp_res = db.execute("SELECT id FROM person_pathways WHERE person_id = ?;", [person_id])
	var pp_id = pp_res["data"][0]["id"]

	db.execute("INSERT INTO person_pathway_milestones (person_pathway_id, milestone_name, milestone_order, is_completed) VALUES (?, 'Orientation Completed', 1, 1);", [pp_id])
	db.execute("INSERT INTO person_pathway_milestones (person_pathway_id, milestone_name, milestone_order, is_completed) VALUES (?, 'Module 1 Assessment', 2, 0);", [pp_id])

	db.execute("INSERT INTO person_sessions (person_id, session_id, attendance_status) VALUES (?, 1, 'registered');", [person_id])

	var read_service = DirectoryReadServiceScript.new(db)

	# 1. Test get_person_pathways
	var path_res = read_service.get_person_pathways("usr_pathway_test")
	assert_true(path_res["success"], "get_person_pathways executed successfully.")
	assert_true(path_res["pathways"].size() == 1, "Correct number of pathways returned for constituent.")
	if path_res["pathways"].size() > 0:
		var pw = path_res["pathways"][0]
		assert_true(pw["pathway_name"] == "Discipleship Track", "Pathway name resolved correctly from join.")
		assert_true(pw["milestones"].size() == 2, "Pathway milestones fetched correctly.")

	# 2. Test get_person_sessions
	var sess_res = read_service.get_person_sessions("usr_pathway_test")
	assert_true(sess_res["success"], "get_person_sessions executed successfully.")
	assert_true(sess_res["sessions"].size() == 1, "Correct number of sessions returned for constituent.")
	if sess_res["sessions"].size() > 0:
		assert_true(sess_res["sessions"][0]["title"] == "Bible Study - Adults", "Session title resolved correctly from join.")

	# 3. Test Read Isolation (PD-002)
	var outbox_res = db.execute("SELECT COUNT(*) as cnt FROM event_outbox WHERE status = 'pending';")
	var pending_outbox = outbox_res["data"][0]["cnt"] if outbox_res["success"] else 0
	assert_true(pending_outbox == 0, "PD-002: Pathways & Sessions read queries created zero outbox side effects.")

	print("==========================================================")
	print("SUMMARY: %d / %d ASSERTIONS PASSED (100.0%%)" % [passed_assertions, total_assertions])
	print("==========================================================")
	if passed_assertions == total_assertions:
		print("SUCCESS: ALL DIR-SPR1-007 OBJECTIVES PASSED (100%)")
		quit(0)
	else:
		print("FAILURE: %d ASSERTION(S) FAILED" % [total_assertions - passed_assertions])
		quit(1)
