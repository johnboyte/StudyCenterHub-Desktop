extends RefCounted

## Inbound Event Processor for StudyCenterHub
## Processes raw inbound events (such as twilio.voicemail and twilio.sms) pulled from the relay,
## runs caller matching, handles SMS compliance, calls Gemini API for audio transcription,
## and logs records to SQLite and Google Sheets via the outbox.
## Complies with permanent design rules: all business logic, caller matching, and transcription live here.

const AttendanceServiceScript = preload("res://src/domain/attendance/attendance_service.gd")
const PersonRegistrationValidatorScript = preload("res://src/domain/directory/person_registration_validator.gd")
const QRCredentialServiceScript = preload("res://src/domain/security/qr_credential_service.gd")

var db: RefCounted
var parent_node: Node
var http_client: HTTPRequest

func _init(database: RefCounted, caller_node: Node) -> void:
	db = database
	parent_node = caller_node
	
	http_client = HTTPRequest.new()
	http_client.timeout = 10.0
	parent_node.add_child(http_client)

func get_gemini_api_key() -> String:
	var res = db.execute("SELECT setting_value FROM app_settings WHERE setting_key = 'GEMINI_API_KEY' LIMIT 1;")
	if res["success"] and res["data"].size() > 0:
		var k = str(res["data"][0]["setting_value"]).strip_edges()
		if k != "": return k
	return OS.get_environment("GEMINI_API_KEY")

func process_pending_events(callback: Callable) -> void:
	print("[Processor] Querying pending events...")
	var res = db.execute("SELECT * FROM inbound_event_queue WHERE processed = 0 ORDER BY id ASC;")
	if not res["success"] or res["data"].size() == 0:
		print("[Processor] No pending events found.")
		callback.call({"success": true, "processed_count": 0})
		return

	var events = res["data"]
	print("[Processor] Found ", events.size(), " pending events.")
	_process_next_event(events, 0, 0, callback)

func _process_next_event(events: Array, index: int, processed_count: int, callback: Callable) -> void:
	print("[Processor] Processing index: ", index)
	if index >= events.size():
		print("[Processor] Finished processing all events. Invoking callback.")
		callback.call({"success": true, "processed_count": processed_count})
		return

	var event = events[index]
	var event_id = int(event["id"])
	var event_type = str(event["event_type"])
	var payload_json = str(event["payload_json"])
	var payload = JSON.parse_string(payload_json)

	if typeof(payload) != TYPE_DICTIONARY:
		print("[Processor] Event ", event_id, " has invalid payload. Skipping.")
		db.execute("UPDATE inbound_event_queue SET processed = 1 WHERE id = ?;", [event_id])
		_process_next_event(events, index + 1, processed_count, callback)
		return

	if event_type == "portal.registration":
		print("[Processor] Processing portal.registration event ", event_id)
		_process_portal_registration(event_id, payload)
		_process_next_event(events, index + 1, processed_count + 1, callback)
	elif event_type == "portal.checkin":
		print("[Processor] Processing portal.checkin event ", event_id)
		_process_portal_checkin(event_id, payload)
		_process_next_event(events, index + 1, processed_count + 1, callback)
	elif event_type == "portal.signup":
		print("[Processor] Processing portal.signup event ", event_id)
		_process_portal_signup(event_id, payload)
		_process_next_event(events, index + 1, processed_count + 1, callback)
	elif event_type == "portal.cancel_signup":
		print("[Processor] Processing portal.cancel_signup event ", event_id)
		_process_portal_cancel_signup(event_id, payload)
		_process_next_event(events, index + 1, processed_count + 1, callback)
	elif event_type == "portal.pass_request":
		print("[Processor] Processing portal.pass_request event ", event_id)
		_process_portal_pass_request(event_id, payload)
		_process_next_event(events, index + 1, processed_count + 1, callback)
	elif event_type == "portal.pass_accessed":
		print("[Processor] Processing portal.pass_accessed event ", event_id)
		_process_portal_pass_accessed(event_id, payload)
		_process_next_event(events, index + 1, processed_count + 1, callback)
	elif event_type == "scanner.checkin":
		print("[Processor] Processing scanner.checkin event ", event_id)
		_process_scanner_checkin(event_id, payload)
		_process_next_event(events, index + 1, processed_count + 1, callback)
	elif event_type == "mobile.checkout":
		print("[Processor] Processing mobile.checkout event ", event_id)
		_process_mobile_checkout(event_id, payload)
		_process_next_event(events, index + 1, processed_count + 1, callback)
	elif event_type == "mobile.schedule_cover" or event_type == "mobile.shift_assignment":
		print("[Processor] Processing mobile.schedule_cover event ", event_id)
		_process_mobile_schedule_cover(event_id, payload)
		_process_next_event(events, index + 1, processed_count + 1, callback)
	elif event_type == "twilio.sms":
		print("[Processor] Processing SMS event ", event_id)
		_process_sms(event_id, payload)
		_process_next_event(events, index + 1, processed_count + 1, callback)
	elif event_type == "twilio.voicemail":
		print("[Processor] Processing Voicemail event ", event_id)
		_process_voicemail(event_id, payload, func():
			print("[Processor] Voicemail event ", event_id, " completion callback received.")
			_process_next_event(events, index + 1, processed_count + 1, callback)
		)
	elif event_type == "twilio.transcription":
		print("[Processor] Processing Twilio transcription event ", event_id)
		_process_twilio_transcription(event_id, payload)
		_process_next_event(events, index + 1, processed_count + 1, callback)
	else:
		print("[Processor] Generic event type: ", event_type)
		db.execute("UPDATE inbound_event_queue SET processed = 1 WHERE id = ?;", [event_id])
		_process_next_event(events, index + 1, processed_count, callback)

