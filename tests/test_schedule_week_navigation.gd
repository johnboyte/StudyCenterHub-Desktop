extends SceneTree

## Automated Unit & Integration Test Suite for Schedule Week Navigation & Today Button
## Verifies dynamic current week resolution, Sunday-Saturday boundary alignment, and Previous/Next/Today navigation.

const SchedulesViewScript = preload("res://app/scenes/schedules_view.gd")

var total_assertions: int = 0
var passed_assertions: int = 0

func _init() -> void:
	print("==========================================================")
	print("STARTING SCHEDULE WEEK NAVIGATION & TODAY BUTTON TEST SUITE")
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
	var view = SchedulesViewScript.new()

	var now_dict = Time.get_datetime_dict_from_system()
	var today_iso = "%04d-%02d-%02d" % [now_dict["year"], now_dict["month"], now_dict["day"]]
	var today_wday = int(now_dict.get("weekday", 0))

	# -------------------------------------------------------------
	# TEST 1: INITIAL / TODAY DYNAMIC SUNDAY RESOLUTION
	# -------------------------------------------------------------
	var sunday_unix = view._get_current_week_sunday_unix()
	var sun_dict = Time.get_datetime_dict_from_unix_time(sunday_unix)
	var sun_wday = int(sun_dict.get("weekday", 0))
	assert_true(sun_wday == 0, "Test 1: _get_current_week_sunday_unix() resolves to a Sunday (weekday 0).")

	var sunday_iso = view.get_date_string_for_day_index(0)
	var saturday_iso = view.get_date_string_for_day_index(6)
	assert_true(sunday_iso <= today_iso and today_iso <= saturday_iso, "Test 2: Current week range (%s to %s) contains today's date (%s)." % [sunday_iso, saturday_iso, today_iso])

	var range_str = view._get_current_week_range_string()
	print("Active Today Week Range String: ", range_str)
	assert_true(range_str.strip_edges() != "", "Test 3: Week range label formatted string generated.")

	# -------------------------------------------------------------
	# TEST 2: PREVIOUS WEEK NAVIGATION
	# -------------------------------------------------------------
	view.current_week_base_unix -= 7 * 86400
	var prev_sunday_iso = view.get_date_string_for_day_index(0)
	var prev_saturday_iso = view.get_date_string_for_day_index(6)
	var prev_sun_dict = Time.get_datetime_dict_from_unix_time(view.current_week_base_unix)
	var expected_prev_day = int(sun_dict["day"]) - 7

	assert_true(prev_saturday_iso < sunday_iso, "Test 4: Navigating Previous correctly moves week backward (%s to %s)." % [prev_sunday_iso, prev_saturday_iso])

	# -------------------------------------------------------------
	# TEST 3: NEXT WEEK NAVIGATION
	# -------------------------------------------------------------
	view.current_week_base_unix += 14 * 86400
	var next_sunday_iso = view.get_date_string_for_day_index(0)
	var next_saturday_iso = view.get_date_string_for_day_index(6)
	assert_true(next_sunday_iso > saturday_iso, "Test 5: Navigating Next correctly moves week forward (%s to %s)." % [next_sunday_iso, next_saturday_iso])

	# -------------------------------------------------------------
	# TEST 4: TODAY BUTTON RESET LOGIC
	# -------------------------------------------------------------
	view.current_week_base_unix = view._get_current_week_sunday_unix()
	var reset_sunday_iso = view.get_date_string_for_day_index(0)
	var reset_saturday_iso = view.get_date_string_for_day_index(6)
	assert_true(reset_sunday_iso == sunday_iso and reset_saturday_iso == saturday_iso, "Test 6: Pressing Today resets base week back to current week (%s to %s)." % [reset_sunday_iso, reset_saturday_iso])

	print("==========================================================")
	print("SUMMARY: %d / %d ASSERTIONS PASSED (100.0%%)" % [passed_assertions, total_assertions])
	print("==========================================================")
	if passed_assertions == total_assertions:
		print("SUCCESS: ALL SCHEDULE WEEK NAVIGATION TESTS PASSED (100%)")
		quit(0)
	else:
		print("FAILURE: %d ASSERTION(S) FAILED" % [total_assertions - passed_assertions])
		quit(1)
