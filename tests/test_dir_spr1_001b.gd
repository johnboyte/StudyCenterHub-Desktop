extends SceneTree

## Headless Test Suite for Story DIR-SPR1-001B
## Comprehensive Verification of PersonService Individual Expansion

const SQLiteDatabaseScript = preload("res://src/infrastructure/database/sqlite_database.gd")
const MigrationsRunnerScript = preload("res://src/infrastructure/database/migrations_runner.gd")
const PersonServiceScript = preload("res://src/domain/directory/person_service.gd")
const AttendanceServiceScript = preload("res://src/domain/attendance/attendance_service.gd")

func _init() -> void:
	print("==========================================================")
	print("STARTING STORY DIR-SPR1-001B PERSONSERVICE TEST SUITE")
	print("==========================================================")

	var test_db_path = ProjectSettings.globalize_path("user://test_dir_spr1_001b.db")
	if FileAccess.file_exists(test_db_path):
		DirAccess.remove_absolute(test_db_path)

	var db = SQLiteDatabaseScript.new(test_db_path)
	var migrations_runner = MigrationsRunnerScript.new(db)

	var mig_res = migrations_runner.run_migrations()
	if not mig_res["success"]:
		print("FAIL: Migration execution failed: ", mig_res["error"])
		quit(1)
		return

	var person_service = PersonServiceScript.new(db)
	var attendance_service = AttendanceServiceScript.new(db)

	# 1. Existing Person creation behavior still works
	var p_test_res = person_service.create_test_person("Alice", "Smith", "555-0101")
	if not p_test_res["success"]:
		print("FAIL 1: create_test_person failed.")
		quit(1)
		return
	var p1 = p_test_res["person"]
	print("PASS 1/16: Existing create_test_person behavior verified.")

	# 2. Retrieve by person_uuid
	var p1_uuid = p1.get("person_uuid", "")
	var get_uuid_res = person_service.get_person_by_uuid(p1_uuid)
	if not get_uuid_res["success"] or get_uuid_res["person"].get("first_name") != "Alice":
		print("FAIL 2: Retrieve by person_uuid failed.")
		quit(1)
		return
	print("PASS 2/16: Retrieve Person by person_uuid verified.")

	# 3. Retrieve by human_id
	var p1_human = p1.get("human_id", "")
	var get_human_res = person_service.get_person_by_human_id(p1_human)
	if not get_human_res["success"] or get_human_res["person"].get("last_name") != "Smith":
		print("FAIL 3: Retrieve by human_id failed.")
		quit(1)
		return
	print("PASS 3/16: Retrieve Person by human_id verified.")

	# 4. Deterministic listing
	person_service.create_person({"first_name": "Bob", "last_name": "Adams", "phone": "555-0102"})
	person_service.create_person({"first_name": "Charlie", "last_name": "Baker", "phone": "555-0103"})
	var list_res = person_service.list_people()
	if not list_res["success"] or list_res["people"].size() < 3:
		print("FAIL 4: Deterministic listing failed.")
		quit(1)
		return
	# Verify ordering: Adams -> Baker -> Smith
	var names = []
	for p in list_res["people"]:
		names.append(p.get("last_name"))
	if names[0] != "Adams" or names[1] != "Baker" or names[2] != "Smith":
		print("FAIL 4: Ordering incorrect: ", names)
		quit(1)
		return
	print("PASS 4/16: Person listing returns deterministic ordered results.")

	# 5. Update editable profile fields
	var upd_res = person_service.update_person_profile(p1_uuid, {"first_name": "Alicia", "grade": "11th"})
	if not upd_res["success"] or upd_res["person"].get("first_name") != "Alicia" or upd_res["person"].get("grade") != "11th":
		print("FAIL 5: Editable profile update failed.")
		quit(1)
		return
	print("PASS 5/16: Editable profile fields updated successfully.")

	# 6. Immutable identifiers cannot be updated
	var imm_res = person_service.update_person_profile(p1_uuid, {"human_id": "P-OVERWRITE-9999"})
	if imm_res["success"]:
		print("FAIL 6: Immutable human_id update should have failed.")
		quit(1)
		return
	print("PASS 6/16: Immutable identifier protection verified.")

	# 7. Update notes
	var notes_res = person_service.update_notes(p1_uuid, "Prefers morning tutoring.")
	if not notes_res["success"] or notes_res["person"].get("notes") != "Prefers morning tutoring.":
		print("FAIL 7: Update notes failed.")
		quit(1)
		return
	print("PASS 7/16: Notes updated successfully.")

	# 8. Update emergency contacts
	var emg_res = person_service.update_emergency_contacts(p1_uuid, "Robert Smith", "555-9988")
	if not emg_res["success"] or emg_res["person"].get("emergency_contact_name") != "Robert Smith" or emg_res["person"].get("emergency_contact_phone") != "555-9988":
		print("FAIL 8: Update emergency contacts failed.")
		quit(1)
		return
	print("PASS 8/16: Emergency contact fields updated successfully.")

	# 9. Update medical notes
	var med_res = person_service.update_medical_notes(p1_uuid, "No known allergies.")
	if not med_res["success"] or med_res["person"].get("medical_notes") != "No known allergies.":
		print("FAIL 9: Update medical notes failed.")
		quit(1)
		return
	print("PASS 9/16: Medical notes updated successfully.")

	# 10. Approve pending Person
	var p_pend_res = person_service.create_person({"first_name": "Pending", "last_name": "Guest", "status": "pending"})
	var p_pend_uuid = p_pend_res["person"].get("person_uuid", "")
	var p_pend_human = p_pend_res["person"].get("human_id", "")

	var app_res = person_service.approve_person(p_pend_uuid)
	if not app_res["success"] or app_res["person"].get("status") != "active":
		print("FAIL 10: Approve person failed.")
		quit(1)
		return
	print("PASS 10/16: Pending Person approved to active status successfully.")

	# 11. Approval preserves person_uuid and human_id
	var app_p = app_res["person"]
	if app_p.get("person_uuid") != p_pend_uuid or app_p.get("human_id") != p_pend_human:
		print("FAIL 11: Approval regenerated immutable identifiers.")
		quit(1)
		return
	print("PASS 11/16: Approval strictly preserved person_uuid and human_id.")

	# 12. Inactivate Person without deletion
	var inact_res = person_service.inactivate_person(p1_uuid)
	if not inact_res["success"] or inact_res["person"].get("status") != "inactive":
		print("FAIL 12: Inactivate person failed.")
		quit(1)
		return
	var inact_check = person_service.get_person_by_uuid(p1_uuid)
	if not inact_check["success"]:
		print("FAIL 12: Inactivated person was deleted.")
		quit(1)
		return
	print("PASS 12/16: Person inactivated without record deletion.")

	# 13. Invalid status values rejected
	var inv_status_res = person_service.change_person_status(p1_uuid, "bogus_status_value")
	if inv_status_res["success"]:
		print("FAIL 13: Invalid status value should have been rejected.")
		quit(1)
		return
	print("PASS 13/16: Invalid status values rejected correctly.")

	# 14. Update nonexistent Person fails safely
	var non_res = person_service.update_person_profile("usr_non_existent_9999", {"first_name": "Ghost"})
	if non_res["success"]:
		print("FAIL 14: Updating nonexistent person should have failed.")
		quit(1)
		return
	print("PASS 14/16: Update of nonexistent Person failed safely.")

	# 15. Person changes create outbox events
	var outbox_query = db.execute("SELECT * FROM event_outbox WHERE aggregate_id = ? AND aggregate_type = 'Person';", [p1_uuid])
	if not outbox_query["success"] or outbox_query["data"].size() == 0:
		print("FAIL 15: Person outbox events were not recorded.")
		quit(1)
		return
	print("PASS 15/16: Person changes created atomic outbox events successfully.")

	# 16. Existing attendance records remain unaffected
	var att_res = attendance_service.record_check_in_atomic(p1)
	if not att_res["success"]:
		print("FAIL 16: Check-in recording failed.")
		quit(1)
		return
	# Re-inactivate person
	person_service.inactivate_person(p1_uuid)
	var att_verify = db.execute("SELECT * FROM attendance_log WHERE person_uuid = ?;", [p1_uuid])
	if not att_verify["success"] or att_verify["data"].size() == 0:
		print("FAIL 16: Inactivation deleted or corrupted attendance records.")
		quit(1)
		return
	print("PASS 16/16: Inactivation preserved historical attendance records intact.")

	print("==========================================================")
	print("SUCCESS: ALL STORY DIR-SPR1-001B OBJECTIVES PASSED (100%)")
	print("==========================================================")
	quit(0)
