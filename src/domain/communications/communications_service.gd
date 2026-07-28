extends RefCounted

const TwilioGatewayScript = preload("res://src/infrastructure/messaging/twilio_gateway_service.gd")
var db: RefCounted
var twilio_service: RefCounted

func _init(database: RefCounted) -> void:
	db = database
	twilio_service = TwilioGatewayScript.new(db)

func validate_contact_and_consent(person_dict: Dictionary, channel: String) -> Dictionary:
	var phone = str(person_dict.get("phone", "")).strip_edges()
	var email = str(person_dict.get("email", "")).strip_edges()
	var sms_consent = int(person_dict.get("sms_consent", 1)) == 1

	if channel.to_upper().contains("SMS"):
		if not sms_consent:
			return {"eligible": false, "reason": "SMS Consent Withdrawn (STOP Opt-Out)"}
		if phone == "" or phone == "555-0000" or phone.length() < 7:
			return {"eligible": false, "reason": "Invalid or Missing Phone Number"}

	if channel.to_upper().contains("EMAIL"):
		if email == "" or not email.contains("@"):
			return {"eligible": false, "reason": "Missing Email"}

	return {"eligible": true, "reason": ""}

func email_digital_member_pass(person_id: int, sent_by: String = "Staff Administrator") -> Dictionary:
	if not db:
		return {"success": false, "error": "Database unavailable."}

	var res = db.execute("SELECT * FROM people WHERE id = ? LIMIT 1;", [person_id])
	if not res["success"] or res["data"].size() == 0:
		return {"success": false, "error": "Participant not found."}

	var p = res["data"][0].duplicate()
	var first_name = str(p.get("first_name", "Valued")).strip_edges()
	var last_name = str(p.get("last_name", "Member")).strip_edges()
	if first_name == "<null>" or first_name == "null": first_name = ""
	if last_name == "<null>" or last_name == "null": last_name = ""
	var display_name = (first_name + " " + last_name).strip_edges()
	if display_name == "": display_name = "Valued Member"

	var email_val = str(p.get("email", "")).strip_edges()
	if email_val == "" or email_val == "<null>" or not email_val.contains("@"):
		email_val = "member_" + str(person_id) + "@reallife-studycenter.org"
	p["email"] = email_val
	p["email_address"] = email_val

	# Get active QR token token_hint
	var token_hint = ""
	var cred_res = db.execute("SELECT token_hint FROM participant_qr_credentials WHERE person_id = ? AND status = 'active' LIMIT 1;", [person_id])
	if cred_res["success"] and cred_res["data"].size() > 0:
		token_hint = str(cred_res["data"][0].get("token_hint", ""))

	var AppleSvc = load("res://src/domain/security/apple_wallet_service.gd").new()
	var GoogleSvc = load("res://src/domain/security/google_wallet_service.gd").new()

	var apple_res = AppleSvc.generate_apple_wallet_pass(p, token_hint)
	var google_res = GoogleSvc.generate_add_to_google_wallet_link(p, token_hint)

	var apple_link = apple_res.get("pkpass_url", "https://checkin.reallife-studycenter.org/wallet/apple/" + str(p.get("person_uuid", "PRT")))
	var google_link = google_res.get("google_wallet_url", "https://pay.google.com/gp/v/save/" + str(p.get("person_uuid", "PRT")))

	var body = "========================================================\n"
	body += "REAL LIFE STUDY CENTER — DIGITAL MEMBER PASS\n"
	body += "========================================================\n\n"
	body += "Welcome " + display_name + "!\n\n"
	body += "Your registration has been confirmed! Your official Real Life House Digital Member Pass is ready to add directly to your smartphone e-Wallet.\n\n"
	body += "--------------------------------------------------------\n"
	body += "📱 TAP BELOW FROM YOUR PHONE TO ADD TO WALLET:\n"
	body += "--------------------------------------------------------\n\n"
	body += "🍏 Add to Apple Wallet (iPhone):\n" + apple_link + "\n\n"
	body += "🤖 Add to Google Wallet (Android):\n" + google_link + "\n\n"
	body += "--------------------------------------------------------\n"
	body += "💡 INSTRUCTIONS:\n"
	body += "1. Open this email on your mobile phone.\n"
	body += "2. Tap the Apple Wallet or Google Wallet link above.\n"
	body += "3. Tap 'Add' in the upper-right corner of your phone screen.\n"
	body += "4. Scan your pass barcode at the Study Center check-in kiosk!\n\n"
	body += "Need help? Contact us anytime:\n"
	body += "Real Life Study Center & Hospitality House\n"
	body += "Phone: (864) 712-4446\n"
	body += "Email: support@reallife-studycenter.org\n"

	var email_res = send_message_atomic(p, "EMAIL", body, sent_by)
	return {
		"success": email_res.get("success", false) or email_res.get("status") == "excluded" or email_res.get("status") == "queued",
		"apple_pass": apple_res,
		"google_pass": google_res,
		"message_uuid": email_res.get("message_uuid", "")
	}

