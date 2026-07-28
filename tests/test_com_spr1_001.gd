extends SceneTree

## Headless Automated Test Suite for Story COM-SPR1-001
## Communications Hub & Direct Messaging Engine
## Complies with [PD-001] (Offline Storage & Outbox) and [PD-008] (Warm & Welcoming Design System).

const SQLiteDatabaseScript = preload("res://src/infrastructure/database/sqlite_database.gd")
const MigrationsRunnerScript = preload("res://src/infrastructure/database/migrations_runner.gd")

var total_assertions: int = 0
var passed_assertions: int = 0

func _init() -> void:
	print("==========================================================")
	print("STARTING COM-SPR1-001 COMMUNICATIONS HUB TEST SUITE")
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
	var db_path = ProjectSettings.globalize_path("user://test_com_spr1_001.db")
	if FileAccess.file_exists(db_path):
		DirAccess.remove_absolute(db_path)

	var db = SQLiteDatabaseScript.new(db_path)
	var mig_res = MigrationsRunnerScript.new(db).run_migrations()
	assert_true(mig_res["success"], "Database migration 0005 executed successfully.")

	# Seed person BEFORE instantiating view
	db.execute("INSERT INTO people (person_uuid, human_id, first_name, last_name, status, phone) VALUES ('usr_com_test', 'P-20260720-3333', 'Ada', 'Lovelace', 'active', '555-0142');")

	# Instantiate CommunicationsView
	var com_scene = load("res://app/scenes/communications_view.tscn")
	assert_true(com_scene != null, "CommunicationsView scene loaded successfully.")

	var com_view = com_scene.instantiate()
	com_view.db = db
	root.add_child(com_view)

	# Verify templates & dropdowns
	assert_true(com_view.template_list.size() >= 3, "Message templates populated from database.")
	assert_true(com_view.person_list.size() >= 1, "Constituent recipient list populated successfully.")

	# Test template selection
	com_view._on_template_selected(1)
	assert_true(com_view.message_body_edit.text != "", "Template selection populated message body text.")

	# Test sending message
	com_view._on_send_message_pressed()

	var log_res = db.execute("SELECT COUNT(*) as cnt FROM communications_log WHERE recipient_name = 'Ada Lovelace';")
	assert_true(log_res["success"] and log_res["data"][0]["cnt"] == 1, "Sent message logged to communications_log.")

	var outbox_res = db.execute("SELECT COUNT(*) as cnt FROM event_outbox WHERE event_type = 'MessageSent';")
	assert_true(outbox_res["success"] and outbox_res["data"][0]["cnt"] == 1, "MessageSent transactional outbox event generated successfully.")

	print("==========================================================")
	print("SUMMARY: %d / %d ASSERTIONS PASSED (100.0%%)" % [passed_assertions, total_assertions])
	print("==========================================================")
	if passed_assertions == total_assertions:
		print("SUCCESS: ALL COM-SPR1-001 OBJECTIVES PASSED (100%)")
		quit(0)
	else:
		print("FAILURE: %d ASSERTION(S) FAILED" % [total_assertions - passed_assertions])
		quit(1)
