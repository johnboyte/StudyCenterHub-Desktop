# Focused regression test for SMS message and conversation thread deletion.
# Verifies atomic deletion across inbound_sms_log, communications_log,
# inbound_event_queue, and sms_relay_sessions.

extends SceneTree

const SQLiteDatabaseScript = preload("res://src/infrastructure/database/sqlite_database.gd")
const CommunicationsServiceScript = preload("res://src/domain/communications/communications_service.gd")

func _init():
	print("--- BEGIN SMS DELETE WORKFLOW TEST ---")
	var test_db_path = "user://test_sms_delete_workflow.db"
	
	if FileAccess.file_exists(test_db_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(test_db_path))

	var db = SQLiteDatabaseScript.new(test_db_path)

	# Set up test tables
	db.execute("CREATE TABLE IF NOT EXISTS people (id INTEGER PRIMARY KEY AUTOINCREMENT, person_uuid TEXT, human_id TEXT, first_name TEXT, last_name TEXT, phone TEXT, created_at TEXT, updated_at TEXT);")
	db.execute("CREATE TABLE IF NOT EXISTS voicemails (id INTEGER PRIMARY KEY AUTOINCREMENT, voicemail_uuid TEXT, caller_name TEXT, caller_phone TEXT, duration_sec INTEGER, transcription TEXT, recording_url TEXT, status TEXT, priority TEXT, due_date TEXT, internal_notes TEXT, created_at TEXT, assigned_person_id INTEGER);")
	db.execute("CREATE TABLE IF NOT EXISTS inbound_sms_log (id INTEGER PRIMARY KEY AUTOINCREMENT, message_sid TEXT, from_phone_e164 TEXT, to_phone_e164 TEXT, raw_body TEXT, received_at TEXT, follow_up_status TEXT, assigned_to TEXT, notes TEXT, matched_person_id INTEGER, is_read INTEGER DEFAULT 0, follow_up_updated_at TEXT);")
	db.execute("CREATE TABLE IF NOT EXISTS communications_log (id INTEGER PRIMARY KEY AUTOINCREMENT, message_uuid TEXT, recipient_person_id INTEGER, recipient_name TEXT, recipient_contact TEXT, channel TEXT, message_body TEXT, status TEXT, status_detail TEXT, sent_by_user TEXT, created_at TEXT);")
	db.execute("CREATE TABLE IF NOT EXISTS inbound_event_queue (id INTEGER PRIMARY KEY AUTOINCREMENT, event_type TEXT, provider_event_id TEXT, payload_json TEXT, processed INTEGER DEFAULT 0, created_at TEXT);")
	db.execute("CREATE TABLE IF NOT EXISTS sms_relay_sessions (id INTEGER PRIMARY KEY AUTOINCREMENT, relay_token TEXT, relay_phone_e164 TEXT, constituent_phone_e164 TEXT, person_id INTEGER, source_message_sid TEXT, status TEXT, created_at TEXT, last_activity_at TEXT, expires_at TEXT);")

	var com_service = CommunicationsServiceScript.new(db)
	var test_phone = "+18649348468"

	# Seed 2 inbound messages for test_phone
	db.execute("INSERT INTO inbound_sms_log (message_sid, from_phone_e164, raw_body, received_at, follow_up_status) VALUES ('SMtest001', ?, 'First inbound message', '2026-09-27 12:00:00', 'new');", [test_phone])
	db.execute("INSERT INTO inbound_sms_log (message_sid, from_phone_e164, raw_body, received_at, follow_up_status) VALUES ('SMtest002', ?, 'Second inbound message', '2026-09-27 12:05:00', 'new');", [test_phone])

	# Seed 1 outbound message for test_phone
	db.execute("INSERT INTO communications_log (message_uuid, recipient_contact, channel, message_body, status, created_at) VALUES ('MSGout001', ?, 'SMS', 'Outbound reply to constituent', 'sent', '2026-09-27 12:02:00');", [test_phone])

	# Seed 1 inbound_event_queue entry
	db.execute("INSERT INTO inbound_event_queue (event_type, provider_event_id, payload_json) VALUES ('sms', 'SMtest001', '{\"From\":\"+18649348468\",\"Body\":\"First inbound message\"}');")

	# Seed 1 sms_relay_session entry
	db.execute("INSERT INTO sms_relay_sessions (relay_token, constituent_phone_e164, source_message_sid, status) VALUES ('tok_123', ?, 'SMtest001', 'active');", [test_phone])

	# Verify initial state
	var vms_before = com_service.get_voicemails()
	var thread_before = com_service.get_sms_conversation_thread(test_phone)
	print("Initial inbound count for test_phone: ", thread_before.size())
	if thread_before.size() != 3: # 2 inbound + 1 outbound
		print("FAILED: Expected 3 thread messages initially, found ", thread_before.size())
		quit(1)
		return

	# STEP 1: Delete SINGLE message 'SMtest001'
	print("Executing single message deletion for SMtest001...")
	var single_del_ok = com_service.delete_sms_message_atomic("SMtest001")
	if not single_del_ok:
		print("FAILED: delete_sms_message_atomic returned false")
		quit(1)
		return

	var thread_after_single = com_service.get_sms_conversation_thread(test_phone)
	print("Thread count after single message delete: ", thread_after_single.size())
	if thread_after_single.size() != 2:
		print("FAILED: Expected 2 remaining messages after single delete, found ", thread_after_single.size())
		quit(1)
		return

	# Check that SMtest001 is gone from inbound_event_queue and sms_relay_sessions
	var q_check = db.execute("SELECT id FROM inbound_event_queue WHERE provider_event_id = 'SMtest001';")
	if q_check["success"] and q_check["data"].size() > 0:
		print("FAILED: inbound_event_queue still contains SMtest001")
		quit(1)
		return

	var relay_check = db.execute("SELECT id FROM sms_relay_sessions WHERE source_message_sid = 'SMtest001';")
	if relay_check["success"] and relay_check["data"].size() > 0:
		print("FAILED: sms_relay_sessions still contains SMtest001")
		quit(1)
		return

	print("Single message deletion test PASSED.")

	# STEP 2: Delete ENTIRE CONVERSATION THREAD for test_phone
	print("Executing thread deletion for ", test_phone, "...")
	var thread_del_ok = com_service.delete_sms_conversation_thread_atomic(test_phone)
	if not thread_del_ok:
		print("FAILED: delete_sms_conversation_thread_atomic returned false")
		quit(1)
		return

	var thread_after_all = com_service.get_sms_conversation_thread(test_phone)
	print("Thread count after entire thread delete: ", thread_after_all.size())
	if thread_after_all.size() != 0:
		print("FAILED: Expected 0 messages after full thread delete, found ", thread_after_all.size())
		quit(1)
		return

	var vms_after = com_service.get_voicemails()
	var sms_vms_after = []
	for v in vms_after:
		if str(v.get("item_type")) == "sms":
			sms_vms_after.append(v)

	print("SMS Kanban cards remaining: ", sms_vms_after.size())
	if sms_vms_after.size() != 0:
		print("FAILED: Expected 0 SMS kanban cards, found ", sms_vms_after.size())
		quit(1)
		return

	print("--- ALL SMS DELETE WORKFLOW TESTS PASSED CLEANLY ---")
	quit(0)
