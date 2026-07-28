extends RefCounted

## Cryptographically Secure QR Credential Service for StudyCenterHub
## Enforces 256-bit entropy opaque tokens, SHA-256 database hashing, and OS Keychain protection.

const OSKeychainScript = preload("res://src/infrastructure/security/os_keychain.gd")

var db: RefCounted
var keychain: RefCounted

func _init(p_db: RefCounted = null) -> void:
	db = p_db
	keychain = OSKeychainScript.new()

static func generate_secure_token() -> String:
	var crypto = Crypto.new()
	var bytes = crypto.generate_random_bytes(32) # 256 bits of entropy
	return bytes.hex_encode().to_lower()

static func hash_token(raw_token: String) -> String:
	return raw_token.strip_edges().sha256_text().to_lower()

static func generate_token_hint(raw_token: String) -> String:
	var h = hash_token(raw_token)
	return "Pass ***" + h.right(4)

func issue_credential(person_id: int, person_uuid: String) -> Dictionary:
	if not db:
		return {"success": false, "error": "Database reference unavailable"}

	var raw_token = generate_secure_token()
	var token_hash_val = hash_token(raw_token)
	var hint_val = generate_token_hint(raw_token)
	var cred_id = "QRCR-" + str(Time.get_ticks_usec()) + "-" + str(randi() % 10000)

	# 1. Revoke existing active credential
	var revoke_sql = "UPDATE participant_qr_credentials SET status = 'revoked' WHERE person_id = ? AND status = 'active';"
	db.execute(revoke_sql, [person_id])

	# 2. Insert new credential with SHA-256 hash and hint
	var insert_sql = """
		INSERT INTO participant_qr_credentials (credential_id, person_id, token_hash, token_hint, status, issued_at)
		VALUES (?, ?, ?, ?, 'active', datetime('now'));
	"""
	var res = db.execute(insert_sql, [cred_id, person_id, token_hash_val, hint_val])
	if not res["success"]:
		return {"success": false, "error": "Failed to store credential hash: " + str(res.get("error", ""))}

	# 3. Update people table with SHA-256 hash (never raw token)
	db.execute("UPDATE people SET qr_code_value = ? WHERE id = ?;", [token_hash_val, person_id])

	# 4. Store raw token securely in OS Keychain for reprinting
	if keychain:
		keychain.store_secret("qr_cred_" + cred_id, raw_token)

	return {
		"success": true,
		"credential_id": cred_id,
		"raw_token": raw_token,
		"token_hash": token_hash_val,
		"token_hint": hint_val
	}

func get_active_raw_token(person_id: int) -> String:
	if not db:
		return ""
	var res = db.execute("SELECT credential_id, token_hash FROM participant_qr_credentials WHERE person_id = ? AND status = 'active' LIMIT 1;", [person_id])
	if res["success"] and res["data"].size() > 0:
		var cred_id = str(res["data"][0].get("credential_id", ""))
		if keychain:
			var kc_res = keychain.retrieve_secret("qr_cred_" + cred_id)
			if kc_res["success"] and kc_res["value"] != "":
				return kc_res["value"]
	return ""

func lookup_person_by_raw_token(raw_token: String) -> Dictionary:
	if not db or raw_token.strip_edges() == "" or raw_token.length() < 32:
		return {"success": false, "error": "Invalid token payload"}

	var token_hash_val = hash_token(raw_token)
	var sql = """
		SELECT p.*, c.credential_id, c.issued_at
		FROM participant_qr_credentials c
		JOIN people p ON c.person_id = p.id
		WHERE c.token_hash = ? AND c.status = 'active'
		LIMIT 1;
	"""
	var res = db.execute(sql, [token_hash_val])
	if res["success"] and res["data"].size() > 0:
		return {"success": true, "person": res["data"][0]}
	
	return {"success": false, "error": "Credential invalid or revoked"}

func revoke_credential(person_id: int) -> bool:
	if not db:
		return false
	var res = db.execute("SELECT credential_id FROM participant_qr_credentials WHERE person_id = ? AND status = 'active';", [person_id])
	if res["success"]:
		for row in res["data"]:
			var cred_id = str(row.get("credential_id", ""))
			if keychain:
				keychain.delete_secret("qr_cred_" + cred_id)
	
	db.execute("UPDATE participant_qr_credentials SET status = 'revoked' WHERE person_id = ? AND status = 'active';", [person_id])
	db.execute("UPDATE people SET qr_code_value = NULL WHERE id = ?;", [person_id])
	return true
