extends SceneTree

## Automated Regression Test: Remote Functions Static QR Asset & Poster Decoding Verification
## Verifies that the static PNG asset AND the final rendered poster QR code programmatically decode to EXACTLY:
## https://app.reallife-studycenter.org/public

const MembershipCardEngineScript = preload("res://src/domain/sync/membership_card_engine.gd")

func _init() -> void:
	print("==========================================================")
	print("RUNNING AUTOMATED TEST: REMOTE POSTER STATIC QR VERIFICATION")
	print("==========================================================")

	# 1. Verify Static PNG Asset directly
	var static_asset_path = ProjectSettings.globalize_path(MembershipCardEngineScript.REMOTE_SIGN_CONFIG["static_qr_path"])
	print("🔍 Testing Static PNG Asset Path:", static_asset_path)
	assert(FileAccess.file_exists(static_asset_path), "Static QR PNG asset file must exist on disk")

	var py_code_asset = "import cv2; detector = cv2.QRCodeDetector(); val, pts, qr = detector.detectAndDecode(cv2.imread('" + static_asset_path + "')); print('STATIC_DECODED_URL:' + str(val))"
	var out_asset = []
	var exit_code_asset = OS.execute("python3", ["-c", py_code_asset], out_asset, true)
	assert(exit_code_asset == 0, "Python QR decoder for static asset must succeed")

	var static_decoded_url = ""
	for line in out_asset:
		var line_str = str(line).strip_edges()
		if line_str.begins_with("STATIC_DECODED_URL:"):
			static_decoded_url = line_str.substr(19).strip_edges()

	print("✅ Static Asset Decoded Target URL (OpenCV):", static_decoded_url)
	var expected_url = "https://app.reallife-studycenter.org/public"
	assert(static_decoded_url == expected_url, "Static asset decoded URL must equal exactly '" + expected_url + "', got: '" + static_decoded_url + "'")

	# 2. Render actual poster QR image
	var poster_img = MembershipCardEngineScript.render_remote_qr_sign()
	assert(poster_img != null and not poster_img.is_empty(), "Poster image must not be null or empty")
	print("✅ Poster Image rendered successfully:", poster_img.get_width(), "x", poster_img.get_height())

	# 3. Save poster image to user directory
	var save_path = OS.get_user_data_dir() + "/test_remote_poster_decoding.png"
	var err = poster_img.save_png(save_path)
	assert(err == OK, "Poster image PNG export must succeed")
	print("✅ Poster image exported to:", save_path)

	# 4. Decode QR code from the exported poster PNG using OpenCV
	var py_code_poster = "import cv2; detector = cv2.QRCodeDetector(); val, pts, qr = detector.detectAndDecode(cv2.imread('" + save_path + "')); print('POSTER_DECODED_URL:' + str(val))"
	var out_poster = []
	var exit_code_poster = OS.execute("python3", ["-c", py_code_poster], out_poster, true)
	assert(exit_code_poster == 0, "Python QR decoder for poster image must succeed")

	var poster_decoded_url = ""
	for line in out_poster:
		var line_str = str(line).strip_edges()
		if line_str.begins_with("POSTER_DECODED_URL:"):
			poster_decoded_url = line_str.substr(19).strip_edges()

	print("✅ Rendered Poster Decoded Target URL (OpenCV):", poster_decoded_url)
	assert(poster_decoded_url == expected_url, "Rendered poster decoded URL must equal exactly '" + expected_url + "', got: '" + poster_decoded_url + "'")

	print("==========================================================")
	print("ALL REMOTE POSTER STATIC QR DECODING TESTS PASSED 100%")
	print("==========================================================")
	quit()
