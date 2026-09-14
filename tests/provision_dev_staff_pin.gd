extends SceneTree

## Provision Development Staff PIN for John Boyte
## Target DB: studycenterhub_development.db (DEVELOPMENT ONLY)

const SQLiteDatabaseScript = preload("res://src/infrastructure/database/sqlite_database.gd")
const StaffMobileServiceScript = preload("res://src/domain/directory/staff_mobile_service.gd")
const GatewaySyncServiceScript = preload("res://src/domain/sync/gateway_sync_service.gd")

func _init() -> void:
	print("==========================================================")
	print("PROVISIONING DEVELOPMENT STAFF MOBILE PIN (123456)")
	print("==========================================================")

	OS.set_environment("STUDYCENTERHUB_ENV", "development")

	var db = SQLiteDatabaseScript.new()
	print("[DevProvision] Target DB Path: ", db.db_path)

	# Fetch John Boyte person record ID
	var res_p = db.execute("SELECT id, human_id, first_name, last_name FROM people WHERE human_id = 'P-20260813-F9C7' OR (first_name = 'John' AND last_name = 'Boyte') LIMIT 1;")
	if not res_p["success"] or res_p["data"].size() == 0:
		print("FAIL: John Boyte record not found in development database.")
		quit(1)
		return

	var p_id = int(res_p["data"][0]["id"])
	print("[DevProvision] Found John Boyte person ID: ", p_id)

	var staff_svc = StaffMobileServiceScript.new(db)
	var res_pin = staff_svc.set_staff_mobile_pin(p_id, "123456")
	print("[DevProvision] PIN Set Result: ", res_pin)

	if not res_pin["success"]:
		print("FAIL: Failed to set Development staff PIN: ", res_pin.get("error"))
		quit(1)
		return

	print("[DevProvision] Publishing updated Development staff credential index to dev-gateway...")
	var sync_svc = GatewaySyncServiceScript.new(db, null)
	sync_svc.publish_staff_credentials_index(func(res_sync):
		print("[DevProvision] Staff Credential Sync Result: ", res_sync)
		print("==========================================================")
		print("SUCCESS: DEVELOPMENT STAFF MOBILE CREDENTIAL PROVISIONED")
		print("==========================================================")
		quit(0)
	)
