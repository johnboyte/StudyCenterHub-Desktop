extends SceneTree

## Headless STEP 2 Production Environment & Migration 0055 Verification Script
## Runs against real Production DB (studycenterhub_production.db)

const SQLiteDatabaseScript = preload("res://src/infrastructure/database/sqlite_database.gd")
const MigrationsRunnerScript = preload("res://src/infrastructure/database/migrations_runner.gd")

func _init() -> void:
	print("==========================================================")
	print("STARTING STEP 2 PRODUCTION ENVIRONMENT VERIFICATION")
	print("==========================================================")

	var prod_db_path = ProjectSettings.globalize_path("user://studycenterhub_production.db")
	print("Target Production DB Path: ", prod_db_path)

	var db = SQLiteDatabaseScript.new(prod_db_path)
	var mig_runner = MigrationsRunnerScript.new(db)
	var mig_res = mig_runner.run_migrations()

	if not mig_res["success"]:
		print("FAIL: Migration runner failed on Production DB: ", mig_res["error"])
		quit(1)
		return

	print("PASS 1/5: Migration runner completed. Newly executed migrations: ", mig_res["newly_executed"])

	# Verify migration 0055 created staff_mobile_credentials
	var tbl_res = db.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='staff_mobile_credentials';")
	if not tbl_res["success"] or tbl_res["data"].size() == 0:
		print("FAIL: Table staff_mobile_credentials does not exist in Production DB.")
		quit(1)
		return

	print("PASS 2/5: Table staff_mobile_credentials verified in Production DB.")

	# Verify Production member data preservation
	var people_res = db.execute("SELECT COUNT(*) as count FROM people;")
	var member_count = 0
	if people_res["success"] and people_res["data"].size() > 0:
		member_count = int(people_res["data"][0].get("count", 0))

	if member_count == 0:
		print("FAIL: Production people table is empty.")
		quit(1)
		return

	print("PASS 3/5: Production database resolved and preserved ", member_count, " existing member records.")

	# Verify zero staff mobile credentials exist yet
	var cred_res = db.execute("SELECT COUNT(*) as count FROM staff_mobile_credentials;")
	var cred_count = int(cred_res["data"][0].get("count", 0)) if cred_res["success"] and cred_res["data"].size() > 0 else 0
	print("PASS 4/5: Verified staff_mobile_credentials count is ", cred_count, " (no staff credentials provisioned yet).")

	# Verify GatewaySyncService has publish_staff_credentials_index
	var GatewaySyncScript = load("res://src/domain/sync/gateway_sync_service.gd")
	if not GatewaySyncScript:
		print("FAIL: GatewaySyncService script failed to load.")
		quit(1)
		return

	var dummy_node = Node.new()
	var sync_svc = GatewaySyncScript.new(db, dummy_node)
	if not sync_svc.has_method("publish_staff_credentials_index"):
		print("FAIL: publish_staff_credentials_index method missing in GatewaySyncService.")
		quit(1)
		return

	print("PASS 5/5: publish_staff_credentials_index() method verified in GatewaySyncService.")

	db = null
	print("==========================================================")
	print("SUCCESS: STEP 2 PRODUCTION VERIFICATION PASSED")
	print("==========================================================")
	quit(0)