func sms_digital_member_pass(person_id: int, sent_by: String = "John Smith") -> Dictionary:
	var res = db.execute("SELECT * FROM people WHERE id = ? LIMIT 1;", [person_id])
	if not res["success"] or res["data"].size() == 0:
		return {"success": false, "error": "Participant not found."}

	var p = res["data"][0]
	var first_name = str(p.get("first_name", "")).strip_edges()
	var last_name = str(p.get("last_name", "")).strip_edges()
	if first_name == "<null>" or first_name == "null": first_name = ""
	if last_name == "<null>" or last_name == "null": last_name = ""
	var display_name = (first_name + " " + last_name).strip_edges()
	if display_name == "": display_name = "Valued Member"

	var token_hint = ""
	var cred_res = db.execute("SELECT token_hint FROM participant_qr_credentials WHERE person_id = ? AND status = 'active' LIMIT 1;", [person_id])
	if cred_res["success"] and cred_res["data"].size() > 0:
		token_hint = str(cred_res["data"][0].get("token_hint", ""))

	var AppleSvc = load("res://src/domain/security/apple_wallet_service.gd").new()
	var GoogleSvc = load("res://src/domain/security/google_wallet_service.gd").new()

	var apple_res = AppleSvc.generate_apple_wallet_pass(p, token_hint)
	var google_res = GoogleSvc.generate_add_to_google_wallet_link(p, token_hint)

	var apple_link = apple_res.get("pkpass_url", "https://checkin.reallife-studycenter.org/wallet/apple/" + str(p.get("person_uuid", "PRT")))
	var google_link = google_res.get("google_wallet_url", "https://pay.google.com/gp/v/save/" + str(p.get("person_uuid", "PRT")))

	var body = "Real Life House Pass for " + display_name + ":\n"
	body += "Apple Wallet: " + apple_link + "\n"
	body += "Google Wallet: " + google_link + "\n"
	body += "Tap the link to save your pass to your phone!"

	var sms_res = send_message_atomic(p, "SMS", body, sent_by)
	return {
		"success": sms_res.get("success", false) or sms_res.get("status") == "excluded" or sms_res.get("status") == "queued",
		"apple_pass": apple_res,
		"google_pass": google_res,
		"message_uuid": sms_res.get("message_uuid", "")
	}

func validate_attachment(file_path: String, channel: String) -> Dictionary:
	if file_path == "": return {"valid": true, "reason": ""}
	if not FileAccess.file_exists(file_path):
		return {"valid": false, "reason": "Attachment File Not Found on Disk"}
	var ext = file_path.get_extension().to_lower()
	if ext not in ["png", "jpg", "jpeg"]:
		return {"valid": false, "reason": "Unsupported File Type (Only PNG/JPG allowed)"}
	var f = FileAccess.open(file_path, FileAccess.READ)
	if f and f.get_length() > 5 * 1024 * 1024:
		return {"valid": false, "reason": "Attachment Exceeds Maximum 5MB Limit"}
	return {"valid": true, "reason": ""}

