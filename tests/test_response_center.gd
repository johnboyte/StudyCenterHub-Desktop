extends SceneTree

## Automated Headless Test Suite for Communications Response Center
## Verifies that assignments, work items, and database-driven IVR updates resolve correctly

const SQLiteDatabaseScript = preload("res://src/infrastructure/database/sqlite_database.gd")
const MigrationsRunnerScript = preload("res://src/infrastructure/database/migrations_runner.gd")
const CommunicationsServiceScript = preload("res://src/domain/communications/communications_service.gd")

func _init() -> void:
	print("==========================================================")
	print("STARTING COMMUNICATIONS RESPONSE CENTER TEST SUITE")
	print("==========================================================")

	var db_path = ProjectSettings.globalize_path("user://studycenterhub_test_response_center.db")
	
	if FileAccess.file_exists(db_path):
		DirAccess.remove_absolute(db_path)

	var db = SQLiteDatabaseScript.new(db_path)
	
	# Run migrations
	var mig_runner = MigrationsRunnerScript.new(db)
	var mig_res = mig_runner.run_migrations()
	if not mig_res["success"]:
		print("FAIL: Migrations failed: ", mig_res["error"])
		quit(1)
		return

	# Insert mock staff & participant
	db.execute("INSERT INTO people (id, person_uuid, human_id, first_name, last_name, primary_role, phone) VALUES (1, 'staff_marcus', 'STF-0001', 'Marcus', 'Vance', 'staff', '509-555-0101');")
	db.execute("INSERT INTO people (id, person_uuid, human_id, first_name, last_name, primary_role, phone) VALUES (2, 'stud_sam', 'PRT-1002', 'Samantha', 'Diaz', 'Participant', '509-555-0108');")

	# Insert a mock voicemail from Samantha
	var vm_uuid = "vm_test_901"
	db.execute("INSERT INTO voicemails (voicemail_uuid, caller_name, caller_phone, duration_sec, transcription, status, priority) VALUES (?, 'Unknown Caller', '509-555-0108', 30, 'Need help with registration.', 'new', 'Medium');", [vm_uuid])

	var com_service = CommunicationsServiceScript.new(db)

	# Test 1: Verify get_voicemails joins and matches caller ID
	var vms = com_service.get_voicemails()
	if vms.size() == 0:
		print("FAIL: No voicemails retrieved.")
		quit(1)
		return
		
	var vm = vms[0]
	if vm["matched_caller_name"] != "Samantha Diaz":
		print("FAIL: Caller ID phone matching failed. Expected Samantha Diaz, got: ", vm["matched_caller_name"])
		quit(1)
		return
	print("PASS 1/3: Caller ID matching by phone number verified.")

	# Test 2: Update voicemail work item status and notes
	var up_res = com_service.update_voicemail_workflow(vm_uuid, 1, "in_progress", "High", "2026-07-31", "Staff reviewing case.")
	if not up_res["success"]:
		print("FAIL: Failed to update voicemail workflow.")
		quit(1)
		return
		
	var check_vms = com_service.get_voicemails()
	var check_vm = check_vms[0]
	if check_vm["status"] != "in_progress" or check_vm["priority"] != "High" or int(check_vm["assigned_person_id"]) != 1 or check_vm["assignee_name"] != "Marcus Vance":
		print("FAIL: Workflow assignment persistence mismatch.")
		quit(1)
		return
	print("PASS 2/3: Work Item state transitions and staff assignment persisted successfully.")

	# Test 3: Edit and verify database-driven IVR menu options
	db.execute("UPDATE ivr_menu_options SET script_text = 'Custom hours script test' WHERE digit = '2';")
	var check_ivr = db.execute("SELECT script_text FROM ivr_menu_options WHERE digit = '2';")
	if check_ivr["data"][0]["script_text"] != "Custom hours script test":
		print("FAIL: IVR database script update failed.")
		quit(1)
		return
	print("PASS 3/3: Database-driven IVR script management verified.")

	# Cleanup test db
	db = null
	if dir and dir.file_exists("studycenterhub_test_response_center.db"):
		dir.remove("studycenterhub_test_response_center.db")

	print("==========================================================")
	print("SUCCESS: COMMUNICATIONS RESPONSE CENTER VERIFICATION PASSED")
	print("==========================================================")
	quit(0)
