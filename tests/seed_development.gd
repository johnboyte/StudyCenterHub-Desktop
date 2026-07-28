extends SceneTree

## Repeatable Database Seeder for Development Environment
## Forces target to studycenterhub_development.db and populates it with Real Life test data

const SQLiteDatabaseScript = preload("res://src/infrastructure/database/sqlite_database.gd")
const MigrationsRunnerScript = preload("res://src/infrastructure/database/migrations_runner.gd")

func _init() -> void:
	print("==========================================================")
	print("STARTING DEVELOPMENT DATABASE SEEDING ENGINE")
	print("==========================================================")

	# Safety: Force STUDYCENTERHUB_ENV to development so Staging/Production are never affected
	OS.set_environment("STUDYCENTERHUB_ENV", "development")
	
	var db = SQLiteDatabaseScript.new()
	print("[Seed] Target Database Path: ", db.db_path)

	# 1. Run migrations first to ensure database schema is up-to-date
	var mig_runner = MigrationsRunnerScript.new(db)
	var mig_res = mig_runner.run_migrations()
	if not mig_res["success"]:
		print("FAIL: Migrations failed during seed: ", mig_res["error"])
		quit(1)
		return
	print("[Seed] Database migrations ran successfully. (New: ", mig_res["newly_executed"], ")")

	# 2. Ensure dynamic tables (created in controllers, not migrations) exist before reset
	db.execute("""
		CREATE TABLE IF NOT EXISTS app_settings (
			setting_key TEXT PRIMARY KEY,
			setting_value TEXT,
			updated_at TEXT DEFAULT (datetime('now'))
		);
	""")
	
	db.execute("""
		CREATE TABLE IF NOT EXISTS center_hour_overrides (
			id INTEGER PRIMARY KEY AUTOINCREMENT,
			override_date TEXT UNIQUE NOT NULL,
			is_closed INTEGER NOT NULL DEFAULT 0,
			session1_start TEXT NOT NULL DEFAULT '03:00 PM',
			session1_end TEXT NOT NULL DEFAULT '08:00 PM',
			has_split_shift INTEGER NOT NULL DEFAULT 0,
			session2_start TEXT DEFAULT NULL,
			session2_end TEXT DEFAULT NULL
		);
	""")

	# 3. Wipe existing data to guarantee repeatability
	print("[Seed] Resetting database tables...")
	var wipe_queries = [
		"DELETE FROM people;",
		"DELETE FROM attendance_log;",
		"DELETE FROM event_outbox;",
		"DELETE FROM participant_qr_credentials;",
		"DELETE FROM participant_pin_credentials;",
		"DELETE FROM participant_verification_sessions;",
		"DELETE FROM participant_verification_audit;",
		"DELETE FROM person_notes;",
		"DELETE FROM sessions;",
		"DELETE FROM person_sessions;",
		"DELETE FROM session_signups;",
		"DELETE FROM communications_log;",
		"DELETE FROM voicemails;",
		"DELETE FROM schedule_entries;",
		"DELETE FROM center_open_hours;",
		"DELETE FROM volunteer_profiles;",
		"DELETE FROM volunteer_shifts;",
		"DELETE FROM pastoral_notes;",
		"DELETE FROM shift_briefings;",
		"DELETE FROM center_hour_overrides;",
		"DELETE FROM app_settings;",
		"DELETE FROM organization_page_header_messages;",
		"DELETE FROM user_page_header_messages;",
		"DELETE FROM birthday_notification_log;"
	]
	var wipe_res = db.execute_transaction(wipe_queries)
	if not wipe_res["success"]:
		print("FAIL: Database wipe failed: ", wipe_res["error"])
		quit(1)
		return
	print("[Seed] Reset complete.")

	# 4. Seed App Settings & Header Messages
	print("[Seed] Seeding app settings & page headers...")
	var settings_queries = [
		"INSERT INTO app_settings (setting_key, setting_value) VALUES ('ORG_ACCENT_INDEX', '2');", # Warm accent theme
		"INSERT INTO app_settings (setting_key, setting_value) VALUES ('phone_system_default', '+15005550006');",
		"INSERT INTO app_settings (setting_key, setting_value) VALUES ('active_supervisor', 'Sarah Jenkins');",
		"INSERT INTO organization_page_header_messages (page_key, message) VALUES ('home', 'Welcome to Real Life Study Center - Daily Dashboard.');",
		"INSERT INTO organization_page_header_messages (page_key, message) VALUES ('people', 'Constituent Directory - Staff, Volunteers, and Students.');",
		"INSERT INTO organization_page_header_messages (page_key, message) VALUES ('schedules', 'Staffing rosters and study center opening hour controls.');"
	]
	db.execute_transaction(settings_queries)

	# 5. Seed Constituents (People)
	print("[Seed] Seeding constituents...")
	
	# Staff & Admins
	_insert_person(db, "usr_marcus", "ADM-001", "Marcus", "Vance", "Executive Pastor", "staff", "Clear", "509-555-0101")
	_insert_person(db, "usr_sarah", "STF-001", "Sarah", "Jenkins", "Center Director", "staff", "Clear", "509-555-0102")
	
	# Interns
	_insert_person(db, "usr_caleb", "INT-001", "Caleb", "Miller", "Academic Intern", "staff", "Clear", "509-555-0103")
	_insert_person(db, "usr_hannah", "INT-002", "Hannah", "Abbot", "Hospitality Intern", "staff", "Clear", "509-555-0104")

	# Volunteers
	_insert_person(db, "usr_david", "VOL-001", "David", "Sterling", "Volunteer Tutor", "volunteer", "Clear", "509-555-0105")
	_insert_person(db, "usr_elizabeth", "VOL-002", "Elizabeth", "Reed", "Check-In Host", "volunteer", "Clear", "509-555-0106")

	# Participants (Students)
	_insert_person(db, "usr_jordan", "PRT-1001", "Jordan", "Taylor", "Participant", "Participant", "Clear", "509-555-0107")
	_insert_person(db, "usr_samantha", "PRT-1002", "Samantha", "Diaz", "Participant", "Participant", "To Be Confirmed", "509-555-0108")
	_insert_person(db, "usr_michael", "PRT-1003", "Michael", "Chen", "Participant", "Participant", "Clear", "509-555-0109")
	_insert_person(db, "usr_ashley", "PRT-1004", "Ashley", "Cooper", "Participant", "Participant", "Clear", "509-555-0110")

	# Fetch person IDs for foreign key relations
	var p_ids = _get_people_ids(db)
	
	# 6. Seed Credentials
	print("[Seed] Seeding PIN and QR credentials...")
	var cred_queries = [
		# Jordan Taylor PIN & QR
		"INSERT INTO participant_pin_credentials (credential_id, person_id, pin_hash, status) VALUES ('PIN-1001', " + str(p_ids["usr_jordan"]) + ", '1234', 'active');",
		"INSERT INTO participant_qr_credentials (credential_id, person_id, token_hash, token_hint, status) VALUES ('QRCR-1001', " + str(p_ids["usr_jordan"]) + ", 'jordan_qr_hash', 'Jordan Taylor badge', 'active');",
		# Michael Chen PIN & QR
		"INSERT INTO participant_pin_credentials (credential_id, person_id, pin_hash, status) VALUES ('PIN-1003', " + str(p_ids["usr_michael"]) + ", '5678', 'active');",
		"INSERT INTO participant_qr_credentials (credential_id, person_id, token_hash, token_hint, status) VALUES ('QRCR-1003', " + str(p_ids["usr_michael"]) + ", 'michael_qr_hash', 'Michael Chen badge', 'active');"
	]
	db.execute_transaction(cred_queries)

	# 7. Seed Normal Operating Hours
	print("[Seed] Seeding center operating hours...")
	var hours_queries = [
		"INSERT INTO center_open_hours (day_of_week, open_time, close_time, is_closed) VALUES ('Sunday', '12:00 PM', '05:00 PM', 0);",
		"INSERT INTO center_open_hours (day_of_week, open_time, close_time, is_closed) VALUES ('Monday', '03:00 PM', '08:00 PM', 0);",
		"INSERT INTO center_open_hours (day_of_week, open_time, close_time, is_closed) VALUES ('Tuesday', '03:00 PM', '08:00 PM', 0);",
		"INSERT INTO center_open_hours (day_of_week, open_time, close_time, is_closed) VALUES ('Wednesday', '03:00 PM', '08:00 PM', 0);",
		"INSERT INTO center_open_hours (day_of_week, open_time, close_time, is_closed) VALUES ('Thursday', '03:00 PM', '08:00 PM', 0);",
		"INSERT INTO center_open_hours (day_of_week, open_time, close_time, is_closed) VALUES ('Friday', '03:00 PM', '06:00 PM', 0);",
		"INSERT INTO center_open_hours (day_of_week, open_time, close_time, is_closed) VALUES ('Saturday', '10:00 AM', '04:00 PM', 0);"
	]
	db.execute_transaction(hours_queries)

	# 8. Seed Staffing Schedule entries (aligned with week of July 19, 2026)
	print("[Seed] Seeding schedule shifts...")
	var schedule_queries = [
		# Sunday July 19
		"INSERT INTO schedule_entries (entry_uuid, person_name, shift_role, shift_date, start_time, end_time, area, sort_order) VALUES ('shf-101', 'Sarah Jenkins', 'Shift Supervisor (Staff)', '2026-07-19', '12:00 PM', '05:00 PM', 'Study Center', 1);",
		# Monday July 20
		"INSERT INTO schedule_entries (entry_uuid, person_name, shift_role, shift_date, start_time, end_time, area, sort_order) VALUES ('shf-201', 'Sarah Jenkins', 'Shift Supervisor (Staff)', '2026-07-20', '09:00 AM', '03:00 PM', 'Study Center', 1);",
		"INSERT INTO schedule_entries (entry_uuid, person_name, shift_role, shift_date, start_time, end_time, area, sort_order) VALUES ('shf-202', 'Caleb Miller', 'Study Tutor (Intern)', '2026-07-20', '03:00 PM', '08:00 PM', 'Study Room #1', 2);",
		# Tuesday July 21
		"INSERT INTO schedule_entries (entry_uuid, person_name, shift_role, shift_date, start_time, end_time, area, sort_order) VALUES ('shf-301', 'Hannah Abbot', 'Check-In Host (Vol)', '2026-07-21', '09:00 AM', '03:00 PM', 'Gathering Room', 1);",
		"INSERT INTO schedule_entries (entry_uuid, person_name, shift_role, shift_date, start_time, end_time, area, sort_order) VALUES ('shf-302', 'David Sterling', 'Study Tutor (Intern)', '2026-07-21', '03:00 PM', '08:00 PM', 'Study Center', 2);",
		# Wednesday July 22
		"INSERT INTO schedule_entries (entry_uuid, person_name, shift_role, shift_date, start_time, end_time, area, sort_order) VALUES ('shf-401', 'Sarah Jenkins', 'Shift Supervisor (Staff)', '2026-07-22', '03:00 PM', '08:00 PM', 'Gathering Room', 1);",
		"INSERT INTO schedule_entries (entry_uuid, person_name, shift_role, shift_date, start_time, end_time, area, sort_order) VALUES ('shf-402', 'Elizabeth Reed', 'Check-In Host (Vol)', '2026-07-22', '03:00 PM', '08:00 PM', 'Study Center', 2);"
	]
	db.execute_transaction(schedule_queries)

	# 9. Seed Sessions & signups
	print("[Seed] Seeding academic sessions & signups...")
	var session_queries = [
		"INSERT INTO sessions (title, session_type, date_text, start_time, end_time, room_location, max_capacity) VALUES ('Fellows Bible Study', 'Fellows Group', '2026-07-21', '06:30 PM', '08:00 PM', 'Fellowship Hall', 15);",
		"INSERT INTO sessions (title, session_type, date_text, start_time, end_time, room_location, max_capacity) VALUES ('Youth Night Gathering', 'Lead Track', '2026-07-22', '07:00 PM', '08:30 PM', 'Youth Room', 30);"
	]
	db.execute_transaction(session_queries)
	
	# Fetch session IDs
	var s_res = db.execute("SELECT id, title FROM sessions;")
	var s_ids = {}
	if s_res["success"]:
		for r in s_res["data"]:
			s_ids[r["title"]] = r["id"]

	var signup_queries = [
		"INSERT INTO session_signups (signup_uuid, session_id, person_id, signup_status) VALUES ('ssg-001', " + str(s_ids["Fellows Bible Study"]) + ", " + str(p_ids["usr_jordan"]) + ", 'registered');",
		"INSERT INTO session_signups (signup_uuid, session_id, person_id, signup_status) VALUES ('ssg-002', " + str(s_ids["Fellows Bible Study"]) + ", " + str(p_ids["usr_michael"]) + ", 'registered');",
		"INSERT INTO session_signups (signup_uuid, session_id, person_id, signup_status) VALUES ('ssg-003', " + str(s_ids["Youth Night Gathering"]) + ", " + str(p_ids["usr_michael"]) + ", 'registered');",
		"INSERT INTO session_signups (signup_uuid, session_id, person_id, signup_status) VALUES ('ssg-004', " + str(s_ids["Youth Night Gathering"]) + ", " + str(p_ids["usr_ashley"]) + ", 'registered');",
		"INSERT INTO person_sessions (person_id, session_id, attendance_status) VALUES (" + str(p_ids["usr_jordan"]) + ", " + str(s_ids["Fellows Bible Study"]) + ", 'registered');",
		"INSERT INTO person_sessions (person_id, session_id, attendance_status) VALUES (" + str(p_ids["usr_michael"]) + ", " + str(s_ids["Fellows Bible Study"]) + ", 'registered');",
		"INSERT INTO person_sessions (person_id, session_id, attendance_status) VALUES (" + str(p_ids["usr_michael"]) + ", " + str(s_ids["Youth Night Gathering"]) + ", 'registered');",
		"INSERT INTO person_sessions (person_id, session_id, attendance_status) VALUES (" + str(p_ids["usr_ashley"]) + ", " + str(s_ids["Youth Night Gathering"]) + ", 'registered');"
	]
	db.execute_transaction(signup_queries)

	# 10. Seed Attendance History & Logs
	print("[Seed] Seeding attendance logs...")
	var att_queries = [
		"INSERT INTO attendance_log (checkin_uuid, person_id, person_uuid, human_id, check_in_date, check_in_time, method, device_uuid) VALUES ('chk-001', " + str(p_ids["usr_jordan"]) + ", 'usr_jordan', 'PRT-1001', '2026-07-21', '09:12 AM', 'Self Registration QR', 'dev_primary_node');",
		"INSERT INTO attendance_log (checkin_uuid, person_id, person_uuid, human_id, check_in_date, check_in_time, method, device_uuid) VALUES ('chk-002', " + str(p_ids["usr_michael"]) + ", 'usr_michael', 'PRT-1003', '2026-07-21', '10:05 AM', 'Self Registration QR', 'dev_primary_node');"
	]
	db.execute_transaction(att_queries)

	# 11. Seed Communications
	print("[Seed] Seeding messages & voicemails...")
	var comm_queries = [
		"INSERT INTO voicemails (voicemail_uuid, caller_name, caller_phone, duration_sec, transcription, status) VALUES ('vm-001', 'Dorothy Diaz', '509-555-9011', 45, 'Hi, I wanted to confirm if my daughter Samantha Diaz is all set for the Wednesday night study group. Please call me back!', 'new');",
		"INSERT INTO voicemails (voicemail_uuid, caller_name, caller_phone, duration_sec, transcription, status) VALUES ('vm-002', 'Pastor Marcus', '509-555-9012', 22, 'Sarah, let\\'s connect tomorrow morning about volunteer schedules for August. Thanks.', 'read');",
		"INSERT INTO communications_log (message_uuid, recipient_person_id, recipient_name, recipient_contact, channel, message_body, status, sent_by_user) VALUES ('msg-001', " + str(p_ids["usr_jordan"]) + ", 'Jordan Taylor', '509-555-0107', 'SMS', 'Hi Jordan! Reminder that Fellows Bible Study starts at 6:30 PM tonight.', 'sent', 'Sarah Jenkins');",
		"INSERT INTO communications_log (message_uuid, recipient_person_id, recipient_name, recipient_contact, channel, message_body, status, sent_by_user) VALUES ('msg-002', " + str(p_ids["usr_samantha"]) + ", 'Samantha Diaz', '509-555-0108', 'SMS', 'Welcome Samantha! Your registration review is pending center confirmation.', 'sent', 'Sarah Jenkins');"
	]
	db.execute_transaction(comm_queries)

	# 12. Seed Pastoral Care & Follow-ups
	print("[Seed] Seeding pastoral care notes...")
	var care_queries = [
		"INSERT INTO pastoral_notes (note_uuid, person_id, author_user, note_type, body, sensitivity_level) VALUES ('pnote_seed_101', " + str(p_ids["usr_jordan"]) + ", 'Pastor Marcus', 'Pastoral Care', 'Jordan is showing strong leadership potential. Recommended for leadership training path.', 'High');",
		"INSERT INTO person_notes (note_uuid, person_id, person_uuid, note_type_uuid, title, body, visibility) VALUES ('nt-seed-102', " + str(p_ids["usr_samantha"]) + ", 'usr_samantha', 'nt_general', 'Onboarding Follow-Up', 'Review pending self-registration and check photo submission details.', 'standard_staff');"
	]
	db.execute_transaction(care_queries)

	print("==========================================================")
	print("SUCCESS: DEVELOPMENT DATABASE SEEDED SUCCESSFULLY")
	print("==========================================================")
	quit(0)

func _insert_person(db: RefCounted, uuid: String, human_id: String, first: String, last: String, role: String, primary_role: String, flag: String, phone: String) -> void:
	var q = "INSERT INTO people (person_uuid, human_id, first_name, last_name, primary_role, flag_status, phone, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, datetime('now'), datetime('now'));"
	var res = db.execute(q, [uuid, human_id, first, last, primary_role, flag, phone])

func _get_people_ids(db: RefCounted) -> Dictionary:
	var res = db.execute("SELECT id, person_uuid FROM people;")
	var dict = {}
	if res["success"]:
		for r in res["data"]:
			dict[r["person_uuid"]] = r["id"]
	return dict
