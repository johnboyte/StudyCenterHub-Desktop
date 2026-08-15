extends SceneTree

## Test script to verify true PBKDF2-HMAC-SHA256 implementation in GDScript matching PHP hash_pbkdf2

func _init() -> void:
	print("==========================================================")
	print("TESTING GDSCRIPT TRUE PBKDF2-HMAC-SHA256 IMPLEMENTATION")
	print("==========================================================")

	var test_pin = "849201"
	var salt_hex = "a1b2c3d4e5f60718293a4b5c6d7e8f90"
	var iterations = 600000

	var derived_hash = derive_true_pbkdf2_sha256(test_pin, salt_hex, iterations)
	print("Derived GDScript Hash String: ", derived_hash)

	quit(0)

# True RFC 2898 PBKDF2-HMAC-SHA256 implementation in GDScript
static func derive_true_pbkdf2_sha256(password: String, salt_hex: String, iterations: int = 600000) -> String:
	var crypto = Crypto.new()
	var pass_bytes = password.to_utf8_buffer()
	
	# Salt is hex decoded to binary bytes to match PHP's hex2bin($salt)
	var salt_bytes = PackedByteArray()
	for i in range(0, salt_hex.length(), 2):
		var hex_sub = salt_hex.substr(i, 2)
		salt_bytes.append(hex_sub.hex_to_int())

	# Block 1 counter bytes: INT32_BE(1) = 00 00 00 01
	var salt_with_block = PackedByteArray(salt_bytes)
	salt_with_block.append(0)
	salt_with_block.append(0)
	salt_with_block.append(0)
	salt_with_block.append(1)

	# U_1 = HMAC-SHA256(password, salt || INT32_BE(1))
	var u_prev = crypto.hmac_digest(HashingContext.HASH_SHA256, pass_bytes, salt_with_block)
	var result = PackedByteArray(u_prev)

	# U_2 .. U_iterations
	for i in range(2, iterations + 1):
		u_prev = crypto.hmac_digest(HashingContext.HASH_SHA256, pass_bytes, u_prev)
		for j in range(32):
			result[j] = result[j] ^ u_prev[j]

	return "pbkdf2:sha256:" + str(iterations) + ":" + salt_hex + ":" + result.hex_encode()
