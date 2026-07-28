extends SceneTree

## Headless Test Suite for Story DIR-SPR1-002
## Verification of DirectoryReadService

const SQLiteDatabaseScript = preload("res://src/infrastructure/database/sqlite_database.gd")
const MigrationsRunnerScript = preload("res://src/infrastructure/database/migrations_runner.gd")
const PersonServiceScript = preload("res://src/domain/directory/person_service.gd")
const DirectoryReadServiceScript = preload("res://src/domain/directory/directory_read_service.gd")

func _init() -> void:
	print("==========================================================")
	print("STARTING STORY DIR-SPR1-002 DIRECTORY READ SERVICE SUITE")
	print("==========================================================")

	var test_db_path = ProjectSettings.globalize_path("user://test_dir_spr1_002.db")
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
	var read_service = DirectoryReadServiceScript.new(db)

	# Seed Test Data: 2 Active, 2 Pending, 1 Inactive
	var p_act1 = person_service.create_person({"first_name": "Aaron", "last_name": "Zimmerman", "status": "active"})["person"]
	var p_act2 = person_service.create_person({"first_name": "Beth", "last_name": "Yates", "status": "active"})["person"]
	var p_pend1 = person_service.create_person({"first_name": "Carl", "last_name": "Xavier", "status": "pending"})["person"]
	var p_pend2 = person_service.create_person({"first_name": "Diane", "last_name": "White", "status": "To Be Confirmed"})["person"]
	var p_inact = person_service.create_person({"first_name": "Eric", "last_name": "Vance", "status": "inactive"})["person"]

	# 1. Get by UUID
	var act1_uuid = p_act1.get("person_uuid", "")
	var get_uuid_res = read_service.get_person(act1_uuid)
	if not get_uuid_res["success"] or get_uuid_res["person"].get("first_name") != "Aaron":
		print("FAIL 1: get_person failed.")
		quit(1)
		return
	print("PASS 1/9: get_person by UUID verified.")

	# 2. Get by human_id
	var act2_human = p_act2.get("human_id", "")
	var get_human_res = read_service.get_person_by_human_id(act2_human)
	if not get_human_res["success"] or get_human_res["person"].get("first_name") != "Beth":
		print("FAIL 2: get_person_by_human_id failed.")
		quit(1)
		return
	print("PASS 2/9: get_person_by_human_id verified.")

	# 3. List active
	var list_act_res = read_service.list_active_people()
	if not list_act_res["success"] or list_act_res["people"].size() != 2:
		print("FAIL 3: list_active_people failed. Count: ", list_act_res["people"].size())
		quit(1)
		return
	print("PASS 3/9: list_active_people verified (Count: 2).")

	# 4. List pending (includes 'pending' and 'To Be Confirmed')
	var list_pend_res = read_service.list_pending_people()
	if not list_pend_res["success"] or list_pend_res["people"].size() != 2:
		print("FAIL 4: list_pending_people failed. Count: ", list_pend_res["people"].size())
		quit(1)
		return
	print("PASS 4/9: list_pending_people verified (Count: 2).")

	# 5. List inactive
	var list_inact_res = read_service.list_inactive_people()
	if not list_inact_res["success"] or list_inact_res["people"].size() != 1:
		print("FAIL 5: list_inactive_people failed.")
		quit(1)
		return
	print("PASS 5/9: list_inactive_people verified (Count: 1).")

	# 6. Counts
	var total_cnt = read_service.count_people()
	var act_cnt = read_service.count_active()
	var pend_cnt = read_service.count_pending()
	var inact_cnt = read_service.count_inactive()
	if total_cnt != 5 or act_cnt != 2 or pend_cnt != 2 or inact_cnt != 1:
		print("FAIL 6: Counts mismatch: Total=", total_cnt, " Act=", act_cnt, " Pend=", pend_cnt, " Inact=", inact_cnt)
		quit(1)
		return
	print("PASS 6/9: All count methods verified (Total: 5, Active: 2, Pending: 2, Inactive: 1).")

	# 7. Deterministic ordering (Yates -> Zimmerman for active)
	var active_names = [list_act_res["people"][0].get("last_name"), list_act_res["people"][1].get("last_name")]
	if active_names[0] != "Yates" or active_names[1] != "Zimmerman":
		print("FAIL 7: Deterministic ordering failed: ", active_names)
		quit(1)
		return
	print("PASS 7/9: Deterministic ordering verified (Yates -> Zimmerman).")

	# 8. Nonexistent person & person_exists
	var non_uuid = "usr_non_existent_00000"
	var non_res = read_service.get_person(non_uuid)
	var exists_true = read_service.person_exists(act1_uuid)
	var exists_false = read_service.person_exists(non_uuid)
	if non_res["success"] or not exists_true or exists_false:
		print("FAIL 8: Nonexistent person or person_exists failed.")
		quit(1)
		return
	print("PASS 8/9: Nonexistent person & person_exists verified.")

	# 9. Strictly Read-Only (Verify Outbox count unchanged by read queries)
	var outbox_before = db.execute("SELECT COUNT(*) AS cnt FROM event_outbox;")["data"][0].get("cnt", 0)
	read_service.list_people()
	read_service.list_active_people()
	read_service.count_people()
	var outbox_after = db.execute("SELECT COUNT(*) AS cnt FROM event_outbox;")["data"][0].get("cnt", 0)
	if outbox_before != outbox_after:
		print("FAIL 9: Read service mutated event_outbox!")
		quit(1)
		return
	print("PASS 9/9: Strictly Read-Only integrity verified (0 mutations or outbox writes).")

	print("==========================================================")
	print("SUCCESS: ALL STORY DIR-SPR1-002 OBJECTIVES PASSED (100%)")
	print("==========================================================")
	quit(0)
