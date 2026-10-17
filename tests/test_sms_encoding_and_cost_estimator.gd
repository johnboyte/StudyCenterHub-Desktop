extends SceneTree

const SMSEncodingHelperScript = preload("res://src/domain/communications/sms_encoding_helper.gd")

func _init() -> void:
	print("==================================================")
	print("RUNNING: SMS Encoding, Segmentation & Cost Tests")
	print("==================================================")
	_run_tests()

func _run_tests() -> void:
	await create_timer(0.05).timeout

	# 1. Test GSM-7 Single Segment (<= 160 chars)
	var gsm_short = "Hello! Looking forward to seeing you at the study tonight."
	var res1 = SMSEncodingHelperScript.analyze_sms(gsm_short, false, 1)
	assert(res1["encoding"] == "GSM-7", "Test 1 failed: Expected GSM-7")
	assert(res1["segments_per_recipient"] == 1, "Test 1 failed: Expected 1 segment")
	assert(res1["total_billable_units"] == 1, "Test 1 failed: Expected 1 total segment")
	assert(abs(res1["estimated_cost"] - 0.0122) < 0.0001, "Test 1 failed: Expected $0.0122")
	print("✓ PASS 1: GSM-7 single segment correctly identified.")

	# 2. Test GSM-7 Multipart (> 160 chars)
	# 170 chars -> 2 segments (153 + 17)
	var gsm_multi = "A".repeat(170)
	var res2 = SMSEncodingHelperScript.analyze_sms(gsm_multi, false, 1)
	assert(res2["encoding"] == "GSM-7", "Test 2 failed: Expected GSM-7")
	assert(res2["segments_per_recipient"] == 2, "Test 2 failed: Expected 2 segments for 170 chars")
	assert(res2["total_billable_units"] == 2, "Test 2 failed: Expected 2 total segments")
	print("✓ PASS 2: GSM-7 multipart segmentation (153 chars/segment) verified.")

	# 3. Test GSM-7 Extension Characters (^, {, }, [, ], ~, |, €)
	# 158 basic chars + 2 extended chars = 162 effective chars -> should spill into 2 segments!
	var gsm_ext = "A".repeat(158) + "[]"
	var res3 = SMSEncodingHelperScript.analyze_sms(gsm_ext, false, 1)
	assert(res3["encoding"] == "GSM-7", "Test 3 failed: Expected GSM-7")
	assert(res3["gsm_extended_count"] == 2, "Test 3 failed: Expected 2 extended chars")
	assert(res3["segments_per_recipient"] == 2, "Test 3 failed: Extended chars should cause 2 segments")
	print("✓ PASS 3: GSM-7 extension characters (2 septets each) verified.")

	# 4. Test Unicode Single Segment (<= 70 chars)
	var uni_short = "Hello! Real Life House — See you tonight!" # contains em dash '—'
	var res4 = SMSEncodingHelperScript.analyze_sms(uni_short, false, 1)
	assert(res4["encoding"] == "Unicode", "Test 4 failed: Expected Unicode")
	assert(res4["segments_per_recipient"] == 1, "Test 4 failed: Expected 1 segment under 70 chars")
	print("✓ PASS 4: Unicode single segment (<= 70 chars) verified.")

	# 5. Test Unicode Multipart (> 70 chars)
	# 75 chars with em dash -> 2 Unicode segments (67 chars/segment)
	var uni_multi = "Real Life House — " + "A".repeat(60)
	var res5 = SMSEncodingHelperScript.analyze_sms(uni_multi, false, 1)
	assert(res5["encoding"] == "Unicode", "Test 5 failed: Expected Unicode")
	assert(res5["segments_per_recipient"] == 2, "Test 5 failed: Expected 2 Unicode segments for >70 chars")
	print("✓ PASS 5: Unicode multipart segmentation (67 chars/segment) verified.")

	# 6. Test Group Recipient Multiplication
	# 27 recipients with 4 Unicode segments = 108 segments
	var group_text = "“Special Announcement” — " + "A".repeat(200) # ~225 chars -> ceil(225/67) = 4 segments
	var res6 = SMSEncodingHelperScript.analyze_sms(group_text, false, 27)
	assert(res6["recipient_count"] == 27, "Test 6 failed: Expected 27 recipients")
	assert(res6["segments_per_recipient"] == 4, "Test 6 failed: Expected 4 segments per recipient")
	assert(res6["total_billable_units"] == 108, "Test 6 failed: Expected 108 total segments")
	assert(abs(res6["estimated_cost"] - (108 * 0.0122)) < 0.01, "Test 6 failed: Cost calculation")
	print("✓ PASS 6: Group recipient multiplication (27 recips * 4 segs = 108 segs) verified.")

	# 7. Test MMS Mode (Attachment)
	var res7 = SMSEncodingHelperScript.analyze_sms("Check out this flyer!", true, 27)
	assert(res7["is_mms"] == true, "Test 7 failed: Expected MMS mode")
	assert(res7["total_billable_units"] == 27, "Test 7 failed: Expected 27 MMS units")
	assert(abs(res7["estimated_cost"] - (27 * 0.0280)) < 0.01, "Test 7 failed: Expected MMS flat rate")
	print("✓ PASS 7: MMS mode classification and flat rate pricing verified.")

	# 8. Test "Optimize for SMS" text replacement and savings calculation
	var unoptimized = "“Tonight’s meeting — 7:30 PM–8:30 PM… Don’t miss it!”"
	var opt_res = SMSEncodingHelperScript.get_optimized_text(unoptimized, 27)
	assert(opt_res["has_changes"] == true, "Test 8 failed: Expected changes")
	assert(not opt_res["optimized_text"].contains("“"), "Test 8 failed: Left quote replaced")
	assert(not opt_res["optimized_text"].contains("”"), "Test 8 failed: Right quote replaced")
	assert(not opt_res["optimized_text"].contains("’"), "Test 8 failed: Apostrophe replaced")
	assert(not opt_res["optimized_text"].contains("—"), "Test 8 failed: Em dash replaced")
	assert(not opt_res["optimized_text"].contains("–"), "Test 8 failed: En dash replaced")
	assert(opt_res["optimized_text"].contains("\""), "Test 8 failed: Straight quote inserted")
	assert(opt_res["optimized_text"].contains("-"), "Test 8 failed: Hyphen inserted")
	assert(opt_res["after"]["encoding"] == "GSM-7", "Test 8 failed: Optimized text should be GSM-7")
	print("✓ PASS 8: 'Optimize for SMS' safe punctuation substitutions verified.")

	# 9. Test Real October Case: Rainy Day Announcement (631 chars)
	var rainy_body = "RAINY DAY AT REAL LIFE HOUSE\nLooking for a place to hang out on this rainy Saturday?\nOPEN THIS MORNING | 10:00·11:30 AM\nPOSSIBLE AFTERNOON HOURS\n2:30–5:30 PM\nIf any of you text back that you'd like to come by this afternoon,\nwe'll open the House from 2:30–5:30 PM as well!\nJust want to know whether we open? Reply:\n“Yes, please let me know about the afternoon hours!”\n\nREMINDER: REAL LIFE IS TOMORROW NIGHT!\n“And You Thought You Knew Him”\nA study of who Christ is and what He really came to do,\nthrough the Gospel of Mark.\n7:30 PM — Refreshments & Fellowship\n7:45 PM — Bible Study Begins\nCome hang out, bring a friend, and join us!"
	var rainy_opt = SMSEncodingHelperScript.get_optimized_text(rainy_body, 23)
	assert(rainy_opt["before"]["segments_per_recipient"] == 10, "Test 9 failed: Original was 10 segments in Unicode")
	assert(rainy_opt["after"]["segments_per_recipient"] == 5, "Test 9 failed: Optimized is 5 segments in GSM-7")
	assert(rainy_opt["savings_per_recipient"] == 5, "Test 9 failed: Expected 5 segments saved per recipient")
	assert(rainy_opt["total_segment_savings"] == 115, "Test 9 failed: Expected 115 total segments saved")
	assert(rainy_opt["percent_savings"] == 50.0, "Test 9 failed: Expected 50% savings")
	print("✓ PASS 9: Real October 'Rainy Day' message optimization (10 -> 5 segs, 50% savings, 115 segs saved) verified.")

	# 10. Test GSM-7 Forwarded Relay Message Formatting
	var fwd = SMSEncodingHelperScript.format_gsm7_relay_message("Sarah Johnson", "(864) 555-1234", "I’ll be there tonight! — See you soon", "ABCD")
	assert(fwd.begins_with("Incoming Text - Sarah Johnson"), "Test 10 failed: Expected 'Incoming Text - Sarah Johnson'")
	assert(not fwd.contains("—"), "Test 10 failed: Should not contain em dash")
	assert(not fwd.contains("’"), "Test 10 failed: Should not contain curly apostrophe")
	assert(fwd.contains("Ref: ABCD"), "Test 10 failed: Token preserved")
	assert(fwd.contains("Reply with:\nABCD your reply"), "Test 10 failed: Reply instructions preserved")
	var fwd_analysis = SMSEncodingHelperScript.analyze_sms(fwd, false, 1)
	assert(fwd_analysis["encoding"] == "GSM-7", "Test 10 failed: Formatted notification envelope is GSM-7")
	print("✓ PASS 10: GSM-7 Forwarded Relay Message formatting verified.")
	# 11. Test Zero Recipients: Per-recipient segments preserved, total units 0, cost $0.00
	var zero_res = SMSEncodingHelperScript.analyze_sms("Important session reminder tonight!", false, 0)
	assert(zero_res["recipient_count"] == 0, "Test 11 failed: Expected 0 recipients")
	assert(zero_res["segments_per_recipient"] == 1, "Test 11 failed: Expected 1 segment per recipient")
	assert(zero_res["total_billable_units"] == 0, "Test 11 failed: Expected 0 total billable units")
	assert(zero_res["estimated_cost"] == 0.0, "Test 11 failed: Expected $0.00 cost")
	print("✓ PASS 11: Zero recipients handling (per-recipient preserved, total units 0, cost $0.00) verified.")

	print("\n==================================================")
	print("ALL 11 SMS ENCODING & ESTIMATOR TESTS PASSED!")
	print("==================================================")
	quit(0)
