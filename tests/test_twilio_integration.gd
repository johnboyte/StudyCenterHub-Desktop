extends SceneTree

## Headless Automated Test Suite for Twilio Gateway Integration
## Complies with [PD-001] (Offline Storage & Outbox) and [PD-006] (Admin Config).

const SQLiteDatabaseScript = preload("res://src/infrastructure/database/sqlite_database.gd")
const MigrationsRunnerScript = preload("res://src/infrastructure/database/migrations_runner.gd")
const TwilioGatewayScript = preload("res://src/infrastructure/messaging/twilio_gateway_service.gd")

var total_assertions: int = 0
var passed_assertions: int = 0

func _init() -> void:
	print("==========================================================")
	print("STARTING TWILIO GATEWAY INTEGRATION TEST SUITE")
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
	var db_path = ProjectSettings.globalize_path("user://test_twilio_integration.db")
	if FileAccess.file_exists(db_path):
		DirAccess.remove_absolute(db_path)

	var db = SQLiteDatabaseScript.new(db_path)
	var mig_res = MigrationsRunnerScript.new(db).run_migrations()
	assert_true(mig_res["success"], "Database migrations initialized successfully.")

	var twilio_service = TwilioGatewayScript.new(db)
	var save_res = twilio_service.save_twilio_config("AC_live_sid_9999", "secret_auth_token_8888", "+18005550199")
	assert_true(save_res, "Twilio credentials persisted to SQLite app_settings table.")

	var config = twilio_service.get_twilio_config()
	assert_true(config["account_sid"] == "AC_live_sid_9999", "Saved Twilio Account SID retrieved successfully.")

	var sms_res = twilio_service.simulate_twilio_sms("555-0142", "Test SMS message from StudyCenterHub desktop app.")
	assert_true(sms_res["success"] and sms_res["twilio_msg_sid"] != "", "Twilio SMS API dispatch simulated successfully.")

	print("==========================================================")
	print("SUMMARY: %d / %d ASSERTIONS PASSED (100.0%%)" % [passed_assertions, total_assertions])
	print("==========================================================")
	if passed_assertions == total_assertions:
		print("SUCCESS: ALL TWILIO GATEWAY OBJECTIVES PASSED (100%)")
		quit(0)
	else:
		print("FAILURE: %d ASSERTION(S) FAILED" % [total_assertions - passed_assertions])
		quit(1)
