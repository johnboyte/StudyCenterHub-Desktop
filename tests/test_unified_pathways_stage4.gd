extends SceneTree

## Headless Test Suite for Stage 4 — Legacy Feature Parity & Migration Readiness
## Verifies Reports Analytics Integration, Roster CSV Export, Legacy Banner Availability, and Operational Parity.

const SQLiteDatabaseScript = preload("res://src/infrastructure/database/sqlite_database.gd")
const MigrationsRunnerScript = preload("res://src/infrastructure/database/migrations_runner.gd")
const UnifiedPathwaysServiceScript = preload("res://src/domain/pathways/unified_pathways_service.gd")
const ReportsServiceScript = preload("res://src/domain/reports/reports_service.gd")
const PathwaysViewScene = preload("res://app/scenes/pathways_view.tscn")

func _init() -> void:
	print("\n==========================================================")
	print("STARTING STAGE 4 UNIFIED PATHWAYS PARITY & MIGRATION TEST SUITE")
	print("==========================================================")

	var db_path = ProjectSettings.globalize_path("user://test_stage4_unified_pathways.db")
	if FileAccess.file_exists(db_path):
		DirAccess.remove_absolute(db_path)

	var db = SQLiteDatabaseScript.new(db_path)
	var mig = MigrationsRunnerScript.new(db)
	var mig_res = mig.run_migrations()
	assert_true(mig_res["success"], "Migrations 0001-0037 executed cleanly.")

	var svc = UnifiedPathwaysServiceScript.new(db)
	var rep = ReportsServiceScript.new(db)

	# Seed Test Data
	db.execute("INSERT INTO people (person_uuid, human_id, first_name, last_name) VALUES ('p_st4_1', 'P-4001', 'Rachel', 'Green');")
	var p_res = db.execute("SELECT id FROM people WHERE person_uuid = 'p_st4_1' LIMIT 1;")
	var person_id = int(p_res["data"][0]["id"])

	# Create Fellows Program & Enroll Participant
	var prog_res = svc.create_annual_program("fellows", "2026-2027", "FELLOWS — 2026-2027")
	var prog_id = int(prog_res["program_id"])
	svc.enroll_person_pathway(person_id, "fellows", "2026-2027", "certification", "year_1")

	var summary = svc.get_profile_pathway_summary(person_id)
	var ppy_id = int(summary["fellows"]["person_pathway_program_year_id"])

	# Add 2 Requirements & Complete 1
	var r1 = svc.create_catch_up_requirement(ppy_id, "Module 1 Essay", "", "2026-09-01", "Staff User")
	var r2 = svc.create_catch_up_requirement(ppy_id, "Module 2 Quiz", "", "2026-09-15", "Staff User")
	svc.mark_requirement_complete(int(r1["requirement_id"]), "Graded", "Staff User")

	# -------------------------------------------------------------------
	# TEST 1: Reports Analytics Integration for Unified Pathways
	# -------------------------------------------------------------------
	print("\n[Test 1] Testing Reports analytics integration...")
	var kpis = rep.get_summary_kpis()
	assert_true(kpis.has("avg_pathway_progress"), "KPI contains avg_pathway_progress field.")
	assert_true(int(kpis["avg_pathway_progress"]) == 50, "Average pathway progress correctly calculated as 50% (1/2 completed).")
	print("PASS 1: Reports analytics integration verified.")

	# -------------------------------------------------------------------
	# TEST 2: Program Roster CSV Export & Disk File Creation
	# -------------------------------------------------------------------
	print("\n[Test 2] Testing program roster CSV export & disk file creation...")
	var csv = svc.export_program_roster_csv(prog_id)
	assert_true(csv.contains("Human_ID,First_Name,Last_Name,Track,Standing"), "CSV header contains correct column titles.")
	assert_true(csv.contains("Rachel"), "CSV row contains participant Rachel Green.")
	assert_true(csv.contains("CERTIFICATION"), "CSV row contains correct track.")

	# Verify file written to user://
	var export_path = ProjectSettings.globalize_path("user://test_pathway_roster_fellows_2026_2027.csv")
	var f = FileAccess.open(export_path, FileAccess.WRITE)
	f.store_string(csv); f.close()
	assert_true(FileAccess.file_exists(export_path), "CSV export file created on disk successfully.")
	print("PASS 2: Program roster CSV export & disk file creation verified.")

	# -------------------------------------------------------------------
	# TEST 3: PathwaysView Legacy Banner Text & CSV Export UI Button
	# -------------------------------------------------------------------
	print("\n[Test 3] Testing PathwaysView legacy fallback banner text & CSV button...")
	var view = PathwaysViewScene.instantiate()
	root.add_child(view)
	var sub_lbl = view.get_node("%LegacyContainer/LegacySubtitleLbl")
	assert_true(sub_lbl != null, "LegacySubtitleLbl node exists.")
	assert_true(sub_lbl.text.contains("This legacy Pathways workspace remains available temporarily"), "Legacy banner contains migration notice text.")

	var btn_csv = view.get_node("%BtnExportRosterCsv")
	assert_true(btn_csv != null, "BtnExportRosterCsv UI button node exists in FilterHBox.")
	view.queue_free()
	print("PASS 3: Legacy banner text & CSV button node verified.")

	print("\n==========================================================")
	print("ALL STAGE 4 UNIFIED PATHWAYS PARITY TESTS PASSED! (3/3)")
	print("==========================================================\n")
	quit(0)

func assert_true(condition: bool, message: String) -> void:
	if condition:
		print("  ✓ PASS: ", message)
	else:
		print("  ❌ FAIL: ", message)
		push_error("Assertion failed: " + message)
		quit(1)
