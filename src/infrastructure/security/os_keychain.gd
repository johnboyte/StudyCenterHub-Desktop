extends RefCounted

## OS Keychain Integration Adapter for StudyCenterHub Next Generation
## Securely stores and retrieves OAuth refresh tokens and sensitive credentials
## using native operating system credential stores (macOS Keychain via /usr/bin/security).
## ZERO secrets are ever written to SQLite business tables or Google Sheets.

const SERVICE_NAME = "StudyCenterHubNextGen"
var security_binary: String = "/usr/bin/security"

func store_secret(account_key: String, secret_value: String) -> Dictionary:
	if secret_value == "":
		return delete_secret(account_key)
		
	# First delete any existing entry to prevent duplicate errors
	delete_secret(account_key)
	
	var args = [
		"add-generic-password",
		"-a", account_key,
		"-s", SERVICE_NAME,
		"-w", secret_value,
		"-U"
	]
	
	var output = []
	var exit_code = OS.execute(security_binary, args, output, true)
	
	if exit_code != 0:
		var err_msg = output[0] if output.size() > 0 else "Keychain storage failed"
		return {"success": false, "error": err_msg}
		
	return {"success": true, "error": ""}

func retrieve_secret(account_key: String) -> Dictionary:
	var args = [
		"find-generic-password",
		"-a", account_key,
		"-s", SERVICE_NAME,
		"-w"
	]
	
	var output = []
	var exit_code = OS.execute(security_binary, args, output, true)
	
	if exit_code != 0:
		return {"success": false, "error": "Secret not found or locked", "value": ""}
		
	var secret_val = output[0].strip_edges() if output.size() > 0 else ""
	return {"success": true, "error": "", "value": secret_val}

func delete_secret(account_key: String) -> Dictionary:
	var args = [
		"delete-generic-password",
		"-a", account_key,
		"-s", SERVICE_NAME
	]
	
	var output = []
	var exit_code = OS.execute(security_binary, args, output, true)
	return {"success": (exit_code == 0), "error": "" if exit_code == 0 else "Delete failed"}
