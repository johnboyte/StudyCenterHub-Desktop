extends RefCounted

## Apple Wallet PassKit (.pkpass) Service for Real Life House Member Pass
## Generates signed PassKit generic passes using standard PKPass structure.
## Uses environment variables APPLE_PASS_TYPE_ID, APPLE_TEAM_ID, APPLE_WALLET_CERT_PATH, APPLE_WALLET_KEY_PATH, APPLE_WWDR_CERT_PATH.

var pass_type_id: String = ""
var team_id: String = ""
var cert_path: String = ""
var key_path: String = ""
var wwdr_path: String = ""

func _init() -> void:
	pass_type_id = OS.get_environment("APPLE_PASS_TYPE_ID")
	if pass_type_id == "": pass_type_id = "pass.org.reallife.house.member"
	
	team_id = OS.get_environment("APPLE_TEAM_ID")
	if team_id == "": team_id = "P9U2VHWT79"
	
	cert_path = OS.get_environment("APPLE_WALLET_CERT_PATH")
	if cert_path == "": cert_path = "/Users/johnboyte/.gemini/config/wallet_keys/pass_cert.pem"
	
	key_path = OS.get_environment("APPLE_WALLET_KEY_PATH")
	if key_path == "": key_path = "/Users/johnboyte/.gemini/config/wallet_keys/pass_key.pem"
	
	wwdr_path = OS.get_environment("APPLE_WWDR_CERT_PATH")
	if wwdr_path == "": wwdr_path = "/Users/johnboyte/.gemini/config/wallet_keys/wwdr.pem"

func is_configured() -> bool:
	return pass_type_id != "" and team_id != "" and cert_path != "" and FileAccess.file_exists(cert_path) and key_path != "" and FileAccess.file_exists(key_path)

func generate_pass_json(person_data: Dictionary, raw_token: String) -> String:
	var first_name = str(person_data.get("first_name", "Valued")).strip_edges()
	var last_name = str(person_data.get("last_name", "Member")).strip_edges()
	if first_name == "<null>" or first_name == "null": first_name = ""
	if last_name == "<null>" or last_name == "null": last_name = ""
	var display_name = (first_name + " " + last_name).strip_edges()
	if display_name == "": display_name = "Valued Member"

	var person_uuid = str(person_data.get("person_uuid", "PRT-" + str(person_data.get("id", 0))))
	var qr_url = "https://checkin.reallife-studycenter.org/public-returning"
	if raw_token != "":
		qr_url += "?credential=" + raw_token

	var phone_val = "(864) 712-4446" # Official Study Center Support & Contact Line

	var pass_dict = {
		"formatVersion": 1,
		"passTypeIdentifier": pass_type_id if pass_type_id != "" else "pass.org.reallife.house.member",
		"serialNumber": person_uuid,
		"teamIdentifier": team_id if team_id != "" else "REAL_LIFE_TEAM_ID",
		"organizationName": "Real Life House",
		"description": "Real Life House Member Pass",
		"logoText": "",
		"backgroundColor": "rgb(0, 0, 0)",
		"foregroundColor": "rgb(255, 255, 255)",
		"labelColor": "rgb(218, 165, 32)",
		"dataDetectorTypes": ["PKDataDetectorTypePhoneNumber", "PKDataDetectorTypeLink"],
		"generic": {
			"headerFields": [],
			"primaryFields": [
				{
					"key": "member_name",
					"label": "MEMBER NAME",
					"value": display_name
				}
			],
			"secondaryFields": [
				{
					"key": "organization",
					"label": "FACILITY",
					"value": "Real Life Study Center"
				}
			],
			"auxiliaryFields": [
				{
					"key": "support_phone",
					"label": "PHONE",
					"value": phone_val,
					"dataDetectorTypes": ["PKDataDetectorTypePhoneNumber"]
				}
			],
			"backFields": [
				{
					"key": "about_real_life_house",
					"label": "About Real Life House",
					"value": "Real Life House is a Study Center & Hospitality House near Anderson University where students and community members are welcomed into a Christ-centered environment for study, fellowship, hospitality, discipleship, and life-on-life relationships. Our mission is to help people know Christ, grow in faith, and serve others through the transforming power of the gospel. We are committed to supporting local churches and campus ministries as they minister to students."
				},
				{
					"key": "real_life_community",
					"label": "Real Life",
					"value": "Our Bible study and fellowship community meets most Sundays from 7:45–9:00 PM for biblical teaching, discussion, prayer, worship, and authentic Christian community."
				},
				{
					"key": "contact_info",
					"label": "Contact",
					"value": "For more information, stop by or call (864) 712-4446.",
					"dataDetectorTypes": ["PKDataDetectorTypePhoneNumber"]
				},
				{
					"key": "website_info",
					"label": "Website",
					"value": "https://reallifehouse.org",
					"dataDetectorTypes": ["PKDataDetectorTypeLink"]
				}
			]
		},
		"barcode": {
			"format": "PKBarcodeFormatQR",
			"message": qr_url,
			"messageEncoding": "iso-8859-1",
			"altText": "Scan at Check-In"
		},
		"barcodes": [
			{
				"format": "PKBarcodeFormatQR",
				"message": qr_url,
				"messageEncoding": "iso-8859-1",
				"altText": "Scan at Check-In"
			}
		]
	}
	return JSON.stringify(pass_dict, "  ")

