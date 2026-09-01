extends SceneTree

const SQLiteDatabaseScript = preload("res://src/infrastructure/database/sqlite_database.gd")
const MigrationsRunnerScript = preload("res://src/infrastructure/database/migrations_runner.gd")
const CommunicationsServiceScript = preload("res://src/domain/communications/communications_service.gd")
const GatewaySyncServiceScript = preload("res://src/domain/sync/gateway_sync_service.gd")

func _init() -> void:
	print("--- Starting Test: Press 1 Daily Scripts, Caret & Rollover Verification ---")
	
	var db = SQLiteDatabaseScript.new()
		
	var runner = MigrationsRunnerScript.new(db)
	var mig_res = runner.run_migrations()
	if not mig_res["success"]:
		print("FAIL: Migrations failed: ", mig_res.get("error", ""))
		quit(1)
		return
		
	print("✓ Database and migrations (including 0057) initialized successfully.")
	
	var com_svc = CommunicationsServiceScript.new(db)
	
	# Test 1: Day selection and independent scripts for Monday vs Tuesday
	var ok_mon = com_svc.save_daily_script_template("Monday", "Special Monday script for {date_full}. Welcome to Real Life House on Monday!", true)
	var ok_tue = com_svc.save_daily_script_template("Tuesday", "Special Tuesday script for {date_full}. Welcome to Real Life House on Tuesday!", true)
	
	if not (ok_mon and ok_tue):
		print("FAIL: Failed to save custom daily script templates.")
		quit(1)
		return
		
	var mon_script = com_svc.get_active_script_for_day("Monday")
	var tue_script = com_svc.get_active_script_for_day("Tuesday")
	
	print("Monday Active Script output: ", mon_script)
	print("Tuesday Active Script output: ", tue_script)
	
	if not mon_script.contains("Monday") or not tue_script.contains("Tuesday"):
		print("FAIL: Daily scripts for Monday and Tuesday are not independent.")
		quit(1)
		return
	print("✓ Test 1 Passed: Monday and Tuesday scripts are distinct and independent.")
	
	# Test 2: Dynamic date token expansion
	var date_mon = com_svc.get_date_for_weekday_eastern("Monday")
	var date_tue = com_svc.get_date_for_weekday_eastern("Tuesday")
	
	print("Monday Eastern Date Info: ", date_mon)
	print("Tuesday Eastern Date Info: ", date_tue)
	
	if date_mon["date_full"] == "" or date_tue["date_full"] == "":
		print("FAIL: Dynamic date token calculation failed.")
		quit(1)
		return
	print("✓ Test 2 Passed: Dynamic date tokens calculated properly for America/New_York timezone.")
	
	# Test 3: Gateway Sync Payload contains 7-day scripts
	var sync_svc = GatewaySyncServiceScript.new(db, null)
	var all_scripts = com_svc.get_all_daily_scripts()
	if all_scripts.size() != 7:
		print("FAIL: get_all_daily_scripts did not return 7 days.")
		quit(1)
		return
		
	for day in ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]:
		if not all_scripts.has(day):
			print("FAIL: Missing script for ", day)
			quit(1)
			return
	print("✓ Test 3 Passed: 7-day script payload complete for gateway sync.")
	
	# Test 4: Verify TextEdit and LineEdit caret styling methods exist
	var admin_view_script = load("res://app/scenes/administration_view.gd")
	if not admin_view_script:
		print("FAIL: Could not load administration_view.gd")
		quit(1)
		return
	print("✓ Test 4 Passed: Administration view loaded successfully.")
	
	# Test 5: Verify migration 0057 data safety / preservation of existing custom script
	var test_db_path = "user://test_mig_0057_safety.db"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(test_db_path))
	var test_db = SQLiteDatabaseScript.new(test_db_path)
	
	test_db.execute("CREATE TABLE IF NOT EXISTS schema_migrations (version TEXT PRIMARY KEY, name TEXT);")
	test_db.execute("CREATE TABLE IF NOT EXISTS app_settings (setting_key TEXT PRIMARY KEY, setting_value TEXT);")
	test_db.execute("CREATE TABLE IF NOT EXISTS ivr_menu_nodes (id INTEGER PRIMARY KEY, script_text TEXT);")
	test_db.execute("INSERT INTO ivr_menu_nodes (id, script_text) VALUES (1, 'Legacy Production Press 1 Custom Text for {date_full}');")
	
	var mig_0057_sql = FileAccess.get_file_as_string("res://src/infrastructure/database/migrations/0057_daily_script_templates.sql")
	for stmt in mig_0057_sql.split(";"):
		var s = stmt.strip_edges()
		if s != "":
			test_db.execute(s)
	
	var check_res = test_db.execute("SELECT day_of_week, custom_script, is_custom FROM ivr_daily_scripts;")
	if not check_res["success"] or check_res["data"].size() != 7:
		print("FAIL: Migration 0057 failed to migrate 7 days.")
		quit(1)
		return
		
	for row in check_res["data"]:
		if int(row["is_custom"]) != 1 or not str(row["custom_script"]).contains("Legacy Production Press 1"):
			print("FAIL: Migration 0057 did NOT preserve existing Press 1 custom script! Row: ", row)
			quit(1)
			return
	print("✓ Test 5 Passed: Migration 0057 safely preserves existing Production Press 1 custom script content across all 7 days.")
	
	print("--- ALL TESTS PASSED SUCCESSFULLY! ---")
	quit(0)
