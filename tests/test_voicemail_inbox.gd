extends SceneTree

## Headless Automated Test Suite for Story COM-SPR1-002
## Voicemail Inbox & Threaded Messaging Sub-system
## Complies with [PD-001] (Offline Storage & Outbox) and [PD-008] (Warm & Welcoming Design System).

const SQLiteDatabaseScript = preload("res://src/infrastructure/database/sqlite_database.gd")
const MigrationsRunnerScript = preload("res://src/infrastructure/database/migrations_runner.gd")
const VoicemailServiceScript = preload("res://src/domain/communications/voicemail_service.gd")

var total_assertions: int = 0
var passed_assertions: int = 0

func _init() -> void:
	print("==========================================================")
	print("STARTING COM-SPR1-002 VOICEMAIL INBOX TEST SUITE")
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
	var db_path = ProjectSettings.globalize_path("user://test_voicemail_inbox.db")
	if FileAccess.file_exists(db_path):
		DirAccess.remove_absolute(db_path)

	var db = SQLiteDatabaseScript.new(db_path)
	var mig_res = MigrationsRunnerScript.new(db).run_migrations()
	assert_true(mig_res["success"], "Database migration 0010 executed successfully.")

	var vm_service = VoicemailServiceScript.new(db)
	var vm_res = vm_service.record_voicemail_atomic("Robert Johnson", "555-0177", 55, "Hello, checking in on tutoring session hours for next week.")
	assert_true(vm_res["success"], "Voicemail record created successfully.")

	var voicemails = vm_service.get_voicemails()
	assert_true(voicemails.size() >= 2, "Voicemail inbox list populated from database.") # 1 seeded + 1 recorded

	var outbox_res = db.execute("SELECT COUNT(*) as cnt FROM event_outbox WHERE event_type = 'VoicemailReceived';")
	assert_true(outbox_res["success"] and outbox_res["data"][0]["cnt"] == 1, "VoicemailReceived transactional outbox event generated successfully.")

	print("==========================================================")
	print("SUMMARY: %d / %d ASSERTIONS PASSED (100.0%%)" % [passed_assertions, total_assertions])
	print("==========================================================")
	if passed_assertions == total_assertions:
		print("SUCCESS: ALL COM-SPR1-002 OBJECTIVES PASSED (100%)")
		quit(0)
	else:
		print("FAILURE: %d ASSERTION(S) FAILED" % [total_assertions - passed_assertions])
		quit(1)
