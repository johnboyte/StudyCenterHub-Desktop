extends SceneTree

func _init():
	print("=== INSPECTING INSTALLED PRODUCTION PCK COMMUNICATIONS_SERVICE.GD ===")
	var pck_path = "/Applications/StudyCenterHub.app/Contents/Resources/StudyCenterHub-Desktop-Production.pck"
	var loaded = ProjectSettings.load_resource_pack(pck_path)
	print("PCK Load success: ", loaded)

	var com_file = FileAccess.open("res://src/domain/communications/communications_service.gd", FileAccess.READ)
	if com_file:
		var text = com_file.get_as_text()
		print("Found communications_service.gd in PCK (Length: ", text.length(), ")")
		var lines = text.split("\n")
		for i in range(lines.size()):
			var l = lines[i]
			if "checkin.reallife-studycenter.org" in l or "pkpass_url" in l or "upload_pass.php" in l:
				print("Line ", i + 1, ": ", l)
	else:
		print("ERROR reading res://src/domain/communications/communications_service.gd from PCK")

	quit()