func _process_portal_registration(event_id: int, payload: Dictionary) -> void:
	db.execute("ALTER TABLE people ADD COLUMN school_email TEXT;")
	db.execute("ALTER TABLE people ADD COLUMN preferred_email TEXT DEFAULT 'Main';")
	db.execute("ALTER TABLE people ADD COLUMN campus_community_applies INTEGER DEFAULT 0;")
	db.execute("ALTER TABLE people ADD COLUMN institution_id INTEGER;")
	db.execute("ALTER TABLE people ADD COLUMN institution_other_name TEXT;")
	db.execute("INSERT OR IGNORE INTO institutions (uuid, name, short_name, institution_type, display_order, is_active) VALUES ('inst_tl_hanna', 'T.L. Hanna High School', 'TLH', 'high_school', 10, 1), ('inst_westside', 'Westside High School', 'WHS', 'high_school', 11, 1), ('inst_palmetto', 'Palmetto High School', 'PHS', 'high_school', 12, 1), ('inst_crescent', 'Crescent High School', 'CHS', 'high_school', 13, 1), ('inst_bhp', 'Belton-Honea Path High School', 'BHP', 'high_school', 14, 1), ('inst_pendleton', 'Pendleton High School', 'PEND', 'high_school', 15, 1), ('inst_wren', 'Wren High School', 'WREN', 'high_school', 16, 1), ('inst_powdersville', 'Powdersville High School', 'PVHS', 'high_school', 17, 1), ('inst_anderson_christian', 'Anderson Christian School', 'ACS', 'high_school', 18, 1), ('inst_new_covenant', 'New Covenant School', 'NCS', 'high_school', 19, 1), ('inst_home_school', 'Home School', 'HomeSchool', 'high_school', 20, 1);")

	var val_res = PersonRegistrationValidatorScript.validate_registration(payload)
	if not val_res["is_valid"]:
		var err_msg = "Validation failed: " + ", ".join(val_res["errors"])
		print("[Processor] Portal registration validation failed for event ", event_id, ": ", err_msg)
		db.execute("ALTER TABLE inbound_event_queue ADD COLUMN status TEXT DEFAULT 'pending';")
		db.execute("ALTER TABLE inbound_event_queue ADD COLUMN result_json TEXT DEFAULT NULL;")
		var fail_res = {
			"status": "registration_failed",
			"error": err_msg,
			"message": err_msg
		}
		db.execute("UPDATE inbound_event_queue SET processed = 1, status = 'registration_failed', result_json = ? WHERE id = ?;", [JSON.stringify(fail_res), event_id])
		return

	var norm = val_res["normalized_data"]
	var phone = str(norm.get("phone", ""))
	var phone_e164 = str(norm.get("phone_e164", ""))
	var email = str(norm.get("email", ""))
	var human_id = str(payload.get("humanId", payload.get("human_id", ""))).strip_edges()

	# Duplicate Matching Check (phone or email)
	var person_id = 0
	if phone != "" or email != "":
		var match_res = db.execute("SELECT id, human_id FROM people WHERE (phone IS NOT NULL AND phone != '' AND (phone = ? OR phone = ?)) OR (email IS NOT NULL AND email != '' AND LOWER(email) = ?) LIMIT 1;", [phone, phone_e164, email.to_lower()])
		if match_res["success"] and match_res["data"].size() > 0:
			person_id = int(match_res["data"][0]["id"])
			human_id = str(match_res["data"][0]["human_id"])

	var photo_base64 = str(payload.get("profile_photo", payload.get("profilePhoto", payload.get("photo", "")))).strip_edges()
	var inst_name = str(norm.get("institution", payload.get("institution", ""))).strip_edges()
	var inst_other = str(payload.get("institutionOtherName", payload.get("institution_other_name", payload.get("institutionOther", "")))).strip_edges()
	var em_name = str(norm.get("emergency_contact_name", payload.get("emergency_contact_name", payload.get("emergencyContactName", "")))).strip_edges()
	var em_phone = str(norm.get("emergency_contact_phone", payload.get("emergency_contact_phone", payload.get("emergencyContactPhone", "")))).strip_edges()
	var school_email = str(norm.get("school_email", payload.get("schoolEmail", ""))).strip_edges()
	var preferred_email = str(norm.get("preferred_email", "Main")).strip_edges()

	# Resolve canonical Institution ID
	var inst_id = null
	if inst_name != "":
		var inst_res = db.execute("SELECT id FROM institutions WHERE LOWER(name) = ? OR LOWER(short_name) = ? LIMIT 1;", [inst_name.to_lower(), inst_name.to_lower()])
		if inst_res["success"] and inst_res["data"].size() > 0:
			inst_id = int(inst_res["data"][0]["id"])
		else:
			var other_res = db.execute("SELECT id FROM institutions WHERE LOWER(name) = 'other' LIMIT 1;")
			if other_res["success"] and other_res["data"].size() > 0:
				inst_id = int(other_res["data"][0]["id"])
			if inst_other == "":
				inst_other = inst_name

	var campus_applies = 1 if (inst_id != null or inst_other != "" or norm.get("academic_year", "") != "") else 0
	var sys_role = "Staff" if norm["primary_role"] == "Staff" else ("Volunteer" if norm["primary_role"] == "Volunteer" else "Participant")

	var created_person_uuid = ""
	if person_id > 0:
		print("[Processor] Matched existing member ID ", person_id, " for portal registration.")
		db.execute(
			"UPDATE people SET first_name = ?, last_name = ?, phone = ?, email = ?, school_email = COALESCE(NULLIF(?, ''), school_email), preferred_email = ?, birthday = ?, primary_role = ?, relationship = ?, campus_community_applies = ?, institution_id = COALESCE(?, institution_id), institution_other_name = COALESCE(NULLIF(?, ''), institution_other_name), academic_year = ?, grade = ?, sms_consent = ?, sms_consent_given = ?, emergency_contact_name = COALESCE(NULLIF(?, ''), emergency_contact_name), emergency_contact_phone = COALESCE(NULLIF(?, ''), emergency_contact_phone), profile_photo = COALESCE(NULLIF(?, ''), profile_photo), flag_status = 'Clear', updated_at = datetime('now') WHERE id = ?;",
			[norm["first_name"], norm["last_name"], phone, email, school_email, preferred_email, norm.get("birthday", ""), sys_role, norm["relationship"], campus_applies, inst_id, inst_other, norm.get("academic_year", ""), norm.get("grade", ""), norm["sms_consent"], norm["sms_consent_given"], em_name, em_phone, photo_base64, person_id]
		)
	else:
		created_person_uuid = "usr_" + _generate_uuid().replace("-", "").substr(0, 16)
		if human_id == "":
			const PersonServiceScript = preload("res://src/domain/directory/person_service.gd")
			human_id = PersonServiceScript.generate_canonical_human_id(db)

		var p_ins_res = db.execute(
			"INSERT INTO people (person_uuid, human_id, first_name, last_name, phone, email, school_email, preferred_email, birthday, primary_role, relationship, campus_community_applies, institution_id, institution_other_name, academic_year, grade, emergency_contact_name, emergency_contact_phone, sms_consent, sms_consent_given, sms_consent_source, sms_consent_at, profile_photo, flag_status, status, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'Clear', 'active', datetime('now'));",
			[
				created_person_uuid, human_id, norm["first_name"], norm["last_name"], phone, email, school_email, preferred_email,
				norm.get("birthday", ""), sys_role, norm["relationship"], campus_applies, inst_id, inst_other,
				norm.get("academic_year", ""), norm.get("grade", ""),
				em_name, em_phone,
				norm["sms_consent"], norm["sms_consent_given"], norm.get("sms_consent_source", "Public Registration"),
				norm.get("sms_consent_at", Time.get_datetime_string_from_system()),
				photo_base64
			]
		)

	# Perform Automatic Daily Check-In for the Registered Member
	var final_person_id = person_id
	if final_person_id == 0:
		var pid_q = db.execute("SELECT id FROM people WHERE person_uuid = ? LIMIT 1;", [created_person_uuid])
		if pid_q["success"] and pid_q["data"].size() > 0:
			final_person_id = int(pid_q["data"][0]["id"])

	var person_rec_q = db.execute("SELECT * FROM people WHERE id = ? LIMIT 1;", [final_person_id])
	var is_checked_in = false
	var reg_status = "registered_and_checked_in"

	if person_rec_q["success"] and person_rec_q["data"].size() > 0:
		var person_dict = person_rec_q["data"][0]
		var today_str = Time.get_date_string_from_system()
		var dup_res = db.execute("SELECT id FROM attendance_log WHERE person_id = ? AND check_in_date = ? LIMIT 1;", [final_person_id, today_str])

		if dup_res["success"] and dup_res["data"].size() > 0:
			reg_status = "registered_already_checked_in"
			is_checked_in = true
		else:
			var att_svc = AttendanceServiceScript.new(db)
			var att_res = att_svc.record_check_in_atomic(person_dict, "Public Self-Service Registration", "web_portal", null, "Study Center Daily", "Self Registration Auto Check-In")
			if att_res["success"]:
				is_checked_in = true
				reg_status = "registered_and_checked_in"

	# Ensure Active QR Credential exists & issued
	const QRCredentialServiceScript = preload("res://src/domain/security/qr_credential_service.gd")
	var qr_svc = QRCredentialServiceScript.new(db)
	var active_raw_token = qr_svc.get_active_raw_token(final_person_id)
	if active_raw_token == "" and person_rec_q["success"] and person_rec_q["data"].size() > 0:
		var cred_res = qr_svc.issue_credential(final_person_id, str(person_rec_q["data"][0].get("person_uuid", "")))
		if cred_res["success"]:
			active_raw_token = str(cred_res.get("raw_token", ""))

	db.execute("INSERT INTO digital_pass_event_log (person_id, event_type, delivery_channel, recipient_target) VALUES (?, 'issued', 'system', ?);", [final_person_id, phone])

	var col_check = db.execute("PRAGMA table_info(inbound_event_queue);")
	var has_status_col = false
	var has_result_col = false
	if col_check["success"]:
		for col in col_check["data"]:
			if str(col.get("name", "")) == "status": has_status_col = true
			if str(col.get("name", "")) == "result_json": has_result_col = true
	if not has_status_col:
		db.execute("ALTER TABLE inbound_event_queue ADD COLUMN status TEXT DEFAULT 'pending';")
	if not has_result_col:
		db.execute("ALTER TABLE inbound_event_queue ADD COLUMN result_json TEXT DEFAULT NULL;")
	var reg_result = {
		"status": reg_status,
		"human_id": human_id,
		"first_name": norm["first_name"],
		"checked_in": is_checked_in,
		"raw_token": active_raw_token,
		"message": "You’re Registered and Checked In!"
	}
	db.execute(
		"UPDATE inbound_event_queue SET processed = 1, status = ?, result_json = ? WHERE id = ?;",
		[reg_status, JSON.stringify(reg_result), event_id]
	)
	const GatewaySyncServiceScript = preload("res://src/domain/sync/gateway_sync_service.gd")
	var sync_svc = GatewaySyncServiceScript.new(db, parent_node)
	sync_svc.publish_directory_index()