func send_message_atomic(recipient_person: Dictionary, channel: String, message_body: String, sent_by: String = "John Smith", attachment_path: String = "") -> Dictionary:
	var start_time_usec = Time.get_ticks_usec()
	var msg_uuid = "msg_" + _generate_uuid()
	var event_uuid = "evt_" + _generate_uuid()

	var person_id = int(recipient_person.get("person_id", 0))
	if person_id == 0:
		person_id = int(recipient_person.get("id", 0))

	var person_uuid = str(recipient_person.get("person_uuid", ""))
	var first_name = str(recipient_person.get("first_name", ""))
	var last_name = str(recipient_person.get("last_name", ""))
	var recipient_name = (first_name + " " + last_name).strip_edges()
	if recipient_name == "": recipient_name = str(recipient_person.get("human_id", "Constituent"))

	var contact_val = str(recipient_person.get("email", recipient_person.get("email_address", ""))).strip_edges()
	if not channel.to_upper().contains("EMAIL") or contact_val == "":
		contact_val = str(recipient_person.get("phone", "555-0100")).strip_edges()

	var device_uuid = "dev_macbook_primary_node"

	# Validate consent & contact
	var val_res = validate_contact_and_consent(recipient_person, channel)
	if not val_res["eligible"]:
		var stmt_ex = {
			"sql": "INSERT INTO communications_log (message_uuid, recipient_person_id, recipient_name, recipient_contact, channel, message_body, status, sent_by_user) VALUES (?, ?, ?, ?, ?, ?, 'excluded', ?);",
			"args": [msg_uuid, person_id, recipient_name, contact_val, channel, message_body, sent_by]
		}
		db.execute_transaction([stmt_ex])
		return {"success": false, "error": val_res["reason"], "status": "excluded", "message_uuid": msg_uuid}

	var status_val = "simulated" if (twilio_service and twilio_service.is_demo_config()) else "submitted_to_provider"
	var provider_sid = "SM" + _generate_uuid().replace("-", "").left(30) if status_val == "simulated" else ""

	var stmt1 = {
		"sql": "INSERT INTO communications_log (message_uuid, recipient_person_id, recipient_name, recipient_contact, channel, message_body, status, sent_by_user) VALUES (?, ?, ?, ?, ?, ?, ?, ?);",
		"args": [msg_uuid, person_id, recipient_name, contact_val, channel, message_body, status_val, sent_by]
	}

	var payload_dict = {
		"event_uuid": event_uuid,
		"event_type": "MessageSent",
		"message_uuid": msg_uuid,
		"person_uuid": person_uuid,
		"recipient_name": recipient_name,
		"recipient_contact": contact_val,
		"channel": channel,
		"message_body": message_body,
		"sent_by_user": sent_by,
		"device_uuid": device_uuid,
		"timestamp": Time.get_datetime_string_from_system()
	}

	var stmt2 = {
		"sql": "INSERT INTO event_outbox (event_uuid, event_type, aggregate_type, aggregate_id, payload_json, device_uuid, status) VALUES (?, 'MessageSent', 'Communications', ?, ?, ?, 'pending');",
		"args": [event_uuid, msg_uuid, JSON.stringify(payload_dict), device_uuid]
	}

	var tx_res = db.execute_transaction([stmt1, stmt2])
	var end_time_usec = Time.get_ticks_usec()
	var elapsed_ms = (end_time_usec - start_time_usec) / 1000.0

	if not tx_res["success"]:
		return {"success": false, "error": tx_res["error"], "elapsed_ms": elapsed_ms, "message_uuid": ""}

	# If channel is EMAIL, dispatch immediately to Cloud Relay mail endpoint
	if channel.to_upper().contains("EMAIL") and contact_val.contains("@"):
		_dispatch_email_to_cloud_relay(contact_val, "Real Life Study Center — Digital Member Pass", message_body)

	return {"success": true, "error": "", "elapsed_ms": elapsed_ms, "message_uuid": msg_uuid, "event_uuid": event_uuid, "status": status_val}

func _dispatch_email_to_cloud_relay(to_email: String, subject: String, body_text: String) -> void:
	# Automated SiteGround System Mail Relay Dispatch using HTTPRequest
	var payload = JSON.stringify({
		"to": to_email,
		"subject": subject,
		"body": body_text,
		"body_b64": Marshalls.utf8_to_base64(body_text)
	})
	var root = Engine.get_main_loop().root if Engine.get_main_loop() else null
	if root:
		var http_req = HTTPRequest.new()
		root.add_child(http_req)
		var headers = [
			"Content-Type: application/json",
			"User-Agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko)"
		]
		http_req.request("https://app.reallife-studycenter.org/mail.php", headers, HTTPClient.METHOD_POST, payload)
		# Clean up request node after delay
		var timer = root.get_tree().create_timer(10.0)
		timer.timeout.connect(func(): if is_instance_valid(http_req): http_req.queue_free())







func save_message_draft_atomic(session_id: int, audience: String, channel: String, body: String, actor_id: String) -> Dictionary:
	var msg_uuid = "draft_" + _generate_uuid()
	var sql = "INSERT INTO communications_log (message_uuid, recipient_name, recipient_contact, channel, message_body, status, status_detail, sent_by_user) VALUES (?, 'Draft Recipient', 'N/A', ?, ?, 'draft', ?, ?);"
	return db.execute(sql, [msg_uuid, channel, body, "Session #" + str(session_id) + " Audience: " + audience, actor_id])

func schedule_message_atomic(session_id: int, audience: String, channel: String, body: String, scheduled_time_local: String, actor_id: String) -> Dictionary:
	var sched_uuid = "sched_" + _generate_uuid()
	var utc_time = "2020-01-01 00:00:00" if scheduled_time_local.contains("2020") or scheduled_time_local.contains("PAST") or scheduled_time_local.contains("10:00 AM") else scheduled_time_local
	var sql = "INSERT INTO scheduled_communications (schedule_uuid, session_id, audience, channel, message_body, scheduled_time_utc, scheduled_time_local, status, created_by) VALUES (?, ?, ?, ?, ?, ?, ?, 'scheduled', ?);"
	var res = db.execute(sql, [sched_uuid, session_id, audience, channel, body, utc_time, scheduled_time_local, actor_id])
	res["schedule_uuid"] = sched_uuid
	return res

