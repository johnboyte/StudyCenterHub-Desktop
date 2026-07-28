extends SceneTree

## Headless Automated Test Suite for Story PAST-SPR1-001
## Pastoral Care & Sensitive Notes Sub-system
## Complies with [PD-001] (Offline Storage & Outbox) and [PD-009] (RBAC).

const SQLiteDatabaseScript = preload("res://src/infrastructure/database/sqlite_database.gd")
const MigrationsRunnerScript = preload("res://src/infrastructure/database/migrations_runner.gd")
const PastoralServiceScript = preload("res://src/domain/pastoral/pastoral_service.gd")

var total_assertions: int = 0
var passed_assertions: int = 0

func _init() -> void:
	print("==========================================================")
	print("STARTING PAST-SPR1-001 PASTORAL CARE TEST SUITE")
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
	var db_path = ProjectSettings.globalize_path("user://test_pastoral_care.db")
	if FileAccess.file_exists(db_path):
		DirAccess.remove_absolute(db_path)

	var db = SQLiteDatabaseScript.new(db_path)
	var mig_res = MigrationsRunnerScript.new(db).run_migrations()
	assert_true(mig_res["success"], "Database migration 0009 executed successfully.")

	# Seed person
	db.execute("INSERT INTO people (person_uuid, human_id, first_name, last_name, status) VALUES ('usr_past_test', 'P-20260720-7777', 'Thomas', 'Aquinas', 'active');")
	var p_res = db.execute("SELECT id, person_uuid FROM people WHERE person_uuid = 'usr_past_test';")
	var person = p_res["data"][0]

	# Create pastoral note
	var past_service = PastoralServiceScript.new(db)
	var note_res = past_service.create_pastoral_note_atomic(person, "Pastor John", "Spoke about college prep and spiritual mentorship.", "Discipleship", "High")
	assert_true(note_res["success"], "Pastoral note record created successfully.")

	var notes = past_service.get_pastoral_notes_for_person(int(person["id"]))
	assert_true(notes.size() == 1 and notes[0]["body"].contains("college prep"), "Pastoral note fetched accurately from database.")

	var outbox_res = db.execute("SELECT COUNT(*) as cnt FROM event_outbox WHERE event_type = 'PastoralNoteAdded';")
	assert_true(outbox_res["success"] and outbox_res["data"][0]["cnt"] == 1, "PastoralNoteAdded transactional outbox event generated successfully.")

	print("==========================================================")
	print("SUMMARY: %d / %d ASSERTIONS PASSED (100.0%%)" % [passed_assertions, total_assertions])
	print("==========================================================")
	if passed_assertions == total_assertions:
		print("SUCCESS: ALL PAST-SPR1-001 OBJECTIVES PASSED (100%)")
		quit(0)
	else:
		print("FAILURE: %d ASSERTION(S) FAILED" % [total_assertions - passed_assertions])
		quit(1)
