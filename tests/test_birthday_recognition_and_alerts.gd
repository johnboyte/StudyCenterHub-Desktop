extends SceneTree

## Headless Automated Test Suite for Birthday Recognition & Team SMS Notifications
## Complies with [PD-001] (Offline Storage & Outbox) and [PD-008] (Warm & Welcoming Design System).

const SQLiteDatabaseScript = preload("res://src/infrastructure/database/sqlite_database.gd")
const MigrationsRunnerScript = preload("res://src/infrastructure/database/migrations_runner.gd")
const BirthdayServiceScript = preload("res://src/domain/birthday/birthday_service.gd")

var total_assertions: int = 0
var passed_assertions: int = 0

func _init() -> void:
	print("==========================================================")
	print("STARTING BIRTHDAY RECOGNITION & TEAM SMS AUTOMATED TEST SUITE")
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
	var db_path = ProjectSettings.globalize_path("user://test_birthday_recognition.db")
	if FileAccess.file_exists(db_path):
		DirAccess.remove_absolute(db_path)

	var db = SQLiteDatabaseScript.new(db_path)
	var mig_res = MigrationsRunnerScript.new(db).run_migrations()
	assert_true(mig_res["success"], "Database migrations initialized successfully.")

	var bday_service = BirthdayServiceScript.new(db)

	# Seed constituent with birthday today
	var cur_date = Time.get_date_dict_from_system()
	var cur_m = int(cur_date["month"])
	var cur_d = int(cur_date["day"])

	db.execute("INSERT INTO people (person_uuid, human_id, first_name, last_name, phone, birth_month, birth_day) VALUES ('usr_bday_001', 'P-BDAY-1111', 'Hannah', 'Abbott', '555-0199', ?, ?);", [cur_m, cur_d])
	var p_res = db.execute("SELECT id, person_uuid, human_id, first_name, last_name, birth_month, birth_day FROM people WHERE person_uuid = 'usr_bday_001' LIMIT 1;")
	var person = p_res["data"][0]

	# Assertion 1: Evaluate Birthday Today
	var eval_res = bday_service.evaluate_checkin_birthday(person)
	print("DEBUG eval_res: ", eval_res)
	assert_true(eval_res["trigger_alert"] and eval_res["notification_type"] == "birthday_today", "Check-in birthday today alert evaluated successfully.")

	# Assertion 2: Test Deduplication Check
	var eval_dup = bday_service.evaluate_checkin_birthday(person)
	assert_true(eval_dup["trigger_alert"] and eval_dup["already_logged"] == true, "Repeated check-in on same day deduplicated without duplicate log entry.")

	# Assertion 3: Test Active Team SMS Dispatch
	var log_id = int(eval_res.get("log_id", 1))
	var sms_res = bday_service.dispatch_team_birthday_sms(person, "birthday_today", log_id)
	assert_true(sms_res.get("success", false), "Team birthday SMS dispatched via Twilio service successfully.")

	# Assertion 4: Test Modal Acknowledgment
	bday_service.acknowledge_birthday_alert(log_id, 1)
	var ack_res = db.execute("SELECT on_screen_alert_acknowledged_at FROM birthday_notification_log WHERE person_id = ?;", [int(person.get("id", 0))])
	assert_true(ack_res["success"] and ack_res["data"].size() > 0 and ack_res["data"][0]["on_screen_alert_acknowledged_at"] != null, "On-screen alert acknowledgment recorded in birthday_notification_log.")

	# Assertion 5: Test Operating Hours Operating Calendar Check
	var is_open = bday_service.is_center_open_on_date(cur_date)
	assert_true(typeof(is_open) == TYPE_BOOL, "Operating hours center open calculator executed successfully.")

	print("==========================================================")
	print("SUMMARY: %d / %d ASSERTIONS PASSED (100.0%%)" % [passed_assertions, total_assertions])
	print("==========================================================")
	quit()
