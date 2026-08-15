import hashlib

test_pin = b"849201"
salt_bytes = bytes.fromhex("a1b2c3d4e5f60718293a4b5c6d7e8f90")
iterations = 600000

derived = hashlib.pbkdf2_hmac('sha256', test_pin, salt_bytes, iterations)
derived_hex = derived.hex()

print("Python/PHP Standard PBKDF2 Hex Digest:", derived_hex)
expected_gdscript_hex = "a5816f0141543951fbe03ef70eeeacab746ab6a60d5bf0c966096e59259e0807"

if derived_hex == expected_gdscript_hex:
    print("MATCH SUCCESS: GDScript true PBKDF2 matches Python/PHP standard PBKDF2 100% byte-for-byte!")
else:
    print("MISMATCH: Python:", derived_hex, "vs GDScript:", expected_gdscript_hex)
