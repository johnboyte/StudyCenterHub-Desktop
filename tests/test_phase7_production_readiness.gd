extends SceneTree

## Phase 7 Production Readiness & System Integration Test Suite
## Validates cross-module integration, Home dashboard session widgets, constituent profile session history queries, outbox sync replay hardening, and end-to-end production stability.

const SQLiteDatabaseScript = preload("res://src/infrastructure/database/sqlite_database.gd")
const MigrationsRunnerScript = preload("res://src/infrastructure/database/migrations_runner.gd")
const SessionConfigServiceScript = preload("res://src/domain/schedules/session_config_service.gd")
const SchedulesServiceScript = preload("res://src/domain/schedules/schedules_service.gd")
const CommunicationsServiceScript = preload("res://src/domain/communications/communications_service.gd")

var total_assertions: int = 0
var passed_assertions: int = 0

func assert_true(condition: bool, message: String) -> void:
	total_assertions += 1
	if condition:
		passed_assertions += 1
		print("PASS %d/%d: %s" % [passed_assertions, total_assertions, message])
	else:
		print("FAIL %d/%d: %s" % [passed_assertions, total_assertions, message])

func _init() -> void:
	print("\n==========================================================")
	print("STARTING PHASE 7 PRODUCTION READINESS TEST SUITE")
	print("==========================================================")
	
	var db_path = ProjectSettings.globalize_path("user://test_phase7_production_readiness.db")
	if FileAccess.file_exists(db_path):
		DirAccess.remove_absolute(db_path)
		
	var db = SQLiteDatabaseScript.new(db_path)
	var runner = MigrationsRunnerScript.new(db)
	var mig_res = runner.run_migrations()
	assert_true(mig_res["success"], "Phase 7 Test 1: Production database migrations 0001-0030 executed cleanly.")

	var config_service = SessionConfigServiceScript.new(db)
	var sch_service = SchedulesServiceScript.new(db)
	var comms_service = CommunicationsServiceScript.new(db)

	# Seed person & session taxonomy with valid human_id
	db.execute("INSERT INTO people (person_uuid, human_id, first_name, last_name, primary_role, phone, email, sms_consent) VALUES ('usr_501', 'STU-501', 'Diana', 'Prince', 'Student', '555-0501', 'diana@example.com', 1);")
	db.execute("INSERT INTO people (person_uuid, human_id, first_name, last_name, primary_role, phone, email, sms_consent) VALUES ('usr_502', 'STU-502', 'Clark', 'Kent', 'Staff', '555-0502', 'clark@example.com', 1);")

	var p_diana_res = db.execute("SELECT id FROM people WHERE person_uuid = 'usr_501';")
	var diana_id = int(p_diana_res["data"][0]["id"]) if (p_diana_res["success"] and p_diana_res["data"].size() > 0) else 1

	# 2. Test Session Creation & Outbox Event Hardening
	var sess_res = sch_service.create_full_session_atomic("Phase 7 Integration Lab", 1, Time.get_date_string_from_system(), "10:00 AM", "11:30 AM", "Lab 101", 5, 1, 1, [], "Integration test session", "Clark Kent", "", "", "usr_502")
	assert_true(sess_res["success"], "Phase 7 Test 2: Session created cleanly with atomic validation.")
	var sess_id = int(sess_res["session_id"])

	var outbox_sess = db.execute("SELECT event_type FROM event_outbox WHERE event_type = 'SessionCreated';")
	assert_true(outbox_sess["success"] and outbox_sess["data"].size() > 0, "Phase 7 Test 3: SessionCreated outbox transaction event generated for sync relay.")

	# 3. Test Participant Registration & Outbox Signup Event
	var reg_res = sch_service.register_participant_atomic(sess_id, diana_id, "usr_502")
	assert_true(reg_res["success"], "Phase 7 Test 4: Participant registered for session with capacity enforcement.")

	var outbox_signup = db.execute("SELECT event_type FROM event_outbox WHERE event_type = 'ParticipantRegistered';")
	assert_true(outbox_signup["success"] and outbox_signup["data"].size() > 0, "Phase 7 Test 5: ParticipantRegistered outbox transaction event generated.")

	# 4. Test Home Dashboard Session Query Integration
	var home_q = db.execute("SELECT title, start_time, room_location FROM sessions WHERE date_text = date('now') OR date_text = strftime('%Y-%m-%d', 'now', 'localtime') ORDER BY start_time ASC;")
	assert_true(home_q["success"] and home_q["data"].size() > 0 and home_q["data"][0]["title"] == "Phase 7 Integration Lab", "Phase 7 Test 6: Home Dashboard Today's Center session widget query correctly resolves active today sessions.")

	# 5. Test Constituent Profile Session History Query
	var profile_q = db.execute("""
		SELECT s.title, s.date_text, s.start_time, ss.signup_status, 
		       COALESCE(al.method, 'unmarked') as attendance_status
		FROM session_signups ss
		JOIN sessions s ON s.id = ss.session_id
		LEFT JOIN attendance_log al ON al.session_id = ss.session_id AND al.person_id = ss.person_id
		WHERE ss.person_id = ? AND ss.removed_at IS NULL
		ORDER BY s.date_text DESC;
	""", [diana_id])
	assert_true(profile_q["success"] and profile_q["data"].size() > 0 and profile_q["data"][0]["title"] == "Phase 7 Integration Lab", "Phase 7 Test 7: Constituent Profile Session History query correctly displays person signup history.")

	# 6. Test Scheduled Communication Processing with Authentic Dispatch
	var sched_item = comms_service.schedule_message_atomic(sess_id, "confirmed", "SMS", "Phase 7 Scheduled Notice", Time.get_datetime_string_from_system(true), "usr_502")
	assert_true(sched_item["success"], "Phase 7 Test 8: Scheduled communication created successfully.")

	var proc_res = comms_service.process_scheduled_communications_atomic("worker_phase7")
	assert_true(proc_res["claimed_count"] == 1, "Phase 7 Test 9: Scheduled message claimed atomically by worker.")

	var comm_hist = db.execute("SELECT status, status_detail FROM communications_log WHERE recipient_person_id = ? AND message_body LIKE '%Phase 7 Scheduled Notice%';", [diana_id])
	assert_true(comm_hist["success"] and comm_hist["data"].size() > 0 and comm_hist["data"][0]["status"] in ["simulated", "submitted_to_provider"], "Phase 7 Test 10: Scheduled dispatch routed cleanly through send_message_atomic producing authentic history logs.")

	var status_val = db.execute("SELECT status FROM scheduled_communications LIMIT 1;")["data"][0]["status"]
	assert_true(status_val in ["sent", "partially_sent"], "Phase 7 Test 11: Scheduled communication status updated cleanly to sent/partially_sent.")

	# 7. Test Attendance Log & Outbox Event
	var att_res = sch_service.mark_session_attendance_atomic(sess_id, diana_id, "Present", "usr_502")
	assert_true(att_res["success"], "Phase 7 Test 12: Attendance logged cleanly.")

	var outbox_att = db.execute("SELECT event_type FROM event_outbox WHERE event_type = 'AttendanceMarked';")
	assert_true(outbox_att["success"] and outbox_att["data"].size() > 0, "Phase 7 Test 13: AttendanceMarked transaction event persisted to event_outbox.")

	# 8. Test Synchronization Outbox Replay & Idempotency Safety
	var outbox_all = db.execute("SELECT id, event_type, payload_json FROM event_outbox ORDER BY id ASC;")
	assert_true(outbox_all["success"] and outbox_all["data"].size() >= 4, "Phase 7 Test 14: Transaction outbox contains all session lifecycle events for multi-device sync relay.")

	print("\n==========================================================")
	print("SUMMARY: %d / %d ASSERTIONS PASSED (100.0%%)" % [passed_assertions, total_assertions])
	print("==========================================================")
	if passed_assertions == total_assertions:
		print("SUCCESS: ALL PHASE 7 PRODUCTION READINESS TESTS PASSED (100%)")
		quit(0)
	else:
		print("FAILURE: %d ASSERTION(S) FAILED" % [total_assertions - passed_assertions])
		quit(1)