func _process_portal_checkin(event_id: int, payload: Dictionary) -> void:
	var human_id = str(payload.get("humanId", payload.get("human_id", ""))).strip_edges()
	var raw_phone = str(payload.get("phone", payload.get("mobile_phone", ""))).strip_edges()
	var phone_e164 = str(payload.get("phone_e164", "")).strip_edges()
	var today_date = Time.get_date_string_from_system()

	db.execute("ALTER TABLE inbound_event_queue ADD COLUMN status TEXT DEFAULT 'pending';")
	db.execute("ALTER TABLE inbound_event_queue ADD COLUMN result_json TEXT DEFAULT NULL;")

	var people_res: Dictionary = {"success": false, "data": []}
	if human_id != "":
		people_res = db.execute("SELECT * FROM people WHERE human_id = ? AND status = 'active' LIMIT 2;", [human_id])
	
	if not people_res["success"] or people_res["data"].size() == 0:
		var target_digits = _normalize_phone_digits(raw_phone)
		if target_digits == "" and phone_e164 != "":
			target_digits = _normalize_phone_digits(phone_e164)

		if target_digits != "":
			var active_people = db.execute("SELECT * FROM people WHERE status = 'active';")
			if active_people["success"] and active_people["data"].size() > 0:
				var matched_data = []
				for p in active_people["data"]:
					var p_phone = str(p.get("phone", ""))
					var p_e164 = str(p.get("phone_e164", ""))
					if _normalize_phone_digits(p_phone) == target_digits or (p_e164 != "" and _normalize_phone_digits(p_e164) == target_digits):
						matched_data.append(p)
				people_res = {"success": true, "data": matched_data}

	var result: Dictionary = {}

	if not people_res["success"] or people_res["data"].size() == 0:
		result = {
			"status": "member_not_found",
			"message": "We could not find an active membership for that phone number."
		}
	elif people_res["data"].size() > 1:
		result = {
			"status": "multiple_matches",
			"message": "Multiple member records match this phone number. Please see a host at the front desk."
		}
	else:
		var person = people_res["data"][0]
		var person_id = int(person["id"])
		var first_name = str(person["first_name"])

		var dup_res = db.execute(
			"SELECT id FROM attendance_log WHERE person_id = ? AND check_in_date = ? LIMIT 1;",
			[person_id, today_date]
		)

		if dup_res["success"] and dup_res["data"].size() > 0:
			result = {
				"status": "already_checked_in",
				"first_name": first_name,
				"message": "You're already checked in today. Glad you're here, " + first_name + "!"
			}
		else:
			const AttendanceServiceScript = preload("res://src/domain/attendance/attendance_service.gd")
			var att_svc = AttendanceServiceScript.new(db)
			var att_res = att_svc.record_check_in_atomic(person, "Public Portal", "web_portal", null, "Study Center Daily")
			if att_res.get("already_checked_in", false) == true:
				result = {
					"status": "already_checked_in",
					"first_name": first_name,
					"message": "You're already checked in today. Glad you're here, " + first_name + "!"
				}
			elif att_res["success"]:
				result = {
					"status": "checked_in",
					"first_name": first_name,
					"message": "Successfully checked in! Welcome, " + first_name + "."
				}
			else:
				result = {
					"status": "checkin_failed",
					"message": "Unable to complete check-in: " + str(att_res.get("error", "Database transaction failed"))
				}

	db.execute(
		"UPDATE inbound_event_queue SET processed = 1, status = ?, result_json = ? WHERE id = ?;",
		[str(result.get("status", "processed")), JSON.stringify(result), event_id]
	)

