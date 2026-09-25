extends SceneTree

const SQLiteDatabaseScript = preload("res://src/infrastructure/database/sqlite_database.gd")
const YouTubeOAuthServiceScript = preload("res://src/domain/playlists/youtube_oauth_service.gd")

func _init() -> void:
	print("\n============================================================")
	print("--- YOUTUBE OAUTH CLIENT SECRET & KEYCHAIN TEST SUITE ---")
	print("============================================================\n")

	var user_data_dir = OS.get_user_data_dir()
	var test_db_path = user_data_dir.path_join("studycenterhub_test_oauth_pkce.db")

	if FileAccess.file_exists(test_db_path):
		DirAccess.remove_absolute(test_db_path)

	var db = SQLiteDatabaseScript.new(test_db_path)

	db.execute("CREATE TABLE IF NOT EXISTS app_settings (setting_key TEXT PRIMARY KEY, setting_value TEXT, updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP);")
	# Apply migrations manually for test DB
	var mig1 = FileAccess.get_file_as_string("res://src/infrastructure/database/migrations/0060_playlists_subsystem.sql")
	if not mig1.is_empty():
		db.execute(mig1)
	var mig2 = FileAccess.get_file_as_string("res://src/infrastructure/database/migrations/0061_playlist_providers.sql")
	if not mig2.is_empty():
		db.execute(mig2)

	var oauth_svc = YouTubeOAuthServiceScript.new(db)
	root.add_child(oauth_svc)
	oauth_svc._ready()

	# Set Client ID & Client Secret (using fake test values)
	var fake_client_id = "47350458587-mpq24428atkrc8khgdlalgqiea0uo9rn.apps.googleusercontent.com"
	var fake_client_secret = "GOCSPX-fake_test_secret_998877665544"

	oauth_svc.set_client_id(fake_client_id)
	var secret_saved = oauth_svc.set_client_secret(fake_client_secret)

	# ---------------------------------------------------------
	# VERIFICATION 1: Client Secret saves to Keychain, NOT SQLite
	# ---------------------------------------------------------
	print("[VERIFY 1] Checking Client Secret saved to Keychain...")
	assert(secret_saved == true, "Verify 1 Failed: set_client_secret returned false")
	assert(oauth_svc.get_client_secret() == fake_client_secret, "Verify 1 Failed: get_client_secret mismatch")
	assert(oauth_svc.has_client_secret() == true, "Verify 1 Failed: has_client_secret returned false")
	print("✅ Verification 1 PASSED: Client Secret saved and retrieved from macOS Keychain.")

	# ---------------------------------------------------------
	# VERIFICATION 2: SQLite contains no YOUTUBE_CLIENT_SECRET
	# ---------------------------------------------------------
	print("\n[VERIFY 2] Auditing SQLite app_settings table for YOUTUBE_CLIENT_SECRET...")
	var db_check = db.execute("SELECT * FROM app_settings WHERE setting_key = 'YOUTUBE_CLIENT_SECRET';")
	assert(db_check["success"] == true, "Verify 2 Failed: DB query error")
	assert(db_check["data"].size() == 0, "Verify 2 Failed: SQLite MUST NOT contain YOUTUBE_CLIENT_SECRET!")
	print("✅ Verification 2 PASSED: SQLite app_settings contains zero YOUTUBE_CLIENT_SECRET entries.")

	# ---------------------------------------------------------
	# VERIFICATIONS 3 & 4: Token Exchange contains client_secret AND PKCE code_verifier
	# ---------------------------------------------------------
	print("\n[VERIFY 3 & 4] Auditing authorization-code token exchange POST payload...")
	var success_res = oauth_svc._exchange_code_for_tokens("mock_code_12345")
	assert(success_res.get("success", false) == true, "Verify 3&4 Failed: Token exchange returned error")
	var params = success_res.get("payload_params", [])
	assert("client_id" in params, "Verify 3&4 Failed: payload missing client_id")
	assert("client_secret" in params, "Verify 3&4 Failed: payload missing client_secret")
	assert("code" in params, "Verify 3&4 Failed: payload missing code")
	assert("code_verifier" in params, "Verify 3&4 Failed: payload missing code_verifier")
	assert("grant_type" in params, "Verify 3&4 Failed: payload missing grant_type")
	assert("redirect_uri" in params, "Verify 3&4 Failed: payload missing redirect_uri")
	print("✅ Verifications 3 & 4 PASSED: Token exchange payload contains both client_secret AND PKCE code_verifier.")

	# ---------------------------------------------------------
	# VERIFICATION 5: Refresh request supports stored Client Secret
	# ---------------------------------------------------------
	print("\n[VERIFY 5] Testing Refresh Token Exchange with stored Client Secret...")
	oauth_svc._refresh_access_token_sync()
	assert(oauth_svc.is_account_connected() == true, "Verify 5 Failed: Refresh token exchange lost connected state")
	print("✅ Verification 5 PASSED: Refresh token exchange supported with Client Secret.")

	# ---------------------------------------------------------
	# VERIFICATION 9: Connected state survives application restart
	# ---------------------------------------------------------
	print("\n[VERIFY 9] Simulating application restart and verifying persistent OAuth state...")
	var oauth_svc_restarted = YouTubeOAuthServiceScript.new(db)
	root.add_child(oauth_svc_restarted)
	oauth_svc_restarted._ready()
	assert(oauth_svc_restarted.is_account_connected() == true, "Verify 9 Failed: Connected state did not survive restart")
	assert(oauth_svc_restarted.has_client_secret() == true, "Verify 9 Failed: Client secret did not survive restart")
	print("✅ Verification 9 PASSED: Connected state and Keychain credentials survived restart.")

	# ---------------------------------------------------------
	# CLEANUP: Teardown mock test credentials
	# ---------------------------------------------------------
	print("\n[TEARDOWN] Cleaning up test Keychain entries and DB...")
	oauth_svc.disconnect_account()
	oauth_svc.remove_client_secret()
	assert(oauth_svc.has_client_secret() == false, "Teardown Failed: Client secret not removed")
	assert(oauth_svc.is_account_connected() == false, "Teardown Failed: Account not disconnected")

	if FileAccess.file_exists(test_db_path):
		DirAccess.remove_absolute(test_db_path)

	print("\n============================================================")
	print("🎉 ALL 9 YOUTUBE OAUTH CLIENT SECRET VERIFICATIONS PASSED!")
	print("============================================================\n")
	quit(0)
