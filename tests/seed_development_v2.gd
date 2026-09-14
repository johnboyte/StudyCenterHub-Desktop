extends SceneTree

## Repeatable Database Seeder for Development Environment (V2)
## Forces target to studycenterhub_development.db and populates it with 30 realistic constituents,
## 8 sessions over next 2 weeks, 2 weeks of staff shifts (covered/uncovered), and supporting operational items.

const SQLiteDatabaseScript = preload("res://src/infrastructure/database/sqlite_database.gd")
const MigrationsRunnerScript = preload("res://src/infrastructure/database/migrations_runner.gd")
const StaffMobileServiceScript = preload("res://src/domain/directory/staff_mobile_service.gd")

func _init() -> void:
	print("==========================================================")
	print("STARTING DEVELOPMENT DATABASE SEEDING V2 (30 PEOPLE)")
	print("==========================================================")

	OS.set_environment("STUDYCENTERHUB_ENV", "development")
	
	var db = SQLiteDatabaseScript.new()
	print("[SeedV2] Target Database Path: ", db.db_path)

	# 1. Run migrations first to ensure database schema is up-to-date
	var mig_runner = MigrationsRunnerScript.new(db)
	var mig_res = mig_runner.run_migrations()
	if not mig_res["success"]:
		print("FAIL: Migrations failed during seed: ", mig_res["error"])
		quit(1)
		return

	# Ensure additional columns exist in people table
	db.execute("ALTER TABLE people ADD COLUMN primary_email TEXT DEFAULT '';")
	db.execute("ALTER TABLE people ADD COLUMN sms_consent INTEGER DEFAULT 1;")
	db.execute("ALTER TABLE people ADD COLUMN institution TEXT DEFAULT 'T.L. Hanna High School';")
	db.execute("ALTER TABLE people ADD COLUMN academic_year TEXT DEFAULT 'Junior';")
	db.execute("ALTER TABLE people ADD COLUMN major TEXT DEFAULT 'General Studies';")
	db.execute("ALTER TABLE people ADD COLUMN residence TEXT DEFAULT 'Anderson, SC';")
	db.execute("ALTER TABLE people ADD COLUMN graduation_term TEXT DEFAULT 'Spring 2027';")
	db.execute("ALTER TABLE people ADD COLUMN community_connected INTEGER DEFAULT 1;")
	db.execute("ALTER TABLE people ADD COLUMN birthday TEXT DEFAULT '2008-05-15';")
	db.execute("ALTER TABLE people ADD COLUMN staff_classification TEXT DEFAULT 'Participant';")

	db.execute("""
		CREATE TABLE IF NOT EXISTS app_settings (
			setting_key TEXT PRIMARY KEY,
			setting_value TEXT,
			updated_at TEXT DEFAULT (datetime('now'))
		);
	""")

	# 2. Reset database tables for clean test repeatable state
	print("[SeedV2] Resetting database tables...")
	var wipe_queries = [
		"DELETE FROM people;",
		"DELETE FROM attendance_log;",
		"DELETE FROM event_outbox;",
		"DELETE FROM participant_qr_credentials;",
		"DELETE FROM participant_pin_credentials;",
		"DELETE FROM person_notes;",
		"DELETE FROM sessions;",
		"DELETE FROM person_sessions;",
		"DELETE FROM session_signups;",
		"DELETE FROM communications_log;",
		"DELETE FROM voicemails;",
		"DELETE FROM schedule_entries;",
		"DELETE FROM center_open_hours;",
		"DELETE FROM shift_briefings;",
		"DELETE FROM app_settings;",
		"DELETE FROM birthday_notification_log;"
	]
	db.execute_transaction(wipe_queries)

	# 3. Seed App Settings & Header Messages
	db.execute("INSERT INTO app_settings (setting_key, setting_value) VALUES ('phone_system_default', '+18645550100');")
	db.execute("INSERT INTO app_settings (setting_key, setting_value) VALUES ('active_supervisor', 'Sarah Jenkins');")

	# 4. Seed Normal Operating Hours
	var hours_queries = [
		"INSERT INTO center_open_hours (day_of_week, open_time, close_time, is_closed) VALUES ('Sunday', '01:00 PM', '05:00 PM', 0);",
		"INSERT INTO center_open_hours (day_of_week, open_time, close_time, is_closed) VALUES ('Monday', '03:15 PM', '06:00 PM', 0);",
		"INSERT INTO center_open_hours (day_of_week, open_time, close_time, is_closed) VALUES ('Tuesday', '03:15 PM', '06:00 PM', 0);",
		"INSERT INTO center_open_hours (day_of_week, open_time, close_time, is_closed) VALUES ('Wednesday', '03:15 PM', '06:00 PM', 0);",
		"INSERT INTO center_open_hours (day_of_week, open_time, close_time, is_closed) VALUES ('Thursday', '03:15 PM', '06:00 PM', 0);",
		"INSERT INTO center_open_hours (day_of_week, open_time, close_time, is_closed) VALUES ('Friday', '03:15 PM', '06:00 PM', 0);",
		"INSERT INTO center_open_hours (day_of_week, open_time, close_time, is_closed) VALUES ('Saturday', '10:00 AM', '04:00 PM', 1);"
	]
	db.execute_transaction(hours_queries)

	# 5. Seed 30 Constituents (People)
	print("[SeedV2] Seeding 30 Development constituents...")

	# Staff (4)
	_add_person(db, "usr_john_boyte", "P-20260813-F9C7", "John", "Boyte", "Executive Director", "staff", "Team Leader", "johnboytejr@gmail.com", "864-934-4080", "Clemson University", "Graduate", "Ministry Leadership", "Anderson, SC", "Spring 2026", 1, "1990-08-14")
	_add_person(db, "usr_sarah_j", "P-20260815-S001", "Sarah", "Jenkins", "Center Director", "staff", "Team Leader", "sarah.jenkins@reallife-studycenter.org", "864-555-0102", "Anderson University", "Staff", "Education", "Anderson, SC", "Spring 2024", 1, "1992-03-22")
	_add_person(db, "usr_marcus_v", "P-20260815-S002", "Marcus", "Vance", "Operations Pastor", "staff", "Staff", "marcus.vance@reallife-studycenter.org", "864-555-0103", "Erskine College", "Staff", "Theology", "Belton, SC", "Spring 2020", 1, "1988-11-05")
	_add_person(db, "usr_rachel_m", "P-20260815-S003", "Rachel", "Moore", "Student Coordinator", "staff", "Staff", "rachel.moore@reallife-studycenter.org", "864-555-0104", "Clemson University", "Staff", "Communications", "Clemson, SC", "Spring 2025", 1, "1995-07-19")

	# Interns (4)
	_add_person(db, "usr_caleb_m", "P-20260815-I001", "Caleb", "Miller", "Academic Intern", "staff", "Intern", "caleb.miller@reallife-studycenter.org", "864-555-0105", "Anderson University", "Senior", "Mathematics", "Anderson, SC", "Spring 2027", 1, "2004-04-12")
	_add_person(db, "usr_hannah_a", "P-20260815-I002", "Hannah", "Abbot", "Hospitality Intern", "staff", "Intern", "hannah.abbot@reallife-studycenter.org", "864-555-0106", "Tri-County Tech", "Sophomore", "Human Services", "Pendleton, SC", "Spring 2027", 1, "2005-09-30")
	_add_person(db, "usr_tyler_w", "P-20260815-I003", "Tyler", "Wright", "Tutoring Intern", "staff", "Intern", "tyler.wright@reallife-studycenter.org", "864-555-0107", "Clemson University", "Junior", "Physics", "Clemson, SC", "Spring 2027", 1, "2004-12-08")
	_add_person(db, "usr_megan_k", "P-20260815-I004", "Megan", "King", "Media Intern", "staff", "Intern", "megan.king@reallife-studycenter.org", "864-555-0108", "Anderson University", "Junior", "Graphic Design", "Anderson, SC", "Spring 2027", 1, "2005-02-14")

	# Volunteers (4)
	_add_person(db, "usr_david_s", "P-20260815-V001", "David", "Sterling", "Volunteer Tutor", "volunteer", "Volunteer", "david.sterling@gmail.com", "864-555-0109", "Clemson University Alum", "Volunteer", "Engineering", "Anderson, SC", "N/A", 1, "1998-06-18")
	_add_person(db, "usr_elizabeth_r", "P-20260815-V002", "Elizabeth", "Reed", "Check-In Host", "volunteer", "Volunteer", "elizabeth.reed@yahoo.com", "864-555-0110", "Community Partner", "Volunteer", "Business", "Powdersville, SC", "N/A", 1, "1997-10-25")
	_add_person(db, "usr_brian_h", "P-20260815-V003", "Brian", "Hayes", "Study Hall Mentor", "volunteer", "Volunteer", "brian.hayes@outlook.com", "864-555-0111", "T.L. Hanna Parent", "Volunteer", "Accounting", "Anderson, SC", "N/A", 1, "1985-01-11")
	_add_person(db, "usr_grace_l", "P-20260815-V004", "Grace", "Long", "Event Host", "volunteer", "Volunteer", "grace.long@gmail.com", "864-555-0112", "Westside Parent", "Volunteer", "Nursing", "Anderson, SC", "N/A", 1, "1989-05-04")

	# Students / Participants (18)
	var students = [
		["usr_jordan_t", "P-20260815-P001", "Jordan", "Taylor", "jordan.taylor@student.org", "864-555-0113", "T.L. Hanna High School", "Junior", "STEM Track", "Anderson, SC", "Spring 2027", "2008-08-15"],
		["usr_samantha_d", "P-20260815-P002", "Samantha", "Diaz", "samantha.diaz@student.org", "864-555-0114", "Westside High School", "Sophomore", "Humanities", "Anderson, SC", "Spring 2028", "2009-03-10"],
		["usr_michael_c", "P-20260815-P003", "Michael", "Chen", "michael.chen@student.org", "864-555-0115", "T.L. Hanna High School", "Senior", "Pre-Med Track", "Anderson, SC", "Spring 2026", "2007-11-22"],
		["usr_ashley_c", "P-20260815-P004", "Ashley", "Cooper", "ashley.cooper@student.org", "864-555-0116", "Palmetto High School", "Junior", "Business", "Williamston, SC", "Spring 2027", "2008-01-09"],
		["usr_ethan_b", "P-20260815-P005", "Ethan", "Brooks", "ethan.brooks@student.org", "864-555-0117", "Crescent High School", "Freshman", "General Studies", "Iva, SC", "Spring 2029", "2010-06-30"],
		["usr_olivia_m", "P-20260815-P006", "Olivia", "Martin", "olivia.martin@student.org", "864-555-0118", "Belton-Honea Path High School", "Junior", "Arts Track", "Belton, SC", "Spring 2027", "2008-12-14"],
		["usr_noah_g", "P-20260815-P007", "Noah", "Garcia", "noah.garcia@student.org", "864-555-0119", "Pendleton High School", "Sophomore", "Computer Science", "Pendleton, SC", "Spring 2028", "2009-07-04"],
		["usr_ava_p", "P-20260815-P008", "Ava", "Patterson", "ava.patterson@student.org", "864-555-0120", "Wren High School", "Senior", "Biology", "Piedmont, SC", "Spring 2026", "2007-09-18"],
		["usr_liam_s", "P-20260815-P009", "Liam", "Sullivan", "liam.sullivan@student.org", "864-555-0121", "Powdersville High School", "Junior", "Robotics", "Powdersville, SC", "Spring 2027", "2008-04-03"],
		["usr_emma_w", "P-20260815-P010", "Emma", "Watson", "emma.watson@student.org", "864-555-0122", "Anderson Christian School", "Junior", "Literature", "Anderson, SC", "Spring 2027", "2008-10-27"],
		["usr_lucas_h", "P-20260815-P011", "Lucas", "Howard", "lucas.howard@student.org", "864-555-0123", "New Covenant School", "Freshman", "History", "Anderson, SC", "Spring 2029", "2010-02-17"],
		["usr_mia_j", "P-20260815-P012", "Mia", "Jackson", "mia.jackson@student.org", "864-555-0124", "Home School", "Sophomore", "Music", "Anderson, SC", "Spring 2028", "2009-11-08"],
		["usr_benjamin_f", "P-20260815-P013", "Benjamin", "Foster", "benjamin.foster@student.org", "864-555-0125", "T.L. Hanna High School", "Junior", "Chemistry", "Anderson, SC", "Spring 2027", "2008-05-20"],
		["usr_chloe_n", "P-20260815-P014", "Chloe", "Nelson", "chloe.nelson@student.org", "864-555-0126", "Westside High School", "Senior", "Psychology", "Anderson, SC", "Spring 2026", "2007-07-12"],
		["usr_alexander_r", "P-20260815-P015", "Alexander", "Ross", "alexander.ross@student.org", "864-555-0127", "Palmetto High School", "Sophomore", "Economics", "Williamston, SC", "Spring 2028", "2009-09-01"],
		["usr_sophia_e", "P-20260815-P016", "Sophia", "Ellis", "sophia.ellis@student.org", "864-555-0128", "Crescent High School", "Junior", "Environmental Science", "Iva, SC", "Spring 2027", "2008-03-25"],
		["usr_daniel_v", "P-20260815-P017", "Daniel", "Vargas", "daniel.vargas@student.org", "864-555-0129", "T.L. Hanna High School", "Senior", "Mathematics", "Anderson, SC", "Spring 2026", "2007-12-04"],
		["usr_isabella_k", "P-20260815-P018", "Isabella", "Knight", "isabella.knight@student.org", "864-555-0130", "Westside High School", "Freshman", "General Studies", "Anderson, SC", "Spring 2029", "2010-08-02"]
	]

	for st in students:
		_add_person(db, st[0], st[1], st[2], st[3], "Participant", "Participant", "Participant", st[4], st[5], st[6], st[7], st[8], st[9], st[10], 1, st[11])

	var p_ids = _get_people_ids(db)

	# 6. Seed Attendance Signed In Today (8 people signed in today)
	print("[SeedV2] Seeding Signed In Today records...")
	var today_str = Time.get_date_string_from_system()
	var signed_in_uuids = ["usr_john_boyte", "usr_sarah_j", "usr_caleb_m", "usr_david_s", "usr_jordan_t", "usr_michael_c", "usr_ethan_b", "usr_ava_p"]
	var p_info = _get_people_info(db)
	for s_uuid in signed_in_uuids:
		var pid = p_info[s_uuid]["id"]
		var hid = p_info[s_uuid]["human_id"]
		db.execute("INSERT INTO attendance_log (checkin_uuid, person_id, person_uuid, human_id, check_in_date, check_in_time, method, device_uuid) VALUES (?, ?, ?, ?, ?, '03:20 PM', 'Development Self Check-In', 'dev_kiosk_1');", ['chk_' + s_uuid, pid, s_uuid, hid, today_str])

	# 7. Seed 8 Sessions / Events (Next 2 weeks)
	print("[SeedV2] Seeding 8 Sessions & Events...")
	var sessions_data = [
		["Fellows Bible Study & Discussion", "Fellows Group", today_str, "06:30 PM", "08:00 PM", "Main Study Hall", 15, 1],
		["High School STEM Tutoring Workshop", "Lead Track", today_str, "04:00 PM", "05:30 PM", "Tutoring Lab", 20, 1],
		["Open Study & Quiet Reading Hall", "Open Study", today_str, "03:15 PM", "06:00 PM", "Gathering Room", 50, 0],
		["College Prep & SAT Practice Lab", "Academic Workshop", "2026-08-18", "04:30 PM", "06:00 PM", "Study Room #1", 12, 1],
		["Leadership Fellows Roundtable", "Lead Track", "2026-08-20", "05:00 PM", "06:30 PM", "Main Study Hall", 10, 1],
		["Community Youth Hospitality Night", "Community Event", "2026-08-22", "06:00 PM", "08:00 PM", "Main Study Hall", 40, 0],
		["Calculus & AP Math Problem Solving", "Academic Workshop", "2026-08-25", "04:00 PM", "05:30 PM", "Tutoring Lab", 15, 1],
		["Fall 2026 Volunteer Orientation", "Volunteer Briefing", "2026-08-27", "06:00 PM", "07:30 PM", "Gathering Room", 25, 1]
	]

	for sd in sessions_data:
		db.execute("INSERT INTO sessions (title, session_type, date_text, start_time, end_time, room_location, max_capacity, is_active) VALUES (?, ?, ?, ?, ?, ?, ?, 1);", [sd[0], sd[1], sd[2], sd[3], sd[4], sd[5], sd[6]])

	var s_res = db.execute("SELECT id, title FROM sessions;")
	var s_ids = {}
	if s_res["success"]:
		for r in s_res["data"]:
			s_ids[r["title"]] = r["id"]

	# Seed signups for signup-required sessions
	db.execute("INSERT INTO session_signups (signup_uuid, session_id, person_id, signup_status) VALUES ('ssg-101', ?, ?, 'confirmed');", [s_ids["Fellows Bible Study & Discussion"], p_ids["usr_jordan_t"]])
	db.execute("INSERT INTO session_signups (signup_uuid, session_id, person_id, signup_status) VALUES ('ssg-102', ?, ?, 'confirmed');", [s_ids["Fellows Bible Study & Discussion"], p_ids["usr_michael_c"]])
	db.execute("INSERT INTO session_signups (signup_uuid, session_id, person_id, signup_status) VALUES ('ssg-103', ?, ?, 'waitlist');", [s_ids["Fellows Bible Study & Discussion"], p_ids["usr_samantha_d"]])
	db.execute("INSERT INTO session_signups (signup_uuid, session_id, person_id, signup_status) VALUES ('ssg-104', ?, ?, 'confirmed');", [s_ids["High School STEM Tutoring Workshop"], p_ids["usr_ethan_b"]])

	# 8. Seed 2 Weeks of Staff Shifts (Covered & Intentionally Uncovered)
	print("[SeedV2] Seeding 2 weeks of Staff Shifts...")
	var shifts_data = [
		["shf-dev-1", "John Boyte", "Team Leader", today_str, "03:15 PM", "06:00 PM", "Main Study Hall", "Opening supervisor on duty"],
		["shf-dev-2", "Caleb Miller", "Intern", today_str, "03:15 PM", "06:00 PM", "Tutoring Lab", "STEM & Math tutoring coverage"],
		["shf-dev-3", "", "Volunteer", today_str, "04:00 PM", "06:00 PM", "Check-In Desk", "UNCOVERED: Check-In desk greeting"],
		["shf-dev-4", "Sarah Jenkins", "Team Leader", "2026-08-17", "03:15 PM", "06:00 PM", "Main Study Hall", "Monday center operations"],
		["shf-dev-5", "", "Staff", "2026-08-17", "03:15 PM", "06:00 PM", "Gathering Room", "UNCOVERED: Study hall proctor"],
		["shf-dev-6", "Hannah Abbot", "Intern", "2026-08-18", "03:15 PM", "06:00 PM", "Check-In Desk", "Tuesday greeting host"],
		["shf-dev-7", "David Sterling", "Volunteer", "2026-08-18", "04:00 PM", "06:00 PM", "Tutoring Lab", "Tuesday tutoring support"],
		["shf-dev-8", "Marcus Vance", "Staff", "2026-08-19", "03:15 PM", "06:00 PM", "Main Study Hall", "Wednesday staff lead"],
		["shf-dev-9", "", "Intern", "2026-08-19", "03:15 PM", "06:00 PM", "Gathering Room", "UNCOVERED: Wednesday evening intern"],
		["shf-dev-10", "John Boyte", "Team Leader", "2026-08-20", "03:15 PM", "06:00 PM", "Main Study Hall", "Thursday team leader"],
		["shf-dev-11", "Elizabeth Reed", "Volunteer", "2026-08-21", "03:15 PM", "06:00 PM", "Check-In Desk", "Friday check-in desk"]
	]

	for sh in shifts_data:
		db.execute("INSERT INTO schedule_entries (entry_uuid, person_name, shift_role, shift_date, start_time, end_time, area, notes, sort_order) VALUES (?, ?, ?, ?, ?, ?, ?, ?, 99);", [sh[0], sh[1], sh[2], sh[3], sh[4], sh[5], sh[6], sh[7]])

	# 9. Seed Operational Items (Notes, Briefings, Inbox, Tasks)
	print("[SeedV2] Seeding operational notes, handoffs, and tasks...")
	db.execute("INSERT INTO shift_briefings (briefing_uuid, author_name, briefing_date, title, body, priority) VALUES ('brf-1', 'John Boyte', ?, 'Opening Shift Briefing', 'All quiet in Main Study Hall. Tutoring Lab prepared for STEM workshop.', 'normal');", [today_str])
	db.execute("INSERT INTO person_notes (note_uuid, person_id, person_uuid, title, body, visibility) VALUES ('nt-1', ?, 'usr_jordan_t', 'Academic Progress Note', 'Jordan completed AP Physics practice module with Caleb.', 'standard_staff');", [p_ids["usr_jordan_t"]])
	db.execute("INSERT INTO person_notes (note_uuid, person_id, person_uuid, title, body, visibility) VALUES ('nt-2', ?, 'usr_samantha_d', 'Registration Check', 'Parent confirmed SMS consent for Wednesday night group.', 'standard_staff');", [p_ids["usr_samantha_d"]])

	# 10. Provision Development Staff Mobile PIN (123456) for John Boyte (johnboytejr@gmail.com)
	print("[SeedV2] Provisioning Development staff PIN (123456) for John Boyte...")
	var staff_svc = StaffMobileServiceScript.new(db)
	var jb_pid = p_ids.get("usr_john_boyte", 0)
	if jb_pid > 0:
		staff_svc.set_staff_mobile_pin(jb_pid, "123456")

	print("==========================================================")
	print("SUCCESS: DEVELOPMENT DATABASE SEEDED CLEANLY WITH 30 PEOPLE")
	print("==========================================================")
	quit(0)