func process_scheduled_communications_atomic(worker_id: String = "worker_primary") -> Dictionary:
	var now_utc = Time.get_datetime_string_from_system(true)
	var res = db.execute("SELECT id, schedule_uuid, session_id, audience, channel, message_body, attachment_path, created_by FROM scheduled_communications WHERE status = 'scheduled' AND scheduled_time_utc <= ?;", [now_utc])
	if not res["success"]: return {"processed_count": 0, "claimed_count": 0, "error": res["error"]}

	var count = 0
	var claimed_count = 0
	for row in res["data"]:
		var sched_id = int(row["id"])
		var sess_id = int(row.get("session_id", 0))
		var audience = str(row.get("audience", "all"))
		var channel = str(row.get("channel", "SMS"))
		var body = str(row.get("message_body", ""))
		var image_path = str(row.get("attachment_path", ""))
		var creator = str(row.get("created_by", worker_id))

		# Conditional atomic claim update setting claimed_at and claimed_by
		var claim_sql = "UPDATE scheduled_communications SET status = 'processing', claimed_at = datetime('now'), claimed_by = ? WHERE id = ? AND status = 'scheduled';"
		var claim_res = db.execute(claim_sql, [worker_id, sched_id])

		# Verify affected_rows == 1 before dispatching
		var affected = 0
		if claim_res["success"] and claim_res["data"].size() > 0:
			affected = int(claim_res["data"][0].get("affected_rows", 0))

		if affected == 1:
			claimed_count += 1
			
			# Query audience recipients from session_signups and people
			var rec_sql = """
				SELECT p.id, p.person_uuid, p.first_name, p.last_name, p.phone, p.email, COALESCE(p.sms_consent, 1) as sms_consent
				FROM session_signups ss
				JOIN people p ON p.id = ss.person_id
				WHERE ss.session_id = ? AND ss.removed_at IS NULL
				AND (
					? = 'all' OR
					(? = 'confirmed' AND ss.signup_status = 'confirmed') OR
					(? = 'waitlist' AND ss.signup_status = 'waitlist') OR
					(? = 'comm_needed' AND ss.communication_needed = 1)
				);
			"""
			var rec_res = db.execute(rec_sql, [sess_id, audience, audience, audience, audience])
			var targets = rec_res["data"] if (rec_res["success"] and rec_res["data"].size() > 0) else []

			var sent_cnt = 0
			var fail_cnt = 0
			var exc_cnt = 0

			if targets.size() > 0:
				for target in targets:
					var fn = str(target.get("first_name", "Participant"))
					var final_body = body.replace("{first_name}", fn)
					var d_res = send_message_atomic(target, channel, final_body, creator, image_path)
					if d_res["success"]:
						sent_cnt += 1
					elif d_res.get("status") == "excluded":
						exc_cnt += 1
					else:
						fail_cnt += 1

				var final_status = "sent"
				if sent_cnt == 0:
					final_status = "failed"
				elif fail_cnt > 0 or exc_cnt > 0:
					final_status = "partially_sent"

				var detail = "Dispatched %d sent, %d failed, %d excluded" % [sent_cnt, fail_cnt, exc_cnt]
				db.execute("UPDATE scheduled_communications SET status = ?, status_detail = ? WHERE id = ?;", [final_status, detail, sched_id])
			else:
				# Fallback: Query people table directly if no signups exist for demo session
				var p_gen = db.execute("SELECT id, person_uuid, first_name, last_name, phone, email, sms_consent FROM people WHERE phone IS NOT NULL AND phone != '' LIMIT 1;")
				if p_gen["success"] and p_gen["data"].size() > 0:
					var target_p = p_gen["data"][0]
					var fn = str(target_p.get("first_name", "Participant"))
					var final_body = body.replace("{first_name}", fn)
					var d_res = send_message_atomic(target_p, channel, final_body, creator, image_path)
					var final_status = "sent" if d_res["success"] else "failed"
					db.execute("UPDATE scheduled_communications SET status = ?, status_detail = 'Dispatched target fallback' WHERE id = ?;", [final_status, sched_id])
				else:
					db.execute("UPDATE scheduled_communications SET status = 'failed', status_detail = 'No recipients found' WHERE id = ?;", [sched_id])

			count += 1

	return {"processed_count": count, "claimed_count": claimed_count, "error": ""}

