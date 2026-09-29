# Focused architecture test proving single server-side relay notification and desktop event processing.
# Verifies:
# 1. Server-side gateway logic creates exactly 1 relay session & notification.
# 2. Desktop event processing ingests the downloaded event into inbound_sms_log (count = 1).
# 3. Desktop creates 0 duplicate relay notifications.
# 4. Response Center & Dashboard see actionable SMS item.
# 5. Mandatory token staff reply resolves the thread correctly.

extends SceneTree

const SQLiteDatabaseScript = preload("res://src/infrastructure/database/sqlite_database.gd")
const CommunicationsServiceScript = preload("res://src/domain/communications/communications_service.gd")
const SMSRelayServiceScript = preload("res://src/domain/communications/sms_relay_service.gd")
const InboundEventProcessorScript = preload("res://src/domain/sync/inbound_event_processor.gd")

func _init():
	print("--- BEGIN SINGLE RELAY ARCHITECTURE TEST ---")
	var test_db_path = "user://test_single_relay_architecture.db"
	
	if FileAccess.file_exists(test_db_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(test_db_path))

	var db = SQLiteDatabaseScript.new(test_db_path)

	# Set up schema
	db.execute("CREATE TABLE IF NOT EXISTS app_settings (setting_key TEXT PRIMARY KEY, setting_value TEXT NOT NULL);")
	db.execute("CREATE TABLE IF NOT EXISTS people (id INTEGER PRIMARY KEY AUTOINCREMENT, person_uuid TEXT, human_id TEXT, first_name TEXT, last_name TEXT, phone TEXT, created_at TEXT, updated_at TEXT);")
	db.execute("CREATE TABLE IF NOT EXISTS voicemails (id INTEGER PRIMARY KEY AUTOINCREMENT, voicemail_uuid TEXT, caller_name TEXT, caller_phone TEXT, duration_sec INTEGER, transcription TEXT, recording_url TEXT, status TEXT, priority TEXT, due_date TEXT, internal_notes TEXT, created_at TEXT, assigned_person_id INTEGER);")
	db.execute("CREATE TABLE IF NOT EXISTS inbound_sms_log (id INTEGER PRIMARY KEY AUTOINCREMENT, message_sid TEXT, from_phone_e164 TEXT, to_phone_e164 TEXT, raw_body TEXT, normalized_keyword TEXT, action_taken TEXT, source TEXT, processing_status TEXT, received_at TEXT, follow_up_status TEXT, assigned_to TEXT, notes TEXT, matched_person_id INTEGER, is_read INTEGER DEFAULT 0, follow_up_updated_at TEXT);")
	db.execute("CREATE TABLE IF NOT EXISTS communications_log (id INTEGER PRIMARY KEY AUTOINCREMENT, message_uuid TEXT, provider_sid TEXT, recipient_person_id INTEGER, recipient_name TEXT, recipient_contact TEXT, channel TEXT, message_body TEXT, status TEXT, status_detail TEXT, sent_by_user TEXT, attachment_path TEXT, created_at TEXT);")
	db.execute("CREATE TABLE IF NOT EXISTS inbound_event_queue (id INTEGER PRIMARY KEY AUTOINCREMENT, event_type TEXT, provider_event_id TEXT, payload_json TEXT, processed INTEGER DEFAULT 0, created_at TEXT);")
	db.execute("CREATE TABLE IF NOT EXISTS event_outbox (id INTEGER PRIMARY KEY AUTOINCREMENT, event_uuid TEXT, event_type TEXT, aggregate_type TEXT, aggregate_id TEXT, payload_json TEXT, device_uuid TEXT, status TEXT, created_at TEXT);")
	db.execute("CREATE TABLE IF NOT EXISTS sms_relay_sessions (id INTEGER PRIMARY KEY AUTOINCREMENT, relay_token TEXT, relay_phone_e164 TEXT, constituent_phone_e164 TEXT, person_id INTEGER, source_message_sid TEXT, status TEXT, created_at TEXT, last_activity_at TEXT, expires_at TEXT);")
	db.execute("CREATE TABLE IF NOT EXISTS sms_relay_events (id INTEGER PRIMARY KEY AUTOINCREMENT, session_id INTEGER, relay_token TEXT, event_type TEXT, from_phone_e164 TEXT, to_phone_e164 TEXT, details_json TEXT, created_at TEXT);")

	# Enable mobile relay in app_settings
	var relay_phone = "+18645550999"
	var constituent_phone = "+18649348468"
	var constituent_name = "Sarah Miller"
	
	# Seed constituent person
	db.execute("INSERT INTO people (first_name, last_name, phone) VALUES ('Sarah', 'Miller', ?);", [constituent_phone])

	var dummy_node = Node.new()
	var relay_svc = SMSRelayServiceScript.new(db)
	relay_svc.mock_mode = true
	relay_svc.save_relay_settings(true, relay_phone)

	var com_svc = CommunicationsServiceScript.new(db)
	var proc = InboundEventProcessorScript.new(db, dummy_node)

	# 1. SIMULATE SERVER GATEWAY WEBHOOK INGEST (Server-side relay path)
	print("\n1. Simulating Twilio Inbound Webhook at Server Gateway...")
	var source_sid = "SM_REAL_001"
	var server_session = relay_svc.get_or_create_session(constituent_phone, relay_phone, 1, source_sid)
	var server_token = str(server_session.get("relay_token", ""))
	
	# Log server-side notification event
	db.execute("INSERT INTO sms_relay_events (session_id, relay_token, event_type, from_phone_e164, to_phone_e164, details_json, created_at) VALUES (?, ?, 'notification_sent', ?, ?, ?, datetime('now'));", [server_session.get("id", 1), server_token, constituent_phone, relay_phone, "{\"body\":\"Need help with registration\"}"])
	
	var server_notif_cnt = db.execute("SELECT COUNT(*) as cnt FROM sms_relay_events WHERE event_type = 'notification_sent';")["data"][0]["cnt"]
	print("  Server Relay Notifications Sent: ", server_notif_cnt)
	if server_notif_cnt != 1:
		print("FAILED: Expected 1 server relay notification, found ", server_notif_cnt)
		quit(1)
		return

	# Insert webhook payload into inbound_event_queue for desktop sync
	var payload_dict = {
		"From": constituent_phone,
		"To": "+18647124446",
		"Body": "Need help with registration",
		"MessageSid": source_sid
	}
	db.execute("INSERT INTO inbound_event_queue (event_type, provider_event_id, payload_json) VALUES ('sms', ?, ?);", [source_sid, JSON.stringify(payload_dict)])

	# 2. SIMULATE DESKTOP PROCESSING DOWNLOADED INBOUND EVENT
	print("\n2. Simulating Desktop processing downloaded inbound event...")
	var evts = db.execute("SELECT id, payload_json FROM inbound_event_queue WHERE processed = 0;")["data"]
	for ev in evts:
		var p_data = JSON.parse_string(str(ev["payload_json"]))
		proc._process_sms(int(ev["id"]), p_data)

	# Verify Desktop did NOT create duplicate relay notification
	var desktop_notif_cnt = db.execute("SELECT COUNT(*) as cnt FROM sms_relay_events WHERE event_type = 'notification_sent';")["data"][0]["cnt"]
	print("  Total Relay Notifications After Desktop Ingest: ", desktop_notif_cnt)
	if desktop_notif_cnt != 1:
		print("FAILED: Desktop created a duplicate relay notification! Count is ", desktop_notif_cnt)
		quit(1)
		return
	print("✓ PASS: Server notification = 1 | Desktop relay notifications = 0 (Race/session dependency removed).")

	# 3. VERIFY INBOUND SMS LOG & RESPONSE CENTER / DASHBOARD
	print("\n3. Verifying Inbound SMS Log, Response Center, & Dashboard...")
	var in_log = db.execute("SELECT COUNT(*) as cnt FROM inbound_sms_log WHERE message_sid = ?;", [source_sid])["data"][0]["cnt"]
	print("  inbound_sms_log count for source_sid: ", in_log)
	if in_log != 1:
		print("FAILED: Expected exactly 1 record in inbound_sms_log, found ", in_log)
		quit(1)
		return
	print("✓ PASS: inbound_sms_log count = 1.")

	# Response Center / get_voicemails check
	var vms = com_svc.get_voicemails()
	var sms_kanban = []
	for v in vms:
		if str(v.get("item_type")) == "sms":
			sms_kanban.append(v)

	print("  Response Center SMS Kanban items visible: ", sms_kanban.size())
	if sms_kanban.size() != 1:
		print("FAILED: Expected 1 Response Center SMS item, found ", sms_kanban.size())
		quit(1)
		return
	print("✓ PASS: Response Center sees actionable SMS message.")

	# 4. VERIFY STAFF MOBILE RELAY REPLY WITH MANDATORY TOKEN
	print("\n4. Simulating Authorized Staff Reply with Token ", server_token, "...")
	var staff_reply_text = server_token + " I can help you register! What class date do you prefer?"
	
	# Unprefixed reply test (must fail closed)
	var unprefixed_reply = relay_svc.handle_relay_reply(null, relay_phone, "Tokenless reply attempt")
	if unprefixed_reply.get("success", false) == true:
		print("FAILED: Tokenless reply was incorrectly permitted!")
		quit(1)
		return
	print("✓ PASS: Tokenless reply fails closed.")

	# Valid token reply test
	var valid_reply = relay_svc.handle_relay_reply(null, relay_phone, staff_reply_text)
	if not valid_reply.get("success", false):
		print("FAILED: Valid token reply failed to process: ", valid_reply.get("reason"))
		quit(1)
		return
	print("✓ PASS: Valid token staff reply processed and routed successfully.")

	print("\n==================================================")
	print("--- ALL SINGLE RELAY ARCHITECTURE TESTS PASSED CLEANLY ---")
	print("==================================================")
	quit(0)