func _add_person(db: RefCounted, uuid: String, human_id: String, first: String, last: String, p_role: String, s_class: String, role_name: String, email: String, phone: String, inst: String, acad: String, maj: String, res_loc: String, grad: String, comm: int, bday: String) -> void:
	var q = """
		INSERT INTO people (
			person_uuid, human_id, first_name, last_name, primary_role, staff_classification,
			primary_email, phone, sms_consent, institution, academic_year, major, residence,
			graduation_term, community_connected, birthday, flag_status, created_at, updated_at
		) VALUES (?, ?, ?, ?, ?, ?, ?, ?, 1, ?, ?, ?, ?, ?, ?, ?, 'Clear', datetime('now'), datetime('now'));
	"""
	db.execute(q, [uuid, human_id, first, last, p_role, s_class, email, phone, inst, acad, maj, res_loc, grad, comm, bday])

func _get_people_ids(db: RefCounted) -> Dictionary:
	var res = db.execute("SELECT id, person_uuid FROM people;")
	var dict = {}
	if res["success"]:
		for r in res["data"]:
			dict[r["person_uuid"]] = r["id"]
	return dict

func _get_people_info(db: RefCounted) -> Dictionary:
	var res = db.execute("SELECT id, person_uuid, human_id FROM people;")
	var dict = {}
	if res["success"]:
		for r in res["data"]:
			dict[r["person_uuid"]] = {"id": r["id"], "human_id": r["human_id"]}
	return dict
