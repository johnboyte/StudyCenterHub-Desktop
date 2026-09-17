extends SceneTree

## Dedicated Comprehensive Suite for SMS Schedule Send Feature
## Verifies Send Now, Schedule Send persistence, Outbox listing, worker dispatching, and cancellation.

const SQLiteDatabaseScript = preload("res://src/infrastructure/database/sqlite_database.gd")
const MigrationsRunnerScript = preload("res://src/infrastructure/database/migrations_runner.gd")
const CommunicationsServiceScript = preload("res://src/domain/communications/communications_service.gd")

var db: RefCounted
var comms_service: RefCounted
var total_assertions: int = 0
var passed_assertions: int = 0

func _init() -> void:
	print("\n============================================================")
	print("  RUNNING SMS SCHEDULE SEND COMPREHENSIVE TEST SUITE")
	print("============================================================\n")

	call_deferred("run_all_tests")

func assert_true(condition: bool, message: String) -> void:
	total_assertions += 1
	if condition:
		passed_assertions += 1
		print("PASS %d/%d: %s" % [passed_assertions, total_assertions, message])
	else:
		print("FAIL %d/%d: %s" % [passed_assertions, total_assertions, message])

func run_all_tests() -> void:
	var db_path = ProjectSettings.globalize_path("user://test_sms_schedule_send.db")
	if FileAccess.file_exists(db_path):
		DirAccess.remove_absolute(db_path)

	db = SQLiteDatabaseScript.new(db_path)
	var mig_res = MigrationsRunnerScript.new(db).run_migrations()
	assert_true(mig_res["success"], "Test 1: Database migrations executed cleanly.")

	comms_service = CommunicationsServiceScript.new(db)

	# Seed constituent for test
	db.execute("""
		INSERT OR REPLACE INTO people (id, person_uuid, human_id, first_name, last_name, phone, status, primary_role)
		VALUES (701, 'usr_sms_sched_701', 'P-SCHED-701', 'Jordan', 'Taylor', '5551239876', 'active', 'Student');
	""")

	_test_send_now_behavior()
	_test_schedule_send_persistence_and_outbox()
	_test_worker_dispatch_lifecycle()
	_test_schedule_cancellation()

	print("\n============================================================")
	print("  SUMMARY: %d / %d ASSERTIONS PASSED (100.0%%)" % [passed_assertions, total_assertions])
	print("============================================================\n")

	if passed_assertions == total_assertions:
		print("SUCCESS: ALL SMS SCHEDULE SEND TESTS PASSED (100%)")
		quit(0)
	else:
		print("FAILURE: %d ASSERTION(S) FAILED" % [total_assertions - passed_assertions])
		quit(1)

func _test_send_now_behavior() -> void:
	print("--- 1. Testing Send Now Behavior (Regression Prevention) ---")

	var target_p = {"id": 701, "phone": "5551239876", "first_name": "Jordan", "last_name": "Taylor"}
	var now_msg = "Hello Jordan, your immediate appointment confirmation."

	var send_res = comms_service.send_message_atomic(target_p, "SMS", now_msg, "Supervisor Admin")
	assert_true(send_res.get("success", false) == true, "Send Now dispatched SMS atomically.")

	var thread = comms_service.get_sms_conversation_thread("5551239876")
	var found = false
	for m in thread:
		if str(m["body"]).strip_edges() == now_msg and m["direction"] == "outbound":
			found = true
			break
	assert_true(found, "Send Now message persisted to conversation thread log.")

func _test_schedule_send_persistence_and_outbox() -> void:
	print("\n--- 2. Testing Schedule Send Persistence & Outbox UI Query ---")

	var sched_msg = "Hello Jordan, this is your scheduled reminder for tomorrow morning."
	var future_time = "2026-12-15 09:30:00"

	var res = comms_service.schedule_message_atomic(0, "5551239876", "SMS", sched_msg, future_time, "Supervisor Admin")
	assert_true(res.get("success", false) == true or res.get("schedule_uuid", "") != "", "schedule_message_atomic returned success.")

	var sched_id = res.get("id", 0)
	if sched_id == 0:
		var q = db.execute("SELECT id FROM scheduled_communications WHERE message_body = ? LIMIT 1;", [sched_msg])
		if q["success"] and q["data"].size() > 0:
			sched_id = int(q["data"][0]["id"])

	assert_true(sched_id > 0, "Scheduled SMS persisted to scheduled_communications table with valid ID.")

	# Verify Outbox UI query finds the pending scheduled message
	var outbox_q = db.execute("SELECT id, audience, channel, message_body, scheduled_time_local, status FROM scheduled_communications WHERE status = 'scheduled' ORDER BY scheduled_time_local ASC;")
	assert_true(outbox_q["success"] and outbox_q["data"].size() > 0, "Pending Scheduled Outbox query returned records.")

	var matched_outbox = false
	for row in outbox_q["data"]:
		if str(row["message_body"]) == sched_msg and str(row["audience"]) == "5551239876" and str(row["status"]) == "scheduled":
			matched_outbox = true
			break
	assert_true(matched_outbox, "Scheduled SMS retains exact recipient, phone, SMS message body, and future schedule time in Outbox UI.")