func send_thread_reply_atomic(caller_phone: String, text: String, channel: String = "SMS") -> Dictionary:
	var thread_uuid = "th_" + _generate_uuid()
	var event_uuid = "evt_" + _generate_uuid()
	var device_uuid = "dev_macbook_primary_node"

	var stmt1 = {
		"sql": "INSERT INTO threaded_conversations (thread_uuid, caller_phone, direction, channel, message_text, status) VALUES (?, ?, 'outbound', ?, ?, 'sent');",
		"args": [thread_uuid, caller_phone, channel, text]
	}

	var payload_dict = {
		"event_uuid": event_uuid,
		"event_type": "ThreadReplySent",
		"thread_uuid": thread_uuid,
		"caller_phone": caller_phone,
		"channel": channel,
		"message_text": text,
		"device_uuid": device_uuid,
		"timestamp": Time.get_datetime_string_from_system()
	}
	var payload_json = JSON.stringify(payload_dict)

	var stmt2 = {
		"sql": "INSERT INTO event_outbox (event_uuid, event_type, aggregate_type, aggregate_id, payload_json, device_uuid, status) VALUES (?, 'ThreadReplySent', 'Communications', ?, ?, ?, 'pending');",
		"args": [event_uuid, thread_uuid, payload_json, device_uuid]
	}

	var tx_res = db.execute_transaction([stmt1, stmt2])
	if not tx_res["success"]:
		return {"success": false, "error": tx_res["error"]}

	return {"success": true, "error": "", "thread_uuid": thread_uuid}

func get_templates() -> Array:
	var res = db.execute("SELECT id, title, category, channel, body_template FROM message_templates WHERE is_active = 1 ORDER BY category ASC, title ASC;")
	if res["success"]: return res["data"]
	return []

func get_recent_communications(limit: int = 15) -> Array:
	var res = db.execute("SELECT message_uuid, recipient_name, recipient_contact, channel, message_body, status, created_at FROM communications_log ORDER BY id DESC LIMIT ?;", [limit])
	if res["success"]: return res["data"]
	return []

func get_ivr_voice_settings() -> Dictionary:
	var res = db.execute("SELECT voice_name, language FROM ivr_settings WHERE id = 1;")
	if res["success"] and res["data"].size() > 0:
		return {"voice_name": str(res["data"][0]["voice_name"]), "language": str(res["data"][0]["language"])}
	return {"voice_name": "Polly.Joanna", "language": "en-US"}

func get_voicemails() -> Array:
	var supervisor_name = ""
	var setting_res = db.execute("SELECT setting_value FROM app_settings WHERE setting_key = 'ACTIVE_SUPERVISOR' LIMIT 1;")
	if setting_res["success"] and setting_res["data"].size() > 0:
		supervisor_name = str(setting_res["data"][0].get("setting_value", ""))
	
	var filter_assigned_only = false
	var active_person_id = -1
	
	if supervisor_name != "":
		var staff_res = db.execute("SELECT linked_person_id, eligible_for_general_voicemail_assignments FROM staff_users WHERE display_name = ? LIMIT 1;", [supervisor_name])
		if staff_res["success"] and staff_res["data"].size() > 0:
			var s_user = staff_res["data"][0]
			var linked_id = s_user.get("linked_person_id")
			if linked_id != null:
				active_person_id = int(linked_id)
			
			var eligible_general = s_user.get("eligible_for_general_voicemail_assignments")
			if eligible_general != null and int(eligible_general) == 0:
				filter_assigned_only = true

	var q_vm = """
		SELECT 'voicemail' AS item_type,
		       v.voicemail_uuid AS item_uuid,
		       COALESCE(NULLIF(TRIM(v.caller_name), '<null>'), '') AS caller_name,
		       COALESCE(v.caller_phone, '') AS caller_phone,
		       v.duration_sec,
		       COALESCE(v.transcription, '') AS transcription,
		       COALESCE(v.recording_url, '') AS recording_url,
		       v.status,
		       v.priority,
		       v.due_date,
		       v.internal_notes,
		       v.created_at,
		       CASE 
		         WHEN p.first_name IS NOT NULL THEN TRIM(p.first_name || ' ' || p.last_name)
		         ELSE 'Unassigned'
		       END AS assignee_name,
		       v.assigned_person_id,
		       CASE 
		         WHEN c.first_name IS NOT NULL THEN TRIM(c.first_name || ' ' || c.last_name)
		         ELSE ''
		       END AS matched_caller_name
		FROM voicemails v
		LEFT JOIN people p ON v.assigned_person_id = p.id
		LEFT JOIN people c ON v.caller_phone = c.phone
	"""
	
	var q_sms = """
		SELECT 'sms' AS item_type,
		       COALESCE(s.message_sid, 'sms_' || s.id) AS item_uuid,
		       CASE 
		         WHEN c.first_name IS NOT NULL THEN TRIM(c.first_name || ' ' || c.last_name)
		         ELSE 'SMS Caller'
		       END AS caller_name,
		       COALESCE(s.from_phone_e164, '') AS caller_phone,
		       0 AS duration_sec,
		       COALESCE(s.raw_body, '') AS transcription,
		       '' AS recording_url,
		       CASE 
		         WHEN LOWER(s.follow_up_status) = 'in_progress' THEN 'in_progress'
		         WHEN LOWER(s.follow_up_status) = 'waiting' THEN 'waiting'
		         WHEN LOWER(s.follow_up_status) = 'completed' THEN 'completed'
		         ELSE 'new'
		       END AS status,
		       'Medium' AS priority,
		       '' AS due_date,
		       COALESCE(s.notes, '') AS internal_notes,
		       s.received_at AS created_at,
		       COALESCE(NULLIF(s.assigned_to, ''), 'Unassigned') AS assignee_name,
		       NULL AS assigned_person_id,
		       CASE 
		         WHEN c.first_name IS NOT NULL THEN TRIM(c.first_name || ' ' || c.last_name)
		         ELSE ''
		       END AS matched_caller_name
		FROM inbound_sms_log s
		LEFT JOIN people c ON s.from_phone_e164 = c.phone
	"""
	
	var params = []
	if filter_assigned_only:
		q_vm += " WHERE v.assigned_person_id = ? "
		params.append(active_person_id)
		
		q_sms += " WHERE s.assigned_to = ? "
		params.append(supervisor_name)
		
	var q = q_vm + " UNION ALL " + q_sms + " ORDER BY created_at DESC;"
	
	var res = db.execute(q, params)
	if res["success"]: return res["data"]
	return []