func generate_apple_wallet_pass(person_data: Dictionary, raw_token: String) -> Dictionary:
	if not is_configured():
		return {
			"success": false,
			"configured": false,
			"status": "IMPLEMENTED — ADMINISTRATOR CERTIFICATES/ISSUER SETUP REQUIRED",
			"error": "Apple Wallet setup required: Pass Type Certificate (.pem), Private Key, and WWDR Certificate missing."
		}

	var pass_json = generate_pass_json(person_data, raw_token)
	var serial = str(person_data.get("person_uuid", "PRT"))
	var temp_pass_dir = ProjectSettings.globalize_path("user://wallet/apple_" + serial)
	DirAccess.make_dir_recursive_absolute(temp_pass_dir)

	var pass_file = FileAccess.open(temp_pass_dir + "/pass.json", FileAccess.WRITE)
	if pass_file:
		pass_file.store_string(pass_json)
		pass_file.close()

	# Copy graphic header logo images into pass directory
	var logo_1x_path = ProjectSettings.globalize_path("res://assets/cards/pass_logo.png")
	var logo_2x_path = ProjectSettings.globalize_path("res://assets/cards/pass_logo@2x.png")
	var logo_3x_path = ProjectSettings.globalize_path("res://assets/cards/pass_logo@3x.png")
	if FileAccess.file_exists(logo_1x_path):
		DirAccess.copy_absolute(logo_1x_path, temp_pass_dir + "/logo.png")
	if FileAccess.file_exists(logo_2x_path):
		DirAccess.copy_absolute(logo_2x_path, temp_pass_dir + "/logo@2x.png")
	if FileAccess.file_exists(logo_3x_path):
		DirAccess.copy_absolute(logo_3x_path, temp_pass_dir + "/logo@3x.png")

	# Create profile thumbnail images for Apple Wallet pass (locked in for pass face rendering)
	_create_thumbnail_assets(person_data, temp_pass_dir)

	# Execute sign_pkpass.py helper script
	var script_path = ProjectSettings.globalize_path("res://src/infrastructure/wallet/sign_pkpass.py")
	var output_pkpass = ProjectSettings.globalize_path("user://wallet/" + serial + ".pkpass")
	var output = []
	var exit_code = OS.execute("python3", [script_path, temp_pass_dir, cert_path, key_path, wwdr_path, output_pkpass], output)

	if exit_code == 0:
		var pass_id = serial
		var upload_url = "https://app.reallife-studycenter.org/upload_pass.php?pass_id=" + pass_id
		var http = HTTPClient.new()
		var err = http.connect_to_host("app.reallife-studycenter.org", 80)
		if err == OK:
			var timeout = 40
			while (http.get_status() == HTTPClient.STATUS_CONNECTING or http.get_status() == HTTPClient.STATUS_RESOLVING) and timeout > 0:
				http.poll()
				OS.delay_msec(20)
				timeout -= 1
			if http.get_status() == HTTPClient.STATUS_CONNECTED:
				var headers = [
					"Content-Type: application/vnd.apple.pkpass",
					"User-Agent: StudyCenterHub/1.0"
				]
				var pass_bytes = FileAccess.get_file_as_bytes(output_pkpass)
				http.request_raw(HTTPClient.METHOD_POST, "/upload_pass.php?pass_id=" + pass_id, headers, pass_bytes)
				timeout = 40
				while http.get_status() == HTTPClient.STATUS_REQUESTING and timeout > 0:
					http.poll()
					OS.delay_msec(20)
					timeout -= 1

		var public_url = "https://app.reallife-studycenter.org/upload_pass.php?pass_id=" + pass_id
		return {
			"success": true,
			"configured": true,
			"pkpass_file": output_pkpass,
			"pkpass_url": public_url
		}
	else:
		return {
			"success": false,
			"configured": true,
			"error": "OpenSSL signing error: " + str(output)
		}

