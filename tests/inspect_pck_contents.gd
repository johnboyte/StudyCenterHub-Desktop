extends SceneTree

func _init() -> void:
	print("==========================================================")
	print("INSPECTING CANDIDATE PCK FILE LIST & SCRIPTS")
	print("==========================================================")
	
	var pck_path = "/Users/johnboyte/Development/StudyCenterHub-Desktop/builds/StudyCenterHub-Desktop-Candidate.pck"
	var success = ProjectSettings.load_resource_pack(pck_path, true)
	print("Resource Pack Load Success: ", success)
	
	# Try reading res://app/scenes/directory_view.gd or directory_view.gdc
	if FileAccess.file_exists("res://app/scenes/directory_view.gd"):
		var f = FileAccess.open("res://app/scenes/directory_view.gd", FileAccess.READ)
		if f:
			var txt = f.get_as_text()
			print("res://app/scenes/directory_view.gd exists in PCK! Length: ", txt.length())
			if "Save Current as Original" in txt or "Save as Original" in txt:
				print("❌ FOUND OLD TEXT IN PCK: 'Save Current as Original' / 'Save as Original'")
			else:
				print("✅ CLEAN: 'Save Current as Original' is NOT in res://app/scenes/directory_view.gd inside PCK")
	else:
		print("res://app/scenes/directory_view.gd NOT FOUND as raw text in PCK")

	if FileAccess.file_exists("res://app/scenes/directory_view.gdc"):
		print("res://app/scenes/directory_view.gdc (compiled bytecode) EXISTS in PCK!")
		var f = FileAccess.open("res://app/scenes/directory_view.gdc", FileAccess.READ)
		if f:
			var buf = f.get_buffer(f.get_length())
			var ascii = buf.get_string_from_ascii()
			var utf8 = buf.get_string_from_utf8()
			if "Save Current as Original" in ascii or "Save as Original" in ascii or "Save Current as Original" in utf8 or "Save as Original" in utf8:
				print("❌ FOUND OLD TEXT IN BYTECODE (.gdc): 'Save Current as Original'")
			else:
				print("✅ CLEAN: 'Save Current as Original' NOT found in compiled bytecode (.gdc)")

	print("==========================================================")
	quit(0)
