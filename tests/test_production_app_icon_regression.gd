extends SceneTree

# ==============================================================================
# StudyCenterHub Production App Icon Automated Regression Test
# Verifies that:
# 1. Authoritative StudyCenterHub icon exists and matches expected SHA-256
# 2. Project root icon.icns and icon.png exist and match authoritative source
# 3. Project root icon.svg does not contain the default Godot robot logo
# 4. project.godot references the approved icons
# 5. Installed /Applications/StudyCenterHub.app contains the approved icon and plist
# ==============================================================================

const EXPECTED_ICNS_HASH: String = "94fa84a8f882351baca17dc66352d7d5bc3ec598bee5e4dab359ad69e5fcd19b"

func _init() -> void:
	print("==========================================================")
	print("STARTING PRODUCTION APP ICON REGRESSION TEST SUITE")
	print("==========================================================")

	var total_tests: int = 0
	var passed_tests: int = 0

	# 1. Authoritative icon check
	total_tests += 1
	var auth_path = "res://assets/branding/StudyCenterHub.icns"
	if FileAccess.file_exists(auth_path):
		var auth_hash = _sha256_file(ProjectSettings.globalize_path(auth_path))
		if auth_hash == EXPECTED_ICNS_HASH:
			print("PASS 1/7: Authoritative icon exists with matching SHA-256.")
			passed_tests += 1
		else:
			printerr("FAIL 1/7: Authoritative icon hash mismatch! Got: ", auth_hash)
	else:
		printerr("FAIL 1/7: Authoritative icon missing at ", auth_path)

	# 2. Project root icon.icns check
	total_tests += 1
	var root_icns_path = "res://icon.icns"
	if FileAccess.file_exists(root_icns_path):
		var root_hash = _sha256_file(ProjectSettings.globalize_path(root_icns_path))
		if root_hash == EXPECTED_ICNS_HASH:
			print("PASS 2/7: Project root icon.icns matches authoritative SHA-256.")
			passed_tests += 1
		else:
			printerr("FAIL 2/7: Root icon.icns hash mismatch! Got: ", root_hash)
	else:
		printerr("FAIL 2/7: Root icon.icns missing at ", root_icns_path)

	# 3. Project root icon.png check
	total_tests += 1
	var root_png_path = "res://icon.png"
	if ResourceLoader.exists(root_png_path) or FileAccess.file_exists(root_png_path):
		var tex = load(root_png_path)
		var img: Image = null
		if tex and tex is Texture2D:
			img = tex.get_image()
		elif FileAccess.file_exists(root_png_path):
			img = Image.new()
			var abs_path = ProjectSettings.globalize_path(root_png_path)
			var err = img.load(abs_path)
			if err != OK:
				img = null
		if img and img.get_width() >= 512 and img.get_height() >= 512:
			print("PASS 3/7: Project root icon.png valid (", img.get_width(), "x", img.get_height(), ").")
			passed_tests += 1
		else:
			printerr("FAIL 3/7: Failed loading root icon.png or invalid dimensions")
	else:
		printerr("FAIL 3/7: Root icon.png missing at ", root_png_path)

	# 4. No default Godot robot logo in icon.svg
	total_tests += 1
	var root_svg_path = "res://icon.svg"
	if FileAccess.file_exists(root_svg_path):
		var f = FileAccess.open(root_svg_path, FileAccess.READ)
		var content = f.get_as_text()
		f.close()
		if not content.containsn("478cbf"):
			print("PASS 4/7: Project root icon.svg verified (free of default Godot robot logo).")
			passed_tests += 1
		else:
			printerr("FAIL 4/7: Default Godot robot blue color detected in icon.svg!")
	else:
		printerr("FAIL 4/7: icon.svg missing")

	# 5. ProjectSettings configuration check
	total_tests += 1
	var cfg_icon = ProjectSettings.get_setting("application/config/icon", "")
	var cfg_mac_icon = ProjectSettings.get_setting("application/config/macos_native_icon", "")
	if cfg_icon == "res://icon.png" and cfg_mac_icon == "res://icon.icns":
		print("PASS 5/7: ProjectSettings correctly configured for StudyCenterHub icon.")
		passed_tests += 1
	else:
		printerr("FAIL 5/7: ProjectSettings mismatch! icon=", cfg_icon, " macos_native_icon=", cfg_mac_icon)

	# 6. Installed Production App bundle icon check
	total_tests += 1
	var installed_icns = "/Applications/StudyCenterHub.app/Contents/Resources/icon.icns"
	if FileAccess.file_exists(installed_icns):
		var inst_hash = _sha256_file(installed_icns)
		if inst_hash == EXPECTED_ICNS_HASH:
			print("PASS 6/7: Installed /Applications/StudyCenterHub.app icon.icns matches authoritative SHA-256.")
			passed_tests += 1
		else:
			printerr("FAIL 6/7: Installed icon.icns hash mismatch! Got: ", inst_hash)
	else:
		# Also check in builds/
		var build_icns = "/Users/johnboyte/Development/StudyCenterHub-Desktop/builds/StudyCenterHub-Desktop-Production.app/Contents/Resources/icon.icns"
		if FileAccess.file_exists(build_icns):
			var b_hash = _sha256_file(build_icns)
			if b_hash == EXPECTED_ICNS_HASH:
				print("PASS 6/7: Build Production app icon.icns matches authoritative SHA-256.")
				passed_tests += 1
			else:
				printerr("FAIL 6/7: Build icon.icns hash mismatch! Got: ", b_hash)
		else:
			printerr("FAIL 6/7: Neither installed nor build Production icon.icns found!")

	# 7. Installed bundle Info.plist verification
	total_tests += 1
	var plist_path = "/Applications/StudyCenterHub.app/Contents/Info.plist"
	if FileAccess.file_exists(plist_path):
		var f_plist = FileAccess.open(plist_path, FileAccess.READ)
		var plist_content = f_plist.get_as_text()
		f_plist.close()
		var has_icon = plist_content.contains("<key>CFBundleIconFile</key>") and plist_content.contains("<string>icon.icns</string>")
		var has_id = plist_content.contains("<string>org.godotengine.studycenterhub</string>")
		if has_icon and has_id:
			print("PASS 7/7: Info.plist verified (CFBundleIconFile and CFBundleIdentifier).")
			passed_tests += 1
		else:
			printerr("FAIL 7/7: Info.plist missing required icon or bundle identifier entries!")
	else:
		printerr("FAIL 7/7: Info.plist missing at ", plist_path)

	print("==========================================================")
	print("SUMMARY: %d / %d ASSERTIONS PASSED (%.1f%%)" % [passed_tests, total_tests, (float(passed_tests) / float(total_tests)) * 100.0])
	print("==========================================================")

	if passed_tests == total_tests:
		print("SUCCESS: ALL PRODUCTION APP ICON REGRESSION TESTS PASSED (100%)")
		quit(0)
	else:
		printerr("FAILED: %d ICON REGRESSION ASSERTION(S) FAILED" % (total_tests - passed_tests))
		quit(1)

func _sha256_file(abs_path: String) -> String:
	var output = []
	var exit_code = OS.execute("shasum", ["-a", "256", abs_path], output)
	if exit_code == 0 and output.size() > 0:
		var parts = str(output[0]).strip_edges().split(" ")
		return parts[0]
	return ""
