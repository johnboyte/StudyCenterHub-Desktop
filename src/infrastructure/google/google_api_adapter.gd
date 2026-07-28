extends RefCounted

## Google API & OAuth Adapter for StudyCenterHub Next Generation
## Manages Customer-Owned Google Workspace Authorization, OAuth Tokens, and Scopes.
## AP-001 & AP-005 Compliant: Secrets stored only in OS Keychain; local writes operate offline.

const OSKeychainScript = preload("res://src/infrastructure/security/os_keychain.gd")

const SCOPE_DRIVE_FILE = "https://www.googleapis.com/auth/drive.file"
const SCOPE_SHEETS = "https://www.googleapis.com/auth/spreadsheets"

var keychain: RefCounted
var is_mock_mode: bool = true
var is_online: bool = true
var is_authorized: bool = false
var authorized_email: String = ""

func _init(use_mock: bool = true) -> void:
	is_mock_mode = use_mock
	keychain = OSKeychainScript.new()

func connect_google_workspace(customer_email: String = "admin@studycenter.org") -> Dictionary:
	if customer_email == "":
		return {"success": false, "error": "Customer Google Workspace email required."}

	# Simulate PKCE token exchange
	var mock_refresh_token = "rt_cust_workspace_" + _generate_uuid()
	var mock_access_token = "at_cust_workspace_" + _generate_uuid()
	
	# Store refresh token in OS Keychain ONLY
	var store_res = keychain.store_secret("google_refresh_token", mock_refresh_token)
	if not store_res["success"]:
		return {"success": false, "error": "Failed to store refresh token in OS Keychain: " + store_res["error"]}
		
	is_authorized = true
	authorized_email = customer_email
	return {
		"success": true,
		"error": "",
		"email": customer_email,
		"scopes": [SCOPE_DRIVE_FILE, SCOPE_SHEETS]
	}

func disconnect_google_workspace() -> Dictionary:
	keychain.delete_secret("google_refresh_token")
	is_authorized = false
	authorized_email = ""
	return {"success": true, "error": ""}

func check_authorization_status() -> Dictionary:
	var ret = keychain.retrieve_secret("google_refresh_token")
	if ret["success"] and ret["value"] != "":
		is_authorized = true
		if authorized_email == "":
			authorized_email = "admin@studycenter.org"
		return {"authorized": true, "email": authorized_email}
	else:
		is_authorized = false
		return {"authorized": false, "email": ""}

func set_online_status(online: bool) -> void:
	is_online = online

func _generate_uuid() -> String:
	var b1 = "%08X" % (randi() % 4294967295)
	var b2 = "%04X" % (randi() % 65536)
	var b3 = "%04X" % (randi() % 65536)
	return (b1 + "-" + b2 + "-" + b3).to_lower()