func _create_thumbnail_assets(person_data: Dictionary, pass_dir: String) -> void:
	var photo_path = str(person_data.get("photo_url", "")).strip_edges()
	if photo_path == "" or photo_path == "<null>":
		photo_path = str(person_data.get("profile_photo", "")).strip_edges()

	var photo_img: Image = null

	if photo_path != "" and photo_path != "<null>":
		if photo_path.begins_with("data:image"):
			var comma_idx = photo_path.find(",")
			if comma_idx != -1:
				var b64_str = photo_path.substr(comma_idx + 1)
				var bytes = Marshalls.base64_to_raw(b64_str)
				photo_img = Image.new()
				if photo_img.load_png_from_buffer(bytes) != OK:
					if photo_img.load_jpg_from_buffer(bytes) != OK:
						photo_img = null
		elif FileAccess.file_exists(photo_path):
			photo_img = Image.load_from_file(photo_path)

	if photo_img and not photo_img.is_empty():
		var w = photo_img.get_width()
		var h = photo_img.get_height()
		var side = min(w, h)
		var crop_x = (w - side) / 2
		var crop_y = (h - side) / 2
		var cropped = photo_img.get_region(Rect2i(crop_x, crop_y, side, side))

		var thumb_2x = cropped.duplicate() as Image
		thumb_2x.resize(180, 180, Image.INTERPOLATE_BILINEAR)
		thumb_2x.save_png(pass_dir + "/thumbnail@2x.png")

		var thumb_1x = cropped.duplicate() as Image
		thumb_1x.resize(90, 90, Image.INTERPOLATE_BILINEAR)
		thumb_1x.save_png(pass_dir + "/thumbnail.png")

		# If strip@2x.png exists in pass_dir, overlay profile photo on right side of strip
		var strip_file = pass_dir + "/strip@2x.png"
		if FileAccess.file_exists(strip_file):
			var strip_img = Image.load_from_file(strip_file)
			if strip_img:
				var frame_2x = Image.create(180, 180, false, Image.FORMAT_RGBA8)
				frame_2x.blit_rect(thumb_2x, Rect2i(0, 0, 180, 180), Vector2i(0, 0))
				for fy in range(180):
					for fx in range(180):
						if fx <= 2 or fx >= 177 or fy <= 2 or fy >= 177:
							frame_2x.set_pixel(fx, fy, Color(0.737, 0.635, 0.439, 1.0))
				strip_img.blit_rect(frame_2x, Rect2i(0, 0, 180, 180), Vector2i(550, 33))
				strip_img.save_png(strip_file)

				var strip_1x_img = strip_img.duplicate() as Image
				strip_1x_img.resize(375, 123, Image.INTERPOLATE_BILINEAR)
				strip_1x_img.save_png(pass_dir + "/strip.png")
	else:
		var avatar_img = Image.create(180, 180, false, Image.FORMAT_RGBA8)
		avatar_img.fill(Color(0.12, 0.16, 0.23, 1.0))
		for y in range(180):
			for x in range(180):
				var dx_head = float(x - 90)
				var dy_head = float(y - 68)
				var dist_head = sqrt(dx_head * dx_head + dy_head * dy_head)
				
				var dx_body = float(x - 90) / 55.0
				var dy_body = float(y - 145) / 38.0
				var dist_body = sqrt(dx_body * dx_body + dy_body * dy_body)

				if dist_head <= 32.0 or dist_body <= 1.0:
					avatar_img.set_pixel(x, y, Color(0.737, 0.635, 0.439, 1.0))

		avatar_img.save_png(pass_dir + "/thumbnail@2x.png")

		var avatar_1x = avatar_img.duplicate() as Image
		avatar_1x.resize(90, 90, Image.INTERPOLATE_BILINEAR)
		avatar_1x.save_png(pass_dir + "/thumbnail.png")
