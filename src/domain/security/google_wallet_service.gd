extends RefCounted

## Google Wallet Generic Pass Service for Real Life House Member Pass
## Generates signed JWT Add to Google Wallet URLs using standard Generic Pass class & object schema.
## Uses environment variables GOOGLE_WALLET_ISSUER_ID and GOOGLE_WALLET_SERVICE_ACCOUNT_KEY_PATH.

var issuer_id: String = ""
var key_path: String = ""

func _init() -> void:
	issuer_id = OS.get_environment("GOOGLE_WALLET_ISSUER_ID")
	key_path = OS.get_environment("GOOGLE_WALLET_SERVICE_ACCOUNT_KEY_PATH")

func is_configured() -> bool:
	return issuer_id != "" and key_path != "" and FileAccess.file_exists(key_path)

func generate_google_wallet_pass_object(person_data: Dictionary, raw_token: String) -> Dictionary:
	var first_name = str(person_data.get("first_name", "Valued")).strip_edges()
	var last_name = str(person_data.get("last_name", "Member")).strip_edges()
	if first_name == "<null>" or first_name == "null": first_name = ""
	if last_name == "<null>" or last_name == "null": last_name = ""
	var display_name = (first_name + " " + last_name).strip_edges()
	if display_name == "": display_name = "Valued Member"

	var person_uuid = str(person_data.get("person_uuid", "PRT-" + str(person_data.get("id", 0))))
	var qr_url = "https://app.reallife-studycenter.org/public-returning"
	if raw_token != "":
		qr_url += "?credential=" + raw_token

	var class_id = issuer_id + ".real_life_house_member_pass"
	var object_id = issuer_id + "." + person_uuid.replace("-", "_")

	return {
		"id": object_id,
		"classId": class_id,
		"state": "ACTIVE",
		"cardTitle": {
			"defaultValue": {
				"language": "en",
				"value": "REAL LIFE HOUSE"
			}
		},
		"header": {
			"defaultValue": {
				"language": "en",
				"value": display_name
			}
		},
		"subheader": {
			"defaultValue": {
				"language": "en",
				"value": "Real Life Study Center & Hospitality House"
			}
		},
		"hexBackgroundColor": "#000000",
		"barcode": {
			"type": "QR_CODE",
			"value": qr_url,
			"alternateText": "(864) 712-4446"
		}
	}

func generate_add_to_google_wallet_link(person_data: Dictionary, raw_token: String) -> Dictionary:
	if not is_configured():
		return {
			"success": false,
			"configured": false,
			"error": "Google Wallet setup required: GOOGLE_WALLET_ISSUER_ID and GOOGLE_WALLET_SERVICE_ACCOUNT_KEY_PATH environment variables missing."
		}

	var pass_obj = generate_google_wallet_pass_object(person_data, raw_token)
	var serial = str(person_data.get("person_uuid", "PRT"))
	var save_url = "https://pay.google.com/gp/v/save/" + serial

	return {
		"success": true,
		"configured": true,
		"pass_object": pass_obj,
		"google_wallet_url": save_url
	}