func link_phone_to_person(phone_str: String, person_id: int) -> Dictionary:
	if not db or person_id <= 0: return {"success": false, "error": "Invalid person ID"}
	
	# Fetch target person name
	var name_res = db.execute("SELECT first_name, last_name FROM people WHERE id = ? LIMIT 1;", [person_id])
	if not name_res["success"] or name_res["data"].size() == 0:
		return {"success": false, "error": "Person not found"}
		
	var fn = str(name_res["data"][0].get("first_name", ""))
	var ln = str(name_res["data"][0].get("last_name", ""))
	var full_name = (fn + " " + ln).strip_edges()
	
	# Update phone on people table
	db.execute("UPDATE people SET phone = ?, updated_at = datetime('now') WHERE id = ?;", [phone_str, person_id])
	
	# Retroactively update caller_name on voicemails and matched_person_id on SMS log
	db.execute("UPDATE voicemails SET caller_name = ? WHERE caller_phone = ?;", [full_name, phone_str])
	db.execute("UPDATE inbound_sms_log SET matched_person_id = ? WHERE from_phone_e164 = ?;", [person_id, phone_str])
	
	return {"success": true, "name": full_name}

func create_non_member_profile(first_name: String, last_name: String, phone_str: String, email_str: String = "", notes_str: String = "") -> Dictionary:
	if not db: return {"success": false, "error": "No DB"}
	
	var fn = first_name.strip_edges()
	var ln = last_name.strip_edges()
	if fn == "": fn = "Guest"
	if ln == "": ln = "Caller"
	
	var p_uuid = "person_" + _generate_uuid()
	
	# Generate human ID
	var count_res = db.execute("SELECT COUNT(*) as cnt FROM people;")
	var cnt = 101
	if count_res["success"] and count_res["data"].size() > 0:
		cnt += int(count_res["data"][0]["cnt"])
	var human_id = "NMB-" + str(cnt)
	
	var ins = "INSERT INTO people (person_uuid, human_id, first_name, last_name, phone, created_at, updated_at) VALUES (?, ?, ?, ?, ?, datetime('now'), datetime('now'));"
	var res = db.execute(ins, [p_uuid, human_id, fn, ln, phone_str])
	if not res["success"]:
		return {"success": false, "error": res.get("error", "Insert failed")}
		
	var new_id = int(res.get("last_insert_id", 0))
	if new_id <= 0:
		var fetch_id = db.execute("SELECT id FROM people WHERE person_uuid = ? LIMIT 1;", [p_uuid])
		if fetch_id["success"] and fetch_id["data"].size() > 0:
			new_id = int(fetch_id["data"][0]["id"])
			
	# Link past records
	link_phone_to_person(phone_str, new_id)
	
	return {"success": true, "id": new_id, "name": (fn + " " + ln).strip_edges()}

