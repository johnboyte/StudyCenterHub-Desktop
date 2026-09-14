extends SceneTree

func _init() -> void:
	print("--- INSPECTING ALL FILES IN INSTALLED PRODUCTION PCK ---")
	
	# Open directory inside PCK when loaded via main-pack
	var target_scripts = [
		"res://app/scenes/administration_view.gd",
		"res://app/scenes/administration_view.gdc",
		"res://app/scenes/app_shell.gd",
		"res://app/scenes/app_shell.gdc",
		"res://app/scenes/home_view.gd",
		"res://app/scenes/home_view.gdc",
		"res://src/domain/communications/communications_service.gd",
		"res://src/domain/communications/communications_service.gdc",
		"res://src/domain/sync/gateway_sync_service.gd",
		"res://src/domain/sync/gateway_sync_service.gdc"
	]
	
	for s_path in target_scripts:
		var exists = FileAccess.file_exists(s_path)
		print(s_path, " -> EXISTS: ", exists)
		if exists and s_path.ends_with(".gd"):
			var content = FileAccess.get_file_as_string(s_path)
			print("  [Content len]: ", content.length(), " bytes")
			if s_path.contains("administration_view"):
				print("  [Contains selected_ivr_day]: ", content.contains("selected_ivr_day"))
				print("  [Contains _create_selectable_label]: ", content.contains("_create_selectable_label"))
	
	quit(0)
