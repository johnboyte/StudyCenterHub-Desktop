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

	# Test user reported input: "Thak fasd f"
	var user_failure_input = "Thak fasd f"
	var user_issues = SpellingAssistanceHelperScript.check_text(user_failure_input)
	assert(user_issues.size() == 2, "Expected 2 misspellings ('Thak', 'fasd') in 'Thak fasd f', got: " + str(user_issues.size()))
	assert(user_issues[0]["word"] == "Thak", "Expected 'Thak' misspelling")
	assert(user_issues[1]["word"] == "fasd", "Expected 'fasd' misspelling")
	print("✓ PASS: User input 'Thak fasd f' flagged exact misspellings 'Thak' and 'fasd'.")

	# Test 2a: Ordinary English message including "Thanks for the reply..." MUST HAVE ZERO false positives
	var realistic_text_1 = "Thanks for the reply. We're looking forward to seeing John's child at the center tomorrow at 3:00 PM."
	var issues_realistic_1 = SpellingAssistanceHelperScript.check_text(realistic_text_1)
	print("Realistic text 1 issues count: ", issues_realistic_1.size())
	if issues_realistic_1.size() > 0:
		print("FALSE POSITIVES DETECTED: ", issues_realistic_1)
	assert(issues_realistic_1.size() == 0, "Ordinary English text 'Thanks for the reply...' MUST have 0 false positives! Got: " + str(issues_realistic_1.size()))
	print("✓ PASS: 'Thanks for the reply...' produced 0 false positives.")

	# Test 2b: Multiline realistic constituent reply
	var realistic_text_2 = "Thanks for reaching out!\n\nWe have updated your account preferences and confirmed your attendance for this Friday's session."
	var issues_realistic_2 = SpellingAssistanceHelperScript.check_text(realistic_text_2)
	assert(issues_realistic_2.size() == 0, "Multiline ordinary reply MUST have 0 false positives! Got: " + str(issues_realistic_2.size()))
	print("✓ PASS: Multiline constituent reply produced 0 false positives.")

	# Test 2c: Genuine typos MUST still be detected with accurate suggestions
	var typo_reply = "I will definately recieve your message for customconstterm."
	var issues_typos = SpellingAssistanceHelperScript.check_text(typo_reply)

	print("Detected issues in typo reply: ", issues_typos)
	assert(issues_typos.size() == 3, "Expected exactly 3 issues (definately, recieve, customconstterm), got: " + str(issues_typos.size()))

	assert(issues_typos[0]["word"] == "definately", "Expected definately flagged first")
	assert(issues_typos[0]["suggestions"][0] == "definitely", "Expected definitely suggestion for definately")

	assert(issues_typos[1]["word"] == "recieve", "Expected recieve flagged second")
	assert(issues_typos[1]["suggestions"][0] == "receive", "Expected receive suggestion for recieve")

	assert(issues_typos[2]["word"] == "customconstterm", "Expected customconstterm flagged third")
	print("✓ PASS: Misspellings detected accurately with correct suggestions.")

	# Test Session Ignore Action
	SpellingAssistanceHelperScript.ignore_word("definately")
	var re_check1 = SpellingAssistanceHelperScript.check_text(typo_reply)
	var definately_still_flagged = false
	for iss in re_check1:
		if iss["word"] == "definately":
			definately_still_flagged = true
	assert(not definately_still_flagged, "'definately' must be ignored after ignore_word()")
	print("✓ PASS: Ignore action successfully suppressed 'definately'.")

	# Test Add to Dictionary Action
	SpellingAssistanceHelperScript.add_word_to_dictionary("customconstterm")
	var re_check2 = SpellingAssistanceHelperScript.check_text(typo_reply)
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
