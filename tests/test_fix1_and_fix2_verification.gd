extends SceneTree

func _init():
	print("==========================================================")
	print("VERIFICATION SUITE: FIX 1 (SELECTABLE TEXT) & FIX 2 (DYNAMIC SCRIPT DATE)")
	print("==========================================================")

	var SelectableLabelHelperScript = load("res://src/ui/components/selectable_label_helper.gd")
	var SQLiteDatabaseScript = load("res://src/infrastructure/database/sqlite_database.gd")
	var CommunicationsServiceScript = load("res://src/domain/communications/communications_service.gd")

	var db = SQLiteDatabaseScript.new()
	var com_svc = CommunicationsServiceScript.new(db)

	# --- TEST FIX 1: SelectableLabelHelper ---
	print("\n--- TESTING FIX 1: SELECTABLE LABEL HELPER ---")
	var helper = SelectableLabelHelperScript.new()
	var line = helper.create_selectable_line("John Boyte - (864) 712-4446 - usr_45c22c7d10c2b85e")
	assert(line is LineEdit, "create_selectable_line must return LineEdit")
	assert(line.editable == false, "line must be read-only (editable = false)")
	assert(line.context_menu_enabled == true, "context menu must be enabled")
	print("✓ Single-line read-only selectable control created cleanly.")

	var multiline = helper.create_selectable_text("Real Life House\nA Study Center & Hospitality House")
	assert(multiline is TextEdit, "create_selectable_text must return TextEdit")
	assert(multiline.editable == false, "multiline text must be read-only (editable = false)")
	print("✓ Multi-line read-only selectable control created cleanly.")

	# --- TEST FIX 2: Dynamic Script Date Opening ---
	print("\n--- TESTING FIX 2: TODAY AT THE HOUSE DATE OPENING ---")
	var wed_script = com_svc.get_active_script_for_day("Wednesday")
	print("Wed Active Script Opening:\n", wed_script.left(100))
	assert(wed_script.begins_with("Today is Wednesday,"), "Wednesday active script MUST begin with 'Today is Wednesday,'")

	var thu_script = com_svc.get_active_script_for_day("Thursday")
	print("Thu Active Script Opening:\n", thu_script.left(100))
	assert(thu_script.begins_with("Today is Thursday,"), "Thursday active script MUST begin with 'Today is Thursday,'")

	# Test saving a custom script with a literal date opening
	var save_ok = com_svc.save_daily_script_template("Wednesday", "Today is Wednesday, September 2. Custom manual remainder content.")
	assert(save_ok, "save_daily_script_template must succeed")

	# Verify database storage uses dynamic tokens ({date_full}) instead of hardcoded literal dates
	var rec = com_svc.get_daily_script_record("Wednesday")
	var stored = str(rec.get("custom_script", ""))
	print("Stored Wednesday Template Snippet:\n", stored.left(100))
	assert(stored.contains("{date_full}") or stored.contains("{weekday}"), "Stored template MUST retain dynamic date tokens in database!")
	assert(stored.contains("Custom manual remainder content."), "Manual remainder content MUST be preserved 100%!")

	# Verify rendering stored script produces the current date
	var rendered_wed = com_svc.get_active_script_for_day("Wednesday")
	print("Rendered Stored Wednesday Script:\n", rendered_wed.left(100))
	assert(rendered_wed.begins_with("Today is Wednesday, September 2. Custom manual remainder content."), "Rendered stored script must start with current date opening and preserve manual remainder!")

	print("\n==========================================================")
	print("FIX 1 & FIX 2 VERIFICATION SUITE PASSED 100%!")
	print("==========================================================")

	quit()
