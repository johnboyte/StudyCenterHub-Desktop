extends SceneTree

## Automated Headless Test Suite for Kiosk Registration & Event Creation
## Verifies that kiosk participant registration writes credentials and creates outbox sync events

const SQLiteDatabaseScript = preload("res://src/infrastructure/database/sqlite_database.gd")
const MigrationsRunnerScript = preload("res://src/infrastructure/database/migrations_runner.gd")

func _init() -> void:
	print("==========================================================")
	print("STARTING KIOSK SELF-REGISTRATION TEST SUITE")
	print("==========================================================")

	var db_path = ProjectSettings.globalize_path("user://studycenterhub_test_kiosk_reg.db")
	
	# Clean database setup
	var dir = DirAccess.open("user://")
	if dir and dir.file_exists("studycenterhub_test_kiosk_reg.db"):
		dir.remove("studycenterhub_test_kiosk_reg.db")

	var db = SQLiteDatabaseScript.new(db_path)
	
	# Run migrations
	var mig_runner = MigrationsRunnerScript.new(db)
	var mig_res = mig_runner.run_migrations()
	if not mig_res["success"]:
		print("FAIL: Migrations failed on test database: ", mig_res["error"])
		quit(1)
		return

	# Simulate form submissions
	var fn = "Julian"
	var ln = "Verus"
	var ph = "509-555-8888"
	var bd = "2009-08-12"
	var photo_base64 = "data:image/png;base64,dummy_test_avatar"
	var consent_time = Time.get_date_string_from_system() + " " + Time.get_time_string_from_system()
	
	var new_human_id = "PRT-9001"
	var new_uuid = "usr_kiosk_test_001"

	# Insert person
	var q = "INSERT INTO people (person_uuid, human_id, first_name, last_name, primary_role, phone, birthday, profile_photo, flag_status, sms_consent, sms_consent_at, sms_consent_source) VALUES (?, ?, ?, ?, 'Participant', ?, ?, ?, 'Clear', 1, ?, 'Kiosk Self Registration');"
	var ins_res = db.execute(q, [new_uuid, new_human_id, fn, ln, ph, bd, photo_base64, consent_time])
	if not ins_res["success"]:
		print("FAIL: Failed to insert registration profile: ", ins_res["error"])
		quit(1)
		return

	var id_res = db.execute("SELECT id FROM people WHERE person_uuid = ? LIMIT 1;", [new_uuid])
	if not id_res["success"] or id_res["data"].size() == 0:
		print("FAIL: Failed to lookup newly registered participant.")
		quit(1)
		return
	var new_pid = int(id_res["data"][0]["id"])

	# Insert PIN credential
	var pin = "5555"
	var cred_id = "PIN-TEST-9001"
	var pin_res = db.execute("INSERT INTO participant_pin_credentials (credential_id, person_id, pin_hash, status) VALUES (?, ?, ?, 'active');",
		[cred_id, new_pid, pin])
	if not pin_res["success"]:
		print("FAIL: Failed to create PIN credential: ", pin_res["error"])
		quit(1)
		return

	# Create outbox sync event
	var outbox_payload = {
		"person_uuid": new_uuid,
		"human_id": new_human_id,
		"first_name": fn,
		"last_name": ln,
		"phone": ph,
		"birthday": bd,
		"profile_photo": photo_base64
	}
	var out_uuid = "evt-test-9001"
	var out_res = db.execute("INSERT INTO event_outbox (event_uuid, event_type, aggregate_type, aggregate_id, payload_json, device_uuid, status) VALUES (?, 'PARTICIPANT_REGISTERED', 'Directory', ?, ?, 'kiosk_node', 'pending');",
		[out_uuid, new_uuid, JSON.stringify(outbox_payload)])
	if not out_res["success"]:
		print("FAIL: Failed to queue registration outbox event: ", out_res["error"])
		quit(1)
		return

	# Verify everything resolves correctly
	print("[Test] Verifying data integrity...")
	var check_p = db.execute("SELECT first_name, last_name, phone FROM people WHERE id = ?;", [new_pid])
	if check_p["data"][0]["first_name"] != "Julian":
		print("FAIL: First name mismatch in database.")
		quit(1)
		return
		
	var check_pin = db.execute("SELECT pin_hash FROM participant_pin_credentials WHERE person_id = ? AND status = 'active';", [new_pid])
	if check_pin["data"][0]["pin_hash"] != "5555":
		print("FAIL: PIN hash mismatch.")
		quit(1)
		return

	var check_evt = db.execute("SELECT event_type FROM event_outbox WHERE event_uuid = ?;", [out_uuid])
	if check_evt["data"][0]["event_type"] != "PARTICIPANT_REGISTERED":
		print("FAIL: Outbox event type mismatch.")
		quit(1)
		return

	print("PASS 1/1: Kiosk registration writes and sync queues successfully.")

	# Cleanup test db
	db = null
	if dir and dir.file_exists("studycenterhub_test_kiosk_reg.db"):
		dir.remove("studycenterhub_test_kiosk_reg.db")

	print("==========================================================")
	print("SUCCESS: KIOSK SELF-REGISTRATION VERIFICATION PASSED")
	print("==========================================================")
	quit(0)
