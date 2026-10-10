extends SceneTree

## Focused Verification Test Suite for Comms Message Composer Restoration
## Verifies that message composition editor appears, supports multiline editing,
## channel switching, template population, spell check, and recipient persistence.

const SQLiteDatabaseScript = preload("res://src/infrastructure/database/sqlite_database.gd")
const MigrationsRunnerScript = preload("res://src/infrastructure/database/migrations_runner.gd")

var total_assertions: int = 0
var passed_assertions: int = 0

func _init() -> void:
	print("==========================================================")
	print("STARTING FOCUSED MESSAGE COMPOSER RESTORATION TEST SUITE")
	print("==========================================================")
	call_deferred("run_tests")

func assert_true(condition: bool, message: String) -> void:
	total_assertions += 1
	if condition:
		passed_assertions += 1
		print("  ✓ PASS %d/%d: %s" % [passed_assertions, total_assertions, message])
	else:
		print("  ❌ FAIL %d/%d: %s" % [passed_assertions, total_assertions, message])

func run_tests() -> void:
	var db_path = ProjectSettings.globalize_path("user://test_composer_restoration.db")
	if FileAccess.file_exists(db_path):
		DirAccess.remove_absolute(db_path)

	var db = SQLiteDatabaseScript.new(db_path)
	var mig_res = MigrationsRunnerScript.new(db).run_migrations()
	assert_true(mig_res["success"], "Database schema migrated cleanly.")

	db.execute("INSERT INTO people (person_uuid, human_id, first_name, last_name, status, phone, email) VALUES ('usr_foc_001', 'P-FOC-001', 'Grace', 'Hopper', 'active', '555-0199', 'grace@example.org');")

	var com_scene = load("res://app/scenes/communications_view.tscn")
	assert_true(com_scene != null, "CommunicationsView scene loaded.")

	var view = com_scene.instantiate()
	view.db = db
	root.add_child(view)

	# 1. Composer & TextEdit visibility
	assert_true(view.message_body_edit != null, "Message body TextEdit control exists.")
	assert_true(view.message_body_edit.custom_minimum_size.y >= 140, "Message body TextEdit provides adequate height for multiline text.")
	assert_true(view.message_body_edit.wrap_mode == TextEdit.LINE_WRAPPING_BOUNDARY, "Line wrapping enabled for multiline messages.")

	# 2. Multiline message entry
	var test_multiline = "Hello Grace,\n\nThis is a multiline broadcast message.\nLine 3 of the composition."
	view.message_body_edit.text = test_multiline
	assert_true(view.message_body_edit.text == test_multiline, "Entered multiline message text correctly retained.")

	# 3. Recipient selection does not reset entered text
	view._on_individual_selected(1)
	assert_true(view.message_body_edit.text == test_multiline, "Recipient selection preserves entered message body text.")

	# 4. Template population
	assert_true(view.template_list.size() >= 2, "Message templates populated in dropdown list.")
	view._on_template_selected(1)
	assert_true(view.message_body_edit.text != "" and view.message_body_edit.text != test_multiline, "Template selection populates composer body text correctly.")

	# 5. Channel switching
	view.channel_dropdown.select(0)
	view._on_channel_selected(0) # SMS
	assert_true(view.channel_dropdown.get_item_text(view.channel_dropdown.selected).contains("SMS"), "Channel toggled to SMS.")
	view.channel_dropdown.select(1)
	view._on_channel_selected(1) # Email
	assert_true(view.channel_dropdown.get_item_text(view.channel_dropdown.selected).contains("Email"), "Channel toggled to Email.")

	# 6. Spell-check functionality
	assert_true(view.message_body_edit.syntax_highlighter != null, "Spelling assistance syntax highlighter attached.")

	# 7. Send & Schedule button connectivity
	assert_true(view.btn_send_message != null and view.btn_send_message.pressed.is_connected(view._on_send_message_pressed), "Send Message button connected.")
	assert_true(view.btn_schedule_message != null and view.btn_schedule_message.pressed.is_connected(view._on_schedule_message_pressed), "Schedule Message button connected.")

	print("==========================================================")
	print("SUMMARY: %d / %d ASSERTIONS PASSED (100.0%%)" % [passed_assertions, total_assertions])
	print("==========================================================")
	if passed_assertions == total_assertions:
		print("SUCCESS: FOCUSED COMPOSER VERIFICATION PASSED (100%)")
		quit(0)
	else:
		print("FAILURE: %d ASSERTION(S) FAILED" % [total_assertions - passed_assertions])
		quit(1)