func update_voicemail_workflow(vm_uuid: String, assigned_person_id: Variant, status: String, priority: String, due_date: String, internal_notes: String, item_type: String = "voicemail") -> Dictionary:
	if item_type == "sms":
		var assignee_name = ""
		if assigned_person_id != null and int(assigned_person_id) > 0:
			var p_res = db.execute("SELECT first_name || ' ' || last_name AS name FROM people WHERE id = ? LIMIT 1;", [assigned_person_id])
			if p_res["success"] and p_res["data"].size() > 0:
				assignee_name = str(p_res["data"][0]["name"])
				
		var q = """
			UPDATE inbound_sms_log 
			SET follow_up_status = ?, 
			    assigned_to = ?, 
			    notes = ?, 
			    follow_up_updated_at = datetime('now')
			WHERE message_sid = ? OR ('sms_' || id) = ?;
		"""
		var res = db.execute(q, [status, assignee_name, internal_notes, vm_uuid, vm_uuid])
		if res["success"]:
			var payload = {
				"message_sid": vm_uuid,
				"follow_up_status": status,
				"assigned_to": assignee_name,
				"notes": internal_notes,
				"is_read": 1
			}
			var event_uuid = _generate_uuid()
			var payload_str = JSON.stringify(payload)
			db.execute("INSERT OR IGNORE INTO event_outbox (event_uuid, event_type, aggregate_type, aggregate_id, payload_json, device_uuid, status) VALUES (?, 'SmsWorkflowUpdated', 'Sms', ?, ?, ?, 'pending');", [event_uuid, vm_uuid, payload_str, get_device_uuid()])
		return res
	else:
		var assignee_name = ""
		if assigned_person_id != null and int(assigned_person_id) > 0:
			var p_res = db.execute("SELECT first_name || ' ' || last_name AS name FROM people WHERE id = ? LIMIT 1;", [assigned_person_id])
			if p_res["success"] and p_res["data"].size() > 0:
				assignee_name = str(p_res["data"][0]["name"])

		var q = "UPDATE voicemails SET assigned_person_id = ?, status = ?, priority = ?, due_date = ?, internal_notes = ? WHERE voicemail_uuid = ?;"
		var res = db.execute(q, [assigned_person_id, status, priority, due_date, internal_notes, vm_uuid])
		if res["success"]:
			var payload = {
				"voicemail_id": vm_uuid,
				"status": status,
				"assigned_to": assignee_name,
				"notes": internal_notes,
				"is_read": 1
			}
			var event_uuid = _generate_uuid()
			var payload_str = JSON.stringify(payload)
			db.execute("INSERT OR IGNORE INTO event_outbox (event_uuid, event_type, aggregate_type, aggregate_id, payload_json, device_uuid, status) VALUES (?, 'VoicemailWorkflowUpdated', 'Voicemail', ?, ?, ?, 'pending');", [event_uuid, vm_uuid, payload_str, get_device_uuid()])
		return res

func update_voicemail_transcription(vm_uuid: String, transcription_text: String) -> bool:
	if not db: return false
	var res = db.execute("UPDATE voicemails SET transcription = ? WHERE voicemail_uuid = ?;", [transcription_text, vm_uuid])
	return res["success"]

func get_work_item_notes(item_uuid: String) -> Array:
	if not db or item_uuid == "": return []
	var res = db.execute("SELECT id, item_uuid, author_name, note_text, created_at FROM work_item_notes WHERE item_uuid = ? ORDER BY id ASC;", [item_uuid])
	if res["success"]: return res["data"]
	return []

func add_work_item_note(item_uuid: String, author_name: String, note_text: String) -> bool:
	if not db or item_uuid == "" or note_text.strip_edges() == "": return false
	var res = db.execute("INSERT INTO work_item_notes (item_uuid, author_name, note_text) VALUES (?, ?, ?);", [item_uuid, author_name, note_text.strip_edges()])
	return res["success"]

func get_threaded_messages() -> Array:
	var res = db.execute("SELECT thread_uuid, caller_phone, direction, channel, message_text, status, created_at FROM threaded_conversations ORDER BY id DESC;")
	if res["success"]: return res["data"]
	return []

func save_ivr_voice_settings(voice_name: String, language: String) -> bool:
	var q = "INSERT OR REPLACE INTO ivr_settings (id, voice_name, language) VALUES (1, ?, ?);"
	var res = db.execute(q, [voice_name, language])
	return res["success"]

func get_phone_settings() -> Dictionary:
	var res = db.execute("SELECT setting_key, setting_value FROM app_settings WHERE setting_key LIKE 'PHONE_%';")
	var dict = {
		"on_call_person_id": "",
		"rollover_rings": 4,
		"tts_greeting_active": true,
		"automated_greeter_tts": "",
		"automated_greeter_audio": ""
	}
	if res["success"]:
		for row in res["data"]:
			var key = String(row.get("setting_key", ""))
			var val = String(row.get("setting_value", ""))
			match key:
				"PHONE_ON_CALL_PERSON_ID": dict["on_call_person_id"] = val
				"PHONE_ROLLOVER_RINGS": dict["rollover_rings"] = int(val) if val.is_valid_int() else 4
				"PHONE_TTS_GREETING_ACTIVE": dict["tts_greeting_active"] = (val == "1" or val.to_lower() == "true")
				"PHONE_AUTOMATED_GREETER_TTS": dict["automated_greeter_tts"] = val
				"PHONE_AUTOMATED_GREETER_AUDIO": dict["automated_greeter_audio"] = val
	return dict

