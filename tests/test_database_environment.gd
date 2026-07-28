extends SceneTree

## Headless Test Suite for Database Environment Resolution
## Verifies environment separation of database files

const SQLiteDatabaseScript = preload("res://src/infrastructure/database/sqlite_database.gd")

func _init() -> void:
	print("==========================================================")
	print("STARTING DATABASE ENVIRONMENT RESOLUTION TEST SUITE")
	print("==========================================================")

	# 1. Verify Staging environment resolution
	OS.set_environment("STUDYCENTERHUB_ENV", "staging")
	var db_staging = SQLiteDatabaseScript.new()
	var staging_path = db_staging.db_path
	print("[Test] Staging resolved to: ", staging_path)
	if not staging_path.ends_with("studycenterhub_staging.db"):
		print("FAIL: Staging environment resolved to incorrect database path.")
		quit(1)
		return
	print("PASS 1/4: Staging environment successfully resolved.")

	# 2. Verify Production environment resolution
	OS.set_environment("STUDYCENTERHUB_ENV", "production")
	var db_prod = SQLiteDatabaseScript.new()
	var prod_path = db_prod.db_path
	print("[Test] Production resolved to: ", prod_path)
	if not prod_path.ends_with("studycenterhub_production.db"):
		print("FAIL: Production environment resolved to incorrect database path.")
		quit(1)
		return
	print("PASS 2/4: Production environment successfully resolved.")

	# 3. Verify Development (Default) environment resolution
	OS.set_environment("STUDYCENTERHUB_ENV", "")
	var db_dev = SQLiteDatabaseScript.new()
	var dev_path = db_dev.db_path
	print("[Test] Default resolved to: ", dev_path)
	if not dev_path.ends_with("studycenterhub_development.db"):
		print("FAIL: Default/empty environment resolved to incorrect database path.")
		quit(1)
		return
	print("PASS 3/4: Default environment resolved to development successfully.")

	# 4. Verify explicit path overrides bypass environment resolution
	var explicit_db = SQLiteDatabaseScript.new("user://studycenterhub_explicit_test.db")
	var explicit_path = explicit_db.db_path
	print("[Test] Explicit override resolved to: ", explicit_path)
	if not explicit_path.ends_with("studycenterhub_explicit_test.db"):
		print("FAIL: Explicit path parameter did not override environment path.")
		quit(1)
		return
	print("PASS 4/4: Explicit path override bypassed environment successfully.")

	# Clean up any created directories/files
	db_staging = null
	db_prod = null
	db_dev = null
	explicit_db = null

	var dir = DirAccess.open("user://")
	if dir:
		# Just clean up the temporary explicit test DB file if created
		if dir.file_exists("studycenterhub_explicit_test.db"):
			dir.remove("studycenterhub_explicit_test.db")

	print("==========================================================")
	print("SUCCESS: DATABASE ENVIRONMENT TESTING PASSED (100%)")
	print("==========================================================")
	quit(0)
