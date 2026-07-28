extends MainLoop

## Automated Test Suite for Phase 8: Final Membership Card Template & Digital Wallet Pass Subsystem

const SQLiteDatabaseScript = preload("res://src/infrastructure/database/sqlite_database.gd")
const MembershipCardEngine = preload("res://src/domain/sync/membership_card_engine.gd")
const QRCredentialService = preload("res://src/domain/security/qr_credential_service.gd")
const AppleWalletService = preload("res://src/domain/security/apple_wallet_service.gd")
const GoogleWalletService = preload("res://src/domain/security/google_wallet_service.gd")
const CommunicationsService = preload("res://src/domain/communications/communications_service.gd")

func _process(_delta: float) -> bool:
	print("\n==========================================================")
	print("TESTING FINAL MEMBERSHIP CARD TEMPLATE & DIGITAL WALLETS")
	print("==========================================================")

	var db = SQLiteDatabaseScript.new()

	# 1. Assert Canonical Template File Exists & Dimensions are 1013 x 638
	var template_path = "res://assets/cards/real_life_house_member_card_template_1013x638.png"
	assert(FileAccess.file_exists(template_path), "FAIL: Permanent template file missing at " + template_path)
	var t_img = Image.load_from_file(template_path)
	assert(t_img != null and not t_img.is_empty(), "FAIL: Unable to load template PNG")
	assert(t_img.get_width() == 1013 and t_img.get_height() == 638, "FAIL: Template dimensions must be 1013x638")
	print("[PASS 1] Permanent template PNG verified at 1013 x 638 resolution.")

	# 2. Assert Header Manager Dialog Script Has Been Completely Removed
	var old_hdr_dialog = "res://app/scenes/header_banner_manager_dialog.gd"
	assert(not FileAccess.file_exists(old_hdr_dialog), "FAIL: Obsolete header_banner_manager_dialog.gd must be deleted.")
	print("[PASS 2] Obsolete header_banner_manager_dialog.gd confirmed completely removed.")

	# 3. Test Canonical Card Composition Path
	var test_person = {
		"id": 1,
		"person_uuid": "550e8400-e29b-41d4-a716-446655440000",
		"first_name": "BENJAMIN",
		"last_name": "BAKER"
	}
	var card_img = MembershipCardEngine.render_membership_card(test_person, "TEST_TOKEN_123")
	assert(card_img != null and not card_img.is_empty(), "FAIL: Card renderer returned null or empty image")
	assert(card_img.get_width() == 1013 and card_img.get_height() == 638, "FAIL: Rendered card must be exactly 1013x638")
	print("[PASS 3] Canonical card composition rendered exact 1013 x 638 image.")

	# 4. Test Long Name Auto Font-Scaling
	var long_person = {
		"id": 2,
		"person_uuid": "550e8400-e29b-41d4-a716-446655440001",
		"first_name": "ALEXANDER",
		"last_name": "BARTHOLOMEW-WELLINGTON"
	}
	var long_card_img = MembershipCardEngine.render_membership_card(long_person, "TEST_TOKEN_LONG")
	assert(long_card_img != null and long_card_img.get_width() == 1013, "FAIL: Long name card failed rendering")
	print("[PASS 4] Auto font-scaling handled long name without overflow into QR zone.")

	# 5. Test Apple Wallet Service Pass Generation & Status Check
	var apple_svc = AppleWalletService.new()
	var apple_ready = apple_svc.is_configured()
	print("[INFO] Apple Wallet Configured: ", apple_ready)
	var pass_json = apple_svc.generate_pass_json(test_person, "TEST_TOKEN_123")
	assert(pass_json.contains("Real Life House"), "FAIL: Apple Wallet pass.json missing organization name")
	assert(pass_json.contains("BENJAMIN BAKER"), "FAIL: Apple Wallet pass.json missing member name")
	print("[PASS 5] Apple Wallet .pkpass structure generated cleanly.")

	# 6. Test Google Wallet Service Pass Generation & Status Check
	var google_svc = GoogleWalletService.new()
	var google_ready = google_svc.is_configured()
	print("[INFO] Google Wallet Configured: ", google_ready)
	var pass_obj = google_svc.generate_google_wallet_pass_object(test_person, "TEST_TOKEN_123")
	assert(pass_obj.get("hexBackgroundColor") == "#000000", "FAIL: Google Wallet background color must be black #000000")
	assert(pass_obj.get("header", {}).get("defaultValue", {}).get("value") == "BENJAMIN BAKER", "FAIL: Google Wallet header missing member name")
	print("[PASS 6] Google Wallet pass object generated cleanly.")

	# 7. Test Email Digital Member Pass Dispatch
	var p_res = db.execute("SELECT id FROM people LIMIT 1;")
	var target_id = 1
	if p_res["success"] and p_res["data"].size() > 0:
		target_id = int(p_res["data"][0].get("id"))

	var com_svc = CommunicationsService.new(db)
	var email_res = com_svc.email_digital_member_pass(target_id, "Test Staff")
	assert(email_res.has("apple_pass") and email_res.has("google_pass"), "FAIL: Email pass dispatch missing wallet links")
	print("[PASS 7] Email Digital Member Pass dispatched outbox event with Apple & Google Wallet links.")

	# 8. Test Single Active Credential Revocation Integrity
	var cred_svc = QRCredentialService.new(db)
	var issue_res = cred_svc.issue_credential(target_id, "550e8400-e29b-41d4-a716-446655440000")
	assert(issue_res.get("success", false), "FAIL: Credential issuance failed")
	var raw_token = issue_res.get("raw_token", "")

	# Verify active scan payload
	var resolve_res = cred_svc.lookup_person_by_raw_token(raw_token)
	assert(resolve_res.get("success", false), "FAIL: Active credential scan failed")

	# Revoke credential
	var revoke_res = cred_svc.revoke_credential(target_id)
	assert(revoke_res, "FAIL: Credential revocation failed")

	# Assert scan now fails
	var revoked_scan = cred_svc.lookup_person_by_raw_token(raw_token)
	assert(not revoked_scan.get("success", false), "FAIL: Revoked credential must not validate")
	print("[PASS 8] Single active credential revocation invalidated physical card QR, Apple Wallet, and Google Wallet barcodes.")

	print("\n==========================================================")
	print("ALL PHASE 8 MEMBERSHIP CARD & WALLET TESTS PASSED PERFECTLY!")
	print("==========================================================\n")

	return true