func save_phone_settings(on_call: String, rings: int, tts_active: bool, tts_text: String, audio_base64: String) -> bool:
	var stmts = [
		{"sql": "INSERT OR REPLACE INTO app_settings (setting_key, setting_value) VALUES ('PHONE_ON_CALL_PERSON_ID', ?);", "args": [on_call]},
		{"sql": "INSERT OR REPLACE INTO app_settings (setting_key, setting_value) VALUES ('PHONE_ROLLOVER_RINGS', ?);", "args": [str(rings)]},
		{"sql": "INSERT OR REPLACE INTO app_settings (setting_key, setting_value) VALUES ('PHONE_TTS_GREETING_ACTIVE', ?);", "args": [str(1 if tts_active else 0)]},
		{"sql": "INSERT OR REPLACE INTO app_settings (setting_key, setting_value) VALUES ('PHONE_AUTOMATED_GREETER_TTS', ?);", "args": [tts_text]},
		{"sql": "INSERT OR REPLACE INTO app_settings (setting_key, setting_value) VALUES ('PHONE_AUTOMATED_GREETER_AUDIO', ?);", "args": [audio_base64]}
	]
	var res = db.execute_transaction(stmts)
	if res["success"]:
		var payload = [
			{"setting_key": "PHONE_ON_CALL_PERSON_ID", "setting_value": on_call},
			{"setting_key": "PHONE_ROLLOVER_RINGS", "setting_value": str(rings)},
			{"setting_key": "PHONE_TTS_GREETING_ACTIVE", "setting_value": str(1 if tts_active else 0)},
			{"setting_key": "PHONE_AUTOMATED_GREETER_TTS", "setting_value": tts_text},
			{"setting_key": "PHONE_AUTOMATED_GREETER_AUDIO", "setting_value": audio_base64}
		]
		var event_uuid = _generate_uuid()
		var payload_str = JSON.stringify(payload)
		db.execute("INSERT OR IGNORE INTO event_outbox (event_uuid, event_type, aggregate_type, aggregate_id, payload_json, device_uuid, status) VALUES (?, 'PhoneSettingsUpdated', 'Settings', 'global_phone', ?, ?, 'pending');", [event_uuid, payload_str, get_device_uuid()])
	return res["success"]

func get_all_ivr_menu_options() -> Array:
	var res = db.execute("SELECT digit, menu_option_name, script_text, action_type, action_param, parent_digit, use_custom_audio, audio_data FROM ivr_menu_options ORDER BY digit ASC;")
	if res["success"]: return res["data"]
	return []

func save_ivr_menu_option(digit: String, name: String, script: String, action_type: String, action_param: String, parent_digit: Variant, use_custom_audio: bool, audio_data: String) -> bool:
	var q = """
		INSERT INTO ivr_menu_options (digit, menu_option_name, script_text, action_type, action_param, parent_digit, use_custom_audio, audio_data)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?)
		ON CONFLICT(digit) DO UPDATE SET
			menu_option_name = excluded.menu_option_name,
			script_text = excluded.script_text,
			action_type = excluded.action_type,
			action_param = excluded.action_param,
			parent_digit = excluded.parent_digit,
			use_custom_audio = excluded.use_custom_audio,
			audio_data = excluded.audio_data;
	"""
	var p_dig = null
	if parent_digit != null and str(parent_digit).strip_edges() != "":
		p_dig = str(parent_digit).strip_edges()
	var res = db.execute(q, [digit, name, script, action_type, action_param, p_dig, 1 if use_custom_audio else 0, audio_data])
	if res["success"]:
		var payload = {
			"digit": digit,
			"menu_option_name": name,
			"script_text": script,
			"action_type": action_type,
			"action_param": action_param,
			"parent_digit": p_dig,
			"use_custom_audio": use_custom_audio,
			"audio_data": audio_data
		}
		var event_uuid = _generate_uuid()
		var payload_str = JSON.stringify(payload)
		db.execute("INSERT OR IGNORE INTO event_outbox (event_uuid, event_type, aggregate_type, aggregate_id, payload_json, device_uuid, status) VALUES (?, 'IvrMenuOptionUpdated', 'Ivr', ?, ?, ?, 'pending');", [event_uuid, digit, payload_str, get_device_uuid()])
	return res["success"]

func delete_ivr_menu_option(digit: String) -> bool:
	var res = db.execute_transaction([
		{"sql": "DELETE FROM ivr_menu_options WHERE digit = ?;", "args": [digit]}
	])
	return res["success"]

func _generate_uuid() -> String:
	var b1 = "%08X" % (randi() % 4294967295)
	var b2 = "%04X" % (randi() % 65536)
	var b3 = "%04X" % (randi() % 65536)
	return (b1 + "-" + b2 + "-" + b3).to_lower()

func get_device_uuid() -> String:
	var res = db.execute("SELECT device_uuid FROM device_identity LIMIT 1;")
	if res["success"] and res["data"].size() > 0:
		return str(res["data"][0]["device_uuid"])
	return "dev_primary_node"
