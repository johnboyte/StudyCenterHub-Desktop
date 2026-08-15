extends RefCounted

## Staff Mobile Credentials Management Service
## Handles setting, resetting, disabling, and deriving 600,000-iteration PBKDF2
## slow password hashes for Staff Mobile Access credentials.

var db: RefCounted

func _init(database: RefCounted) -> void:
	db = database

# Derives a true RFC 2898 PBKDF2-HMAC-SHA256 salted password hash with 600,000 iterations
static func derive_pbkdf2_hash(pin: String, salt_hex: String = "") -> String:
	var crypto = Crypto.new()
	if salt_hex == "":
		var salt_bytes_rand = crypto.generate_random_bytes(16)
		salt_hex = salt_bytes_rand.hex_encode()

	var iterations = 600000
	var pass_bytes = pin.strip_edges().to_utf8_buffer()

	# Decode hex salt to binary bytes matching PHP's hex2bin($salt)
	var salt_bytes = PackedByteArray()
	for i in range(0, salt_hex.length(), 2):
		salt_bytes.append(salt_hex.substr(i, 2).hex_to_int())

	# Initial block counter INT32_BE(1) = 00 00 00 01
	var salt_with_block = PackedByteArray(salt_bytes)
	salt_with_block.append(0)
	salt_with_block.append(0)
	salt_with_block.append(0)
	salt_with_block.append(1)

	# U_1 = HMAC-SHA256(password, salt || INT32_BE(1))
	var u_prev = crypto.hmac_digest(HashingContext.HASH_SHA256, pass_bytes, salt_with_block)
	var result = PackedByteArray(u_prev)

	# Stretch across 600,000 iterations
	for i in range(2, iterations + 1):
		u_prev = crypto.hmac_digest(HashingContext.HASH_SHA256, pass_bytes, u_prev)
		for j in range(32):
			result[j] = result[j] ^ u_prev[j]

	return "pbkdf2:sha256:" + str(iterations) + ":" + salt_hex + ":" + result.hex_encode()

# Enables or resets a Staff Mobile PIN (must be 6 numeric digits)
func set_staff_mobile_pin(person_id: int, pin: String) -> Dictionary:
	if not db or person_id <= 0:
		return {"success": false, "error": "Invalid person ID"}

	var clean_pin = pin.strip_edges()
	if clean_pin.length() != 6 or not clean_pin.is_valid_int():
		return {"success": false, "error": "Mobile Staff PIN must be exactly 6 numeric digits."}

	# Verify staff eligibility
	var p_res = db.execute("""
		SELECT id, human_id, first_name, last_name, primary_role, staff_classification, status 
		FROM people WHERE id = ? LIMIT 1;
	""", [person_id])

	if not p_res["success"] or p_res["data"].size() == 0:
		return {"success": false, "error": "Person profile not found."}

	var p = p_res["data"][0]
	var st = String(p.get("status", "")).to_lower()
	var role = String(p.get("primary_role", "")).to_lower()
	var classif = String(p.get("staff_classification", "")).to_lower()

	if st != "active":
		return {"success": false, "error": "Cannot enable Mobile Access for inactive staff records."}

	var valid_roles = ["staff", "team leader", "supervisor", "administrator", "intern", "volunteer"]
	if not (role in valid_roles or classif in valid_roles):
		return {"success": false, "error": "Only active Staff, Team Leaders, Supervisors, Administrators, Interns, and Volunteers are eligible for Mobile Access."}

	var human_id = String(p.get("human_id", ""))
	var pin_hash = derive_pbkdf2_hash(clean_pin)

	# Fetch existing credential version
	var existing_res = db.execute("SELECT credential_version FROM staff_mobile_credentials WHERE person_id = ? LIMIT 1;", [person_id])
	var cur_ver = 1
	if existing_res["success"] and existing_res["data"].size() > 0:
		cur_ver = int(existing_res["data"][0].get("credential_version", 1)) + 1

	var sql = """
		INSERT INTO staff_mobile_credentials (
			person_id, human_id, pin_pbkdf_hash, credential_version, mobile_access_enabled, updated_at
		) VALUES (?, ?, ?, ?, 1, datetime('now'))
		ON CONFLICT(person_id) DO UPDATE SET
			pin_pbkdf_hash = excluded.pin_pbkdf_hash,
			credential_version = staff_mobile_credentials.credential_version + 1,
			mobile_access_enabled = 1,
			updated_at = datetime('now');
	"""
	var exec_res = db.execute(sql, [person_id, human_id, pin_hash, cur_ver])
	if not exec_res["success"]:
		return {"success": false, "error": exec_res["error"]}

	return {
		"success": true,
		"message": "Staff Mobile Access enabled successfully with 6-digit PIN.",
		"credential_version": cur_ver
	}

# Disables Staff Mobile Access and revokes existing mobile sessions
func disable_staff_mobile_access(person_id: int) -> Dictionary:
	if not db or person_id <= 0:
		return {"success": false, "error": "Invalid person ID"}

	var sql = """
		UPDATE staff_mobile_credentials 
		SET mobile_access_enabled = 0, 
		    credential_version = credential_version + 1, 
		    updated_at = datetime('now')
		WHERE person_id = ?;
	"""
	var res = db.execute(sql, [person_id])
	return res

# Checks mobile access status for a person
func get_staff_mobile_status(person_id: int) -> Dictionary:
	if not db or person_id <= 0:
		return {"enabled": false, "version": 0}

	var res = db.execute("SELECT mobile_access_enabled, credential_version, updated_at FROM staff_mobile_credentials WHERE person_id = ? LIMIT 1;", [person_id])
	if res["success"] and res["data"].size() > 0:
		var row = res["data"][0]
		return {
			"enabled": int(row.get("mobile_access_enabled", 0)) == 1,
			"version": int(row.get("credential_version", 1)),
			"updated_at": String(row.get("updated_at", ""))
		}
	return {"enabled": false, "version": 0}
