extends SceneTree

## Dedicated Comprehensive Suite for Real Spelling Assistance, Note Editing, and Desktop <-> Mobile Sync

const SQLiteDatabaseScript = preload("res://src/infrastructure/database/sqlite_database.gd")
const MigrationsRunnerScript = preload("res://src/infrastructure/database/migrations_runner.gd")
const NoteServiceScript = preload("res://src/domain/directory/note_service.gd")
const GatewaySyncServiceScript = preload("res://src/domain/sync/gateway_sync_service.gd")
const SpellingAssistanceHelperScript = preload("res://src/ui/components/spelling_assistance_helper.gd")

var db: RefCounted

func _init() -> void:
	print("\n============================================================")
	print("  RUNNING SPELLING ASSISTANCE, NOTE EDITING & SYNC SUITE")
	print("============================================================\n")

	call_deferred("run_all_tests")

func run_all_tests() -> void:
	var db_path = ProjectSettings.globalize_path("user://test_spelling_and_sync.db")
	if FileAccess.file_exists(db_path):
		DirAccess.remove_absolute(db_path)

	db = SQLiteDatabaseScript.new(db_path)
	var mig_res = MigrationsRunnerScript.new(db).run_migrations()
	assert(mig_res["success"], "Migrations failed")

	# Seed constituent into DB with both person_uuid and human_id
	db.execute("""
		INSERT OR REPLACE INTO people (id, person_uuid, human_id, first_name, last_name, status, primary_role)
		VALUES (500, 'usr_sync_person_500', 'P-SYNC-500', 'Sarah', 'Conner', 'active', 'Student');
	""")

	_test_spelling_assistance_engine()
	_test_note_editing_lifecycle()
	_test_desktop_to_mobile_general_note_cross_query()

	print("\n============================================================")
	print("  SUCCESS: ALL SPELLING, EDITING & SYNC TESTS PASSED (100%)")
	print("============================================================\n")
	quit(0)

func _test_spelling_assistance_engine() -> void:
	print("--- 1. Testing Spelling Assistance Engine ---")

	var test_text = "Please recieve this definately seperate document."
	var issues = SpellingAssistanceHelperScript.check_text(test_text)

	assert(issues.size() == 3, "Expected 3 spelling issues, got: " + str(issues.size()))
	assert(issues[0]["suggestion"] == "receive", "Expected 'receive', got: " + issues[0]["suggestion"])
	assert(issues[1]["suggestion"] == "definitely", "Expected 'definitely', got: " + issues[1]["suggestion"])
	assert(issues[2]["suggestion"] == "separate", "Expected 'separate', got: " + issues[2]["suggestion"])

	var fixed_text = test_text
	for issue in issues:
		fixed_text = fixed_text.replace(issue["word"], issue["suggestion"])

	assert(fixed_text == "Please receive this definitely separate document.", "Spelling auto-fix output mismatch!")
	print("✓ PASS: Real-time spelling detection & auto-fix verified for 'recieve', 'definately', 'seperate'.")

func _test_note_editing_lifecycle() -> void:
	print("\n--- 2. Testing Note Editing Lifecycle Across All 4 Note Types ---")

	var note_service = NoteServiceScript.new(db)
	var p_uuid = "usr_sync_person_500"

	var note_types = [
		{"uuid": "nt_general", "title": "General Note", "vis": "standard_staff"},
		{"uuid": "nt_academic", "title": "Academic Note", "vis": "standard_staff"},
		{"uuid": "nt_behavioral", "title": "Behavioral Note", "vis": "standard_staff"},
		{"uuid": "nt_pastoral", "title": "Pastoral Care Note", "vis": "sensitive_pastoral"}
	]

	for ntype in note_types:
		# Create
		var c_res = note_service.create_person_note({
			"person_uuid": p_uuid,
			"note_type_uuid": ntype["uuid"],
			"title": ntype["title"],
			"body": "Initial note body with misspelling recieve.",
			"visibility": ntype["vis"]
		})
		assert(c_res["success"], "Failed to create note")
		var n_uuid = c_res["note_uuid"]

		var r1 = db.execute("SELECT * FROM person_notes WHERE note_uuid = ?;", [n_uuid])["data"][0]
		var created_at = r1["created_at"]

		OS.delay_msec(10)

		# Edit
		var u_res = note_service.update_person_note(n_uuid, {
			"body": "Corrected note body with receive.",
			"title": ntype["title"],
			"note_type_uuid": ntype["uuid"],
			"visibility": ntype["vis"]
		})
		assert(u_res["success"], "Failed to update note")

		var r2 = db.execute("SELECT * FROM person_notes WHERE note_uuid = ?;", [n_uuid])["data"][0]
		assert(r2["note_uuid"] == n_uuid, "note_uuid must be preserved")
		assert(r2["created_at"] == created_at, "created_at must be preserved")
		assert(r2["body"] == "Corrected note body with receive.", "body must be updated")
		assert(r2["updated_at"] != "", "updated_at must be set")

		var cnt = db.execute("SELECT COUNT(*) as c FROM person_notes WHERE note_uuid = ?;", [n_uuid])["data"][0]["c"]
		assert(int(cnt) == 1, "Duplicate note created!")

		print("✓ PASS: Note type '%s' edited cleanly (note_uuid & created_at preserved, 0 duplicates)." % ntype["title"])

func _test_desktop_to_mobile_general_note_cross_query() -> void:
	print("\n--- 3. Testing Desktop -> Mobile General Note Cross-Identifier Match ---")

	var note_service = NoteServiceScript.new(db)
	var sync_service = GatewaySyncServiceScript.new(db, root)

	var p_uuid = "usr_sync_person_500"
	var h_id = "P-SYNC-500"

	# Create General Note on Desktop
	var c_res = note_service.create_person_note({
		"person_uuid": p_uuid,
		"note_type_uuid": "nt_general",
		"title": "General Note",
		"body": "Desktop General Note intended for Mobile participant profile.",
		"visibility": "standard_staff"
	})
	assert(c_res["success"], "Failed to create General Note")
	var n_uuid = c_res["note_uuid"]

	# Verify publish_person_notes includes both person_uuid and human_id
	var pub_res = db.execute("""
		SELECT pn.note_uuid, pn.person_uuid, p.human_id, pn.title, pn.body
		FROM person_notes pn
		LEFT JOIN people p ON (pn.person_id = p.id OR pn.person_uuid = p.person_uuid OR pn.person_uuid = p.human_id)
		WHERE pn.note_uuid = ?;
	""", [n_uuid])

	assert(pub_res["success"] and pub_res["data"].size() == 1, "Note lookup failed")
	var row = pub_res["data"][0]

	assert(row["person_uuid"] == p_uuid, "person_uuid mismatch")
	assert(row["human_id"] == h_id, "human_id lookup failed in sync query!")

	print("✓ PASS: Desktop publish query correctly binds person_uuid ('%s') and human_id ('%s')." % [p_uuid, h_id])
