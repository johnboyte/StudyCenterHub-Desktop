extends SceneTree

## Automated test for Preview Dialog UI layout and Call My Phone button

const AdministrationViewScript = preload("res://app/scenes/administration_view.gd")
const SQLiteDatabaseScript = preload("res://src/infrastructure/database/sqlite_database.gd")

func _init() -> void:
	print("\n============================================================")
	print("  TESTING PREVIEW CALL DIALOG UI & BUTTON LAYOUT")
	print("============================================================\n")
	call_deferred("run_test")

func run_test() -> void:
	var test_db_path = ProjectSettings.globalize_path("user://test_preview_dialog_ui.db")
	if FileAccess.file_exists(test_db_path):
		DirAccess.remove_absolute(test_db_path)

	var db = SQLiteDatabaseScript.new(test_db_path)
	db.execute("CREATE TABLE IF NOT EXISTS app_settings (setting_key TEXT PRIMARY KEY, setting_value TEXT);")
	db.execute("INSERT INTO app_settings (setting_key, setting_value) VALUES ('PHONE_LAST_PREVIEW_DESTINATION', '+18649344080');")

	var admin_view = AdministrationViewScript.new()
	admin_view.db = db
	root.add_child(admin_view)

	# Call target phone prefill test
	var target_ph = admin_view._get_preview_target_phone("")
	assert(target_ph == "+18649344080", "Prefill phone failed! Expected +18649344080, got: " + target_ph)
	print("✓ PASS 1: Remembered phone prefilled correctly: ", target_ph)

	# Trigger preview call dialog
	admin_view._show_preview_call_dialog("Polly.Matthew-Generative", "Matthew Generative", "Testing main greeting script", target_ph)

	# Find modal_bg in children
	var modal_bg: ColorRect = null
	for child in admin_view.get_children():
		if child is ColorRect:
			modal_bg = child
			break

	assert(modal_bg != null, "Preview ColorRect modal overlay not found!")
	
	var call_btn: Button = null
	var cancel_btn: Button = null
	var queue = [modal_bg]
	while queue.size() > 0:
		var current = queue.pop_front()
		if current is Button:
			if current.text == "📞 Call My Phone":
				call_btn = current
			elif current.text == "Cancel":
				cancel_btn = current
		for child in current.get_children():
			queue.append(child)

	assert(call_btn != null, "Primary action button '📞 Call My Phone' missing!")
	assert(cancel_btn != null, "Cancel button missing!")
	print("✓ PASS 2: Custom modal overlay created with visible buttons: '", call_btn.text, "' and '", cancel_btn.text, "'")

	print("\n============================================================")
	print("  SUCCESS: PREVIEW DIALOG UI TEST PASSED 100%")
	print("============================================================\n")
	quit(0)
