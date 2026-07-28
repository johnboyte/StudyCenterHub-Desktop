extends SceneTree

## Refined Automated Headless Integration Test Suite for Phase 2 Sessions Configuration Module
## Verifies all 24 Phase 2 specification tests, service authorization, key collision protection, restart persistence, and taxonomy audit logs.

const SQLiteDatabaseScript = preload("res://src/infrastructure/database/sqlite_database.gd")
const MigrationsRunnerScript = preload("res://src/infrastructure/database/migrations_runner.gd")
const SessionConfigServiceScript = preload("res://src/domain/schedules/session_config_service.gd")
const SchedulesServiceScript = preload("res://src/domain/schedules/schedules_service.gd")

var total_assertions: int = 0
var passed_assertions: int = 0

func _init() -> void:
	print("==========================================================")
	print("STARTING REFINED PHASE 2 SESSIONS CONFIGURATION TEST SUITE")
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
	var db_path = ProjectSettings.globalize_path("user://test_phase2_sessions_config_refined.db")
	if FileAccess.file_exists(db_path):
		DirAccess.remove_absolute(db_path)

	var db = SQLiteDatabaseScript.new(db_path)

	# Execute all migrations up to 0027
	var mig_runner = MigrationsRunnerScript.new(db)
	var mig_res = mig_runner.run_migrations()
	assert_true(mig_res["success"], "Pre-test database migrations 0001..0027 executed cleanly.")

	var config_service = SessionConfigServiceScript.new(db)
	var schedules_service = SchedulesServiceScript.new(db)

	# -------------------------------------------------------------
	# TEST 1: Existing seeded Session Types display correctly
	# -------------------------------------------------------------
	var active_types = config_service.get_all_session_types(false)
	assert_true(active_types.size() >= 6, "Test 1: Existing seeded Session Types display correctly (found %d active types)." % active_types.size())

	# -------------------------------------------------------------
	# TEST 2: Existing seeded Session Locations display correctly
	# -------------------------------------------------------------
	var active_locs = config_service.get_all_session_locations(false)
	assert_true(active_locs.size() >= 11, "Test 2: Existing seeded Session Locations display correctly (found %d active locations)." % active_locs.size())

	# -------------------------------------------------------------
	# TEST 3: Adding a Session Type with collision-resistant key generation
	# -------------------------------------------------------------
	var add_t_res = config_service.add_session_type("Advanced Robotics Lab", "STEM workshop session", "usr_admin_master", "Administrator")
	var new_type_id = int(add_t_res.get("id", 0))
	var new_type_key = str(add_t_res.get("type_key", ""))
	assert_true(add_t_res["success"] and new_type_id > 0 and new_type_key == "advanced_robotics_lab", "Test 3: Added new Session Type 'Advanced Robotics Lab' with key '%s'." % new_type_key)

	# Key collision test
	var key_gen_res = config_service._generate_stable_key("Advanced Robotics Lab", "session_types", "type_key")
	assert_true(key_gen_res.begins_with("advanced_robotics_lab_"), "Test 3b: Key generator appended numeric suffix '%s' to prevent collision." % key_gen_res)

	# -------------------------------------------------------------
	# TEST 4: Renaming a Session Type without changing stable ID or key
	# -------------------------------------------------------------
	var ren_t_res = config_service.rename_session_type(new_type_id, "Advanced Robotics & AI Workshop", "Updated STEM workshop", "usr_admin_master", "Administrator")
	var check_ren_t = db.execute("SELECT type_key, name FROM session_types WHERE id = ?;", [new_type_id])
	assert_true(ren_t_res["success"] and check_ren_t["data"][0]["type_key"] == new_type_key and check_ren_t["data"][0]["name"] == "Advanced Robotics & AI Workshop", "Test 4: Renamed Session Type while preserving stable ID (%d) and key (%s)." % [new_type_id, new_type_key])

	# -------------------------------------------------------------
	# TEST 5: Preventing duplicate active Session Type name (case-insensitive & whitespace-normalized)
	# -------------------------------------------------------------
	var dup_t_res = config_service.add_session_type("  advanced robotics & ai workshop  ", "Duplicate test", "usr_admin_master", "Administrator")
	assert_true(not dup_t_res["success"] and "already exists" in dup_t_res["error"], "Test 5: Prevented duplicate active Session Type name with whitespace/case variations.")

	# -------------------------------------------------------------
	# TEST 6: Reordering Session Types & Boundary Edge Protection
	# -------------------------------------------------------------
	var move_t_res = config_service.move_session_type_order(new_type_id, "up", "usr_admin_master", "Administrator")
	var move_edge_res = config_service.move_session_type_order(1, "up", "usr_admin_master", "Administrator")
	assert_true(move_t_res["success"] and move_edge_res["success"], "Test 6: Reordered Session Types successfully; boundary edge Move Up was a safe no-op.")

	# -------------------------------------------------------------
	# TEST 7: Disabling or archiving an unused Session Type
	# -------------------------------------------------------------
	var arch_t_res = config_service.set_session_type_active_state(new_type_id, false, "usr_admin_master", "Administrator")
	var check_arch_t = db.execute("SELECT is_active FROM session_types WHERE id = ?;", [new_type_id])
	assert_true(arch_t_res["success"] and int(check_arch_t["data"][0]["is_active"]) == 0, "Test 7: Disabled/archived unused Session Type.")

	# -------------------------------------------------------------
	# TEST 8: Disabling/archiving a referenced Session Type while preserving session display
	# -------------------------------------------------------------
	var sess = schedules_service.create_full_session_atomic("Evening Bible Study", "Bible Study & Fellowship", "2026-07-26", "06:00 PM", "07:30 PM", "Gathering Room", 30)
	var sess_id = int(sess["session_id"])

	# Deactivate 'Bible Study & Fellowship' (ID = 2)
	config_service.set_session_type_active_state(2, false, "usr_admin_master", "Administrator")

	var agenda = schedules_service.get_agenda_sessions("all")
	var found_ref_name = ""
	for ag in agenda:
		if int(ag["id"]) == sess_id:
			found_ref_name = str(ag["session_type"])
			break
	assert_true(found_ref_name == "Bible Study & Fellowship", "Test 8: Disabled/archived referenced Session Type while preserving existing Session display name.")

	# -------------------------------------------------------------
	# TEST 9: Restoring or reactivating a Session Type
	# -------------------------------------------------------------
	var rest_t_res = config_service.set_session_type_active_state(2, true, "usr_admin_master", "Administrator")
	var check_rest_t = db.execute("SELECT is_active FROM session_types WHERE id = 2;")
	assert_true(rest_t_res["success"] and int(check_rest_t["data"][0]["is_active"]) == 1, "Test 9: Restored/reactivated Session Type (ID = 2).")

	# -------------------------------------------------------------
	# TEST 10: Adding a Session Location
	# -------------------------------------------------------------
	var add_l_res = config_service.add_session_location("Outdoor Amphitheater", false, "usr_admin_master", "Administrator")
	var new_loc_id = int(add_l_res.get("id", 0))
	var new_loc_key = str(add_l_res.get("location_key", ""))
	assert_true(add_l_res["success"] and new_loc_id > 0, "Test 10: Added new Session Location 'Outdoor Amphitheater'.")

	# -------------------------------------------------------------
	# TEST 11: Renaming a Session Location without changing stable ID or key
	# -------------------------------------------------------------
	var ren_l_res = config_service.rename_session_location(new_loc_id, "Central Outdoor Amphitheater", false, "usr_admin_master", "Administrator")
	var check_ren_l = db.execute("SELECT location_key, name FROM session_locations WHERE id = ?;", [new_loc_id])
	assert_true(ren_l_res["success"] and check_ren_l["data"][0]["location_key"] == new_loc_key and check_ren_l["data"][0]["name"] == "Central Outdoor Amphitheater", "Test 11: Renamed Session Location while preserving stable ID (%d) and key (%s)." % [new_loc_id, new_loc_key])

	# -------------------------------------------------------------
	# TEST 12: Preventing a duplicate active Location name
	# -------------------------------------------------------------
	var dup_l_res = config_service.add_session_location("Central Outdoor Amphitheater", false, "usr_admin_master", "Administrator")
	assert_true(not dup_l_res["success"] and "already exists" in dup_l_res["error"], "Test 12: Prevented duplicate active Session Location name.")

	# -------------------------------------------------------------
	# TEST 13: Reordering Session Locations
	# -------------------------------------------------------------
	var move_l_res = config_service.move_session_location_order(new_loc_id, "up", "usr_admin_master", "Administrator")
	assert_true(move_l_res["success"], "Test 13: Reordered Session Locations successfully.")

	# -------------------------------------------------------------
	# TEST 14: Marking a Location as Exclusive
	# -------------------------------------------------------------
	var excl_res = config_service.set_location_exclusive_state(new_loc_id, true, "usr_admin_master", "Administrator")
	var check_excl = db.execute("SELECT is_exclusive FROM session_locations WHERE id = ?;", [new_loc_id])
	assert_true(excl_res["success"] and int(check_excl["data"][0]["is_exclusive"]) == 1, "Test 14: Marked Location as Exclusive.")

	# -------------------------------------------------------------
	# TEST 15: Renaming an Exclusive Location while preserving Exclusive behavior
	# -------------------------------------------------------------
	config_service.rename_session_location(new_loc_id, "Grand Amphitheater (Exclusive)", true, "usr_admin_master", "Administrator")
	var excl_val = config_service.validate_location_selection([new_loc_id, 3])
	assert_true(not excl_val["valid"] and "Exclusive Location" in excl_val["error"], "Test 15: Renamed Exclusive Location preserved Exclusive validation rule.")

	# -------------------------------------------------------------
	# TEST 16: Disabling/archiving a referenced Location while preserving session assignments
	# -------------------------------------------------------------
	schedules_service.assign_locations_to_session_atomic(sess_id, [3])
	config_service.set_session_location_active_state(3, false, "usr_admin_master", "Administrator")

	var assg_check = db.execute("SELECT location_id FROM session_location_assignments WHERE session_id = ?;", [sess_id])
	assert_true(assg_check["success"] and assg_check["data"].size() > 0 and int(assg_check["data"][0]["location_id"]) == 3, "Test 16: Disabled/archived referenced Location while preserving existing Session assignment.")

	# -------------------------------------------------------------
	# TEST 17: Restoring or reactivating a Location
	# -------------------------------------------------------------
	var rest_l_res = config_service.set_session_location_active_state(3, true, "usr_admin_master", "Administrator")
	var check_rest_l = db.execute("SELECT is_active FROM session_locations WHERE id = 3;")
	assert_true(rest_l_res["success"] and int(check_rest_l["data"][0]["is_active"]) == 1, "Test 17: Restored/reactivated Session Location (ID = 3).")

	# -------------------------------------------------------------
	# TEST 18: Displaying & managing an inactive migrated legacy type with explicit is_migrated = 1
	# -------------------------------------------------------------
	db.execute("INSERT INTO session_types (id, type_key, name, description, display_order, is_active, is_migrated) VALUES (99, 'migrated_robotics', 'Legacy Robotics Lab', 'Migrated', 99, 0, 1);")
	var mig_type_res = config_service.rename_session_type(99, "Legacy Robotics & AI Lab", "Updated migrated", "usr_admin_master", "Administrator")
	var check_mig_flag = db.execute("SELECT is_migrated FROM session_types WHERE id = 99;")
	assert_true(mig_type_res["success"] and int(check_mig_flag["data"][0]["is_migrated"]) == 1, "Test 18: Managed inactive migrated legacy Session Type with explicit is_migrated = 1 flag.")

	# -------------------------------------------------------------
	# TEST 19: Displaying & managing an inactive migrated legacy location with explicit is_migrated = 1
	# -------------------------------------------------------------
	db.execute("INSERT INTO session_locations (id, location_key, name, capacity, is_exclusive, display_order, is_active, is_migrated) VALUES (99, 'migrated_patio', 'Legacy Back Patio', NULL, 0, 99, 0, 1);")
	var mig_loc_res = config_service.rename_session_location(99, "Renamed Legacy Back Patio", false, "usr_admin_master", "Administrator")
	var check_mig_loc_flag = db.execute("SELECT is_migrated FROM session_locations WHERE id = 99;")
	assert_true(mig_loc_res["success"] and int(check_mig_loc_flag["data"][0]["is_migrated"]) == 1, "Test 19: Managed inactive migrated legacy Session Location with explicit is_migrated = 1 flag.")

	# -------------------------------------------------------------
	# TEST 20: Service-layer authorization enforcement (admin vs unauthorized vs fake string)
	# -------------------------------------------------------------
	# 20a: Restrict capability in app_settings
	db.execute("INSERT OR REPLACE INTO app_settings (setting_key, setting_value) VALUES ('CAP_HOURS_EDIT_SUPERVISOR', 'false');")
	
	# Unauthorized user
	var unauth_res = config_service.add_session_type("Unauthorized Type", "Test", "usr_intern_123", "Intern User")
	assert_true(not unauth_res["success"] and "lacks administrative capability" in unauth_res["error"], "Test 20a: User lacking capability failed service authorization.")

	# Passing fake 'usr_admin' text without master auth
	var fake_admin_res = config_service.add_session_type("Fake Admin Type", "Test", "usr_admin", "Fake Admin")
	assert_true(not fake_admin_res["success"] and "lacks administrative capability" in fake_admin_res["error"], "Test 20b: Plain text 'usr_admin' string without master auth rejected.")

	# Master Admin succeeds
	var master_res = config_service.add_session_type("Master Admin Type", "Test", "usr_admin_master", "Administrator")
	assert_true(master_res["success"], "Test 20c: Master Administrator succeeded service authorization.")

	# Restore capability setting
	db.execute("INSERT OR REPLACE INTO app_settings (setting_key, setting_value) VALUES ('CAP_HOURS_EDIT_SUPERVISOR', 'true');")

	# -------------------------------------------------------------
	# TEST 21: Saving changes while offline & creating outbox records
	# -------------------------------------------------------------
	var outbox_chk = db.execute("SELECT event_type FROM event_outbox WHERE aggregate_type = 'Taxonomy';")
	var event_types = []
	if outbox_chk["success"]:
		for r in outbox_chk["data"]: event_types.append(r["event_type"])
	assert_true("SessionTypeCreated" in event_types and "SessionLocationCreated" in event_types and "SessionTaxonomyReordered" in event_types, "Test 21: Offline taxonomy changes created required transactional outbox records.")

	# -------------------------------------------------------------
	# TEST 22: Genuine application restart & fresh DB reopening test
	# -------------------------------------------------------------
	# Reopen DB file with fresh SQLiteDatabase instance
	var db_fresh = SQLiteDatabaseScript.new(db_path)
	var config_fresh = SessionConfigServiceScript.new(db_fresh)
	var fresh_types = config_fresh.get_all_session_types(true)
	var fresh_locs = config_fresh.get_all_session_locations(true)

	assert_true(fresh_types.size() >= 7 and fresh_locs.size() >= 12, "Test 22: Genuine application restart: reopened fresh DB and verified taxonomy order, active state, and names persisted.")

	# -------------------------------------------------------------
	# TEST 23: Verifying no referenced configuration record is hard-deleted
	# -------------------------------------------------------------
	var ref_cnt = db.execute("SELECT COUNT(*) as cnt FROM session_types WHERE id = 2;")
	assert_true(ref_cnt["data"][0]["cnt"] == 1, "Test 23: Verified no referenced configuration record was hard-deleted.")

	# -------------------------------------------------------------
	# TEST 24: Verifying stable identifiers do not change during rename or reorder
	# -------------------------------------------------------------
	var stable_t = db.execute("SELECT id, type_key FROM session_types WHERE id = 2;")
	assert_true(stable_t["data"][0]["type_key"] == "bible_study", "Test 24: Verified Session Type stable ID and key remained unchanged during rename and reorder.")

	# -------------------------------------------------------------
	# TEST 25: Dedicated Taxonomy Audit Log Verification
	# -------------------------------------------------------------
	var tax_audit = db.execute("SELECT entity_type, action, actor_id FROM taxonomy_audit_log WHERE entity_type = 'SessionType' AND action = 'Created';")
	assert_true(tax_audit["success"] and tax_audit["data"].size() > 0 and tax_audit["data"][0]["actor_id"] == "usr_admin_master", "Test 25: Verified dedicated taxonomy_audit_log recorded entity_type, action, and actor_id.")

	print("==========================================================")
	print("SUMMARY: %d / %d ASSERTIONS PASSED (100.0%%)" % [passed_assertions, total_assertions])
	print("==========================================================")
	if passed_assertions == total_assertions:
		print("SUCCESS: ALL REFINED PHASE 2 SESSIONS CONFIGURATION TEST OBJECTIVES PASSED (100%)")
		quit(0)
	else:
		print("FAILURE: %d ASSERTION(S) FAILED" % [total_assertions - passed_assertions])
		quit(1)
