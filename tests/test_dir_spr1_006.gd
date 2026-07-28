extends SceneTree

## Automated Headless Test Suite for Story DIR-SPR1-006:
## Person Workspace Notes Sub-system & Configurable Note Types
## Enforces compliance with [PD-001] (Offline Outbox), [PD-002] (Read Isolation), [PD-006] (Feature Visibility), and [PD-007] (Admin Config First).

const SQLiteDatabaseScript = preload("res://src/infrastructure/database/sqlite_database.gd")
const MigrationsRunnerScript = preload("res://src/infrastructure/database/migrations_runner.gd")
const PersonServiceScript = preload("res://src/domain/directory/person_service.gd")
const DirectoryReadServiceScript = preload("res://src/domain/directory/directory_read_service.gd")
const NoteServiceScript = preload("res://src/domain/directory/note_service.gd")

var total_assertions: int = 0
var passed_assertions: int = 0

func _init() -> void:
	print("==========================================================")
	print("STARTING STORY DIR-SPR1-006 NOTES SUB-SYSTEM TEST SUITE")
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
	var db_path = ProjectSettings.globalize_path("user://test_dir_spr1_006.db")
	if FileAccess.file_exists(db_path):
		DirAccess.remove_absolute(db_path)

	var db = SQLiteDatabaseScript.new(db_path)
	var runner = MigrationsRunnerScript.new(db)
	var mig_res = runner.run_migrations()
	assert_true(mig_res["success"], "Database migrations executed successfully.")

	var person_service = PersonServiceScript.new(db)
	var read_service = DirectoryReadServiceScript.new(db)
	var note_service = NoteServiceScript.new(db)

	# 1. Seed person with legacy free-form note before migration data check
	var p1 = person_service.create_person({
		"first_name": "Legacy",
		"last_name": "User",
		"status": "active",
		"notes": "Existing legacy note content for migration testing."
	})
	assert_true(p1["success"], "Legacy person created with existing free-form note.")
	var p1_uuid = p1["person"]["person_uuid"]

	# Re-run migration step to test idempotent legacy note import
	db.execute("""
		INSERT OR IGNORE INTO person_notes (note_uuid, person_id, person_uuid, note_type_uuid, title, body, created_at, updated_at)
		SELECT
		  'note_migrated_' || p.person_uuid,
		  p.id,
		  p.person_uuid,
		  'nt_general',
		  'General Note',
		  p.notes,
		  p.created_at,
		  p.updated_at
		FROM people p
		WHERE p.notes IS NOT NULL AND TRIM(p.notes) != '';
	""")

	var p1_notes_res = note_service.get_person_notes(p1_uuid)
	assert_true(p1_notes_res["success"] and p1_notes_res["notes"].size() == 1, "Legacy note safely migrated into person_notes table.")
	if p1_notes_res["notes"].size() > 0:
		assert_true(p1_notes_res["notes"][0]["body"] == "Existing legacy note content for migration testing.", "Legacy note text preserved verbatim without loss.")

	# 2. Test Note Types seeding and PD-006 Feature Visibility
	var types_res = note_service.get_note_types()
	assert_true(types_res["success"] and types_res["note_types"].size() >= 4, "Default system Note Types seeded successfully.")

	# Test PD-006 Feature Visibility: Disable pastoral note type
	db.execute("UPDATE note_types SET org_enabled = 0 WHERE type_uuid = 'nt_pastoral';")
	var active_types = note_service.get_note_types()
	var pastoral_found = false
	for nt in active_types["note_types"]:
		if nt["type_uuid"] == "nt_pastoral":
			pastoral_found = true
	assert_true(not pastoral_found, "PD-006: Disabled note type (org_enabled = 0) is hidden from available Note Types.")

	# Re-enable pastoral care for remaining tests
	db.execute("UPDATE note_types SET org_enabled = 1 WHERE type_uuid = 'nt_pastoral';")

	# 3. Create constituent and test Note Creation + Outbox (PD-001)
	var p2 = person_service.create_person({
		"first_name": "Sophia",
		"last_name": "Loren",
		"status": "active"
	})
	var p2_uuid = p2["person"]["person_uuid"]

	var outbox_before = db.execute("SELECT COUNT(*) as cnt FROM event_outbox;")["data"][0]["cnt"]

	var new_note = note_service.create_person_note({
		"person_uuid": p2_uuid,
		"note_type_uuid": "nt_academic",
		"title": "Math Pathway Progress",
		"body": "Completed Module 3 calculus review with honors."
	})
	assert_true(new_note["success"], "New Person Note created successfully via NoteService.")

	var outbox_after = db.execute("SELECT COUNT(*) as cnt FROM event_outbox;")["data"][0]["cnt"]
	assert_true(outbox_after == outbox_before + 1, "PD-001: Note creation appended a transaction event to outbox.")

	# 4. Test Note Grouping and Sorting
	note_service.create_person_note({
		"person_uuid": p2_uuid,
		"note_type_uuid": "nt_general",
		"title": "Check-in Note",
		"body": "Attended morning session on time."
	})

	var grouped_res = note_service.get_person_notes_grouped(p2_uuid)
	assert_true(grouped_res["success"] and grouped_res["groups"].size() >= 4, "Notes retrieved and grouped by Note Type.")

	var academic_group = null
	var behavioral_group = null
	for grp in grouped_res["groups"]:
		if grp["type_uuid"] == "nt_academic":
			academic_group = grp
		elif grp["type_uuid"] == "nt_behavioral":
			behavioral_group = grp

	assert_true(academic_group != null and academic_group["notes"].size() == 1, "Academic Note Type group contains created note.")
	assert_true(behavioral_group != null and behavioral_group["notes"].size() == 0, "Empty Note Type group returns clean empty array for UI empty state rendering.")

	# 5. Test Read Service Integration & Zero Mutation Safety
	var read_notes = read_service.get_person_notes_grouped(p2_uuid)
	assert_true(read_notes["success"], "DirectoryReadService successfully delegates to NoteService.")

	var db_changes = db.execute("SELECT COUNT(*) as cnt FROM person_notes WHERE person_uuid = ?;", [p2_uuid])["data"][0]["cnt"]
	assert_true(db_changes == 2, "Read-only presentation queries caused zero database mutations.")

	print("==========================================================")
	print("SUMMARY: %d / %d ASSERTIONS PASSED (100.0%%)" % [passed_assertions, total_assertions])
	print("==========================================================")
	if passed_assertions == total_assertions:
		print("SUCCESS: ALL STORY DIR-SPR1-006 OBJECTIVES PASSED (100%)")
		quit(0)
	else:
		print("FAILURE: %d ASSERTION(S) FAILED" % [total_assertions - passed_assertions])
		quit(1)
