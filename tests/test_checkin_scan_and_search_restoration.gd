extends SceneTree

## Regression Test Suite: Check In "Scan QR Badge or Type Name" Restoration
## Drives the real AttendanceView with simulated keyboard events (the same path a
## USB/Bluetooth HID badge scanner uses) against an isolated test database.
## NOTE: This is automated verification only. It does not exercise physical scanner hardware.

const SQLiteDatabaseScript = preload("res://src/infrastructure/database/sqlite_database.gd")
const MigrationsRunnerScript = preload("res://src/infrastructure/database/migrations_runner.gd")
const QRCredentialServiceScript = preload("res://src/domain/security/qr_credential_service.gd")

const TEST_DB_FILE = "test_checkin_scan_and_search_restoration.db"

var total_assertions: int = 0
var passed_assertions: int = 0
var att_view: Node = null
var db: RefCounted = null

func _init() -> void:
	print("==============================================================================")
	print("STARTING CHECK IN SCAN / TYPE-NAME RESTORATION REGRESSION SUITE")
	print("==============================================================================")
	call_deferred("run_all_tests")

func assert_true(condition: bool, message: String) -> void:
	total_assertions += 1
	if condition:
		passed_assertions += 1
		print("PASS %d: %s" % [total_assertions, message])
	else:
		print("FAIL %d: %s" % [total_assertions, message])

func _frames(n: int = 3) -> void:
	for i in range(n):
		await process_frame

## Emulates an HID keyboard-wedge scanner: one key press/release per character, then Return.
func _type_keys(text: String, press_enter: bool) -> void:
	for i in range(text.length()):
		var ch = text.unicode_at(i)
		var down = InputEventKey.new()
		down.pressed = true
		down.unicode = ch
		down.keycode = OS.find_keycode_from_string(text[i].to_upper()) if text[i].strip_edges() != "" else KEY_SPACE
		root.push_input(down)
		var up = InputEventKey.new()
		up.pressed = false
		up.keycode = down.keycode
		root.push_input(up)
	if press_enter:
		var ent = InputEventKey.new()
		ent.pressed = true
		ent.keycode = KEY_ENTER
		ent.physical_keycode = KEY_ENTER
		root.push_input(ent)
		var ent_up = InputEventKey.new()
		ent_up.pressed = false
		ent_up.keycode = KEY_ENTER
		ent_up.physical_keycode = KEY_ENTER
		root.push_input(ent_up)
	await _frames(3)

func _count_rows(pid: int) -> int:
	var r = db.execute("SELECT COUNT(*) AS cnt FROM attendance_log WHERE person_id = ?;", [pid])
	return int(r["data"][0]["cnt"]) if r["success"] and r["data"].size() > 0 else -1

func _total_rows() -> int:
	var r = db.execute("SELECT COUNT(*) AS cnt FROM attendance_log;")
	return int(r["data"][0]["cnt"]) if r["success"] and r["data"].size() > 0 else -1

func _pid(human_id: String) -> int:
	var r = db.execute("SELECT id FROM people WHERE human_id = ? LIMIT 1;", [human_id])
	return int(r["data"][0]["id"])

func _find_text_in_tree(node: Node, needle: String) -> bool:
	for c in node.get_children():
		if (c is Label or c is Button) and str(c.text).to_upper().contains(needle):
			return true
		if _find_text_in_tree(c, needle):
			return true
	return false

func _field_ready_for_next_scan() -> bool:
	var le: LineEdit = att_view.search_line_edit
	return le.text == "" and le.has_focus() and le.is_editing()

