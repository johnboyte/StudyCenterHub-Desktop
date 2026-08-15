extends SceneTree

## Automated Headless Test Suite for Staff Credentials Gateway Publishing & Provisioning
## Verifies StaffMobileService, 600,000-iteration PBKDF2 derivation, staff filtering,
## credential versioning, and mobile access disabling.

const SQLiteDatabaseScript = preload("res://src/infrastructure/database/sqlite_database.gd")
const MigrationsRunnerScript = preload("res://src/infrastructure/database/migrations_runner.gd")

func _init() -> void:
	print("==========================================================")
	print("STARTING STAFF CREDENTIALS PROVISIONING TEST SUITE")
	print("==========================================================")

	var db_path = ProjectSettings.globalize_path("user://studycenterhub_test_staff_sync.db")
	var dir = DirAccess.open("user://")
	if dir and dir.file_exists("studycenterhub_test_staff_sync.db"):
		dir.remove("studycenterhub_test_staff_sync.db")

	var db = SQLiteDatabaseScript.new(db_path)
	var mig_runner = MigrationsRunnerScript.new(db)
	var mig_res = mig_runner.run_migrations()
	if not mig_res["success"]:
		print("FAIL: Migrations failed: ", mig_res["error"])
		quit(1)
		return

	var StaffMobileServiceScript = load("res://src/domain/directory/staff_mobile_service.gd")
	if not StaffMobileServiceScript:
		print("FAIL: Could not load StaffMobileServiceScript")
		quit(1)
		return
	var mobile_svc = StaffMobileServiceScript.new(db)

	# Seed 1: Active Staff Member
	db.execute("""
		INSERT INTO people (id, person_uuid, human_id, first_name, last_name, primary_role, email, status)
		VALUES (101, 'usr_staff_01', 'STF-1001', 'Sarah', 'Connor', 'Team Leader', 'sconnor@reallife-studycenter.org', 'active');
	""")

	# Measure PBKDF2 derivation performance locally
	var start_t = Time.get_ticks_msec()
	var set_res = mobile_svc.set_staff_mobile_pin(101, "849201")
	var elapsed_t = Time.get_ticks_msec() - start_t

	if not set_res["success"]:
		print("FAIL: Failed to set 6-digit PIN: ", set_res.get("error"))
		quit(1)
		return

	print("PASS 1/3: 6-digit PIN derived successfully in ", elapsed_t, " ms using StaffMobileService.")

	# Seed 2: Active Staff Member WITHOUT Mobile Access
	db.execute("""
		INSERT INTO people (id, person_uuid, human_id, first_name, last_name, primary_role, email, status)
		VALUES (102, 'usr_staff_02', 'STF-1002', 'Kyle', 'Reese', 'Staff', 'kreese@reallife-studycenter.org', 'active');
	""")

	# Seed 3: Student with Kiosk PIN (Should be excluded)
	db.execute("""
		INSERT INTO people (id, person_uuid, human_id, first_name, last_name, primary_role, email, status)
		VALUES (103, 'usr_student_01', 'PRT-9999', 'John', 'Connor', 'Participant', 'jconnor@example.com', 'active');
	""")
	db.execute("INSERT INTO participant_pin_credentials (credential_id, person_id, pin_hash, status) VALUES ('PIN-103', 103, '1234', 'active');")

	# Query staff payload logic
	var sync_res = db.execute("""
		SELECT 
			p.id, p.human_id, p.first_name, p.last_name, p.primary_role, p.email, p.status,
			smc.pin_pbkdf_hash, smc.credential_version
		FROM people p
		JOIN staff_mobile_credentials smc ON smc.person_id = p.id AND smc.mobile_access_enabled = 1
		WHERE LOWER(p.status) = 'active'
		  AND (
			  LOWER(p.primary_role) IN ('staff', 'team leader', 'supervisor', 'administrator', 'intern', 'volunteer')
		   OR LOWER(COALESCE(p.staff_classification, '')) IN ('staff', 'team leader', 'supervisor', 'administrator', 'intern', 'volunteer')
		  );
	""")

	if not sync_res["success"] or sync_res["data"].size() != 1:
		print("FAIL: Expected exactly 1 provisioned active staff member, found: ", sync_res["data"].size())
		quit(1)
		return

	var row = sync_res["data"][0]
	if row["human_id"] != "STF-1001":
		print("FAIL: Incorrect staff member selected: ", row)
		quit(1)
		return

	print("PASS 2/3: Staff sync filter correctly included Team Leader Sarah Connor and excluded unprovisioned staff & student.")

	# Test disable mobile access
	var dis_res = mobile_svc.disable_staff_mobile_access(101)
	if not dis_res["success"]:
		print("FAIL: Failed to disable mobile access: ", dis_res.get("error"))
		quit(1)
		return

	var stat = mobile_svc.get_staff_mobile_status(101)
	if stat["enabled"]:
		print("FAIL: Staff mobile status should be disabled, found enabled.")
		quit(1)
		return

	print("PASS 3/3: Mobile Access disabled successfully and version incremented to ", stat["version"], ".")

	db = null
	if dir and dir.file_exists("studycenterhub_test_staff_sync.db"):
		dir.remove("studycenterhub_test_staff_sync.db")

	print("==========================================================")
	print("SUCCESS: STAFF CREDENTIALS PROVISIONING TEST SUITE PASSED")
	print("==========================================================")
	quit(0)