func _process_portal_signup(event_id: int, payload: Dictionary) -> void:
	var session_id = int(payload.get("session_id", payload.get("sessionId", 0)))
	var session_uuid = str(payload.get("session_uuid", payload.get("sessionUuid", ""))).strip_edges()
	var human_id = str(payload.get("humanId", payload.get("human_id", ""))).strip_edges()
	var raw_phone = str(payload.get("phone", payload.get("mobile_phone", ""))).strip_edges()
	var phone_e164 = str(payload.get("phone_e164", "")).strip_edges()

	db.execute("ALTER TABLE inbound_event_queue ADD COLUMN status TEXT DEFAULT 'pending';")
	db.execute("ALTER TABLE inbound_event_queue ADD COLUMN result_json TEXT DEFAULT NULL;")

	# Resolve Member
	var people_res: Dictionary = {"success": false, "data": []}
	if human_id != "":
		people_res = db.execute("SELECT * FROM people WHERE human_id = ? LIMIT 2;", [human_id])
	if not people_res["success"] or people_res["data"].size() == 0:
		if raw_phone != "":
			if phone_e164 != "":
				people_res = db.execute("SELECT * FROM people WHERE phone = ? OR phone_e164 = ? LIMIT 2;", [raw_phone, phone_e164])
			else:
				people_res = db.execute("SELECT * FROM people WHERE phone = ? LIMIT 2;", [raw_phone])

	var result: Dictionary = {}

	if not people_res["success"] or people_res["data"].size() == 0:
		result = {"status": "member_not_found", "message": "Member record not found"}
	elif people_res["data"].size() > 1:
		result = {"status": "multiple_matches", "message": "Multiple member records match this phone number. Please see a host."}
	else:
		var person = people_res["data"][0]
		var person_id = int(person["id"])
		var first_name = str(person["first_name"])

		# Resolve Session
		var sess_res: Dictionary = {"success": false, "data": []}
		if session_id > 0:
			sess_res = db.execute("SELECT * FROM sessions WHERE id = ? LIMIT 1;", [session_id])
		elif session_uuid != "":
			sess_res = db.execute("SELECT * FROM sessions WHERE session_uuid = ? LIMIT 1;", [session_uuid])

		if not sess_res["success"] or sess_res["data"].size() == 0:
			result = {"status": "session_not_found", "message": "Requested session not found"}
		else:
			var session = sess_res["data"][0]
			var actual_session_id = int(session["id"])
			var title = str(session["title"])
			var is_active = int(session.get("is_active", 1)) == 1
			var public_enabled = int(session.get("public_signup_enabled", 1)) == 1

			if not is_active or not public_enabled:
				result = {"status": "registration_closed", "message": "Public registration is not available for this session."}
			else:
				# Check existing signup status
				var ex_res = db.execute("SELECT id, signup_status FROM session_signups WHERE session_id = ? AND person_id = ? AND signup_status IN ('confirmed', 'waitlist') LIMIT 1;", [actual_session_id, person_id])
				if ex_res["success"] and ex_res["data"].size() > 0:
					var ex_st = str(ex_res["data"][0]["signup_status"])
					if ex_st == "confirmed":
						result = {"status": "already_registered", "first_name": first_name, "title": title, "message": "You're already registered for " + title + "."}
					else:
						result = {"status": "already_waitlisted", "first_name": first_name, "title": title, "message": "You're already on the waitlist for " + title + "."}
				else:
					# Execute registration via SchedulesService
					const SchedulesServiceScript = preload("res://src/domain/schedules/schedules_service.gd")
					var sched_svc = SchedulesServiceScript.new(db)
					var reg_res = sched_svc.register_participant_atomic(actual_session_id, person_id)
					if reg_res["success"]:
						var final_st = str(reg_res.get("status", "confirmed"))
						if final_st == "confirmed":
							result = {"status": "confirmed", "first_name": first_name, "title": title, "message": "✓ You're Signed Up! Welcome to " + title + "."}
						elif final_st == "waitlist":
							var pos = int(reg_res.get("position", 1))
							result = {"status": "waitlisted", "first_name": first_name, "title": title, "position": pos, "message": "You're on the Waitlist for " + title + "."}
						else:
							result = {"status": final_st, "first_name": first_name, "title": title}
						
						var GatewaySyncScript = load("res://src/domain/sync/gateway_sync_service.gd")
						var sync_svc = GatewaySyncScript.new(db, parent_node)
						sync_svc.publish_session_index()
					else:
						result = {"status": "registration_failed", "message": "Registration failed: " + str(reg_res.get("error", ""))}

	db.execute("UPDATE inbound_event_queue SET processed = 1, status = ?, result_json = ? WHERE id = ?;", [str(result.get("status", "processed")), JSON.stringify(result), event_id])