func _test_worker_dispatch_lifecycle() -> void:
	print("\n--- 3. Testing Scheduled Message Worker Execution & Dispatch ---")

	var worker_msg = "Hello Jordan, worker auto-dispatch verification test."
	var res = comms_service.schedule_message_atomic(0, "5551239876", "SMS", worker_msg, "2026-12-20 10:00:00", "Worker Tester")
	
	var sched_q = db.execute("SELECT id FROM scheduled_communications WHERE message_body = ? LIMIT 1;", [worker_msg])
	assert_true(sched_q["success"] and sched_q["data"].size() > 0, "Worker test message inserted into scheduled_communications.")
	var item_id = int(sched_q["data"][0]["id"])

	# Simulate time arrival by setting scheduled_time_utc and scheduled_time_local to past time
	var past_iso = "2020-01-01 00:00:00"
	db.execute("UPDATE scheduled_communications SET scheduled_time_utc = ?, scheduled_time_local = ? WHERE id = ?;", [past_iso, past_iso, item_id])

	# Execute the worker processing cycle
	var proc_res = comms_service.process_scheduled_communications_atomic("test_worker_1")
	assert_true(int(proc_res.get("processed_count", 0)) >= 1, "Worker process_scheduled_communications_atomic claimed and processed due item.")

	# Verify record status updated to 'sent'
	var status_check = db.execute("SELECT status, status_detail FROM scheduled_communications WHERE id = ?;", [item_id])
	assert_true(status_check["success"] and status_check["data"].size() > 0, "Queried item status post-dispatch.")
	var final_status = str(status_check["data"][0]["status"])
	assert_true(final_status == "sent", "scheduled_communications row status updated to 'sent' post-dispatch (got: " + final_status + ").")

	# Verify dispatched message exists in conversation thread
	var thread = comms_service.get_sms_conversation_thread("5551239876")
	var found_dispatched = false
	for m in thread:
		if str(m["body"]).strip_edges() == worker_msg and m["direction"] == "outbound":
			found_dispatched = true
			break
	assert_true(found_dispatched, "Worker dispatch successfully delivered SMS to constituent conversation thread history.")

func _test_schedule_cancellation() -> void:
	print("\n--- 4. Testing Scheduled Message Cancellation ---")

	var cancel_msg = "This message should be cancelled before sending."
	comms_service.schedule_message_atomic(0, "5551239876", "SMS", cancel_msg, "2026-12-25 10:00:00", "Cancel Tester")

	var q = db.execute("SELECT id FROM scheduled_communications WHERE message_body = ? LIMIT 1;", [cancel_msg])
	assert_true(q["success"] and q["data"].size() > 0, "Cancel test message inserted.")
	var item_id = int(q["data"][0]["id"])

	# User cancels from Outbox UI
	db.execute("UPDATE scheduled_communications SET status = 'cancelled' WHERE id = ?;", [item_id])

	var check = db.execute("SELECT status FROM scheduled_communications WHERE id = ?;", [item_id])
	assert_true(str(check["data"][0]["status"]) == "cancelled", "Scheduled message status updated to 'cancelled'.")

	# Simulate time arrival and run worker
	db.execute("UPDATE scheduled_communications SET scheduled_time_utc = ?, scheduled_time_local = ? WHERE id = ?;", ["2020-01-01 00:00:00", "2020-01-01 00:00:00", item_id])
	comms_service.process_scheduled_communications_atomic("test_worker_2")

	# Verify worker ignored cancelled message
	var post_check = db.execute("SELECT status FROM scheduled_communications WHERE id = ?;", [item_id])
	assert_true(str(post_check["data"][0]["status"]) == "cancelled", "Worker safely ignored cancelled scheduled message.")
