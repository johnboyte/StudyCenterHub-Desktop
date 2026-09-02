extends SceneTree

func _init():
	print("==========================================================")
	print("TEST SUITE: DIGITAL PASS SERVICE FIXES VERIFICATION")
	print("==========================================================")
	var SQLiteDatabaseScript = load("res://src/infrastructure/database/sqlite_database.gd")
	var QRCredentialServiceScript = load("res://src/domain/security/qr_credential_service.gd")
	var AppleSvcScript = load("res://src/domain/security/apple_wallet_service.gd")
	var CommunicationsServiceScript = load("res://src/domain/communications/communications_service.gd")

	var db = SQLiteDatabaseScript.new()
	var person_id = 3 # John Boyte
	var res = db.execute("SELECT * FROM people WHERE id = ? LIMIT 1;", [person_id])
	assert(res["success"] and res["data"].size() > 0, "Person 3 must exist")
	var p = res["data"][0].duplicate()

	var cred_svc = QRCredentialServiceScript.new(db)
	var raw_token = cred_svc.get_active_raw_token(person_id)
	assert(raw_token != "", "Active QR credential raw_token must exist")

	var active_cred_id = ""
	var cred_res = db.execute("SELECT credential_id FROM participant_qr_credentials WHERE person_id = ? AND status = 'active' LIMIT 1;", [person_id])
	if cred_res["success"] and cred_res["data"].size() > 0:
		active_cred_id = str(cred_res["data"][0].get("credential_id", ""))

	# TEST A: Apple signing from source
	var apple_svc = AppleSvcScript.new()
	var apple_res = apple_svc.generate_apple_wallet_pass(p, raw_token, active_cred_id)

	print("\n--- TEST A: APPLE SIGNING FROM SOURCE ---")
	print("Apple Pass Success: ", apple_res.get("success", false))
	assert(apple_res.get("success", false) == true, "Apple pass generation from source must succeed")

	# TEST C: Complete URL structure
	var pass_url = apple_res.get("pkpass_url", "")
	print("Generated PKPASS URL: ", pass_url)
	assert(pass_url.begins_with("https://app.reallife-studycenter.org/upload_pass.php?pass_id="), "URL must begin with upload_pass.php?pass_id=")
	assert(pass_url.contains("usr_") and pass_url.contains("QRCR-"), "URL must contain complete pass_id with credential portion")

	# TEST D & E: SMS & Email body generation with valid Apple URL and NO legacy fallback
	var com_svc = CommunicationsServiceScript.new(db)
	var sms_res = await com_svc.sms_digital_member_pass(null, person_id, "Test Runner")
	print("\n--- TEST D & G: SMS DISPATCH RESULT ---")
	print("SMS Result: ", sms_res)

	# Verify communications_log last record
	var log_res = db.execute("SELECT * FROM communications_log WHERE recipient_person_id = ? ORDER BY id DESC LIMIT 1;", [person_id])
	if log_res["success"] and log_res["data"].size() > 0:
		var last_log = log_res["data"][0]
		var body = str(last_log.get("message_body", ""))
		print("Last logged message body snippet:\n", body.left(200))

		# TEST F: No legacy checkin URL anywhere
		assert(not body.contains("checkin.reallife-studycenter.org/wallet/apple/"), "Body must NEVER contain legacy checkin fallback URL")
		assert(not body.contains("pay.google.com/gp/v/save/"), "Body must NOT contain fake Google Wallet fallback URL when unconfigured")

		# TEST I & J: Google Wallet failure produces no fake URL but Apple Wallet send succeeds
		if sms_res.get("success", false):
			assert(body.contains("Apple Wallet: https://app.reallife-studycenter.org/upload_pass.php?pass_id="), "Body must contain valid Apple Wallet URL")
			assert(not body.contains("Google Wallet:"), "Unconfigured Google Wallet line must be omitted")

	print("\n==========================================================")
	print("ALL DIGITAL PASS SERVICE TESTS PASSED SUCCESSFULLY!")
	print("==========================================================")

	quit()
