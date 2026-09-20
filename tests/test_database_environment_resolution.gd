extends SceneTree

# ==============================================================================
# TEST SUITE: DATABASE ENVIRONMENT RESOLUTION
# Verifies that StudyCenterHub environment resolution correctly targets production,
# staging, or development databases based on environment variables or runtime paths.
# ==============================================================================

const SQLiteDatabase = preload("res://src/infrastructure/database/sqlite_database.gd")

func _init():
	print("\n==========================================================")
	print("STARTING DATABASE ENVIRONMENT RESOLUTION TEST SUITE")
	print("==========================================================")
	
	var pass_count = 0
	var total_tests = 8

	# Test 1: Explicit STUDYCENTERHUB_ENV = production
	var env1 = SQLiteDatabase.resolve_environment("production", "/Users/johnboyte/Downloads/Godot.app/Contents/MacOS/Godot", [])
	if env1 == "production":
		pass_count += 1
		print("PASS 1/7: Explicit STUDYCENTERHUB_ENV=production resolves to 'production'.")
	else:
		print("FAIL 1/7: Expected 'production', got: ", env1)

	# Test 2: Explicit STUDYCENTERHUB_ENV = staging
	var env2 = SQLiteDatabase.resolve_environment("staging", "/Users/johnboyte/Downloads/Godot.app/Contents/MacOS/Godot", [])
	if env2 == "staging":
		pass_count += 1
		print("PASS 2/7: Explicit STUDYCENTERHUB_ENV=staging resolves to 'staging'.")
	else:
		print("FAIL 2/7: Expected 'staging', got: ", env2)

	# Test 3: Explicit STUDYCENTERHUB_ENV = development
	var env3 = SQLiteDatabase.resolve_environment("development", "/Users/johnboyte/Downloads/Godot.app/Contents/MacOS/Godot", [])
	if env3 == "development":
		pass_count += 1
		print("PASS 3/7: Explicit STUDYCENTERHUB_ENV=development resolves to 'development'.")
	else:
		print("FAIL 3/7: Expected 'development', got: ", env3)

	# Test 4: Unset env with Production .pck cmdline arg (--main-pack .../StudyCenterHub-Desktop-Production.app/Contents/Resources/StudyCenterHub-Desktop-Production.pck)
	var env4 = SQLiteDatabase.resolve_environment("", "/Users/johnboyte/Downloads/Godot.app/Contents/MacOS/Godot", ["--main-pack", "/Users/johnboyte/Development/StudyCenterHub-Desktop/builds/StudyCenterHub-Desktop-Production.app/Contents/Resources/StudyCenterHub-Desktop-Production.pck"])
	if env4 == "production":
		pass_count += 1
		print("PASS 4/7: Production .pck cmdline arg resolves to 'production' when STUDYCENTERHUB_ENV is empty.")
	else:
		print("FAIL 4/7: Expected 'production', got: ", env4)

	# Test 5: Unset env with Production app executable path (.../builds/StudyCenterHub-Desktop-Production.app/Contents/MacOS/StudyCenterHub-Desktop-Production)
	var env5 = SQLiteDatabase.resolve_environment("", "/Users/johnboyte/Development/StudyCenterHub-Desktop/builds/StudyCenterHub-Desktop-Production.app/Contents/MacOS/StudyCenterHub-Desktop-Production", [])
	if env5 == "production":
		pass_count += 1
		print("PASS 5/7: Production .app executable path resolves to 'production' when STUDYCENTERHUB_ENV is empty.")
	else:
		print("FAIL 5/7: Expected 'production', got: ", env5)

	# Test 6: Unset env with RC1/Staging app path (.../builds/StudyCenterHub-Desktop-RC1.app)
	var env6 = SQLiteDatabase.resolve_environment("", "/Users/johnboyte/Development/StudyCenterHub-Desktop/builds/StudyCenterHub-Desktop-RC1.app/Contents/MacOS/StudyCenterHub-Desktop-RC1", [])
	if env6 == "staging":
		pass_count += 1
		print("PASS 6/7: RC1/Staging app executable path resolves to 'staging' when STUDYCENTERHUB_ENV is empty.")
	else:
		print("FAIL 6/7: Expected 'staging', got: ", env6)

	# Test 7: Unset env with standard source launch (Godot --path ...)
	var env7 = SQLiteDatabase.resolve_environment("", "/Users/johnboyte/Downloads/Godot.app/Contents/MacOS/Godot", ["--path", "/Users/johnboyte/Development/StudyCenterHub-Desktop/study-center-hub---desktop"])
	if env7 == "development":
		pass_count += 1
		print("PASS 7/8: Standard source launch defaults to 'development' when STUDYCENTERHUB_ENV is empty.")
	else:
		print("FAIL 7/8: Expected 'development', got: ", env7)

	# Test 8: Unset env with Canonical Installed Production path (/Applications/StudyCenterHub.app/Contents/MacOS/StudyCenterHub)
	var env8 = SQLiteDatabase.resolve_environment("", "/Applications/StudyCenterHub.app/Contents/MacOS/StudyCenterHub", [])
	if env8 == "production":
		pass_count += 1
		print("PASS 8/8: Canonical installed /Applications/StudyCenterHub.app resolves to 'production' intrinsically.")
	else:
		print("FAIL 8/8: Expected 'production', got: ", env8)

	print("==========================================================")
	print("SUMMARY: %d / %d ASSERTIONS PASSED (100.0%%)" % [pass_count, 8])
	print("==========================================================")

	if pass_count == 8:
		print("SUCCESS: ALL DATABASE ENVIRONMENT RESOLUTION TESTS PASSED (100%)")
		quit(0)
	else:
		print("ERROR: DATABASE ENVIRONMENT RESOLUTION TEST SUITE FAILED!")
		quit(1)
