extends SceneTree

func _init():
	print("==========================================================")
	print("EXPORTED CANDIDATE PCK REGRESSION & VERIFICATION TEST")
	print("==========================================================")
	var SQLiteDatabaseScript = load("res://src/infrastructure/database/sqlite_database.gd")
	var QRCredentialServiceScript = load("res://src/domain/security/qr_credential_service.gd")
	var AppleSvcScript = load("res://src/domain/security/apple_wallet_service.gd")
	var CommunicationsServiceScript = load("res://src/domain/communications/communications_service.gd")
	var SelectableLabelHelperScript = load("res://src/ui/components/selectable_label_helper.gd")

	var db = SQLiteDatabaseScript.new()
	var com_svc = CommunicationsServiceScript.new(db)

	# --- 1. SELECTABLE LABEL HELPER REGRESSION ---
	print("\n--- 1. SELECTABLE LABEL HELPER ---")
	var helper = SelectableLabelHelperScript.new()
	var line = helper.create_selectable_line("John Boyte - (864) 712-4446 - usr_45c22c7d10c2b85e")
	assert(line is LineEdit and line.editable == false, "Line control must be read-only LineEdit")
	var text = helper.create_selectable_text("Description / Note text")
	assert(text is TextEdit and text.editable == false, "Text control must be read-only TextEdit")
	print("✓ Selectable label helper verified.")

	# --- 2. TODAY AT THE HOUSE DATE OPENING REGRESSION ---
	print("\n--- 2. TODAY AT THE HOUSE DATE OPENING ---")
	var wed_script = com_svc.get_active_script_for_day("Wednesday")
	print("Rendered Wednesday Active Script:\n", wed_script.left(100))
	assert(wed_script.begins_with("Today is Wednesday,"), "Active script must start with dynamic weekday date opening")

	var days = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
	for d in days:
		var raw_rec = com_svc.get_daily_script_record(d)
		if int(raw_rec.get("is_custom", 0)) == 1:
			com_svc.save_daily_script_template(d, str(raw_rec.get("custom_script", "")), true)

	var rec = com_svc.get_daily_script_record("Wednesday")
	var stored = str(rec.get("custom_script", ""))
	print("Stored Wednesday Template:\n", stored.left(100))
	assert(stored.contains("{date_full}") or stored.contains("{weekday}"), "Stored template MUST retain dynamic tokens")
	print("✓ Dynamic date opening & token storage verified.")

	# --- 3. APPLE WALLET PASS GENERATION REGRESSION ---
	print("\n--- 3. APPLE WALLET PASS GENERATION ---")
	var person_id = 3 # John Boyte
	var p_res = db.execute("SELECT * FROM people WHERE id = ? LIMIT 1;", [person_id])
	assert(p_res["success"] and p_res["data"].size() > 0, "Person 3 must exist")
	var p = p_res["data"][0].duplicate()

	var cred_svc = QRCredentialServiceScript.new(db)
	var raw_token = cred_svc.get_active_raw_token(person_id)

	var active_cred_id = ""
	var cred_res = db.execute("SELECT credential_id FROM participant_qr_credentials WHERE person_id = ? AND status = 'active' LIMIT 1;", [person_id])
	if cred_res["success"] and cred_res["data"].size() > 0:
		active_cred_id = str(cred_res["data"][0].get("credential_id", ""))

	var apple_svc = AppleSvcScript.new()
	var apple_res = apple_svc.generate_apple_wallet_pass(p, raw_token, active_cred_id)
	print("Apple Pass Generation Result: ", apple_res)
	assert(apple_res.get("success", false) == true, "Apple pass generation from candidate must succeed")

	var pkpass_url = str(apple_res.get("pkpass_url", ""))
	print("Generated PKPASS URL: ", pkpass_url)
	assert(pkpass_url.begins_with("https://app.reallife-studycenter.org/upload_pass.php?pass_id="), "URL must begin with app.reallife-studycenter.org/upload_pass.php?pass_id=")
	assert(pkpass_url.contains("usr_") and pkpass_url.contains("QRCR-"), "URL must contain complete pass_id with credential portion")
	assert(not pkpass_url.contains("checkin.reallife-studycenter.org"), "URL must NOT contain legacy checkin hostname")

	var extracted_script = ProjectSettings.globalize_path("user://wallet/sign_pkpass.py")
	print("Extracted sign_pkpass.py path: ", extracted_script)
	assert(FileAccess.file_exists(extracted_script), "Extracted sign_pkpass.py MUST exist in user://wallet/")
	print("✓ Apple Wallet pass generation & runtime extraction verified.")

	# --- 4. PRESS 3-3 CUSTOM WORDING REGRESSION ---
	print("\n--- 4. PRESS 3-3 CUSTOM WORDING REGRESSION ---")
	var p33_res = db.execute("SELECT script_text FROM ivr_menu_nodes WHERE id = 11 LIMIT 1;")
	if p33_res["success"] and p33_res["data"].size() > 0:
		var p33_text = str(p33_res["data"][0].get("script_text", ""))
		print("Press 3-3 Script Text:\n", p33_text)
		assert(p33_text.contains("As our staff, interns, and volunteers grow, so will our house hours!"), "Press 3-3 custom wording MUST be preserved 100%")
	print("✓ Press 3-3 custom wording verified.")

	print("\n==========================================================")
	print("CANDIDATE PCK FULL REGRESSION SUITE PASSED 100%!")
	print("==========================================================")

	quit()
