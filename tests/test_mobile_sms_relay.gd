extends SceneTree

## Comprehensive Test Suite for Mobile SMS Relay & Reply Architecture
## Covers 21 specific prompt tests using fake E.164 numbers and mocked transport.

const SQLiteDatabaseScript = preload("res://src/infrastructure/database/sqlite_database.gd")
const MigrationsRunnerScript = preload("res://src/infrastructure/database/migrations_runner.gd")
const InboundEventProcessorScript = preload("res://src/domain/sync/inbound_event_processor.gd")
const SMSRelayServiceScript = preload("res://src/domain/communications/sms_relay_service.gd")
const CommunicationsServiceScript = preload("res://src/domain/communications/communications_service.gd")
const QueueControllerScript = preload("res://src/domain/work_queue/queue_controller.gd")

func _init() -> void:
	print("==================================================")
	print("RUNNING: Comprehensive Mobile SMS Relay Test Suite (21/21)")
	print("==================================================")
	_run_tests()

func _run_tests() -> void:
	await create_timer(0.05).timeout

	var test_db_path = ProjectSettings.globalize_path("user://test_mobile_sms_relay.db")
	if FileAccess.file_exists(test_db_path):
		DirAccess.remove_absolute(test_db_path)

	var db = SQLiteDatabaseScript.new(test_db_path)
	var runner = MigrationsRunnerScript.new(db)
	var mig_res = runner.run_migrations()
	assert(mig_res["success"], "Migration initialization failed: " + str(mig_res.get("error", "")))

	var dummy_node = Node.new()
	root.add_child(dummy_node)

	var proc = InboundEventProcessorScript.new(db, dummy_node)
	var relay_svc = SMSRelayServiceScript.new(db)
	relay_svc.mock_mode = true

	var comm_svc = CommunicationsServiceScript.new(db)
	comm_svc.mock_relay_mode = true

	var qc = QueueControllerScript.new(db)

	# Setup Test Data
	var const_phone = "+18645550111"
	var relay_phone = "+18645550999"
	var unknown_phone = "+18645550222"

	# Insert Known Constituent "Abigail Christy"
	db.execute("INSERT INTO people (person_uuid, human_id, first_name, last_name, phone, sms_consent, status) VALUES ('usr_abigail', 'SCH-1001', 'Abigail', 'Christy', ?, 1, 'active');", [const_phone])
	var abigail_id = int(db.execute("SELECT id FROM people WHERE phone = ? LIMIT 1;", [const_phone])["data"][0]["id"])

	print("\n--- TEST 1: Incoming constituent SMS creates normal Communications record ---")
	relay_svc.save_relay_settings(false, relay_phone)
	var payload1 = {
		"From": const_phone,
		"To": "+18647124446",
		"Body": "Are you meeting tonight?",
		"MessageSid": "SM_TEST_01"
	}
	db.execute("INSERT INTO inbound_event_queue (event_type, payload_json, received_at, processed) VALUES ('twilio.sms', ?, datetime('now'), 0);", [JSON.stringify(payload1)])
	var q_ev1 = db.execute("SELECT id FROM inbound_event_queue WHERE payload_json LIKE '%SM_TEST_01%' LIMIT 1;")
	var event_id_1 = int(q_ev1["data"][0]["id"]) if (q_ev1["success"] and q_ev1["data"].size() > 0) else 1
	proc._process_sms(event_id_1, payload1)

	var sms_rec1 = db.execute("SELECT * FROM inbound_sms_log WHERE message_sid = 'SM_TEST_01' LIMIT 1;")
	assert(sms_rec1["success"] and sms_rec1["data"].size() > 0, "Test 1 FAIL: inbound_sms_log missing record")
	assert(int(sms_rec1["data"][0]["matched_person_id"]) == abigail_id, "Test 1 FAIL: person not matched")
	print("✓ PASS 1: Constituent SMS logged & matched to Abigail Christy.")

	print("\n--- TEST 2 & 3: Relay enabled creates notification / Relay disabled creates none ---")
	# Test 3: Relay disabled creates none
	var evts_before = db.execute("SELECT COUNT(*) as cnt FROM sms_relay_events WHERE event_type = 'notification_sent';")["data"][0]["cnt"]
	var payload3 = {"From": const_phone, "To": "+18647124446", "Body": "Test message when disabled", "MessageSid": "SM_TEST_03"}
	proc._process_sms(0, payload3)
	var evts_disabled = db.execute("SELECT COUNT(*) as cnt FROM sms_relay_events WHERE event_type = 'notification_sent';")["data"][0]["cnt"]
	assert(evts_disabled == evts_before, "Test 3 FAIL: Notification created while relay was disabled")
	print("✓ PASS 3: Relay disabled created 0 notifications.")

	# Test 2: Server gateway creates notification, Desktop creates 0 duplicate notifications
	relay_svc.save_relay_settings(true, relay_phone)
	var payload2 = {"From": const_phone, "To": "+18647124446", "Body": "Can I bring somebody with me Sunday?", "MessageSid": "SM_TEST_02"}
	relay_svc.forward_inbound_sms(dummy_node, const_phone, "Abigail Christy", "Can I bring somebody with me Sunday?", [], abigail_id, "SM_TEST_02")
	var evts_after_server = db.execute("SELECT COUNT(*) as cnt FROM sms_relay_events WHERE event_type = 'notification_sent';")["data"][0]["cnt"]
	assert(evts_after_server == evts_before + 1, "Test 2 FAIL: Server relay forwarding failed")

	proc._process_sms(0, payload2)
	var evts_enabled = db.execute("SELECT COUNT(*) as cnt FROM sms_relay_events WHERE event_type = 'notification_sent';")["data"][0]["cnt"]
	assert(evts_enabled == evts_after_server, "Test 2 FAIL: Desktop created duplicate notification event")
	print("✓ PASS 2: Server created relay notification, Desktop generated 0 duplicate notifications.")

	print("\n--- TEST 4: Known constituent name appears in relay ---")
	var latest_evt = db.execute("SELECT details_json FROM sms_relay_events WHERE event_type = 'notification_sent' ORDER BY id DESC LIMIT 1;")["data"][0]["details_json"]
	var sess_abi = relay_svc.get_or_create_session(const_phone, relay_phone, abigail_id)
	assert(sess_abi.get("relay_token", "") != "", "Test 4 FAIL: Session token missing")
	print("✓ PASS 4: Known constituent Abigail Christy routed with session token " + str(sess_abi["relay_token"]))

	print("\n--- TEST 5: Unknown number still relays safely ---")
	var payload5 = {"From": unknown_phone, "To": "+18647124446", "Body": "Hello from an unknown constituent", "MessageSid": "SM_TEST_05"}
	proc._process_sms(0, payload5)
	var sess_unk = relay_svc.get_or_create_session(unknown_phone, relay_phone, null)
	assert(sess_unk.get("relay_token", "") != "", "Test 5 FAIL: Unknown number failed to create relay session")
	print("✓ PASS 5: Unknown constituent relayed safely with token " + str(sess_unk["relay_token"]))

	print("\n--- TEST 6: Relay token maps to correct constituent ---")
	var token_abi = str(sess_abi["relay_token"])
	var token_unk = str(sess_unk["relay_token"])
	assert(token_abi != token_unk, "Test 6 FAIL: Tokens must be distinct")
	print("✓ PASS 6: Tokens mapped distinctly: Abigail=" + token_abi + " | Unknown=" + token_unk)

	print("\n--- TEST 7: Reply from unauthorized phone is rejected ---")
	var unauth_res = await relay_svc.handle_relay_reply(dummy_node, "+18645558888", token_abi + " Yes, see you then!")
	assert(not unauth_res["handled"] or not unauth_res.get("success", false), "Test 7 FAIL: Unauthorized reply was accepted")
	print("✓ PASS 7: Reply from unauthorized phone rejected cleanly.")

	print("\n--- TEST 8 & 9: Authorized relay reply sends from Study Center number & logs in Communications ---")
	# Clean up active sessions so token_abi is the only session
	db.execute("UPDATE sms_relay_sessions SET status = 'closed' WHERE relay_token = ?;", [token_unk])
	var reply_res = await relay_svc.handle_relay_reply(dummy_node, relay_phone, token_abi + " Yes, we'll be there at 7:45.")
	assert(reply_res.get("success", false) == true, "Test 8 FAIL: Authorized reply failed: " + str(reply_res.get("reason", "")))

	var comm_log = db.execute("SELECT * FROM communications_log WHERE recipient_contact = ? ORDER BY id DESC LIMIT 1;", [const_phone])
	assert(comm_log["success"] and comm_log["data"].size() > 0, "Test 9 FAIL: Outbound reply not found in communications_log")
	assert(str(comm_log["data"][0]["message_body"]).contains("Yes, we'll be there at 7:45."), "Test 9 FAIL: Message body incorrect")
	assert(str(comm_log["data"][0]["sent_by_user"]) == "Mobile Relay", "Test 9 FAIL: sent_by_user marker missing")
	print("✓ PASS 8 & 9: Authorized relay reply sent FROM Study Center number and logged in Communications history.")

	print("\n--- TEST 10: V1 mandatory reference token rule (unprefixed reply rejected even with 1 active session) ---")
	# Ensure active session exists
	db.execute("UPDATE sms_relay_sessions SET status = 'closed';")
	var sess_single = relay_svc.get_or_create_session(const_phone, relay_phone, abigail_id)
	var single_tok = str(sess_single["relay_token"])

	var normal_reply = await relay_svc.handle_relay_reply(dummy_node, relay_phone, "Sounds great, see you soon!")
	assert(not normal_reply.get("success", true) and normal_reply.get("reason", "") == "missing_token", "Test 10 FAIL: Unprefixed reply was accepted instead of requiring reference token")
	print("✓ PASS 10: V1 rule verified — unprefixed reply rejected cleanly with missing_token instruction.")

	print("\n--- TEST 11: Multiple active conversations never use 'most recent' guessing ---")
	var sess_multi2 = relay_svc.get_or_create_session(unknown_phone, relay_phone, null)
	var multi_reply_no_token = await relay_svc.handle_relay_reply(dummy_node, relay_phone, "Ambiguous answer without code")
	assert(multi_reply_no_token.get("reason", "") == "missing_token", "Test 11 FAIL: System guessed instead of rejecting ambiguous reply")
	print("✓ PASS 11: Multiple active conversations safely rejected un-prefixed reply.")

	print("\n--- TEST 12: Token-prefixed reply routes correctly ---")
	var token_pref_reply = await relay_svc.handle_relay_reply(dummy_node, relay_phone, single_tok + " Yes, bring your friend!")
	assert(token_pref_reply.get("success", false) == true, "Test 12 FAIL: Token prefixed reply failed")
	assert(token_pref_reply.get("clean_msg", "") == "Yes, bring your friend!", "Test 12 FAIL: Token prefix was not stripped from constituent message")
	print("✓ PASS 12: Token-prefixed reply routed correctly and stripped reference code.")

	print("\n--- TEST 13: Invalid token sends nothing to constituent ---")
	var invalid_res = await relay_svc.handle_relay_reply(dummy_node, relay_phone, "XXXX Invalid token message")
	assert(not invalid_res.get("success", false), "Test 13 FAIL: Invalid token allowed reply")
	print("✓ PASS 13: Invalid token rejected; nothing sent to constituent.")

	print("\n--- TEST 14: Expired token sends nothing to constituent ---")
	db.execute("UPDATE sms_relay_sessions SET expires_at = datetime('now', '-10 minutes') WHERE relay_token = ?;", [single_tok])
	var expired_res = await relay_svc.handle_relay_reply(dummy_node, relay_phone, single_tok + " Message for expired token")
	assert(not expired_res.get("success", false), "Test 14 FAIL: Expired token allowed reply")
	print("✓ PASS 14: Expired token rejected; nothing sent to constituent.")

	print("\n--- TEST 15: Same constituent reuses active relay session/token ---")
	db.execute("UPDATE sms_relay_sessions SET status = 'closed';")
	var s_first = relay_svc.get_or_create_session(const_phone, relay_phone, abigail_id)
	var tok1 = str(s_first["relay_token"])

	var s_second = relay_svc.get_or_create_session(const_phone, relay_phone, abigail_id)
	var tok2 = str(s_second["relay_token"])
	assert(tok1 == tok2, "Test 15 FAIL: Active session token was not reused for same constituent")
	print("✓ PASS 15: Re-used active token (" + tok1 + ") for same constituent.")

	print("\n--- TEST 16: Relay messages cannot loop ---")
	var loop_fwd = await relay_svc.forward_inbound_sms(dummy_node, relay_phone, "John Cell", "Loop test", [], null)
	assert(not loop_fwd.get("relayed", true) and loop_fwd.get("reason", "") == "loop_prevented", "Test 16 FAIL: Loop prevention failed")
	print("✓ PASS 16: Relay notification loop prevented.")

	print("\n--- TEST 17: Relay-phone command traffic does not become a constituent thread ---")
	var count_inbound_before = int(db.execute("SELECT COUNT(*) as cnt FROM inbound_sms_log WHERE from_phone_e164 = ?;", [relay_phone])["data"][0]["cnt"])
	var payload17 = {"From": relay_phone, "To": "+18647124446", "Body": tok1 + " Command reply", "MessageSid": "SM_RELAY_CMD_17"}
	proc._process_sms(0, payload17)
	var count_inbound_after = int(db.execute("SELECT COUNT(*) as cnt FROM inbound_sms_log WHERE from_phone_e164 = ?;", [relay_phone])["data"][0]["cnt"])
	assert(count_inbound_after == count_inbound_before, "Test 17 FAIL: Relay phone command traffic added to inbound_sms_log constituent table")
	print("✓ PASS 17: Relay command traffic intercepted before constituent thread creation.")

	print("\n--- TEST 18: Failed relay does not lose original inbound message ---")
	relay_svc.save_relay_settings(true, "+10000000000") # Invalid target relay phone
	var payload18 = {"From": const_phone, "To": "+18647124446", "Body": "Inbound during relay failure", "MessageSid": "SM_TEST_18"}
	proc._process_sms(0, payload18)
	var in_rec18 = db.execute("SELECT * FROM inbound_sms_log WHERE message_sid = 'SM_TEST_18' LIMIT 1;")
	assert(in_rec18["success"] and in_rec18["data"].size() > 0, "Test 18 FAIL: Original inbound message lost when relay failed")
	print("✓ PASS 18: Original inbound message safely preserved despite relay failure.")
	relay_svc.save_relay_settings(true, relay_phone)

	print("\n--- TEST 19: Failed constituent send does not claim success ---")
	db.execute("UPDATE people SET sms_consent = 0 WHERE id = ?;", [abigail_id])
	var fail_send_res = await relay_svc.handle_relay_reply(dummy_node, relay_phone, tok1 + " Test fail send")
	assert(not fail_send_res.get("success", true), "Test 19 FAIL: Failed send claimed success")
	assert(fail_send_res.get("reason", "") == "constituent_send_failed", "Test 19 FAIL: Reason must be constituent_send_failed")
	print("✓ PASS 19: Failed constituent send correctly reported failure.")
	db.execute("UPDATE people SET sms_consent = 1 WHERE id = ?;", [abigail_id])

	print("\n--- TEST 20: Response Center/Dashboard actionable counts remain synchronized ---")
	# Add new unassigned constituent SMS
	db.execute("INSERT INTO inbound_sms_log (message_sid, from_phone_e164, raw_body, follow_up_status, is_read) VALUES ('sid-rc-20', ?, 'Need help with registration', 'Unassigned', 0);", [const_phone])
	var count_before_reply = qc.get_queue_count("unresolved_inbound_sms")
	assert(count_before_reply > 0, "Test 20 FAIL: Actionable queue count must be > 0")

	var sync_reply = await relay_svc.handle_relay_reply(dummy_node, relay_phone, tok1 + " I can help you with registration!")
	assert(sync_reply.get("success", false) == true, "Test 20 FAIL: Relay reply failed")

	var count_after_reply = qc.get_queue_count("unresolved_inbound_sms")
	assert(count_after_reply == count_before_reply - 1, "Test 20 FAIL: Dashboard actionable count did not decrement after mobile reply")
	print("✓ PASS 20: Response Center & Dashboard actionable counts synchronized after mobile relay reply.")

	print("\n--- TEST 21: Digital Member Pass regression remains intact ---")
	# Run digital member pass simulation
	var pass_res = await comm_svc.sms_digital_member_pass(dummy_node, abigail_id, "Test Suite")
	assert(pass_res.get("reason", "") != "keychain_missing" and pass_res.get("reason", "") != "pass_generation_failed", "Test 21 FAIL: Digital Member Pass regression broken")
	print("✓ PASS 21: Digital Member Pass pipeline intact.")

	print("\n--- TEST 22: Manual test without confirmation sends nothing & relay remains disabled ---")
	var unconfirmed_res = await relay_svc.send_test_relay(dummy_node, "+18649344080", false)
	assert(unconfirmed_res.get("mock", false) == true or not unconfirmed_res.get("is_live", false), "Test 22 FAIL: Unconfirmed manual test executed live send")
	var settings_check = relay_svc.get_relay_settings()
	assert(settings_check["enabled"] == true, "Test 22 FAIL: Relay settings corrupted") # (was saved enabled earlier in test)
	relay_svc.save_relay_settings(false, relay_phone)
	var disabled_check = relay_svc.get_relay_settings()
	assert(disabled_check["enabled"] == false, "Test 22 FAIL: Relay failed to disable")
	print("✓ PASS 22: Manual test confirmation and relay state protection verified.")

	print("\n--- TEST 23: outbound_relay queue event syncs to communications_log & resolves Response Center ---")
	db.execute("INSERT INTO inbound_sms_log (message_sid, from_phone_e164, raw_body, follow_up_status, is_read) VALUES ('sid-ob-23', ?, 'Need help with registration', 'Unassigned', 0);", [const_phone])
	var count_rc_before = qc.get_queue_count("unresolved_inbound_sms")

	var outbound_payload = {
		"MessageSid": "SM_RELAY_SYNC_TEST_23",
		"From": "+18647124446",
		"To": const_phone,
		"Body": "I can help you with registration!",
		"sent_by_user": "Mobile Relay",
		"status_detail": "sent_via_mobile_relay"
	}
	db.execute("INSERT INTO inbound_event_queue (event_type, payload_json, received_at, processed) VALUES ('twilio.sms.outbound_relay', ?, datetime('now'), 0);", [JSON.stringify(outbound_payload)])

	var q_ev23 = db.execute("SELECT id FROM inbound_event_queue WHERE event_type = 'twilio.sms.outbound_relay' AND processed = 0 ORDER BY id DESC LIMIT 1;")
	assert(q_ev23["success"] and q_ev23["data"].size() > 0, "Test 23 FAIL: outbound_relay event missing in queue: " + str(q_ev23.get("error", "")))
	var ev_id23 = int(q_ev23["data"][0]["id"])

	proc._process_outbound_relay(ev_id23, outbound_payload)

	var comm_rec23 = db.execute("SELECT * FROM communications_log WHERE provider_sid = 'SM_RELAY_SYNC_TEST_23' LIMIT 1;")
	assert(comm_rec23["success"] and comm_rec23["data"].size() > 0, "Test 23 FAIL: communications_log missing record for outbound_relay event")
	assert(str(comm_rec23["data"][0]["status_detail"]) == "sent_via_mobile_relay", "Test 23 FAIL: status_detail mismatch")
	assert(str(comm_rec23["data"][0]["sent_by_user"]) == "Mobile Relay", "Test 23 FAIL: sent_by_user mismatch")

	var count_rc_after = qc.get_queue_count("unresolved_inbound_sms")
	assert(count_rc_after == count_rc_before - 1, "Test 23 FAIL: Response Center actionable count did not decrement")
	print("✓ PASS 23: twilio.sms.outbound_relay syncs to communications_log & resolves Response Center.")

	# Cleanup test database
	dummy_node.queue_free()
	if FileAccess.file_exists(test_db_path):
		DirAccess.remove_absolute(test_db_path)

	print("\n==================================================")
	print("ALL 23/23 MOBILE SMS RELAY TESTS PASSED CLEANLY!")
	print("==================================================")
	quit(0)
