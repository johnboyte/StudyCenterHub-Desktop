extends SceneTree

## Repeatable Database Seeder for Staging Environment
## Generates a realistic pre-launch Staging dataset with 200+ fictional students,
## months of historical attendance log history, waitlists, call response work items, and notes.

const SQLiteDatabaseScript = preload("res://src/infrastructure/database/sqlite_database.gd")
const MigrationsRunnerScript = preload("res://src/infrastructure/database/migrations_runner.gd")

func _init() -> void:
	print("==========================================================")
	print("STARTING STAGING DATABASE DRESS REHEARSAL SEEDING ENGINE")
	print("==========================================================")

	# Safety Lock: Prevent accidental execution in Production
	var env = OS.get_environment("STUDYCENTERHUB_ENV")
	if env == "production":
		print("ERROR: Safety lock activated. Cannot run staging seeder in PRODUCTION.")
		quit(1)
		return

	if env != "staging":
		OS.set_environment("STUDYCENTERHUB_ENV", "staging")
		print("[Seed] Env was not 'staging'. Forced STUDYCENTERHUB_ENV = staging.")

	var db = SQLiteDatabaseScript.new()
	print("[Seed] Target Staging Database Path: ", db.db_path)

	# 1. Run migrations first to ensure database schema is up-to-date
	var mig_runner = MigrationsRunnerScript.new(db)
	var mig_res = mig_runner.run_migrations()
	if not mig_res["success"]:
		print("FAIL: Migrations failed during staging seed: ", mig_res["error"])
		quit(1)
		return
	print("[Seed] Staging migrations checked successfully.")

	# 2. Ensure dynamic tables exist before wipe
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

	# 3. Wipe existing staging data to guarantee a repeatable starting snapshot
	print("[Seed] Wiping existing staging records...")
	var wipe_queries = [
		"DELETE FROM people;",
		"DELETE FROM attendance_log;",
		"DELETE FROM event_outbox;",
		"DELETE FROM participant_qr_credentials;",
		"DELETE FROM participant_pin_credentials;",
		"DELETE FROM card_print_queue;",
		"DELETE FROM participant_verification_sessions;",
		"DELETE FROM participant_verification_audit;",
		"DELETE FROM person_notes;",
		"DELETE FROM sessions;",
		"DELETE FROM person_sessions;",
		"DELETE FROM session_signups;",
		"DELETE FROM communications_log;",
		"DELETE FROM voicemails;",
		"DELETE FROM inbound_sms_log;",
		"DELETE FROM schedule_entries;",
		"DELETE FROM center_open_hours;",
		"DELETE FROM volunteer_profiles;",
		"DELETE FROM volunteer_shifts;",
		"DELETE FROM pastoral_notes;",
		"DELETE FROM shift_briefings;",
		"DELETE FROM center_hour_overrides;",
		"DELETE FROM app_settings WHERE setting_key != 'GEMINI_API_KEY';",
		"DELETE FROM organization_page_header_messages;",
		"DELETE FROM birthday_notification_log;"
	]
	db.execute_transaction(wipe_queries)
	print("[Seed] Staging tables cleared successfully.")

	# 4. Seed Settings & Headers
	var settings_queries = [
		"INSERT INTO app_settings (setting_key, setting_value) VALUES ('ORG_ACCENT_INDEX', '4');", # Classic Staging Slate
		"INSERT INTO app_settings (setting_key, setting_value) VALUES ('phone_system_default', '+18005550199');",
		"INSERT INTO app_settings (setting_key, setting_value) VALUES ('active_supervisor', 'Director Jenkins');",
		"INSERT INTO app_settings (setting_key, setting_value) VALUES ('VOCAB_GRADE', 'Year');",
		"INSERT INTO organization_page_header_messages (page_key, message) VALUES ('home', 'STAGING ENVIRONMENT - PRE-LAUNCH VERIFICATION WORKSPACE');",
		"INSERT INTO organization_page_header_messages (page_key, message) VALUES ('people', 'Staging Roster - Simulated Ministry Constituents Directory');"
	]
	db.execute_transaction(settings_queries)

	# 5. Seed Staff, Interns, and Volunteers (Roster foundation)
	print("[Seed] Seeding staff, interns, and volunteers...")
	_insert_person(db, "usr_st_director", "STF-101", "Sarah", "Jenkins", "Center Director", "staff", "Clear", "509-555-0201")
	_insert_person(db, "usr_st_pastor", "ADM-101", "Marcus", "Vance", "Executive Pastor", "staff", "Clear", "509-555-0202")
	_insert_person(db, "usr_st_intern1", "INT-101", "Caleb", "Miller", "Academic Intern", "staff", "Clear", "509-555-0203")
	_insert_person(db, "usr_st_intern2", "INT-102", "Hannah", "Abbot", "Hospitality Intern", "staff", "Clear", "509-555-0204")
	_insert_person(db, "usr_st_vol1", "VOL-101", "David", "Sterling", "Volunteer Tutor", "volunteer", "Clear", "509-555-0205")
	_insert_person(db, "usr_st_vol2", "VOL-102", "Elizabeth", "Reed", "Check-In Host", "volunteer", "Clear", "509-555-0206")

	# 6. Generate 225 Realistic Fictional Participants (Students)
	print("[Seed] Generating 225 fictional participant profiles...")
	var first_names = ["Liam", "Noah", "Oliver", "Elijah", "James", "Benjamin", "Lucas", "Alexander", "Emma", "Sophia", "Olivia", "Isabella", "Ava", "Mia", "Charlotte"]
	var last_names = ["Baker", "Campbell", "Evans", "Flores", "Green", "Hill", "Jenkins", "King", "Morris", "Nelson", "Patterson", "Ramirez", "Sanchez", "Turner", "Watson"]
	
	var student_uuids = []
	var count = 0
	
	for first in first_names:
		for last in last_names:
			count += 1
			var uuid = "usr_stage_student_" + str(count)
			var human_id = "PRT-" + str(2000 + count)
			var years = ["Freshman", "Sophomore", "Junior", "Senior"]
			var grade = years[count % years.size()]
			var status = "Clear" if count % 10 != 0 else "To Be Confirmed"
			var phone = "509-555-" + "%04d" % (1000 + count)
			
			_insert_person(db, uuid, human_id, first, last, "Participant", "Participant", status, phone, grade)
			student_uuids.append(uuid)
			
	var p_ids = _get_people_ids(db)
	print("[Seed] Fictional participants created: ", student_uuids.size())

	# 7. Seed Credentials for a subset of students
	print("[Seed] Seeding PIN and QR credentials for 50 check-in students...")
	var cred_queries = []
	for i in range(50):
		var uuid = student_uuids[i]
		var pin = "%04d" % (1000 + i)
		var token = "qr_token_stage_" + str(i)
		var token_hash_val = token.sha256_text().to_lower()
		var hint_val = "Pass ***" + token_hash_val.right(4)
		cred_queries.append("INSERT INTO participant_pin_credentials (credential_id, person_id, pin_hash, status) VALUES ('PIN-S-" + str(i) + "', " + str(p_ids[uuid]) + ", '" + pin + "', 'active');")
		cred_queries.append("INSERT INTO participant_qr_credentials (credential_id, person_id, token_hash, token_hint, status, issued_at) VALUES ('QRCR-S-" + str(i) + "', " + str(p_ids[uuid]) + ", '" + token_hash_val + "', '" + hint_val + "', 'active', datetime('now'));")
		cred_queries.append("UPDATE people SET qr_code_value = '" + token_hash_val + "' WHERE id = " + str(p_ids[uuid]) + ";")
		if i < 5:
			cred_queries.append("INSERT INTO card_print_queue (queue_uuid, person_id, person_uuid, status, added_at) VALUES ('CPQ-INIT-" + str(i) + "', " + str(p_ids[uuid]) + ", '" + uuid + "', 'pending', datetime('now'));")
	db.execute_transaction(cred_queries)

	# 8. Seed Normal Operating Hours
	var hours_queries = [
		"INSERT INTO center_open_hours (day_of_week, open_time, close_time, is_closed) VALUES ('Monday', '03:00 PM', '08:00 PM', 0);",
		"INSERT INTO center_open_hours (day_of_week, open_time, close_time, is_closed) VALUES ('Tuesday', '03:00 PM', '08:00 PM', 0);",
		"INSERT INTO center_open_hours (day_of_week, open_time, close_time, is_closed) VALUES ('Wednesday', '03:00 PM', '08:00 PM', 0);",
		"INSERT INTO center_open_hours (day_of_week, open_time, close_time, is_closed) VALUES ('Thursday', '03:00 PM', '08:00 PM', 0);",
		"INSERT INTO center_open_hours (day_of_week, open_time, close_time, is_closed) VALUES ('Saturday', '10:00 AM', '04:00 PM', 0);"
	]
	db.execute_transaction(hours_queries)

	# 9. Seed 4 Months of Historical Attendance Logs (approx. 85 open days)
	print("[Seed] Seeding 4 months of historical attendance check-ins...")
	var att_queries = []
	
	# Loop over 85 days in the past
	for day_offset in range(120, 0, -1):
		# We check if the day is an open weekday (skipping Friday/Sunday)
		# Calculate simulated date string
		var date_ticks = Time.get_unix_time_from_system() - (day_offset * 86400)
		var datetime = Time.get_datetime_dict_from_unix_time(date_ticks)
		var day_of_week = datetime["weekday"] # 1=Mon, 2=Tue, 3=Wed, 4=Thu, 5=Fri, 6=Sat, 0=Sun
		
		if day_of_week == 0 or day_of_week == 5:
			continue # Closed days
			
		var date_str = "%04d-%02d-%02d" % [datetime["year"], datetime["month"], datetime["day"]]
		
		# Pick 15 to 25 random students checking in on this day
		var seed_rand = day_offset
		for k in range(20):
			seed_rand = (seed_rand * 31 + 17) % student_uuids.size()
			var uuid = student_uuids[seed_rand]
			
			var method = "Self Service QR"
			if k % 3 == 1:
				method = "Self Service PIN"
			elif k % 3 == 2:
				method = "Manual Roster Check-In"
				
			var checkin_uuid = "chk_stg_" + str(day_offset) + "_" + str(k)
			var time_str = "15:%02d:00" % [10 + (k % 50)]
			
			att_queries.append("INSERT INTO attendance_log (checkin_uuid, person_id, person_uuid, human_id, check_in_date, check_in_time, method, device_uuid) VALUES ('" + checkin_uuid + "', " + str(p_ids[uuid]) + ", '" + uuid + "', 'PRT-X', '" + date_str + "', '" + time_str + "', '" + method + "', 'staging_terminal');")

		# Insert logs in transaction batches of 10 days to stay fast
		if att_queries.size() >= 150:
			db.execute_transaction(att_queries)
			att_queries.clear()
			
	if att_queries.size() > 0:
		db.execute_transaction(att_queries)
	print("[Seed] Attendance logs successfully backfilled.")

	# 10. Seed Sessions, signups, and Waitlists (verifying waitlist overflow)
	print("[Seed] Seeding sessions and waitlists...")
	var session_queries = [
		"INSERT INTO sessions (title, session_type, date_text, start_time, end_time, room_location, max_capacity) VALUES ('Math Academic Prep', 'Tutoring', '2026-07-28', '04:00 PM', '05:30 PM', 'Study Room #1', 5);",
		"INSERT INTO sessions (title, session_type, date_text, start_time, end_time, room_location, max_capacity) VALUES ('Staging Launch Briefing', 'Orientation', '2026-07-29', '05:00 PM', '06:00 PM', 'Fellowship Hall', 10);"
	]
	db.execute_transaction(session_queries)
	
	# Fetch session IDs
	var s_res = db.execute("SELECT id, title FROM sessions;")
	var s_ids = {}
	if s_res["success"]:
		for r in s_res["data"]:
			s_ids[r["title"]] = r["id"]

	var signup_queries = []
	# For Math Prep (Max capacity 5): register 8 students to force 3 into waitlist status
	for i in range(8):
		var student_uuid = student_uuids[i]
		var status = "registered" if i < 5 else "waiting"
		signup_queries.append("INSERT INTO session_signups (signup_uuid, session_id, person_id, signup_status) VALUES ('ssg-stg-m-" + str(i) + "', " + str(s_ids["Math Academic Prep"]) + ", " + str(p_ids[student_uuid]) + ", '" + status + "');")
		signup_queries.append("INSERT INTO person_sessions (person_id, session_id, attendance_status) VALUES (" + str(p_ids[student_uuid]) + ", " + str(s_ids["Math Academic Prep"]) + ", '" + status + "');")

	# For Launch Briefing (Max capacity 10): register 12 students to force 2 into waitlist
	for i in range(12):
		var student_uuid = student_uuids[10 + i]
		var status = "registered" if i < 10 else "waiting"
		signup_queries.append("INSERT INTO session_signups (signup_uuid, session_id, person_id, signup_status) VALUES ('ssg-stg-o-" + str(i) + "', " + str(s_ids["Staging Launch Briefing"]) + ", " + str(p_ids[student_uuid]) + ", '" + status + "');")
		signup_queries.append("INSERT INTO person_sessions (person_id, session_id, attendance_status) VALUES (" + str(p_ids[student_uuid]) + ", " + str(s_ids["Staging Launch Briefing"]) + ", '" + status + "');")
	db.execute_transaction(signup_queries)

	# 11. Seed Communications Work Queue
	print("[Seed] Seeding Communications Response Center queue items...")
	var comm_queries = [
		"INSERT INTO voicemails (voicemail_uuid, caller_name, caller_phone, duration_sec, recording_url, transcription, status, priority, due_date, internal_notes, assigned_person_id) VALUES ('vm-stg-001', 'Abigail Patterson', '509-555-1011', 12, 'https://api.twilio.com/2010-04-01/Accounts/AC00000000000000000000000000000000/Recordings/RE00000000000000000000000000000000', 'Hey Sarah, Liam Baker forgot his check-in card today. Can we reset his barcode scan token tomorrow?', 'new', 'Medium', '2026-07-23', 'Need to issue a new QR code in directory card.', " + str(p_ids["usr_st_intern1"]) + ");",
		"INSERT INTO voicemails (voicemail_uuid, caller_name, caller_phone, duration_sec, recording_url, transcription, status, priority, due_date, internal_notes, assigned_person_id) VALUES ('vm-stg-002', 'Liam Baker', '509-555-1012', 30, 'https://api.twilio.com/2010-04-01/Accounts/AC00000000000000000000000000000000/Recordings/RE00000000000000000000000000000000', 'Can I get sign-up approval for the Math Academic Prep tutoring next Tuesday?', 'assigned', 'High', '2026-07-22', 'Currently on waitlist because capacity is full. Reviewing overrides.', " + str(p_ids["usr_st_director"]) + ");",
		"INSERT INTO voicemails (voicemail_uuid, caller_name, caller_phone, duration_sec, recording_url, transcription, status, priority, due_date, internal_notes, assigned_person_id) VALUES ('vm-stg-003', 'Pastor Marcus', '509-555-0202', 15, 'https://api.twilio.com/2010-04-01/Accounts/AC00000000000000000000000000000000/Recordings/RE00000000000000000000000000000000', 'Completed the safety walkthrough of the staging database server.', 'completed', 'Low', '2026-07-20', 'All systems checked out okay.', " + str(p_ids["usr_st_pastor"]) + ");",
		"INSERT INTO voicemails (voicemail_uuid, caller_name, caller_phone, duration_sec, recording_url, transcription, status, priority, due_date, internal_notes, assigned_person_id) VALUES ('vm-stg-004', 'Ava Young', '509-555-1013', 40, 'https://api.twilio.com/2010-04-01/Accounts/AC00000000000000000000000000000000/Recordings/RE00000000000000000000000000000000', 'Hello, I missed checking in my son Joshua on Wednesday. Can a staff member manually mark him present?', 'new', 'Emergency', '2026-07-22', 'Check logs and backfill check-in record.', " + str(p_ids["usr_st_intern2"]) + ");",
		
		"INSERT INTO inbound_sms_log (message_sid, from_phone_e164, to_phone_e164, raw_body, follow_up_status, assigned_to, notes, received_at) VALUES ('sms-stg-001', '509-555-1011', '+18647124446', 'Hey, Liam Patterson is sick today and won''t be making it to the afternoon prep session.', 'Unassigned', NULL, NULL, datetime('now', '-2 hours'));",
		"INSERT INTO inbound_sms_log (message_sid, from_phone_e164, to_phone_e164, raw_body, follow_up_status, assigned_to, notes, received_at) VALUES ('sms-stg-002', '509-555-1012', '+18647124446', 'Could you please confirm if we have tutoring next Monday since it is a holiday?', 'in_progress', 'Sarah Jenkins', 'Intern Sarah is checking the holiday schedule.', datetime('now', '-1 hours'));",
		"INSERT INTO inbound_sms_log (message_sid, from_phone_e164, to_phone_e164, raw_body, follow_up_status, assigned_to, notes, received_at) VALUES ('sms-stg-003', '509-555-0202', '+18647124446', 'Thank you so much for the quick call back, appreciate your help!', 'completed', 'Pastor Marcus', 'Handled and resolved.', datetime('now', '-30 minutes'));"
	]
	db.execute_transaction(comm_queries)

	# 11b. Seed Staffing Schedule entries
	print("[Seed] Seeding schedule shifts...")
	var schedule_queries = [
		"INSERT INTO schedule_entries (entry_uuid, person_name, shift_role, shift_date, start_time, end_time, area, sort_order) VALUES ('shf-stg-101', 'Sarah Jenkins', 'Shift Supervisor (Staff)', '2026-07-19', '12:00 PM', '05:00 PM', 'Study Center', 1);",
		"INSERT INTO schedule_entries (entry_uuid, person_name, shift_role, shift_date, start_time, end_time, area, sort_order) VALUES ('shf-stg-201', 'Sarah Jenkins', 'Shift Supervisor (Staff)', '2026-07-20', '09:00 AM', '03:00 PM', 'Study Center', 1);",
		"INSERT INTO schedule_entries (entry_uuid, person_name, shift_role, shift_date, start_time, end_time, area, sort_order) VALUES ('shf-stg-202', 'Caleb Miller', 'Study Tutor (Intern)', '2026-07-20', '03:00 PM', '08:00 PM', 'Study Room #1', 2);",
		"INSERT INTO schedule_entries (entry_uuid, person_name, shift_role, shift_date, start_time, end_time, area, sort_order) VALUES ('shf-stg-301', 'Hannah Abbot', 'Check-In Host (Vol)', '2026-07-21', '09:00 AM', '03:00 PM', 'Gathering Room', 1);",
		"INSERT INTO schedule_entries (entry_uuid, person_name, shift_role, shift_date, start_time, end_time, area, sort_order) VALUES ('shf-stg-302', 'David Sterling', 'Study Tutor (Intern)', '2026-07-21', '03:00 PM', '08:00 PM', 'Study Center', 2);",
		"INSERT INTO schedule_entries (entry_uuid, person_name, shift_role, shift_date, start_time, end_time, area, sort_order) VALUES ('shf-stg-401', 'Sarah Jenkins', 'Shift Supervisor (Staff)', '2026-07-22', '03:00 PM', '08:00 PM', 'Gathering Room', 1);",
		"INSERT INTO schedule_entries (entry_uuid, person_name, shift_role, shift_date, start_time, end_time, area, sort_order) VALUES ('shf-stg-402', 'Elizabeth Reed', 'Check-In Host (Vol)', '2026-07-22', '03:00 PM', '08:00 PM', 'Study Center', 2);"
	]
	db.execute_transaction(schedule_queries)

	# 12. Seed Pastoral Care notes & Student Follow-up tasks
	print("[Seed] Seeding prayer requests and follow-up notes...")
	var care_queries = [
		"INSERT INTO pastoral_notes (note_uuid, person_id, author_user, note_type, body, sensitivity_level) VALUES ('pnote_stg_001', " + str(p_ids[student_uuids[0]]) + ", 'Pastor Marcus', 'Prayer Request', 'Requested prayer for academic stress and upcoming finals preparation.', 'Standard');",
		"INSERT INTO pastoral_notes (note_uuid, person_id, author_user, note_type, body, sensitivity_level) VALUES ('pnote_stg_002', " + str(p_ids[student_uuids[5]]) + ", 'Sarah Jenkins', 'Pastoral Care', 'Met for monthly tutoring alignment. Showing solid improvement in confidence.', 'High');",
		"INSERT INTO person_notes (note_uuid, person_id, person_uuid, note_type_uuid, title, body, visibility) VALUES ('nt-stg-001', " + str(p_ids[student_uuids[2]]) + ", '" + student_uuids[2] + "', 'nt_general', 'Follow-up Task', 'Call parents about missing emergency contact signatures.', 'standard_staff');"
	]
	db.execute_transaction(care_queries)

	print("==========================================================")
	print("SUCCESS: STAGING DATABASE FULLY SEEDED FOR DRESS REHEARSAL")
	print("==========================================================")
	quit(0)

func _insert_person(db: RefCounted, uuid: String, human_id: String, first: String, last: String, role: String, primary_role: String, flag: String, phone: String, grade: String = "") -> void:
	var q = "INSERT INTO people (person_uuid, human_id, first_name, last_name, primary_role, flag_status, phone, grade, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, datetime('now'), datetime('now'));"
	db.execute(q, [uuid, human_id, first, last, primary_role, flag, phone, grade])

func _get_people_ids(db: RefCounted) -> Dictionary:
	var res = db.execute("SELECT id, person_uuid FROM people;")
	var dict = {}
	if res["success"]:
		for r in res["data"]:
			dict[r["person_uuid"]] = r["id"]
	return dict