func run_all_tests() -> void:
	var dir = DirAccess.open("user://")
	if dir and dir.file_exists(TEST_DB_FILE):
		dir.remove(TEST_DB_FILE)
	db = SQLiteDatabaseScript.new(ProjectSettings.globalize_path("user://" + TEST_DB_FILE))
	var mig = MigrationsRunnerScript.new(db).run_migrations()
	assert_true(mig["success"], "Isolated test database migrated (Production DB untouched).")

	# Seed members
	var seeds = [
		["usr_ada", "T-2001", "Ada", "Lovelace"],
		["usr_charles", "T-2002", "Charles", "Babbage"],
		["usr_grace", "T-2003", "Grace", "Hopper"],
		["usr_linus", "T-2004", "Linus", "Torvalds"],
		["usr_alan", "T-2005", "Alan", "Turing"],
		["usr_kat", "T-2006", "Katherine", "Johnson"],
	]
	for s in seeds:
		db.execute("INSERT INTO people (person_uuid, human_id, first_name, last_name, status, primary_role) VALUES (?, ?, ?, ?, 'active', 'Participant');", s)
	var today = Time.get_date_string_from_system()
	db.execute("INSERT INTO sessions (title, session_type, date_text, start_time, end_time, room_location, is_active) VALUES ('Algebra Lab', 'General Study', ?, '15:00', '16:00', 'Room 2', 1);", [today])

	# Issue QR credentials
	var cred_svc = QRCredentialServiceScript.new(db)
	var tokens = {}
	for hid in ["T-2002", "T-2003", "T-2005", "T-2006"]:
		var pid = _pid(hid)
		var uuid_r = db.execute("SELECT person_uuid FROM people WHERE id = ?;", [pid])
		var res = cred_svc.issue_credential(pid, str(uuid_r["data"][0]["person_uuid"]), "TEST")
		tokens[hid] = str(res.get("raw_token", ""))
		assert_true(tokens[hid] != "", "QR credential issued for " + hid)

	# Instantiate the real Check In view
	att_view = load("res://app/scenes/attendance_view.tscn").instantiate()
	att_view.db = db
	root.add_child(att_view)
	await _frames(5)

	# 1. Temporary diagnostics removed
	var hero = att_view.get_node("MarginContainer/MainVBox/HeroTerminalCard/HeroMargin/HeroVBox")
	assert_true(not hero.has_node("ScannerDiagPanel"), "Temporary ScannerDiagPanel is not present.")
	assert_true(not _find_text_in_tree(att_view, "DIAGNOSTIC"), "No diagnostic labels/buttons anywhere in the Check In view.")
	assert_true(not att_view.has_method("_update_scanner_diagnostic_ui") and not att_view.has_method("_setup_scanner_diagnostic_ui"), "Diagnostic functions removed from AttendanceView.")
	assert_true(not ("_diag_label" in att_view), "Diagnostic state variables removed.")

	# 2. Normal interface + focus
	var le: LineEdit = att_view.search_line_edit
	assert_true(le.visible and le.placeholder_text.to_lower().contains("scan"), "Scan QR Badge / Type Name field is visible.")
	assert_true(le.keep_editing_on_text_submit, "Search field keeps editing after Enter (consecutive scans not dropped).")
	assert_true(le.has_focus() and le.is_editing(), "Search field has keyboard focus and is in editing mode on load.")
	assert_true(att_view.shift_lead_dropdown.item_count > 0 and att_view.shift_lead_dropdown.selected >= 0, "Shift Lead dropdown populated and selected.")
	assert_true(att_view.btn_quick_check_in.visible and att_view.person_dropdown.visible, "Member dropdown and CHECK IN button visible.")

	# 3. Manual name search -> suggestions
	await _type_keys("Lovel", false)
	assert_true(le.text == "Lovel", "Typed keystrokes reached the search field.")
	assert_true(att_view.suggestion_list.visible and att_view.filtered_person_list.size() == 1, "Matching directory member displayed for typed name.")

	# 4. Select member + CHECK IN button
	att_view._on_suggestion_item_selected(0)
	att_view.btn_quick_check_in.emit_signal("pressed")
	await _frames(3)
	var ada_pid = _pid("T-2001")
	assert_true(_count_rows(ada_pid) == 1, "Manual selection check-in recorded exactly one attendance row.")
	assert_true(att_view.toast_panel.visible and att_view.toast_label.text.contains("Check-in complete") and att_view.toast_label.text.contains("Ada"), "Normal check-in confirmation shown: " + att_view.toast_label.text)
	assert_true(_field_ready_for_next_scan(), "Field cleared and refocused after manual check-in.")
	assert_true(att_view.filtered_person_list.size() == att_view.person_list.size(), "Directory filter restored after manual check-in.")

	# 5. Valid QR badge scan (raw token, keystroke-by-keystroke + Return)
	var charles_pid = _pid("T-2002")
	await _type_keys(tokens["T-2002"], true)
	assert_true(_count_rows(charles_pid) == 1, "QR badge scan identified Charles and recorded check-in.")
	assert_true(att_view.toast_panel.visible and att_view.toast_label.text.contains("Check-in complete") and att_view.toast_label.text.contains("Charles"), "QR check-in confirmation visible after scan.")
	assert_true(_field_ready_for_next_scan(), "Field cleared and still editing after QR scan.")

	# 6. Immediate back-to-back scan of another badge
	var grace_pid = _pid("T-2003")
	await _type_keys(tokens["T-2003"], true)
	assert_true(_count_rows(grace_pid) == 1, "Consecutive second badge scan captured and checked in (Grace).")

	# 7. Duplicate protection (re-scan same badge)
	var before = _total_rows()
	await _type_keys(tokens["T-2002"], true)
	assert_true(_total_rows() == before and _count_rows(charles_pid) == 1, "Duplicate badge scan did not create a second attendance row.")
	assert_true(att_view.toast_panel.visible and att_view.toast_label.text.contains("already checked in"), "Duplicate check-in message shown: " + att_view.toast_label.text)

	# 8. Unknown / invalid badge
	before = _total_rows()
	await _type_keys("ZZQX9" + str(randi() % 100000) + "NOTAVALIDTOKEN", true)
	assert_true(_total_rows() == before, "Unknown badge did not record any check-in.")
	assert_true(att_view.toast_panel.visible and att_view.toast_label.text.contains("No matching member"), "Unknown badge shows clear message: " + att_view.toast_label.text)
	assert_true(_field_ready_for_next_scan(), "Field ready for next scan after unknown badge.")

	# 9. Badge encoded as a URL with credential= parameter
	var alan_pid = _pid("T-2005")
	await _type_keys("https://studycenterhub.org/checkin?credential=" + tokens["T-2005"], true)
	assert_true(_count_rows(alan_pid) == 1, "URL-form badge (credential=) resolved and checked in.")

	# 10. Typed name + Enter (roster fallback)
	var linus_pid = _pid("T-2004")
	await _type_keys("Torvalds", true)
	assert_true(_count_rows(linus_pid) == 1, "Typed name + Enter checked in the matching member.")
	assert_true(_field_ready_for_next_scan(), "Field ready after typed-name check-in.")

	# 11. Session Attendance via scan
	att_view.btn_mode_session.emit_signal("pressed")
	await _frames(3)
	assert_true(att_view.current_mode == "Session Attendance" and att_view.session_select_vbox.visible, "Session Attendance mode active with session selector.")
	assert_true(att_view.session_list.size() >= 1, "Active session available for selection.")
	var sess_idx = 0
	for i in range(att_view.session_list.size()):
		if str(att_view.session_list[i].get("title", "")) == "Algebra Lab":
			sess_idx = i
	att_view.session_dropdown.select(sess_idx)
	var kat_pid = _pid("T-2006")
	await _type_keys(tokens["T-2006"], true)
	var sess_r = db.execute("SELECT session_id, mode FROM attendance_log WHERE person_id = ? LIMIT 1;", [kat_pid])
	assert_true(sess_r["success"] and sess_r["data"].size() == 1 and str(sess_r["data"][0]["mode"]) == "Session Attendance" and int(sess_r["data"][0]["session_id"]) == int(att_view.session_list[sess_idx]["id"]), "Session Attendance check-in recorded with correct session_id.")
	assert_true(att_view.toast_label.text.contains("Katherine"), "Session check-in confirmation shown: " + att_view.toast_label.text)

	att_view.btn_mode_daily.emit_signal("pressed")
	await _frames(3)
	assert_true(att_view.current_mode == "Daily Check In" and le.has_focus() and le.is_editing(), "Returning to Daily Check In refocuses the scan field.")

	# Cleanup
	att_view.queue_free()
	await _frames(2)
	db = null
	if dir and dir.file_exists(TEST_DB_FILE):
		dir.remove(TEST_DB_FILE)

	print("==============================================================================")
	print("SUMMARY: %d / %d ASSERTIONS PASSED" % [passed_assertions, total_assertions])
	print("==============================================================================")
	if passed_assertions == total_assertions:
		print("SUCCESS: CHECK IN SCAN / TYPE-NAME RESTORATION SUITE PASSED")
		quit(0)
	else:
		print("FAILURE: %d ASSERTION(S) FAILED" % [total_assertions - passed_assertions])
		quit(1)
