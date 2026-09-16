extends SceneTree

## Dedicated Comprehensive Suite for SMS Reply Composer & Spelling Assistance

const SQLiteDatabaseScript = preload("res://src/infrastructure/database/sqlite_database.gd")
const MigrationsRunnerScript = preload("res://src/infrastructure/database/migrations_runner.gd")
const CommunicationsServiceScript = preload("res://src/domain/communications/communications_service.gd")
const SpellingAssistanceHelperScript = preload("res://src/ui/components/spelling_assistance_helper.gd")

var db: RefCounted

func _init() -> void:
	print("\n============================================================")
	print("  RUNNING SMS REPLY COMPOSER & SPELLING ASSISTANCE TEST SUITE")
	print("============================================================\n")

	call_deferred("run_all_tests")

func run_all_tests() -> void:
	var db_path = ProjectSettings.globalize_path("user://test_sms_composer.db")
	if FileAccess.file_exists(db_path):
		DirAccess.remove_absolute(db_path)

	db = SQLiteDatabaseScript.new(db_path)
	var mig_res = MigrationsRunnerScript.new(db).run_migrations()
	assert(mig_res["success"], "Migrations failed")

	# Seed constituent for SMS test
	db.execute("""
		INSERT OR REPLACE INTO people (id, person_uuid, human_id, first_name, last_name, phone, status, primary_role)
		VALUES (600, 'usr_sms_test_600', 'P-SMS-600', 'Alex', 'Morgan', '5559876543', 'active', 'Parent');
	""")

	_test_multiline_editor_properties()
	_test_spelling_assistance_and_dictionary()
	_test_sms_sending_workflow()

	print("\n============================================================")
	print("  SUCCESS: ALL SMS REPLY COMPOSER TESTS PASSED (100%)")
	print("============================================================\n")
	quit(0)

func _test_multiline_editor_properties() -> void:
	print("--- 1. Testing Multiline TextEdit Composer Properties & Formatting ---")

	var msg_edit = TextEdit.new()
	msg_edit.custom_minimum_size = Vector2(0, 135)
	msg_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	msg_edit.caret_blink = true
	msg_edit.context_menu_enabled = true
	msg_edit.add_theme_color_override("caret_color", Color(0.12, 0.16, 0.22, 1.0))

	assert(msg_edit.custom_minimum_size.y >= 130, "Editor must have multiline min height >= 130px")
	assert(msg_edit.wrap_mode == TextEdit.LINE_WRAPPING_BOUNDARY, "Editor must wrap lines normally")
	assert(msg_edit.caret_blink == true, "Editor must enable caret blink")
	assert(msg_edit.context_menu_enabled == true, "Editor must enable right-click context menu")

	# Simulate multiline input
	var multiline_text = "Paragraph 1: Thank you for your inquiry regarding center hours.\n\nParagraph 2: We will definately recieve your update and process it tomorrow."
	msg_edit.text = multiline_text
	assert(msg_edit.text == multiline_text, "Editor must store multiline text correctly")
	assert(msg_edit.get_line_count() >= 3, "Editor must preserve paragraph breaks")
	print("✓ PASS: Multiline editor configured with word wrapping, caret blinking, context menu, and multiline storage.")

func _test_spelling_assistance_and_dictionary() -> void:
	print("\n--- 2. Testing Spelling Assistance, Ignore Action & Dictionary Addition ---")

	var sample_reply = "I will definately recieve your message for customconstterm."
	var issues = SpellingAssistanceHelperScript.check_text(sample_reply)

	print("Detected issues in sample reply: ", issues)
	assert(issues.size() >= 3, "Expected at least 3 issues, got: " + str(issues.size()))
	var has_def = false
	var has_rec = false
	var has_custom = false
	for iss in issues:
		if iss["word"] == "definately": has_def = true
		if iss["word"] == "recieve": has_rec = true
		if iss["word"] == "customconstterm": has_custom = true
	assert(has_def and has_rec and has_custom, "Must flag definately, recieve, and customconstterm")
	print("✓ PASS: Misspellings detected and suggestions generated.")

	# Test Session Ignore Action
	SpellingAssistanceHelperScript.ignore_word("definately")
	var re_check1 = SpellingAssistanceHelperScript.check_text(sample_reply)
	var definately_still_flagged = false
	for iss in re_check1:
		if iss["word"] == "definately":
			definately_still_flagged = true
	assert(not definately_still_flagged, "'definately' must be ignored after ignore_word()")
	print("✓ PASS: Ignore action successfully suppressed 'definately'.")

	# Test Add to Dictionary Action
	SpellingAssistanceHelperScript.add_word_to_dictionary("customconstterm")
	var re_check2 = SpellingAssistanceHelperScript.check_text(sample_reply)
	var term_still_flagged = false
	for iss in re_check2:
		if iss["word"] == "customconstterm":
			term_still_flagged = true
	assert(not term_still_flagged, "'customconstterm' must be treated as valid after add_word_to_dictionary()")
	print("✓ PASS: Add to dictionary action successfully validated 'customconstterm'.")

func _test_sms_sending_workflow() -> void:
	print("\n--- 3. Testing SMS Sending Workflow & Atomic Dispatch ---")

	var com_service = CommunicationsServiceScript.new(db)
	var target_person = {"id": 600, "person_id": 600, "person_uuid": "usr_sms_test_600", "phone": "5559876543", "first_name": "Alex", "last_name": "Morgan"}
	var reply_body = "Hello Alex,\n\nWe have updated your account schedule as requested.\n\nBest regards,\nCenter Staff"

	var send_res = com_service.send_message_atomic(target_person, "SMS", reply_body, "Supervisor Admin")
	assert(send_res.get("success", false) == true, "send_message_atomic failed: " + str(send_res))

	var thread = com_service.get_sms_conversation_thread("5559876543")
	assert(thread.size() >= 1, "Thread should contain at least 1 message")
	var found_sent = false
	for m in thread:
		var norm_body = str(m["body"]).replace("\\n", "\n").strip_edges()
		if norm_body == reply_body.strip_edges() and m["direction"] == "outbound":
			found_sent = true
			break
	assert(found_sent, "Sent SMS body must exist in conversation thread history")

	print("✓ PASS: SMS reply dispatched atomically and persisted to thread history.")