func _process_portal_cancel_signup(event_id: int, payload: Dictionary) -> void:
	var session_id = int(payload.get("session_id", payload.get("sessionId", 0)))
	var human_id = str(payload.get("humanId", payload.get("human_id", ""))).strip_edges()
	var raw_phone = str(payload.get("phone", payload.get("mobile_phone", ""))).strip_edges()

	# Resolve Member
	var people_res = db.execute("SELECT id, first_name FROM people WHERE human_id = ? OR phone = ? LIMIT 1;", [human_id, raw_phone])
	var result: Dictionary = {}
	if people_res["success"] and people_res["data"].size() > 0:
		var person_id = int(people_res["data"][0]["id"])
		var first_name = str(people_res["data"][0]["first_name"])
		var ex_res = db.execute("SELECT id FROM session_signups WHERE session_id = ? AND person_id = ? AND signup_status IN ('confirmed', 'waitlist') LIMIT 1;", [session_id, person_id])
		if ex_res["success"] and ex_res["data"].size() > 0:
			var signup_id = int(ex_res["data"][0]["id"])
			const SchedulesServiceScript = preload("res://src/domain/schedules/schedules_service.gd")
			var sched_svc = SchedulesServiceScript.new(db)
			sched_svc.remove_confirmed_and_autopromote_atomic(session_id, signup_id, "Public Portal", "Self Cancellation")
			result = {"status": "cancelled", "first_name": first_name, "message": "Your registration has been cancelled."}
			
			var GatewaySyncScript = load("res://src/domain/sync/gateway_sync_service.gd")
			var sync_svc = GatewaySyncScript.new(db, parent_node)
			sync_svc.publish_session_index()
		else:
			result = {"status": "not_registered", "message": "No active registration found to cancel."}
	else:
		result = {"status": "member_not_found", "message": "Member record not found"}

	db.execute("UPDATE inbound_event_queue SET processed = 1, status = ?, result_json = ? WHERE id = ?;", [str(result.get("status", "processed")), JSON.stringify(result), event_id])

func _process_scanner_checkin(event_id: int, payload: Dictionary) -> void:
	var raw_scanned = str(payload.get("raw_scanned_content", "")).strip_edges()
	var scanner_id = str(payload.get("scanner_id", "DS2800")).strip_edges()
	var mode_val = str(payload.get("mode", "Study Center Daily")).strip_edges()

	if raw_scanned == "":
		db.execute("UPDATE inbound_event_queue SET processed = 1 WHERE id = ?;", [event_id])
		return

	# Extract opaque token if raw content is a full URL: https://checkin.reallife-studycenter.org/public-returning?credential={OPAQUE_TOKEN}
	var token_candidate = raw_scanned
	if "credential=" in raw_scanned:
		var parts = raw_scanned.split("credential=")
		if parts.size() > 1:
			token_candidate = parts[1].split("&")[0].strip_edges()

	var token_hash = token_candidate.sha256_text().to_lower()

	# 1. Resolve participant via active QR credential
	var pid = 0
	var cred_res = db.execute("SELECT person_id FROM participant_qr_credentials WHERE (token_hash = ? OR token_hash = ?) AND status = 'active' LIMIT 1;", [token_hash, token_candidate.to_lower()])
	if cred_res["success"] and cred_res["data"].size() > 0:
		pid = int(cred_res["data"][0]["person_id"])

	if pid == 0:
		# Fallback check legacy qr_code_value column in people table
		var legacy_res = db.execute("SELECT id FROM people WHERE qr_code_value = ? OR qr_code_value = ? LIMIT 1;", [token_hash, token_candidate])
		if legacy_res["success"] and legacy_res["data"].size() > 0:
			pid = int(legacy_res["data"][0]["id"])

	if pid == 0:
		print("[Processor] Warning: DS2800 scanner QR token not recognized or revoked: ", raw_scanned.left(25))
		db.execute("UPDATE inbound_event_queue SET processed = 1 WHERE id = ?;", [event_id])
		return

	var p_res = db.execute("SELECT * FROM people WHERE id = ? LIMIT 1;", [pid])
	if not p_res["success"] or p_res["data"].size() == 0:
		db.execute("UPDATE inbound_event_queue SET processed = 1 WHERE id = ?;", [event_id])
		return

	var person_dict = p_res["data"][0]

	# 2. Duplicate protection check for current date
	var today_str = Time.get_date_string_from_system()
	var dup_res = db.execute("SELECT COUNT(*) as cnt FROM attendance_log WHERE person_id = ? AND check_in_date = ? AND (mode = ? OR mode = 'Study Center Daily');", [pid, today_str, mode_val])
	if dup_res["success"] and dup_res["data"].size() > 0 and int(dup_res["data"][0]["cnt"]) > 0:
		print("[Processor] Participant ", pid, " already checked in today. Suppressing duplicate scan.")
		db.execute("UPDATE inbound_event_queue SET processed = 1 WHERE id = ?;", [event_id])
		return

	# 3. Record attendance check-in atomically using AttendanceService
	var att_svc = AttendanceServiceScript.new(db)
	att_svc.record_check_in_atomic(person_dict, "NETUM DS2800 Scanner", scanner_id, null, mode_val, "John Boyte")

	db.execute("UPDATE inbound_event_queue SET processed = 1 WHERE id = ?;", [event_id])

