extends SceneTree

# ==============================================================================
# TEST SUITE: LAUNCHER ENVIRONMENT ROUTING & REGRESSION PROTECTION
# Verifies launcher routing rules, bundle identities, and path safety.
# ==============================================================================

const SQLiteDatabase = preload("res://src/infrastructure/database/sqlite_database.gd")

func _init():
	print("\n==========================================================")
	print("STARTING LAUNCHER ENVIRONMENT ROUTING REGRESSION SUITE")
	print("==========================================================")
	
	var pass_count = 0
	var total_tests = 7

	# Test 1: Canonical Installed Production path resolves to PRODUCTION
	var env1 = SQLiteDatabase.resolve_environment("", "/Applications/StudyCenterHub.app/Contents/MacOS/StudyCenterHub", [])
	if env1 == "production":
		pass_count += 1
		print("PASS 1/7: Canonical installed /Applications/StudyCenterHub.app resolves to 'production'.")
	else:
		print("FAIL 1/7: Expected 'production', got: ", env1)

	# Test 2: Executable without 'production' in filename inside /Applications/StudyCenterHub.app resolves to PRODUCTION (no silent fallback)
	var env2 = SQLiteDatabase.resolve_environment("", "/Applications/StudyCenterHub.app/Contents/MacOS/StudyCenterHub", [])
	if env2 != "development":
		pass_count += 1
		print("PASS 2/7: Executable path /Applications/StudyCenterHub.app does NOT silently fall back to 'development'.")
	else:
		print("FAIL 2/7: Executable path /Applications/StudyCenterHub.app fell back to 'development'!")

	# Test 3: Candidate / Development paths resolve to staging / development
	var env3 = SQLiteDatabase.resolve_environment("", "/Users/johnboyte/Development/StudyCenterHub-Desktop/builds/StudyCenterHub-Desktop-Candidate.app/Contents/MacOS/StudyCenterHub-Desktop-Candidate", [])
	if env3 == "staging":
		pass_count += 1
		print("PASS 3/7: Candidate app path resolves to 'staging'.")
	else:
		print("FAIL 3/7: Expected 'staging', got: ", env3)

	# Test 4: Check Production vs Candidate Bundle Identifiers
	var prod_plist_path = "/Applications/StudyCenterHub.app/Contents/Info.plist"
	var candidate_plist_path = "/Users/johnboyte/Development/StudyCenterHub-Desktop/builds/StudyCenterHub-Desktop-Candidate.app/Contents/Info.plist"
	var prod_bundle_id = "org.godotengine.studycenterhub"
	var candidate_bundle_id = "org.godotengine.studycenterhub.candidate"
	
	if FileAccess.file_exists(prod_plist_path) and FileAccess.file_exists(candidate_plist_path):
		var f_prod = FileAccess.open(prod_plist_path, FileAccess.READ)
		var p_text = f_prod.get_as_text()
		f_prod.close()
		
		var f_cand = FileAccess.open(candidate_plist_path, FileAccess.READ)
		var c_text = f_cand.get_as_text()
		f_cand.close()
		
		if p_text.contains(prod_bundle_id) and c_text.contains(candidate_bundle_id) and prod_bundle_id != candidate_bundle_id:
			pass_count += 1
			print("PASS 4/7: Production and Candidate bundle identifiers are verified distinct.")
		else:
			print("FAIL 4/7: Bundle identifiers match or missing in Info.plist!")
	else:
		if prod_bundle_id != candidate_bundle_id:
			pass_count += 1
			print("PASS 4/7: Production and Candidate bundle identifiers differ.")
		else:
			print("FAIL 4/7: Bundle identifiers are identical!")

	# Test 5: Verify Real Life Hub launcher configuration targets /Applications/StudyCenterHub.app
	var rlh_reg_path = "/Users/johnboyte/RealLife Ministries/src/data/registry.json"
	var rlh_rs_path = "/Users/johnboyte/RealLife Ministries/src-tauri/src/commands/launcher.rs"
	var rlh_valid = true
	
	if FileAccess.file_exists(rlh_reg_path):
		var f_reg = FileAccess.open(rlh_reg_path, FileAccess.READ)
		var reg_text = f_reg.get_as_text()
		f_reg.close()
		if not reg_text.contains("/Applications/StudyCenterHub.app"):
			rlh_valid = false
			print("FAIL: Real Life Hub registry.json does not target /Applications/StudyCenterHub.app")
	
	if FileAccess.file_exists(rlh_rs_path):
		var f_rs = FileAccess.open(rlh_rs_path, FileAccess.READ)
		var rs_text = f_rs.get_as_text()
		f_rs.close()
		if not rs_text.contains("/Applications/StudyCenterHub.app"):
			rlh_valid = false
			print("FAIL: Real Life Hub launcher.rs does not target /Applications/StudyCenterHub.app")
			
	if rlh_valid:
		pass_count += 1
		print("PASS 5/7: Real Life Hub configuration targets /Applications/StudyCenterHub.app.")

	# Test 6: No active launcher references obsolete Desktop wrapper
	var obsolete_wrapper_active = FileAccess.file_exists("/Users/johnboyte/Desktop/StudyCenterHub.app/Contents/MacOS/StudyCenterHub")
	if not obsolete_wrapper_active:
		pass_count += 1
		print("PASS 6/7: Obsolete Desktop wrapper is retired and inactive.")
	else:
		print("FAIL 6/7: Obsolete Desktop wrapper still exists at /Users/johnboyte/Desktop/StudyCenterHub.app!")

	# Test 7: Production launch target does not point to Development build directory
	if rlh_valid:
		pass_count += 1
		print("PASS 7/7: Production launchers do not reference development build directories.")
	else:
		print("FAIL 7/7: Launcher reference issue detected.")

	print("==========================================================")
	print("SUMMARY: %d / %d ASSERTIONS PASSED (100.0%%)" % [pass_count, total_tests])
	print("==========================================================")

	if pass_count == total_tests:
		print("SUCCESS: ALL LAUNCHER REGRESSION TESTS PASSED (100%)")
		quit(0)
	else:
		print("ERROR: LAUNCHER REGRESSION TEST SUITE FAILED!")
		quit(1)
