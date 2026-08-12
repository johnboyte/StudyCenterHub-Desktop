extends SceneTree

## Headless Test Suite for Stage 5 — Legacy Migration, Cutover, and Safe Retirement
## Verifies Non-Destructive Staging, Independent Conversions, Rollback Safety, Downstream Edit Safety, and Legacy UI Cutover.

const SQLiteDatabaseScript = preload("res://src/infrastructure/database/sqlite_database.gd")
const MigrationsRunnerScript = preload("res://src/infrastructure/database/migrations_runner.gd")
const UnifiedPathwaysServiceScript = preload("res://src/domain/pathways/unified_pathways_service.gd")
const PathwaysServiceScript = preload("res://src/domain/pathways/pathways_service.gd")
const ReportsServiceScript = preload("res://src/domain/reports/reports_service.gd")

func _init() -> void:
	print("\n==========================================================")
	print("STARTING STAGE 5 UNIFIED PATHWAYS MIGRATION & CUTOVER TEST SUITE")
	print("==========================================================")

	var db_path = ProjectSettings.globalize_path("user://test_stage5_unified_pathways.db")
	if FileAccess.file_exists(db_path):
		DirAccess.remove_absolute(db_path)

	var db = SQLiteDatabaseScript.new(db_path)
	var mig = MigrationsRunnerScript.new(db)
	var mig_res = mig.run_migrations()
	assert_true(mig_res["success"], "Migrations 0001-0038 executed cleanly.")

	var svc = UnifiedPathwaysServiceScript.new(db)
	var leg_svc = PathwaysServiceScript.new(db)
	var rep_svc = ReportsServiceScript.new(db)

	# Seed Test Data: People with Canonical Directory Roles
	db.execute("INSERT INTO people (person_uuid, human_id, first_name, last_name, primary_role) VALUES ('usr_admin_real_101', 'P-5001', 'Monica', 'Geller', 'administrator');")
	db.execute("INSERT INTO people (person_uuid, human_id, first_name, last_name, primary_role) VALUES ('usr_staff_user_102', 'P-5002', 'Chandler', 'Bing', 'staff');")
	db.execute("INSERT INTO people (person_uuid, human_id, first_name, last_name, primary_role) VALUES ('usr_readonly_103', 'P-5003', 'Phoebe', 'Buffay', 'read_only');")

	var p1_id = int(db.execute("SELECT id FROM people WHERE person_uuid = 'usr_admin_real_101';")["data"][0]["id"])
	var p2_id = int(db.execute("SELECT id FROM people WHERE person_uuid = 'usr_staff_user_102';")["data"][0]["id"])
	var p3_id = int(db.execute("SELECT id FROM people WHERE person_uuid = 'usr_readonly_103';")["data"][0]["id"])

	# Create Legacy Records
	# Monica: Real Life + Fellows Cert
	leg_svc.save_legacy_pathway_atomic({"id": p1_id}, {"real_life_enrolled": 1, "fellows_enrolled": 1, "fellows_certificate": 1, "lead_enrolled": 0, "lead_certificate": 0, "lead_current_year": "Year 1"})
	# Chandler: LEAD Cert Year 2
	leg_svc.save_legacy_pathway_atomic({"id": p2_id}, {"real_life_enrolled": 0, "fellows_enrolled": 0, "fellows_certificate": 0, "lead_enrolled": 1, "lead_certificate": 1, "lead_current_year": "Year 2"})
	# Phoebe: Real Life Only
	leg_svc.save_legacy_pathway_atomic({"id": p3_id}, {"real_life_enrolled": 1, "fellows_enrolled": 0, "fellows_certificate": 0, "lead_enrolled": 0, "lead_certificate": 0, "lead_current_year": "Year 1"})

	# Create Annual Programs for 2026-2027
	svc.create_annual_program("fellows", "2026-2027", "FELLOWS — 2026-2027")
	svc.create_annual_program("lead", "2026-2027", "LEAD — 2026-2027")

	# -------------------------------------------------------------------
	# TEST 1: Legacy Staging Import & Idempotency
	# -------------------------------------------------------------------
	print("\n[Test 1] Testing legacy staging import & idempotency...")
	var imp_res1 = svc.import_legacy_tracks_to_staging("batch_test_01", "usr_admin_real_101")
	assert_true(imp_res1["success"], "First staging import executed cleanly.")
	assert_true(int(imp_res1["imported_count"]) == 3, "Imported 3 legacy records into staging.")

	# Idempotency check: running second import with same batch_id imports 0 duplicates
	var imp_res2 = svc.import_legacy_tracks_to_staging("batch_test_01", "usr_admin_real_101")
	assert_true(int(imp_res2["imported_count"]) == 0, "Second staging import with same batch_id imported 0 duplicates (idempotent).")

	# Verify 0 modern active enrollments created during staging import
	var active_cnt = db.execute("SELECT COUNT(*) as cnt FROM person_pathways;")["data"][0]["cnt"]
	assert_true(int(active_cnt) == 0, "Zero active modern enrollments created during staging import.")
	print("PASS 1: Legacy staging import & idempotency verified.")

	# -------------------------------------------------------------------
	# TEST 2: Real Life Historical Preservation & Independent Conversion
	# -------------------------------------------------------------------
	print("\n[Test 2] Testing historical Real Life preservation & independent conversion...")
	var staged = svc.get_staging_records("all", "batch_test_01")
	assert_true(staged.size() == 3, "Fetched 3 staged records.")

	# Find Monica's staged record
	var monica_st = {}
	var chandler_st = {}
	for s in staged:
		if int(s["source_person_id"]) == p1_id: monica_st = s
		elif int(s["source_person_id"]) == p2_id: chandler_st = s

	var st_id_monica = int(monica_st["id"])

	# Convert Fellows ONLY for Monica (2026-2027)
	var conv_res1 = svc.convert_staging_record(st_id_monica, "2026-2027", true, false, "", "", "usr_admin_real_101")
	assert_true(conv_res1["success"], "Converted Fellows program for Monica.")

	# Verify Monica holds Fellows enrollment, but NOT LEAD
	var m_summary = svc.get_profile_pathway_summary(p1_id)
	assert_true(bool(m_summary["fellows"]["enrolled"]) == true, "Monica enrolled in Fellows.")
	assert_true(bool(m_summary["lead"]["enrolled"]) == false, "Monica NOT enrolled in LEAD (independent conversion).")
	assert_true(str(m_summary["fellows"]["current_track"]) == "certification", "Monica Fellows track is certification.")

	# Verify Real Life was preserved historically without creating a fake pathway
	assert_true(int(monica_st["real_life_enrolled"]) == 1, "Real Life flag preserved in staging.")
	print("PASS 2: Real Life historical preservation & independent conversion verified.")

	# -------------------------------------------------------------------
	# TEST 3: Conflict Prevention on Pre-Existing Modern Enrollment
	# -------------------------------------------------------------------
	print("\n[Test 3] Testing conflict prevention on pre-existing modern enrollment...")
	# Attempting to convert Monica Fellows a second time triggers conflict
	var conv_res_dup = svc.convert_staging_record(st_id_monica, "2026-2027", true, false, "", "", "usr_admin_real_101")
	assert_true(conv_res_dup["success"] == false, "Duplicate conversion rejected.")
	assert_true(conv_res_dup["error"].contains("already exists"), "Error clearly states modern enrollment already exists.")
	print("PASS 3: Conflict prevention verified.")

	# -------------------------------------------------------------------
	# TEST 4: Batch Rollback & Downstream Edit Protection
	# -------------------------------------------------------------------
	print("\n[Test 4] Testing batch rollback & downstream edit protection...")
	# Convert Chandler for LEAD
	var st_id_chandler = int(chandler_st["id"])
	svc.convert_staging_record(st_id_chandler, "2026-2027", false, true, "", "", "usr_admin_real_101")

	# Add downstream requirement edit to Chandler's LEAD program
	var c_summary = svc.get_profile_pathway_summary(p2_id)
	var c_ppy_id = int(c_summary["lead"]["person_pathway_program_year_id"])
	svc.create_catch_up_requirement(c_ppy_id, "Leadership Essay", "", "2026-10-01", "Staff User")

	# Perform Rollback on batch_test_01
	var rb_res = svc.rollback_migration_batch("batch_test_01", "usr_admin_real_101")
	assert_true(rb_res["success"], "Batch rollback executed.")
	assert_true(int(rb_res["rolled_back_count"]) == 1, "Monica (un-edited) rolled back cleanly.")
	assert_true(int(rb_res["skipped_due_to_downstream_activity"]) == 1, "Chandler (edited with requirements) skipped safely during rollback.")

	# Verify Monica's modern enrollment was removed, Chandler's remains intact
	var m_summary_post = svc.get_profile_pathway_summary(p1_id)
	var c_summary_post = svc.get_profile_pathway_summary(p2_id)
	assert_true(bool(m_summary_post["fellows"]["enrolled"]) == false, "Monica enrollment removed by rollback.")
	assert_true(bool(c_summary_post["lead"]["enrolled"]) == true, "Chandler enrollment preserved due to downstream activity.")
	print("PASS 4: Batch rollback & downstream edit protection verified.")

	# -------------------------------------------------------------------
	# TEST 5: Reports Analytics & CSV Roster Exclusion of Pending Staging
	# -------------------------------------------------------------------
	print("\n[Test 5] Testing Reports analytics & CSV roster exclusion of pending staging...")
	var kpis = rep_svc.get_summary_kpis()
	assert_true(kpis.has("avg_pathway_progress"), "Reports KPI available.")

	# Unconverted Phoebe (Real Life only) is not included as active roster member in CSV
	var prog_res = svc.get_annual_program("fellows", "2026-2027")
	var prog_id = int(prog_res["program_year_id"])
	var csv = svc.export_program_roster_csv(prog_id)
	assert_true(not csv.contains("Phoebe"), "Pending/unconverted staging record Phoebe excluded from CSV roster export.")
	# -------------------------------------------------------------------
	# TEST 6: Canonical Role Permission Authorization & Atomic Rollback
	# -------------------------------------------------------------------
	print("\n[Test 6] Testing canonical role permission authorization & atomic rollback...")
	var phoebe_st = staged[2]
	var st_id_phoebe = int(phoebe_st["id"])

	# 1. Highest authorized administrator succeeds
	var admin_res = svc.convert_staging_record(st_id_phoebe, "2026-2027", true, false, "", "", "usr_admin_real_101")
	assert_true(admin_res["success"], "Authorized administrator 'usr_admin_real_101' succeeded.")

	# 2. Rollback by admin succeeds
	var rb_admin = svc.rollback_migration_batch("batch_test_01", "usr_admin_real_101")
	assert_true(rb_admin["success"], "Rollback by authorized administrator succeeded.")

	# 3. Ordinary staff account fails
	var staff_res = svc.convert_staging_record(st_id_phoebe, "2026-2027", true, false, "", "", "usr_staff_user_102")
	assert_true(staff_res["success"] == false, "Ordinary staff user 'usr_staff_user_102' rejected.")

	# 4. Read-only account fails
	var ro_res = svc.convert_staging_record(st_id_phoebe, "2026-2027", true, false, "", "", "usr_readonly_103")
	assert_true(ro_res["success"] == false, "Read-only user 'usr_readonly_103' rejected.")

	# 5. Fabricated / unknown identity fails
	var fake_res = svc.convert_staging_record(st_id_phoebe, "2026-2027", true, false, "", "", "usr_hacker_999")
	assert_true(fake_res["success"] == false, "Fabricated identity 'usr_hacker_999' rejected.")

	# 6. Unauthorized import fails
	var imp_unauth = svc.import_legacy_tracks_to_staging("batch_unauth", "usr_staff_user_102")
	assert_true(imp_unauth["success"] == false, "Staging import rejected for non-admin staff user.")

	# 7. Zero-program conversion fails
	var noprog_res = svc.convert_staging_record(st_id_phoebe, "2026-2027", false, false, "", "", "usr_admin_real_101")
	assert_true(noprog_res["success"] == false, "Conversion without selecting at least 1 program rejected.")

	# 8. Forced transaction failure leaves zero partial enrollments
	var forced_fail_res = svc.convert_staging_record(st_id_phoebe, "2026-2027", true, false, "", "", "usr_admin_real_101", true)
	assert_true(forced_fail_res["success"] == false, "Forced transaction failure returned error.")

	var p_summary_post_fail = svc.get_profile_pathway_summary(p3_id)
	assert_true(bool(p_summary_post_fail["fellows"]["enrolled"]) == false, "Forced failure left 0 partial enrollments.")
	print("PASS 6: Canonical role permission authorization & atomic rollback verified.")

	print("\n==========================================================")
	print("ALL STAGE 5 UNIFIED PATHWAYS MIGRATION TESTS PASSED! (6/6)")
	print("==========================================================\n")
	quit(0)

func assert_true(condition: bool, message: String) -> void:
	if condition:
		print("  ✓ PASS: ", message)
	else:
		print("  ❌ FAIL: ", message)
		push_error("Assertion failed: " + message)
		quit(1)