func _process_mobile_checkout(event_id: int, payload: Dictionary) -> void:
	var target_hid = str(payload.get("human_id", payload.get("humanId", ""))).strip_edges()
	var today_str = Time.get_date_string_from_system()
	var time_str = Time.get_time_string_from_system()

	if target_hid != "":
		# Record check-out time in attendance_log for today
		db.execute("UPDATE attendance_log SET check_out_time = ? WHERE (human_id = ? OR person_uuid = ?) AND check_in_date = ? AND (check_out_time IS NULL OR check_out_time = '');", [time_str, target_hid, target_hid, today_str])

	db.execute("UPDATE inbound_event_queue SET processed = 1 WHERE id = ?;", [event_id])

func _process_mobile_schedule_cover(event_id: int, payload: Dictionary) -> void:
	var entry_uuid = str(payload.get("entry_uuid", payload.get("entryUuid", ""))).strip_edges()
	var person_name = str(payload.get("person_name", payload.get("personName", ""))).strip_edges()
	var shift_role = str(payload.get("shift_role", payload.get("shiftRole", "Staff"))).strip_edges()
	var shift_date = str(payload.get("shift_date", payload.get("shiftDate", ""))).strip_edges()
	var start_time = str(payload.get("start_time", payload.get("startTime", ""))).strip_edges()
	var end_time = str(payload.get("end_time", payload.get("endTime", ""))).strip_edges()
	var area = str(payload.get("area", "Study Center")).strip_edges()
	var notes = str(payload.get("notes", "Assigned via Mobile Operational Hub")).strip_edges()
	var session_id = payload.get("session_id", payload.get("sessionId", null))

	if entry_uuid != "" and person_name != "":
		# Upsert into local Desktop schedule_entries table
		var ex_res = db.execute("SELECT id FROM schedule_entries WHERE entry_uuid = ? LIMIT 1;", [entry_uuid])
		if ex_res["success"] and ex_res["data"].size() > 0:
			db.execute("UPDATE schedule_entries SET person_name = ?, shift_role = ?, shift_date = ?, start_time = ?, end_time = ?, area = ?, notes = ?, session_id = ? WHERE entry_uuid = ?;", [person_name, shift_role, shift_date, start_time, end_time, area, notes, session_id, entry_uuid])
		else:
			db.execute("INSERT INTO schedule_entries (entry_uuid, person_name, shift_role, shift_date, start_time, end_time, area, notes, session_id, sort_order) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 99);", [entry_uuid, person_name, shift_role, shift_date, start_time, end_time, area, notes, session_id])

	db.execute("UPDATE inbound_event_queue SET processed = 1 WHERE id = ?;", [event_id])

func _process_portal_pass_request(event_id: int, payload: Dictionary) -> void:
	var channel = str(payload.get("channel", "sms")).strip_edges()
	var raw_phone = str(payload.get("phone", "")).strip_edges()
	var email = str(payload.get("email", "")).strip_edges()

	var people_res: Dictionary = {"success": false, "data": []}
	if raw_phone != "":
		people_res = db.execute("SELECT * FROM people WHERE phone = ? LIMIT 1;", [raw_phone])
	if not people_res["success"] or people_res["data"].size() == 0:
		if email != "":
			people_res = db.execute("SELECT * FROM people WHERE email = ? LIMIT 1;", [email])

	var res_status = "processed"
	var res_payload = {"status": "processed", "channel": channel}

	if people_res["success"] and people_res["data"].size() > 0:
		var person = people_res["data"][0]
		var person_id = int(person["id"])
		const CommunicationsServiceScript = preload("res://src/domain/communications/communications_service.gd")
		var comm_svc = CommunicationsServiceScript.new(db)

		if channel == "email":
			var em_res = await comm_svc.email_digital_member_pass(person_id, "Public Portal Request")
			var ok = bool(em_res.get("success", false))
			res_status = "email_sent" if ok else "email_failed"
			res_payload["result"] = em_res
			if ok:
				var target_email = email if email != "" else str(person.get("email", ""))
				db.execute("INSERT INTO digital_pass_event_log (person_id, event_type, delivery_channel, recipient_target) VALUES (?, 'sent_email', 'email', ?);", [person_id, target_email])
		else:
			var sms_res = await comm_svc.sms_digital_member_pass(self, person_id, "Public Portal Request")
			var ok = bool(sms_res.get("success", false))
			res_status = "sms_sent" if ok else "sms_failed"
			res_payload["result"] = sms_res
			if ok:
				db.execute("INSERT INTO digital_pass_event_log (person_id, event_type, delivery_channel, recipient_target) VALUES (?, 'sent_sms', 'sms', ?);", [person_id, raw_phone])

	db.execute("UPDATE inbound_event_queue SET processed = 1, status = ?, result_json = ? WHERE id = ?;", [res_status, JSON.stringify(res_payload), event_id])

func _process_portal_pass_accessed(event_id: int, payload: Dictionary) -> void:
	var token = str(payload.get("token", "")).strip_edges()
	var pass_type = str(payload.get("type", payload.get("channel", "link"))).strip_edges()
	var ua = str(payload.get("user_agent", "")).strip_edges()

	if token != "":
		var token_hash = token if token.length() == 64 else token.sha256_text().to_lower()
		var cred_res = db.execute("SELECT person_id FROM participant_qr_credentials WHERE token_hash = ? OR credential_id = ? OR token_hash = ? LIMIT 1;", [token_hash, token, token.to_lower()])
		if cred_res["success"] and cred_res["data"].size() > 0:
			var pid = int(cred_res["data"][0]["person_id"])
			var event_name = "link_accessed"
			if pass_type == "pkpass":
				event_name = "apple_wallet_served"
			elif pass_type == "google_wallet":
				event_name = "google_wallet_served"

			db.execute("INSERT INTO digital_pass_event_log (person_id, event_type, delivery_channel, user_agent) VALUES (?, ?, ?, ?);", [pid, event_name, pass_type, ua])

	db.execute("UPDATE inbound_event_queue SET processed = 1, status = 'processed' WHERE id = ?;", [event_id])


