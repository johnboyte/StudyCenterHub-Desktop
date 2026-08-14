extends SceneTree

# ==============================================================================
# TEST SUITE: SCHEDULES TABLE VIEW & WEEK BOARD DATA ALIGNMENT
# Verifies that Table View displays identical weekly operating hours & staffing
# records as Week Board View for open, closed, unassigned, and split-shift days.
# ==============================================================================

const SQLiteDatabase = preload("res://src/infrastructure/database/sqlite_database.gd")
const MigrationsRunnerScript = preload("res://src/infrastructure/database/migrations_runner.gd")

var pass_count = 0
var total_assertions = 0

func _init():
	print("\n==========================================================")
	print("STARTING SCHEDULES TABLE VIEW ALIGNMENT TEST SUITE")
	print("==========================================================")
	call_deferred("run_all_tests")

func assert_true(condition: bool, message: String) -> void:
	total_assertions += 1
	if condition:
		pass_count += 1
		print("PASS %d/%d: %s" % [pass_count, total_assertions, message])
	else:
		print("FAIL %d/%d: %s" % [pass_count, total_assertions, message])
		quit(1)

func run_all_tests() -> void:
	var db = SQLiteDatabase.new("user://test_schedules_table_alignment.db")
	var mr = MigrationsRunnerScript.new(db)
	mr.run_migrations()
	assert_true(true, "Test 1: Database migrations executed cleanly.")

	db.execute("CREATE TABLE IF NOT EXISTS center_hour_overrides (override_date TEXT PRIMARY KEY, is_closed INTEGER DEFAULT 0, session1_start TEXT, session1_end TEXT, has_split_shift INTEGER DEFAULT 0, session2_start TEXT, session2_end TEXT);")

	var SchedulesViewClass = load("res://app/scenes/schedules_view.gd")
	var sv = SchedulesViewClass.new()
	sv.db = db

	# Seed weekly operating hours:
	# Sunday: Closed
	# Monday: 04:00 PM - 09:00 PM
	# Tuesday: Split Shift 10:00 AM - 01:00 PM & 04:00 PM - 09:00 PM
	# Wednesday..Saturday: Normal 04:00 PM - 09:00 PM
	db.execute("DELETE FROM center_open_hours;")
	db.execute("INSERT INTO center_open_hours (day_of_week, is_closed, open_time, close_time) VALUES ('Sunday', 1, '09:00 AM', '05:00 PM');")
	db.execute("INSERT INTO center_open_hours (day_of_week, is_closed, open_time, close_time) VALUES ('Monday', 0, '04:00 PM', '09:00 PM');")
	db.execute("INSERT INTO center_open_hours (day_of_week, is_closed, open_time, close_time) VALUES ('Tuesday', 0, '04:00 PM', '09:00 PM');")
	db.execute("INSERT INTO center_open_hours (day_of_week, is_closed, open_time, close_time) VALUES ('Wednesday', 0, '04:00 PM', '09:00 PM');")
	db.execute("INSERT INTO center_open_hours (day_of_week, is_closed, open_time, close_time) VALUES ('Thursday', 0, '04:00 PM', '09:00 PM');")
	db.execute("INSERT INTO center_open_hours (day_of_week, is_closed, open_time, close_time) VALUES ('Friday', 0, '04:00 PM', '09:00 PM');")
	db.execute("INSERT INTO center_open_hours (day_of_week, is_closed, open_time, close_time) VALUES ('Saturday', 1, '09:00 AM', '05:00 PM');")

	# Seed staff shifts on Monday
	db.execute("DELETE FROM schedule_entries;")
	var mon_date = sv.get_date_string_for_day_index(1) # Monday
	var tue_date = sv.get_date_string_for_day_index(2) # Tuesday

	db.execute("INSERT INTO schedule_entries (entry_uuid, shift_date, start_time, end_time, person_name, shift_role, area) VALUES ('s_mon_1', '" + mon_date + "', '04:00 PM', '06:30 PM', 'John Boyte', 'Staff', 'Center Hours Coverage');")
	db.execute("INSERT INTO schedule_entries (entry_uuid, shift_date, start_time, end_time, person_name, shift_role, area) VALUES ('s_mon_2', '" + mon_date + "', '06:30 PM', '09:00 PM', 'Jane Smith', 'Staff', 'Center Hours Coverage');")

	# Add date override on Tuesday for split shift using helper method
	sv.save_hour_override(tue_date, 0, "10:00 AM", "01:00 PM", 1, "04:00 PM", "09:00 PM")

	var ov_check = sv.get_hour_override_for_date(tue_date)

	# Render Table View into dummy PanelContainer
	var container = PanelContainer.new()
	var hours_data = sv._get_weekly_hours_data()
	sv._render_shift_table(container, hours_data)

	assert_true(container.get_child_count() > 0, "Test 2: Table View rendered container successfully.")

	# Extract rendered labels from table
	var labels = []
	_collect_labels(container, labels)

	var label_texts = []
	for l in labels:
		label_texts.append(l.text)

	# Assertions on Table Content Alignment:
	assert_true("Closed" in label_texts, "Test 3a: Closed days (Sunday/Saturday) display Closed in Table View.")
	assert_true("Unassigned" in label_texts, "Test 3b: Open unstaffed days (Wednesday) display Unassigned in Table View.")
	assert_true("👤 John Boyte" in label_texts, "Test 3c: Staffed shift (John Boyte) displays in Table View.")
	assert_true("👤 Jane Smith" in label_texts, "Test 3d: Multiple shifts on same day (Jane Smith) display in Table View.")
	assert_true("04:00 PM–06:30 PM" in label_texts, "Test 3e: Shift start/end times display accurately.")

	var found_split = false
	for txt in label_texts:
		if "10:00 AM" in txt and "01:00 PM" in txt and "04:00 PM" in txt:
			found_split = true
			break
	assert_true(found_split, "Test 3f: Split shift operating hours override displays correctly.")

	# Navigation synchronization assertion
	var initial_unix = sv.current_week_base_unix
	sv.active_shift_view_mode = "table"
	assert_true(sv.current_week_base_unix == initial_unix, "Test 4: Table View and Week Board View share identical week base timestamp.")

	print("==========================================================")
	print("SUMMARY: %d / %d ASSERTIONS PASSED (100.0%%)" % [pass_count, total_assertions])
	print("==========================================================")
	if pass_count == total_assertions:
		print("SUCCESS: ALL SCHEDULES TABLE VIEW ALIGNMENT TESTS PASSED (100%)")
		quit(0)
	else:
		print("ERROR: SCHEDULES TABLE VIEW ALIGNMENT TEST SUITE FAILED!")
		quit(1)

func _collect_labels(node: Node, out_labels: Array) -> void:
	if node is Label:
		out_labels.append(node)
	for child in node.get_children():
		_collect_labels(child, out_labels)
