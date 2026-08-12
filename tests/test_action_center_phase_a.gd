extends SceneTree

## Automated Test Suite for Action Center Phase A Queues
## Verifies registration, count SQL accuracy, item resolution, QueueController synchronization, and parameterized navigation.

const SQLiteDatabaseScript = preload("res://src/infrastructure/database/sqlite_database.gd")
const MigrationsRunnerScript = preload("res://src/infrastructure/database/migrations_runner.gd")
const QueueRegistryScript = preload("res://src/domain/work_queue/queue_registry.gd")
const QueueControllerScript = preload("res://src/domain/work_queue/queue_controller.gd")

func _init() -> void:
	print("\n==========================================================")
	print("STARTING ACTION CENTER PHASE A TEST SUITE")
	print("==========================================================")
	call_deferred("_run_tests")

func _run_tests() -> void:
	var db_path = ProjectSettings.globalize_path("user://test_action_center_phase_a.db")
	if FileAccess.file_exists(db_path):
		DirAccess.remove_absolute(db_path)

	var db = SQLiteDatabaseScript.new(db_path)
	var mig_res = MigrationsRunnerScript.new(db).run_migrations()
	if not mig_res.get("success", false):
		print("❌ FAIL: Database migrations 0001-0042 failed.")
		quit(1)
		return
	print("  ✓ PASS: Database migrations 0001-0042 executed cleanly.")

	var qc = QueueControllerScript.new(db)

	# --- Test 1: Verify Registration of Phase A Queues ---
	print("\n[Test 1] Testing QueueRegistry Phase A registration...")
	var phase_a_ids = ["failed_outbound_messages", "unresolved_inbound_sms", "unclaimed_scheduled_broadcasts", "failed_inbound_events"]
	for qid in phase_a_ids:
		if not QueueRegistryScript.has_definition(qid):
			print("❌ FAIL: Missing QueueRegistry definition for: ", qid)
			quit(1)
			return
	print("  ✓ PASS: All 4 Phase A queues successfully registered in QueueRegistry.")

	# --- Test 2: Failed Outbound Messages Queue Count, Callback & Resolution ---
	print("\n[Test 2] Testing failed_outbound_messages count, callback, and resolution...")
	db.execute("INSERT INTO communications_log (message_uuid, recipient_name, recipient_contact, channel, message_body, delivery_status, error_code) VALUES ('msg-f1', 'Alice', '555-0101', 'SMS', 'Hello', 'failed', 'ERR_TWILIO_30008');")

	var cnt_f = qc.get_queue_count("failed_outbound_messages")
	if cnt_f != 1:
		print("❌ FAIL: Expected count = 1 for failed_outbound_messages, got: ", cnt_f)
		quit(1)
		return
	print("  ✓ PASS: failed_outbound_messages count_sql executed accurately (count = 1).")

	# Verify status update helper in TwilioGatewayService
	const TwilioGatewayScript = preload("res://src/infrastructure/messaging/twilio_gateway_service.gd")
	var twilio = TwilioGatewayScript.new(db)
	twilio.process_delivery_status_update("msg-f1", "delivered", "")

	var updated_rec = db.execute("SELECT delivery_status FROM communications_log WHERE message_uuid = 'msg-f1';")
	if not updated_rec["success"] or updated_rec["data"][0]["delivery_status"] != "delivered":
		print("❌ FAIL: Twilio status callback update failed.")
		quit(1)
		return
	print("  ✓ PASS: Twilio delivery status callback update verified.")

	if qc.get_queue_count("failed_outbound_messages") != 0:
		print("❌ FAIL: failed_outbound_messages count did not decrement to 0 after resolution.")
		quit(1)
		return
	print("  ✓ PASS: failed_outbound_messages resolution verified.")

	# --- Test 3: Unresolved Inbound SMS Queue Count & Resolution ---
	print("\n[Test 3] Testing unresolved_inbound_sms count and resolution...")
	db.execute("INSERT INTO inbound_sms_log (message_sid, from_phone_e164, raw_body, is_read, follow_up_status) VALUES ('sid-101', '+15550199', 'Need help with registration', 0, 'Unassigned');")

	var cnt_sms = qc.get_queue_count("unresolved_inbound_sms")
	if cnt_sms != 1:
		print("❌ FAIL: Expected count = 1 for unresolved_inbound_sms, got: ", cnt_sms)
		quit(1)
		return
	print("  ✓ PASS: unresolved_inbound_sms count_sql executed accurately (count = 1).")

	# Verify read vs follow_up_status distinction
	db.execute("UPDATE inbound_sms_log SET is_read = 1 WHERE message_sid = 'sid-101';")
	var cnt_unread_but_unresolved = qc.get_queue_count("unresolved_inbound_sms")
	if cnt_unread_but_unresolved != 1:
		print("❌ FAIL: Read message with follow_up_status = 'Unassigned' was incorrectly excluded from queue.")
		quit(1)
		return
	print("  ✓ PASS: Verified read message needing follow-up correctly remains in queue.")

	# Complete follow-up
	var recs_sms = qc.fetch_queue_records("unresolved_inbound_sms")
	var item_id_sms = int(recs_sms[0]["id"])
	db.execute("UPDATE inbound_sms_log SET is_read = 1, follow_up_status = 'Completed' WHERE id = ?;", [item_id_sms])

	if qc.get_queue_count("unresolved_inbound_sms") != 0:
		print("❌ FAIL: unresolved_inbound_sms count did not decrement to 0 after resolution.")
		quit(1)
		return
	print("  ✓ PASS: unresolved_inbound_sms resolution verified.")

	# --- Test 4: Unclaimed Scheduled Broadcasts Queue Count & Resolution ---
	print("\n[Test 4] Testing unclaimed_scheduled_broadcasts count and resolution...")
	db.execute("INSERT INTO scheduled_communications (schedule_uuid, audience, channel, message_body, scheduled_time_utc, scheduled_time_local, status) VALUES ('sch-101', 'All Students', 'SMS', 'Reminder', date('now', '-1 day'), date('now', '-1 day'), 'scheduled');")

	var cnt_bc = qc.get_queue_count("unclaimed_scheduled_broadcasts")
	if cnt_bc != 1:
		print("❌ FAIL: Expected count = 1 for unclaimed_scheduled_broadcasts, got: ", cnt_bc)
		quit(1)
		return
	print("  ✓ PASS: unclaimed_scheduled_broadcasts count_sql executed accurately (count = 1).")

	var recs_bc = qc.fetch_queue_records("unclaimed_scheduled_broadcasts")
	var item_id_bc = int(recs_bc[0]["id"])
	db.execute("UPDATE scheduled_communications SET status = 'cancelled' WHERE id = ?;", [item_id_bc])

	if qc.get_queue_count("unclaimed_scheduled_broadcasts") != 0:
		print("❌ FAIL: unclaimed_scheduled_broadcasts count did not decrement to 0 after resolution.")
		quit(1)
		return
	print("  ✓ PASS: unclaimed_scheduled_broadcasts resolution verified.")

	# --- Test 5: Failed Inbound Events Queue Count & Resolution ---
	print("\n[Test 5] Testing failed_inbound_events count and resolution...")
	db.execute("INSERT INTO event_inbox (event_uuid, event_type, sequence_num, status, retry_count, error_message) VALUES ('evt-in-101', 'person.updated', 1, 'failed', 5, 'Network timeout');")

	var cnt_evt = qc.get_queue_count("failed_inbound_events")
	if cnt_evt != 1:
		print("❌ FAIL: Expected count = 1 for failed_inbound_events, got: ", cnt_evt)
		quit(1)
		return
	print("  ✓ PASS: failed_inbound_events count_sql executed accurately (count = 1).")

	var recs_evt = qc.fetch_queue_records("failed_inbound_events")
	var item_id_evt = int(recs_evt[0]["id"])
	db.execute("UPDATE event_inbox SET status = 'processed' WHERE id = ?;", [item_id_evt])

	if qc.get_queue_count("failed_inbound_events") != 0:
		print("❌ FAIL: failed_inbound_events count did not decrement to 0 after resolution.")
		quit(1)
		return
	print("  ✓ PASS: failed_inbound_events resolution verified.")

	# --- Test 6: Verify Parameterized Navigation to Views ---
	print("\n[Test 6] Testing parameterized navigation contexts...")
	const ComViewScript = preload("res://app/scenes/communications_view.gd")
	var com_view = ComViewScript.new()
	com_view.db = db
	com_view.configure_queue_mode({"queue_mode": true, "queue_id": "failed_outbound_messages"})
	if not com_view.is_queue_mode or com_view.active_queue_id != "failed_outbound_messages":
		print("❌ FAIL: CommunicationsView failed to configure queue mode for failed_outbound_messages.")
		quit(1)
		return
	print("  ✓ PASS: Parameterized queue mode navigation verified for CommunicationsView.")

	print("\n==========================================================")
	print("ALL ACTION CENTER PHASE A TESTS PASSED! (6/6)")
	print("==========================================================\n")
	quit(0)