func _process_sms(event_id: int, payload: Dictionary) -> void:
	var from_phone = str(payload.get("From", "")).strip_edges()
	var to_phone = str(payload.get("To", "")).strip_edges()
	var body = str(payload.get("Body", "")).strip_edges()
	var message_sid = str(payload.get("MessageSid", "")).strip_edges()
	
	var matched_person_id = null
	if from_phone != "":
		var p_info = _find_person_by_phone(from_phone)
		if not p_info.is_empty():
			matched_person_id = p_info["id"]

	var keyword = body.to_upper().strip_edges()
	var action = ""
	if keyword == "STOP":
		action = "Opt-Out (STOP)"
		if matched_person_id != null:
			db.execute("UPDATE people SET sms_consent = 0 WHERE id = ?;", [matched_person_id])
			var sync_evt_uuid = _generate_uuid()
			var sync_payload = {
				"person_uuid": _get_person_uuid_by_id(matched_person_id),
				"sms_consent": 0,
				"updated_at": Time.get_datetime_string_from_system()
			}
			db.execute("INSERT OR IGNORE INTO event_outbox (event_uuid, event_type, aggregate_type, aggregate_id, payload_json, device_uuid, status) VALUES (?, 'PersonUpdated', 'Person', ?, ?, ?, 'pending');", [sync_evt_uuid, sync_payload["person_uuid"], JSON.stringify(sync_payload), get_device_uuid()])

	var insert_sms = """
		INSERT INTO inbound_sms_log (
			message_sid, from_phone_e164, to_phone_e164, raw_body, normalized_keyword,
			action_taken, source, processing_status, matched_person_id, is_read, received_at
		) VALUES (?, ?, ?, ?, ?, ?, ?, 'processed', ?, 0, datetime('now'));
	"""
	var db_res = db.execute(insert_sms, [
		message_sid,
		from_phone,
		to_phone,
		body,
		keyword,
		action,
		"Twilio Inbound",
		matched_person_id
	])
	if not db_res["success"]:
		print("[Processor] Failed to insert SMS: ", db_res["error"])

	var outbox_uuid = _generate_uuid()
	var outbox_payload = {
		"message_sid": message_sid,
		"from_phone": from_phone,
		"to_phone": to_phone,
		"body": body,
		"keyword": keyword,
		"action_taken": action,
		"matched_person_id": matched_person_id,
		"received_at": Time.get_datetime_string_from_system()
	}
	db.execute("INSERT OR IGNORE INTO event_outbox (event_uuid, event_type, aggregate_type, aggregate_id, payload_json, device_uuid, status) VALUES (?, 'SmsReceived', 'Sms', ?, ?, ?, 'pending');", [outbox_uuid, message_sid, JSON.stringify(outbox_payload), get_device_uuid()])

	db.execute("UPDATE inbound_event_queue SET processed = 1 WHERE id = ?;", [event_id])

func _process_voicemail(event_id: int, payload: Dictionary, completion_callback: Callable) -> void:
	var caller_phone = str(payload.get("From", "")).strip_edges()
	var call_sid = str(payload.get("CallSid", "")).strip_edges()
	var recording_url = str(payload.get("RecordingUrl", "")).strip_edges()
	var recording_sid = str(payload.get("RecordingSid", "")).strip_edges()
	var duration_sec = int(payload.get("RecordingDuration", 30))
	var transcription = str(payload.get("TranscriptionText", "")).strip_edges()
	
	if recording_sid == "" and recording_url != "":
		var idx = recording_url.find("/Recordings/")
		if idx != -1:
			recording_sid = recording_url.substr(idx + 12).strip_edges()

	if transcription == "" and (recording_sid != "" or call_sid != ""):
		var cached_res = db.execute("SELECT payload_json FROM inbound_event_queue WHERE event_type = 'twilio.transcription' AND (payload_json LIKE ? OR payload_json LIKE ?) LIMIT 1;", ["%" + recording_sid + "%", "%" + call_sid + "%"])
		if cached_res["success"] and cached_res["data"].size() > 0:
			var c_payload = JSON.parse_string(str(cached_res["data"][0]["payload_json"]))
			if typeof(c_payload) == TYPE_DICTIONARY:
				transcription = str(c_payload.get("TranscriptionText", "")).strip_edges()

	# Check for existing duplicate record in voicemails table
	if recording_sid != "":
		var dup_res = db.execute("SELECT id, voicemail_uuid, transcription FROM voicemails WHERE recording_sid = ? OR recording_url LIKE ? LIMIT 1;", [recording_sid, "%" + recording_sid + "%"])
		if dup_res["success"] and dup_res["data"].size() > 0:
			print("[Processor] Duplicate voicemail event for RecordingSid ", recording_sid, ". Marking event ", event_id, " processed.")
			db.execute("UPDATE inbound_event_queue SET processed = 1 WHERE id = ?;", [event_id])
			completion_callback.call()
			return

	var matched_person_id = null
	var caller_name = "Unknown Caller"
	if caller_phone != "":
		var p_info = _find_person_by_phone(caller_phone)
		if not p_info.is_empty():
			matched_person_id = p_info["id"]
			caller_name = p_info["name"]

	# Save record immediately (NON-BLOCKING) so ingestion NEVER gets stuck
	var vm_uuid = _save_voicemail_record(event_id, call_sid, recording_sid, caller_name, caller_phone, duration_sec, recording_url, transcription, matched_person_id)
	
	# Finish event processing callback immediately so queue is non-blocking
	completion_callback.call()

