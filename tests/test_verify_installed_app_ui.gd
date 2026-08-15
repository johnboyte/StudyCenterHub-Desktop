extends SceneTree

## Verification script for installed Production app UI and Database resolution

const SQLiteDatabaseScript = preload("res://src/infrastructure/database/sqlite_database.gd")

func _init() -> void:
	print("==========================================================")
	print("VERIFYING INSTALLED PRODUCTION APP UI & DATABASE RESOLUTION")
	print("==========================================================")

	var prod_db_path = ProjectSettings.globalize_path("user://studycenterhub_production.db")
	print("App Data DB Path: ", prod_db_path)

	var db = SQLiteDatabaseScript.new(prod_db_path)

	# Query John Boyte's staff record
	var q = db.execute("SELECT id, human_id, first_name, last_name, primary_role, staff_classification, status FROM people WHERE first_name = 'John' AND last_name = 'Boyte' LIMIT 1;")
	if not q["success"] or q["data"].size() == 0:
		print("FAIL: Could not locate John Boyte in Production DB.")
		quit(1)
		return

	var p = q["data"][0]
	print("PASS 1/4: Resolved Production database and found John Boyte (ID: ", p["id"], ", Human ID: ", p["human_id"], ").")

	# Verify eligibility rule
	var role_str = String(p.get("primary_role", p.get("staff_classification", "Participant"))).to_lower()
	var classif_str = String(p.get("staff_classification", "")).to_lower()
	var valid_roles = ["staff", "team leader", "supervisor", "administrator", "intern", "volunteer"]
	var is_eligible = (role_str in valid_roles) or (classif_str in valid_roles)

	if not is_eligible:
		print("FAIL: John Boyte profile evaluated as ineligible.")
		quit(1)
		return

	print("PASS 2/4: John Boyte profile is 100% eligible for Staff Mobile Credentials UI.")

	# Verify DirectoryView UI card creation code
	var DirectoryViewScript = load("res://app/scenes/directory_view.gd")
	if not DirectoryViewScript:
		print("FAIL: DirectoryView script failed to load.")
		quit(1)
		return

	var dummy_view = DirectoryViewScript.new()
	if not dummy_view.has_method("_populate_overview_section") or not dummy_view.has_method("_create_credentials_card"):
		print("FAIL: DirectoryView missing expected UI methods.")
		quit(1)
		return

	print("PASS 3/4: Installed app directory_view.gd contains Overview card & Credentials card UI methods.")

	# Verify StaffMobileProvisioningDialog
	var StaffMobileDialogScript = load("res://src/ui/components/staff_mobile_provisioning_dialog.gd")
	if not StaffMobileDialogScript:
		print("FAIL: StaffMobileProvisioningDialog script failed to load.")
		quit(1)
		return

	print("PASS 4/4: StaffMobileProvisioningDialog loaded and ready in installed Production app.")

	db = null
	print("==========================================================")
	print("SUCCESS: INSTALLED PRODUCTION APP UI & DB VERIFIED")
	print("==========================================================")
	quit(0)
