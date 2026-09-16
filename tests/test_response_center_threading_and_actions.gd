extends SceneTree

## Automated Headless Test Suite for Response Center Actions, 2-Way SMS Threading, and Auto-Name Normalization
## Verifies that card consolidation, phone format variants, single vs multi-person matching, and reply dispatch work perfectly.

const SQLiteDatabaseScript = preload("res://src/infrastructure/database/sqlite_database.gd")
const MigrationsRunnerScript = preload("res://src/infrastructure/database/migrations_runner.gd")
const CommunicationsServiceScript = preload("res://src/domain/communications/communications_service.gd")

func _init() -> void:
	print("==========================================================")
	print("STARTING RESPONSE CENTER THREADING & ACTIONS TEST SUITE")
	print("==========================================================")

	var db_path = ProjectSettings.globalize_path("user://test_rc_threading.db")
	if FileAccess.file_exists(db_path):
		DirAccess.remove_absolute(db_path)

	var db = SQLiteDatabaseScript.new(db_path)
	var mig_runner = MigrationsRunnerScript.new(db)
	var mig_res = mig_runner.run_migrations()
	if not mig_res["success"]:
		print("FAIL: Migrations failed: ", mig_res["error"])
		quit(1)
		return

	var com_service = CommunicationsServiceScript.new(db)

	# ----------------------------------------------------
	# TEST 1: Phone Normalization Across 5 Format Variants
	# ----------------------------------------------------
	var v1 = CommunicationsServiceScript.normalize_phone_digits("8649344080")
	var v2 = CommunicationsServiceScript.normalize_phone_digits("(864) 934-4080")
	var v3 = CommunicationsServiceScript.normalize_phone_digits("864-934-4080")
	var v4 = CommunicationsServiceScript.normalize_phone_digits("+1 864 934 4080")
	var v5 = CommunicationsServiceScript.normalize_phone_digits("+18649344080")

	if v1 != "8649344080" or v2 != "8649344080" or v3 != "8649344080" or v4 != "8649344080" or v5 != "8649344080":
		print("FAIL: Phone digit normalization failed. Got: ", [v1, v2, v3, v4, v5])
		quit(1)
		return
	print("PASS 1/8: Phone digit normalization handles all 5 format variants.")

	# ----------------------------------------------------
	# TEST 2: Single-Match Automatic Person Name Matching
	# ----------------------------------------------------
	db.execute("INSERT INTO people (id, person_uuid, human_id, first_name, last_name, primary_role, phone, sms_consent) VALUES (10, 'p_john', 'P-0010', 'John', 'Smith', 'Participant', '(864) 934-4080', 1);")

	# Test matching against +18649344080
	var res_match = com_service.resolve_person_by_phone("+18649344080")
	if not res_match.get("matched", false) or res_match.get("name") != "John Smith" or int(res_match.get("person_id")) != 10:
		print("FAIL: Single-match person resolution failed. Got: ", res_match)
		quit(1)
		return
	print("PASS 2/8: Single-match automatic person name matching verified.")

	# ----------------------------------------------------
	# TEST 3: Multi-Person Same-Number Safety (No Guessing)
	# ----------------------------------------------------
	db.execute("INSERT INTO people (id, person_uuid, human_id, first_name, last_name, primary_role, phone, sms_consent) VALUES (11, 'p_jane', 'P-0011', 'Jane', 'Smith', 'Parent', '864-934-4080', 1);")
	
	var res_ambig = com_service.resolve_person_by_phone("8649344080")
	if res_ambig.get("matched", false) or not res_ambig.get("ambiguous", false):
		print("FAIL: Multi-person same-number safety failed. Expected ambiguous=true, got: ", res_ambig)
		quit(1)
		return
	print("PASS 3/8: Multi-person same-number safety (no guessing) verified.")

	# Clean up duplicate person 11 for remaining tests
	db.execute("DELETE FROM people WHERE id = 11;")

	# ----------------------------------------------------
	# TEST 4: Unknown Number Handling
	# ----------------------------------------------------
	var res_unk = com_service.resolve_person_by_phone("+15095559999")
	if res_unk.get("matched", false) or res_unk.get("ambiguous", false):
		print("FAIL: Unknown number resolution returned false match.")
		quit(1)
		return
	print("PASS 4/8: Unknown number handling verified.")

	# ----------------------------------------------------
	# TEST 5: SMS Card Consolidation (Multiple Texts -> 1 Card)
	# ----------------------------------------------------
	db.execute("INSERT INTO inbound_sms_log (message_sid, from_phone_e164, raw_body, follow_up_status, received_at) VALUES ('sms-001', '+18649344080', 'Hi, can I come Sunday?', 'Unassigned', datetime('now', '-30 minutes'));")
	db.execute("INSERT INTO inbound_sms_log (message_sid, from_phone_e164, raw_body, follow_up_status, received_at) VALUES ('sms-002', '864-934-4080', 'What time does it start?', 'Unassigned', datetime('now', '-10 minutes'));")

	var cards = com_service.get_voicemails()
	var sms_cards = []
	for c in cards:
		if c["item_type"] == "sms":
			sms_cards.append(c)

	if sms_cards.size() != 1:
		print("FAIL: SMS consolidation failed. Expected 1 consolidated card, got: ", sms_cards.size())
		quit(1)
		return

	var sms_c = sms_cards[0]
	if sms_c["caller_name"] != "John Smith" or sms_c["msg_count"] != 2 or sms_c["transcription"] != "What time does it start?":
		print("FAIL: Consolidated card data mismatch. Got: ", sms_c)
		quit(1)
		return
	print("PASS 5/8: Multiple SMS messages from same number consolidated into 1 active card.")

	# ----------------------------------------------------
	# TEST 6: 2-Way SMS Thread Chronological History
	# ----------------------------------------------------
	# Insert an outbound response into communications_log
	db.execute("INSERT INTO communications_log (message_uuid, recipient_person_id, recipient_name, recipient_contact, channel, message_body, status, sent_by_user, created_at) VALUES ('msg-out-1', 10, 'John Smith', '(864) 934-4080', 'SMS', 'Absolutely. We would love to have you.', 'sent', 'Real Life', datetime('now', '-20 minutes'));")

	var thread = com_service.get_sms_conversation_thread("8649344080")
	if thread.size() != 3:
		print("FAIL: Thread history length mismatch. Expected 3 messages, got: ", thread.size())
		quit(1)
		return

	if thread[0]["direction"] != "inbound" or thread[1]["direction"] != "outbound" or thread[2]["direction"] != "inbound":
		print("FAIL: Thread history chronological order mismatch. Got directions: ", [thread[0]["direction"], thread[1]["direction"], thread[2]["direction"]])
		quit(1)
		return
	print("PASS 6/8: 2-Way SMS thread history (inbound + outbound) chronologically ordered.")

	# ----------------------------------------------------
	# TEST 7: Reply Dispatch via send_message_atomic
	# ----------------------------------------------------
	var john_dict = {"id": 10, "first_name": "John", "last_name": "Smith", "phone": "(864) 934-4080", "sms_consent": 1}
	var reply_res = com_service.send_message_atomic(john_dict, "SMS", "Sunday service starts at 10:00 AM.", "Pastor Marcus")
	if not reply_res["success"]:
		print("FAIL: Reply dispatch failed: ", reply_res.get("error"))
		quit(1)
		return

	var updated_thread = com_service.get_sms_conversation_thread("8649344080")
	if updated_thread.size() != 4 or updated_thread[3]["body"] != "Sunday service starts at 10:00 AM.":
		print("FAIL: Outgoing reply was not properly recorded in conversation thread.")
		quit(1)
		return
	print("PASS 7/8: Reply dispatch via send_message_atomic logged and updated thread history.")

	# ----------------------------------------------------
	# TEST 8: Link Phone Functionality
	# ----------------------------------------------------
	db.execute("INSERT INTO inbound_sms_log (message_sid, from_phone_e164, raw_body, follow_up_status, received_at) VALUES ('sms-unk-1', '+15095551234', 'Hello from guest', 'Unassigned', datetime('now'));")
	var link_res = com_service.link_phone_to_person("+15095551234", 10)
	if not link_res["success"]:
		print("FAIL: link_phone_to_person failed: ", link_res.get("error"))
		quit(1)
		return

	var check_link_resolve = com_service.resolve_person_by_phone("+15095551234")
	if not check_link_resolve.get("matched", false) or check_link_resolve.get("name") != "John Smith":
		print("FAIL: After linking, person lookup failed to resolve new name.")
		quit(1)
		return
	print("PASS 8/8: Link contact functionality verified.")

	# Cleanup test db
	db = null
	if FileAccess.file_exists(db_path):
		DirAccess.remove_absolute(db_path)

	print("==========================================================")
	print("SUCCESS: RESPONSE CENTER THREADING & ACTIONS VERIFICATION PASSED")
	print("==========================================================")
	quit(0)