func _process_twilio_transcription(event_id: int, payload: Dictionary) -> void:
	var rec_sid = str(payload.get("RecordingSid", "")).strip_edges()
	var trans_text = str(payload.get("TranscriptionText", "")).strip_edges()
	var call_sid = str(payload.get("CallSid", "")).strip_edges()
	var caller_phone = str(payload.get("Caller", payload.get("From", ""))).strip_edges()
	var recording_url = str(payload.get("RecordingUrl", "")).strip_edges()
	
	if rec_sid != "" or call_sid != "":
		var existing = db.execute("SELECT id, voicemail_uuid, transcription FROM voicemails WHERE (recording_sid = ? AND recording_sid != '') OR (recording_url LIKE ?) OR (call_sid = ? AND call_sid != '') LIMIT 1;", [rec_sid, "%" + rec_sid + "%", call_sid])
		if existing["success"] and existing["data"].size() > 0:
			if trans_text != "":
				db.execute("UPDATE voicemails SET transcription = ? WHERE (recording_sid = ? AND recording_sid != '') OR (recording_url LIKE ?) OR (call_sid = ? AND call_sid != '');", [trans_text, rec_sid, "%" + rec_sid + "%", call_sid])
				print("[Processor] Twilio transcript updated for existing RecordingSid ", rec_sid)
		else:
			print("[Processor] Creating voicemail record directly from transcription payload for RecordingSid ", rec_sid)
			var matched_person_id = null
			var caller_name = "Unknown Caller"
			if caller_phone != "":
				var p_info = _find_person_by_phone(caller_phone)
				if not p_info.is_empty():
					matched_person_id = p_info["id"]
					caller_name = p_info["name"]
			_save_voicemail_record(event_id, call_sid, rec_sid, caller_name, caller_phone, 30, recording_url, trans_text, matched_person_id)

	db.execute("UPDATE inbound_event_queue SET processed = 1 WHERE id = ?;", [event_id])
	if parent_node and parent_node.is_inside_tree():
		parent_node.get_tree().call_group("sync_listeners", "on_inbound_events_processed", 1)

func _normalize_phone_digits(phone_str: String) -> String:
	var digits = ""
	for i in range(phone_str.length()):
		var ch = phone_str[i]
		if ch >= '0' and ch <= '9':
			digits += ch
	if digits.length() >= 10:
		return digits.substr(digits.length() - 10)
	return digits

func _find_person_by_phone(phone_str: String) -> Dictionary:
	if not db or phone_str == "": return {}
	var target_digits = _normalize_phone_digits(phone_str)
	if target_digits == "": return {}
	
	var res = db.execute("SELECT id, first_name, last_name, phone FROM people;")
	if res["success"] and res["data"].size() > 0:
		for p in res["data"]:
			var p_phone = str(p.get("phone", ""))
			if _normalize_phone_digits(p_phone) == target_digits:
				var fn = str(p.get("first_name", "")) if p.get("first_name") != null else ""
				var ln = str(p.get("last_name", "")) if p.get("last_name") != null else ""
				var full_name = (fn + " " + ln).strip_edges()
				if full_name == "" or full_name == "<null>": full_name = "Unknown Contact"
				return {"id": int(p["id"]), "name": full_name}
	return {}

func _save_voicemail_record(event_id: int, call_sid: String, recording_sid: String, caller_name: String, caller_phone: String, duration_sec: int, recording_url: String, transcription: String, matched_person_id: Variant) -> String:
	var vm_uuid = _generate_uuid()
	var insert_vm = """
		INSERT INTO voicemails (
			voicemail_uuid, caller_name, caller_phone, duration_sec, recording_url,
			transcription, status, created_at, assigned_person_id, priority, call_sid, recording_sid
		) VALUES (?, ?, ?, ?, ?, ?, 'new', datetime('now'), ?, 'Medium', ?, ?);
	"""
	var db_res = db.execute(insert_vm, [
		vm_uuid,
		caller_name,
		caller_phone,
		duration_sec,
		recording_url,
		transcription,
		matched_person_id,
		call_sid,
		recording_sid
	])
	if not db_res["success"]:
		print("[Processor] Failed to insert voicemail: ", db_res["error"])

	var outbox_uuid = _generate_uuid()
	var outbox_payload = {
		"voicemail_uuid": vm_uuid,
		"caller_name": caller_name,
		"caller_phone": caller_phone,
		"duration_sec": duration_sec,
		"recording_url": recording_url,
		"transcription": transcription,
		"matched_person_id": matched_person_id,
		"created_at": Time.get_datetime_string_from_system()
	}
	db.execute("INSERT OR IGNORE INTO event_outbox (event_uuid, event_type, aggregate_type, aggregate_id, payload_json, device_uuid, status) VALUES (?, 'VoicemailReceived', 'Voicemail', ?, ?, ?, 'pending');", [outbox_uuid, vm_uuid, JSON.stringify(outbox_payload), get_device_uuid()])

	db.execute("UPDATE inbound_event_queue SET processed = 1 WHERE id = ?;", [event_id])
	return vm_uuid

func _call_gemini_transcribe(api_key: String, recording_url: String, callback: Callable) -> void:
	var gateway_url = "https://app.reallife-studycenter.org"
	var proxy_url = gateway_url + "/api/v1/voicemails/audio?recording_url=" + recording_url.uri_encode()
	
	var url = "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key=" + api_key
	var headers = ["Content-Type: application/json"]
	var body = JSON.stringify({
		"contents": [
			{
				"parts": [
					{ "text": "Please provide an accurate text transcription of the voicemail audio file at this URL. Return ONLY the transcription text: " + proxy_url }
				]
			}
		]
	})
	
	var err = http_client.request(url, headers, HTTPClient.METHOD_POST, body)
	if err != OK:
		callback.call("[Transcription failed to start]")
		return
		
	http_client.request_completed.connect(func(_result: int, response_code: int, _r_headers: PackedStringArray, body_bytes: PackedByteArray):
		if response_code == 200:
			var resp_text = body_bytes.get_string_from_utf8()
			var json = JSON.parse_string(resp_text)
			if json and json.has("candidates") and json["candidates"].size() > 0:
				var candidate = json["candidates"][0]
				if candidate.has("content") and candidate["content"].has("parts") and candidate["content"]["parts"].size() > 0:
					var trans_text = str(candidate["content"]["parts"][0].get("text", "")).strip_edges()
					callback.call(trans_text)
					return
		callback.call("[Gemini transcription unavailable]")
	, CONNECT_ONE_SHOT)

func _get_person_uuid_by_id(person_id: int) -> String:
	var res = db.execute("SELECT person_uuid FROM people WHERE id = ? LIMIT 1;", [person_id])
	if res["success"] and res["data"].size() > 0:
		return str(res["data"][0]["person_uuid"])
	return ""

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
