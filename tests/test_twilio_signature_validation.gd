# Focused test for Twilio Webhook Signature Validation Logic
# Uses dummy/test credentials only to verify fail-closed behavior and signature matching.

extends SceneTree

func _init():
	print("--- BEGIN TWILIO SIGNATURE VALIDATION TEST ---")
	
	var dummy_auth_token = "dummy_test_auth_token_1234567890abcdef"
	var url = "https://app.reallife-studycenter.org/api/v1/webhooks/twilio/sms"
	var post_params = {
		"From": "+18649348468",
		"To": "+18647124446",
		"Body": "Test inbound SMS payload",
		"MessageSid": "SMtestdummy12345"
	}

	# Compute valid signature for test payload using Crypto HMAC-SHA1
	var valid_sig = _compute_twilio_signature(url, post_params, dummy_auth_token)
	print("Generated test signature: ", valid_sig)

	# 1. Missing Token => Must fail (false / 403)
	var pass_missing_token = _validate_twilio_request_signature(url, post_params, "", valid_sig)
	if pass_missing_token:
		print("FAILED: Missing token should fail validation!")
		quit(1)
		return
	print("✓ PASS: Missing token fails closed (403).")

	# 2. Missing Signature => Must fail (false / 403)
	var pass_missing_sig = _validate_twilio_request_signature(url, post_params, dummy_auth_token, "")
	if pass_missing_sig:
		print("FAILED: Missing signature should fail validation!")
		quit(1)
		return
	print("✓ PASS: Missing signature fails closed (403).")

	# 3. Invalid Signature => Must fail (false / 403)
	var pass_invalid_sig = _validate_twilio_request_signature(url, post_params, dummy_auth_token, "invalid_base64_sig==")
	if pass_invalid_sig:
		print("FAILED: Invalid signature should fail validation!")
		quit(1)
		return
	print("✓ PASS: Invalid signature fails closed (403).")

	# 4. Valid Signature => Must pass (true)
	var pass_valid = _validate_twilio_request_signature(url, post_params, dummy_auth_token, valid_sig)
	if not pass_valid:
		print("FAILED: Valid signature failed validation!")
		quit(1)
		return
	print("✓ PASS: Correctly generated signature passes authentication.")

	print("--- ALL TWILIO SIGNATURE VALIDATION TESTS PASSED CLEANLY ---")
	quit(0)

func _compute_twilio_signature(url: String, post_data: Dictionary, auth_token: String) -> String:
	if auth_token == "": return ""
	
	var keys = post_data.keys()
	keys.sort()
	
	var data_str = url
	for k in keys:
		data_str += str(k) + str(post_data[k])
		
	var crypto = Crypto.new()
	var key_bytes = auth_token.to_utf8_buffer()
	var data_bytes = data_str.to_utf8_buffer()
	
	var hmac = crypto.hmac_digest(HashingContext.HASH_SHA1, key_bytes, data_bytes)
	return Marshalls.raw_to_base64(hmac)

func _validate_twilio_request_signature(url: String, post_data: Dictionary, auth_token: String, provided_signature: String) -> bool:
	if auth_token == "" or provided_signature == "":
		return false
	var expected = _compute_twilio_signature(url, post_data, auth_token)
	return expected == provided_signature
