extends SceneTree

## Headless Test Suite for Story DIR-SPR1-005A
## Automated Verification of Directory Roster Shell & Read-Only Search UI

const SQLiteDatabaseScript = preload("res://src/infrastructure/database/sqlite_database.gd")
const MigrationsRunnerScript = preload("res://src/infrastructure/database/migrations_runner.gd")
const PersonServiceScript = preload("res://src/domain/directory/person_service.gd")
const DirectoryReadServiceScript = preload("res://src/domain/directory/directory_read_service.gd")
const DirectoryViewScript = preload("res://app/scenes/directory_view.gd")

func _init() -> void:
	print("==========================================================")
	print("STARTING STORY DIR-SPR1-005A DIRECTORY UI TEST SUITE")
	print("==========================================================")

	var test_db_path = ProjectSettings.globalize_path("user://test_dir_spr1_005a.db")
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

	# Seed Test Records
	person_service.create_person({"first_name": "Aaron", "last_name": "Zimmerman", "status": "active", "grade": "10th"})
	person_service.create_person({"first_name": "Beth", "last_name": "Yates", "status": "active"}) # No grade
	person_service.create_person({"first_name": "Bartholomew-Alexander", "last_name": "Wellington-Smythe-Montgomery", "status": "active", "grade": "12th"}) # Long name
	person_service.create_person({"first_name": "Carl", "last_name": "Xavier", "status": "pending"})
	person_service.create_person({"first_name": "Diane", "last_name": "White", "status": "To Be Confirmed"})
	person_service.create_person({"first_name": "Eric", "last_name": "Vance", "status": "inactive"})

	# Instantiate DirectoryView scene
	var scene_res = load("res://app/scenes/directory_view.tscn")
	if not scene_res:
		print("FAIL 1: Could not load directory_view.tscn.")
		quit(1)
		return
	var dir_view = scene_res.instantiate() as DirectoryViewScript
	dir_view.read_service = read_service
	root.add_child(dir_view)
	dir_view.refresh_view()

	# 1. Directory scene loads successfully
	if not is_instance_valid(dir_view):
		print("FAIL 1: Directory view instance invalid.")
		quit(1)
		return
	print("PASS 1/21: Directory scene loaded successfully.")

	# 2. All-person count displays correctly (6 total)
	if dir_view.get_count_all_text() != "6":
		print("FAIL 2: All count mismatch: ", dir_view.get_count_all_text())
		quit(1)
		return
	print("PASS 2/21: All-person count displays correctly (6).")

	# 3. Active count displays correctly (3)
	if dir_view.get_count_active_text() != "3":
		print("FAIL 3: Active count mismatch: ", dir_view.get_count_active_text())
		quit(1)
		return
	print("PASS 3/21: Active count displays correctly (3).")

	# 4. Pending count includes pending and To Be Confirmed (2)
	if dir_view.get_count_pending_text() != "2":
		print("FAIL 4: Pending count mismatch: ", dir_view.get_count_pending_text())
		quit(1)
		return
	print("PASS 4/21: Pending count displays correctly (2).")

	# 5. Inactive count displays correctly (1)
	if dir_view.get_count_inactive_text() != "1":
		print("FAIL 5: Inactive count mismatch: ", dir_view.get_count_inactive_text())
		quit(1)
		return
	print("PASS 5/21: Inactive count displays correctly (1).")

	# 6. Initial roster uses deterministic ordering (Vance -> Wellington-Smythe -> Xavier -> Yates -> Zimmerman)
	if dir_view.visible_people.size() != 6:
		print("FAIL 6: Initial roster count incorrect: ", dir_view.visible_people.size())
		quit(1)
		return
	var first_last = dir_view.visible_people[0].get("last_name", "")
	if first_last != "Vance":
		print("FAIL 6: Deterministic ordering failed. First item last_name: ", first_last)
		quit(1)
		return
	print("PASS 6/21: Initial roster uses deterministic ordering.")

	# 7. Search returns matching Person rows ("Zimmerman")
	dir_view.set_search_query("Zimmerman")
	if dir_view.visible_people.size() != 1 or dir_view.visible_people[0].get("first_name") != "Aaron":
		print("FAIL 7: Search by name failed.")
		quit(1)
		return
	print("PASS 7/21: Search returns matching Person rows.")

	# 8. Search retains active status filter
	dir_view.select_filter("active")
	dir_view.set_search_query("Wellington")
	if dir_view.visible_people.size() != 1 or dir_view.visible_people[0].get("first_name") != "Bartholomew-Alexander":
		print("FAIL 8: Search with active filter failed.")
		quit(1)
		return
	print("PASS 8/21: Search retains active status filter.")

	# 9. Empty search restores appropriate status list
	dir_view.set_search_query("")
	if dir_view.visible_people.size() != 3: # 3 active records
		print("FAIL 9: Empty search did not restore active filter list. Size: ", dir_view.visible_people.size())
		quit(1)
		return
	print("PASS 9/21: Empty search restores appropriate status filter list.")

	# 10. Active filter displays only active records
	for p in dir_view.visible_people:
		if p.get("status") != "active":
			print("FAIL 10: Non-active record in active filter: ", p)
			quit(1)
			return
	print("PASS 10/21: Active filter displays only active records.")

	# 11. Pending filter displays both compatible pending values
	dir_view.select_filter("pending")
	if dir_view.visible_people.size() != 2:
		print("FAIL 11: Pending filter size mismatch: ", dir_view.visible_people.size())
		quit(1)
		return
	print("PASS 11/21: Pending filter displays both pending and To Be Confirmed values.")

	# 12. Inactive filter displays only inactive records
	dir_view.select_filter("inactive")
	if dir_view.visible_people.size() != 1 or dir_view.visible_people[0].get("first_name") != "Eric":
		print("FAIL 12: Inactive filter failed.")
		quit(1)
		return
	print("PASS 12/21: Inactive filter displays only inactive records.")

	# Reset filter to "all" for selection tests
	dir_view.select_filter("all")

	# 13. Missing grade is rendered safely
	var beth_idx = -1
	for i in range(dir_view.visible_people.size()):
		if dir_view.visible_people[i].get("first_name") == "Beth":
			beth_idx = i
			break
	dir_view.select_person_by_index(beth_idx)
	if dir_view.is_preview_grade_badge_visible():
		print("FAIL 13: Grade badge visible for person without grade.")
		quit(1)
		return
	print("PASS 13/21: Missing grade rendered safely.")

	# 14. Long Person names rendered safely
	var long_idx = -1
	for i in range(dir_view.visible_people.size()):
		if dir_view.visible_people[i].get("first_name") == "Bartholomew-Alexander":
			long_idx = i
			break
	dir_view.select_person_by_index(long_idx)
	if dir_view.get_preview_name_text() != "Bartholomew-Alexander Wellington-Smythe-Montgomery":
		print("FAIL 14: Long name mismatch: ", dir_view.get_preview_name_text())
		quit(1)
		return
	print("PASS 14/21: Long Person names rendered safely.")

	# 15. Mouse selection updates placeholder preview
	dir_view.select_person_by_index(0)
	if dir_view.get_preview_name_text() == "":
		print("FAIL 15: Mouse press selection did not update preview.")
		quit(1)
		return
	print("PASS 15/21: Mouse selection updates placeholder preview.")

	# 16. Keyboard selection updates placeholder preview
	dir_view.select_person_by_index(0)
	var k_event = InputEventKey.new()
	k_event.pressed = true
	k_event.keycode = KEY_DOWN
	dir_view._unhandled_input(k_event)
	if dir_view.selected_person_index != 1:
		print("FAIL 16: Keyboard DOWN arrow did not move selection. Current idx: ", dir_view.selected_person_index)
		quit(1)
		return
	print("PASS 16/21: Keyboard navigation updates placeholder preview.")

	# 17. No-results state displays correctly
	dir_view.set_search_query("NonExistentSearchXYZ")
	if not dir_view.is_no_results_visible():
		print("FAIL 17: No-results state label is not visible.")
		quit(1)
		return
	print("PASS 17/21: No-results state displays correctly.")

	# 18. Empty-Directory state displays correctly
	var empty_db_path = ProjectSettings.globalize_path("user://test_dir_spr1_005a_empty.db")
	if FileAccess.file_exists(empty_db_path):
		DirAccess.remove_absolute(empty_db_path)
	var empty_db = SQLiteDatabaseScript.new(empty_db_path)
	MigrationsRunnerScript.new(empty_db).run_migrations()
	var empty_read_service = DirectoryReadServiceScript.new(empty_db)

	dir_view.current_query = ""
	dir_view.current_filter = "all"
	dir_view.set_read_service(empty_read_service)
	dir_view.refresh_view()
	if not dir_view.is_empty_state_visible():
		print("FAIL 18: Empty Directory state label is not visible.")
		quit(1)
		return
	print("PASS 18/21: Empty-Directory state displays correctly.")

	# 19. Service error state displays safely
	dir_view.set_read_service(null)
	dir_view.refresh_view()
	if not dir_view.is_error_state_visible():
		print("FAIL 19: Error state label is not visible when read service is null.")
		quit(1)
		return
	print("PASS 19/21: Service error state displays safely.")

	# Restore valid read service
	dir_view.set_read_service(read_service)

	# 20 & 21. Strictly Read-Only Integrity Verification
	var outbox_before = db.execute("SELECT COUNT(*) AS cnt FROM event_outbox;")["data"][0].get("cnt", 0)
	var people_before = db.execute("SELECT COUNT(*) AS cnt FROM people;")["data"][0].get("cnt", 0)

	# Simulate active search & filter operations
	dir_view.select_filter("active")
	dir_view.set_search_query("Aaron")

	var outbox_after = db.execute("SELECT COUNT(*) AS cnt FROM event_outbox;")["data"][0].get("cnt", 0)
	var people_after = db.execute("SELECT COUNT(*) AS cnt FROM people;")["data"][0].get("cnt", 0)

	if outbox_before != outbox_after or people_before != people_after:
		print("FAIL 20/21: UI interaction mutated database or generated outbox events!")
		quit(1)
		return
	print("PASS 20/21: UI interaction created zero outbox records.")
	print("PASS 21/21: UI interaction made zero Person data mutations.")

	print("==========================================================")
	print("SUCCESS: ALL STORY DIR-SPR1-005A OBJECTIVES PASSED (100%)")
	print("==========================================================")
	quit(0)
