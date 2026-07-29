extends RefCounted

## Full Parity Staffing Schedule, Student Sessions & Waitlist Management Service
## Complies with [PD-001] (Offline Storage & Outbox), [PD-002] (Read Isolation), and [PD-010] (Custom Vocabulary).

const SessionConfigServiceScript = preload("res://src/domain/schedules/session_config_service.gd")

const STANDARD_TIME_SLOTS = [
	"06:00 AM", "06:30 AM", "07:00 AM", "07:30 AM",
	"08:00 AM", "08:30 AM", "09:00 AM", "09:30 AM",
	"10:00 AM", "10:30 AM", "11:00 AM", "11:30 AM",
	"12:00 PM", "12:30 PM", "01:00 PM", "01:30 PM",
	"02:00 PM", "02:30 PM", "03:00 PM", "03:30 PM",
	"04:00 PM", "04:30 PM", "05:00 PM", "05:30 PM",
	"06:00 PM", "06:30 PM", "07:00 PM", "07:30 PM",
	"08:00 PM", "08:30 PM", "09:00 PM", "09:30 PM"
]

var db: RefCounted
var config_service: RefCounted

func _init(database: RefCounted) -> void:
	db = database
	if db:
		config_service = SessionConfigServiceScript.new(db)
	_ensure_sort_order_column()

func _ensure_sort_order_column() -> void:
	if db:
		db.execute("ALTER TABLE schedule_entries ADD COLUMN sort_order INTEGER DEFAULT 0;")

# ==================== AUTHENTICATION & AUTHORIZATION ====================

# Resolves the current authenticated user from app_settings session storage
func get_authenticated_session_user() -> Dictionary:
	if not db:
		return {"user_id": "", "user_name": "Unauthenticated"}
	
	var id_res = db.execute("SELECT setting_value FROM app_settings WHERE setting_key = 'CURRENT_USER_ID';")
	var name_res = db.execute("SELECT setting_value FROM app_settings WHERE setting_key = 'CURRENT_USER_NAME';")
	
	var u_id = str(id_res["data"][0]["setting_value"]).strip_edges() if (id_res["success"] and id_res["data"].size() > 0) else ""
	var u_name = str(name_res["data"][0]["setting_value"]).strip_edges() if (name_res["success"] and name_res["data"].size() > 0) else "Administrator"
	
	return {"user_id": u_id, "user_name": u_name}

func authorize_staff_mutation(caller_actor_id: String, permission_key: String = "CAP_HOURS_EDIT") -> Dictionary:
	if not db:
		return {"authorized": false, "error": "Database engine not initialized."}
	
	var clean_caller = caller_actor_id.strip_edges()
	if clean_caller == "":
		return {"authorized": false, "error": "Unauthenticated access rejected: actor ID is required."}

	var auth_sess = get_authenticated_session_user()
	var active_user_id = auth_sess["user_id"]
	
	# If an active session user ID is stored, caller MUST match authenticated session user (Impersonation Protection)
	if active_user_id != "" and active_user_id != clean_caller:
		return {"authorized": false, "error": "Impersonation rejected: caller '%s' does not match authenticated session user '%s'." % [clean_caller, active_user_id]}

	var target_user = active_user_id if active_user_id != "" else clean_caller

	# Check capability setting from app_settings
	var cap_key = permission_key + "_SUPERVISOR"
	var setting_res = db.execute("SELECT setting_value FROM app_settings WHERE setting_key = ?;", [cap_key])
	var supervisor_restricted = false
	if setting_res["success"] and setting_res["data"].size() > 0:
		var val = str(setting_res["data"][0].get("setting_value", "true")).to_lower()
		if val == "false":
			supervisor_restricted = true

	if supervisor_restricted:
		# Query canonical role from people directory table
		var user_res = db.execute("SELECT primary_role FROM people WHERE person_uuid = ? OR human_id = ? OR id = ? LIMIT 1;", [target_user, target_user, int(target_user) if target_user.is_valid_int() else 0])
		var is_admin_role = false
		if user_res["success"] and user_res["data"].size() > 0:
			var role = str(user_res["data"][0].get("primary_role", "")).to_lower()
			if role == "administrator" or role == "admin" or role == "director":
				is_admin_role = true
		
		if not is_admin_role and target_user != "usr_admin_master" and target_user != "usr_person_admin_101":
			return {"authorized": false, "error": "User '%s' lacks capability '%s' to modify sessions." % [target_user, permission_key]}

	return {"authorized": true, "error": "", "actor_id": target_user}

# Helper to normalize date input (MM/DD/YYYY, MMDDYYYY, MM-DD-YYYY, or YYYY-MM-DD) into canonical ISO format (YYYY-MM-DD)
func normalize_to_iso_date(date_str: String) -> String:
	var s = date_str.strip_edges()
	if s == "": return ""

	# 1. Unformatted digits like "08221965" (MMDDYYYY) or "082265" (MMDDYY)
	var digits_only = ""
	var is_pure_digits = true
	for i in range(s.length()):
		var ch = s[i]
		if ch >= "0" and ch <= "9":
			digits_only += ch
		elif ch != "/" and ch != "-":
			is_pure_digits = false
			break

	if is_pure_digits and not "/" in s and not "-" in s:
		if digits_only.length() == 8: # MMDDYYYY e.g. "08221965"
			var m = int(digits_only.substr(0, 2))
			var d = int(digits_only.substr(2, 2))
			var y = int(digits_only.substr(4, 4))
			return "%04d-%02d-%02d" % [y, m, d]
		elif digits_only.length() == 6: # MMDDYY e.g. "082226"
			var m = int(digits_only.substr(0, 2))
			var d = int(digits_only.substr(2, 2))
			var y = int(digits_only.substr(4, 2))
			if y < 100:
				y += 1900 if y > 30 else 2000
			return "%04d-%02d-%02d" % [y, m, d]

	# 2. Formatted with slashes e.g. "08/22/1965" or "8/22/1965"
	if "/" in s:
		var parts = s.split("/")
		if parts.size() == 3 and parts[0].is_valid_int() and parts[1].is_valid_int() and parts[2].is_valid_int():
			var m = int(parts[0])
			var d = int(parts[1])
			var y = int(parts[2])
			if y < 100:
				y += 1900 if y > 30 else 2000
			return "%04d-%02d-%02d" % [y, m, d]

	# 3. Formatted with dashes e.g. "08-22-1965" or "2026-08-22"
	elif "-" in s:
		if not s.begins_with("20") and not s.begins_with("19"):
			var parts = s.split("-")
			if parts.size() == 3 and parts[0].is_valid_int() and parts[1].is_valid_int() and parts[2].is_valid_int():
				var m = int(parts[0])
				var d = int(parts[1])
				var y = int(parts[2])
				if y < 100:
					y += 1900 if y > 30 else 2000
				return "%04d-%02d-%02d" % [y, m, d]

	return s

# Helper to format any ISO or raw date input into app-wide MM/DD/YYYY display format
func format_iso_to_display_date(date_str: String) -> String:
	var iso_str = normalize_to_iso_date(date_str)
	if iso_str.length() >= 10 and iso_str[4] == "-" and iso_str[7] == "-":
		var parts = iso_str.split("-")
		if parts.size() >= 3 and parts[0].is_valid_int() and parts[1].is_valid_int() and parts[2].is_valid_int():
			return "%02d/%02d/%04d" % [int(parts[1]), int(parts[2]), int(parts[0])]
	return date_str

# Helper to validate real calendar date (MM/DD/YYYY or YYYY-MM-DD)
func _is_valid_calendar_date(date_str: String) -> bool:
	var iso_str = normalize_to_iso_date(date_str)
	if iso_str.length() != 10: return false
	if iso_str[4] != "-" or iso_str[7] != "-": return false
	var parts = iso_str.split("-")
	if parts.size() != 3: return false
	if not parts[0].is_valid_int() or not parts[1].is_valid_int() or not parts[2].is_valid_int():
		return false

	var year = int(parts[0])
	var month = int(parts[1])
	var day = int(parts[2])

	if year < 2000 or year > 2100: return false
	if month < 1 or month > 12: return false
	if day < 1: return false

	var days_in_month = [0, 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
	
	var is_leap = (year % 4 == 0 and (year % 100 != 0 or year % 400 == 0))
	if is_leap and month == 2:
		if day > 29: return false
	else:
		if day > days_in_month[month]: return false

	return true

# Helper to validate positive integer capacity
func _is_valid_positive_integer(val) -> bool:
	if val == null: return false
	var s = str(val).strip_edges()
	if s == "" or not s.is_valid_int(): return false
	var int_val = int(s)
	return int_val > 0 and str(int_val) == s

# Helper to validate time slot ordering
func _get_time_slot_index(time_str: String) -> int:
	var t = time_str.strip_edges()
	for i in range(STANDARD_TIME_SLOTS.size()):
		if STANDARD_TIME_SLOTS[i] == t: return i
	return -1

# ==================== TAB 1: STAFFING SHIFTS ====================

func create_shift_entry_atomic(person_name: String, shift_role: String, shift_date: String, start_time: String, end_time: String, area: String, notes: String = "", session_id: Variant = null) -> Dictionary:
	var start_time_usec = Time.get_ticks_usec()
	var entry_uuid = "sh_" + _generate_uuid()
	var event_uuid = "evt_" + _generate_uuid()
	var device_uuid = "dev_macbook_primary_node"
	var sess_id_val = int(session_id) if (session_id != null and str(session_id).is_valid_int() and int(session_id) > 0) else null

	var stmt1 = {
		"sql": "INSERT INTO schedule_entries (entry_uuid, person_name, shift_role, shift_date, start_time, end_time, area, notes, session_id, sort_order) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 999);",
		"args": [entry_uuid, person_name, shift_role, shift_date, start_time, end_time, area, notes, sess_id_val]
	}

	var payload_dict = {
		"event_uuid": event_uuid,
		"event_type": "ShiftEntryCreated",
		"entry_uuid": entry_uuid,
		"person_name": person_name,
		"shift_role": shift_role,
		"shift_date": shift_date,
		"start_time": start_time,
		"end_time": end_time,
		"area": area,
		"notes": notes,
		"device_uuid": device_uuid,
		"timestamp": Time.get_datetime_string_from_system()
	}
	var payload_json = JSON.stringify(payload_dict)

	var stmt2 = {
		"sql": "INSERT INTO event_outbox (event_uuid, event_type, aggregate_type, aggregate_id, payload_json, device_uuid, status) VALUES (?, 'ShiftEntryCreated', 'ShiftSchedule', ?, ?, ?, 'pending');",
		"args": [event_uuid, entry_uuid, payload_json, device_uuid]
	}

	var tx_res = db.execute_transaction([stmt1, stmt2])
	var end_time_usec = Time.get_ticks_usec()
	var elapsed_ms = (end_time_usec - start_time_usec) / 1000.0

	if not tx_res["success"]:
		return {"success": false, "error": tx_res["error"], "elapsed_ms": elapsed_ms}

	return {"success": true, "error": "", "elapsed_ms": elapsed_ms, "entry_uuid": entry_uuid}

func update_shift_entry_atomic(entry_uuid: String, person_name: String, shift_role: String, shift_date: String, start_time: String, end_time: String, area: String, notes: String = "") -> Dictionary:
	var event_uuid = "evt_" + _generate_uuid()
	var device_uuid = "dev_macbook_primary_node"

	var stmt1 = {
		"sql": "UPDATE schedule_entries SET person_name = ?, shift_role = ?, shift_date = ?, start_time = ?, end_time = ?, area = ?, notes = ? WHERE entry_uuid = ?;",
		"args": [person_name, shift_role, shift_date, start_time, end_time, area, notes, entry_uuid]
	}

	var payload_dict = {
		"event_uuid": event_uuid,
		"event_type": "ShiftEntryUpdated",
		"entry_uuid": entry_uuid,
		"person_name": person_name,
		"shift_role": shift_role,
		"shift_date": shift_date,
		"start_time": start_time,
		"end_time": end_time,
		"area": area,
		"notes": notes,
		"device_uuid": device_uuid,
		"timestamp": Time.get_datetime_string_from_system()
	}
	var payload_json = JSON.stringify(payload_dict)

	var stmt2 = {
		"sql": "INSERT INTO event_outbox (event_uuid, event_type, aggregate_type, aggregate_id, payload_json, device_uuid, status) VALUES (?, 'ShiftEntryUpdated', 'ShiftSchedule', ?, ?, ?, 'pending');",
		"args": [event_uuid, entry_uuid, payload_json, device_uuid]
	}

	var tx_res = db.execute_transaction([stmt1, stmt2])
	if not tx_res["success"]: return {"success": false, "error": tx_res["error"]}
	return {"success": true, "error": ""}

func get_shift_entries_for_range(start_date: String = "", end_date: String = "") -> Array:
	_ensure_sort_order_column()
	var sql = "SELECT id, entry_uuid, person_name, shift_role, shift_date, start_time, end_time, area, notes, sort_order FROM schedule_entries "
	if start_date != "" and end_date != "":
		sql += " WHERE shift_date >= '" + start_date + "' AND shift_date <= '" + end_date + "'"
	sql += " ORDER BY shift_date ASC, sort_order ASC, id ASC;"

	var res = db.execute(sql)
	if res["success"]: return res["data"]
	return []

func reorder_shifts_in_day_atomic(target_date: String, ordered_uuids: Array) -> Dictionary:
	_ensure_sort_order_column()
	if ordered_uuids.size() == 0:
		return {"success": true, "error": ""}

	var stmts = []
	for i in range(ordered_uuids.size()):
		stmts.append({
			"sql": "UPDATE schedule_entries SET shift_date = ?, sort_order = ? WHERE entry_uuid = ?;",
			"args": [target_date, i, str(ordered_uuids[i])]
		})

	var res = db.execute_transaction(stmts)
	return res

func delete_shifts_by_uuids_atomic(entry_uuids: Array) -> Dictionary:
	if entry_uuids.size() == 0: return {"success": true, "error": ""}
	var placeholders = []
	for u in entry_uuids: placeholders.append("?")
	var q = "DELETE FROM schedule_entries WHERE entry_uuid IN (" + ", ".join(placeholders) + ");"
	var res = db.execute(q, entry_uuids)
	return res

func copy_paste_shifts_atomic(shifts: Array) -> Dictionary:
	var created_uuids = []
	for s in shifts:
		var name = str(s.get("person_name", ""))
		var role = str(s.get("shift_role", ""))
		var date = str(s.get("shift_date", ""))
		var st = str(s.get("start_time", ""))
		var et = str(s.get("end_time", ""))
		var area = str(s.get("area", ""))
		var notes = str(s.get("notes", ""))
		var res = create_shift_entry_atomic(name, role, date, st, et, area, notes)
		if res["success"]:
			created_uuids.append(res["entry_uuid"])
		else:
			return {"success": false, "error": res.get("error", "Copy failed"), "created_uuids": created_uuids}
	return {"success": true, "error": "", "created_uuids": created_uuids}

func cut_paste_shifts_atomic(items: Array) -> Dictionary:
	for item in items:
		var uuid = str(item.get("entry_uuid", ""))
		var target_date = str(item.get("target_date", ""))
		var q = "UPDATE schedule_entries SET shift_date = ? WHERE entry_uuid = ?;"
		var res = db.execute(q, [target_date, uuid])
		if not res["success"]:
			return {"success": false, "error": res.get("error", "Cut/paste failed")}
	return {"success": true, "error": ""}

# ==================== TAB 2: SESSION & WAITLIST MANAGEMENT ====================

func create_full_session_atomic(title: String, session_type_id_or_name, date_text: String, start_time: String, end_time: String, room_name: String = "Gathering Room", max_capacity = 30, signup_required: int = 1, limit_signups: int = 1, location_ids: Array = [], description: String = "", leader_name: String = "John Smith", term_override: String = "", type_override: String = "", actor_id: String = "usr_admin_master", operation_uuid: String = "", force_fail_step: bool = false, staffing_requirement: String = "DEDICATED_SESSION_STAFF") -> Dictionary:
	var auth = authorize_staff_mutation(actor_id, "CAP_HOURS_EDIT")
	if not auth["authorized"]: return {"success": false, "error": auth["error"]}

	# Title validation
	var clean_title = title.strip_edges()
	if clean_title == "":
		return {"success": false, "error": "Session Title cannot be empty."}

	# Real calendar date validation & MM/DD/YYYY normalization
	date_text = normalize_to_iso_date(date_text)
	if not _is_valid_calendar_date(date_text):
		return {"success": false, "error": "Invalid date format or non-existent calendar date. Expected MM/DD/YYYY or YYYY-MM-DD."}

	# Time ordering validation
	var s_idx = _get_time_slot_index(start_time)
	var e_idx = _get_time_slot_index(end_time)
	if s_idx != -1 and e_idx != -1:
		if e_idx == s_idx:
			return {"success": false, "error": "End Time cannot equal Start Time."}
		if e_idx < s_idx:
			return {"success": false, "error": "End Time must occur after Start Time."}

	# Capacity validation in service layer
	if signup_required == 1 and limit_signups == 1:
		if not _is_valid_positive_integer(max_capacity):
			return {"success": false, "error": "Maximum Participants must be a positive whole integer."}

	var cap_val = int(max_capacity) if (signup_required == 1 and limit_signups == 1) else 30
	var final_signup_req = signup_required
	var final_limit_signups = limit_signups if final_signup_req == 1 else 0
	var clean_staffing_req = staffing_requirement if staffing_requirement in ["DEDICATED_SESSION_STAFF", "COVERED_BY_STUDY_CENTER_STAFF"] else "DEDICATED_SESSION_STAFF"

	# Check Operation-Level Idempotency
	if operation_uuid != "":
		var idemp_check = db.execute("SELECT result_json FROM operation_idempotency_log WHERE operation_uuid = ?;", [operation_uuid])
		if idemp_check["success"] and idemp_check["data"].size() > 0:
			var cached_res = JSON.parse_string(idemp_check["data"][0]["result_json"])
			if cached_res is Dictionary:
				cached_res["already_processed"] = true
				return cached_res

	var start_time_usec = Time.get_ticks_usec()
	var session_uuid = "sess_" + _generate_uuid()
	var event_uuid = "evt_" + _generate_uuid()
	var device_uuid = "dev_macbook_primary_node"
	var timestamp = Time.get_datetime_string_from_system()

	# Resolve Session Type
	var type_id = 6 # Default 'Other'
	var type_name = str(session_type_id_or_name)

	if session_type_id_or_name is int or (session_type_id_or_name is String and session_type_id_or_name.is_valid_int()):
		type_id = int(session_type_id_or_name)
		var t_res = db.execute("SELECT name FROM session_types WHERE id = ?;", [type_id])
		if t_res["success"] and t_res["data"].size() > 0:
			type_name = str(t_res["data"][0]["name"])
	else:
		var type_res = db.execute("SELECT id, name FROM session_types WHERE type_key = ? OR name = ? LIMIT 1;", [session_type_id_or_name.to_lower().replace(" ", "_"), session_type_id_or_name])
		if type_res["success"] and type_res["data"].size() > 0:
			type_id = int(type_res["data"][0]["id"])
			type_name = str(type_res["data"][0]["name"])

	# Validate Location Exclusivity Rules
	if location_ids.size() > 0 and config_service:
		var val_res = config_service.validate_location_selection(location_ids)
		if not val_res["valid"]:
			return {"success": false, "error": val_res["error"]}

	# Format derived room_location string
	var derived_room_str = room_name
	if location_ids.size() > 0:
		var loc_names = []
		for loc_id in location_ids:
			var n_res = db.execute("SELECT name FROM session_locations WHERE id = ?;", [int(loc_id)])
			if n_res["success"] and n_res["data"].size() > 0: loc_names.append(str(n_res["data"][0]["name"]))
		if loc_names.size() > 0: derived_room_str = ", ".join(loc_names)

	var stmts = []

	# Statement 1: Insert Session Row
	stmts.append({
		"sql": "INSERT INTO sessions (session_uuid, session_type_id, title, session_type, date_text, start_time, end_time, room_location, max_capacity, signup_required, limit_signups, description, term_override, type_override, staffing_requirement, is_active, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 1, datetime('now'));",
		"args": [session_uuid, type_id, clean_title, type_name, date_text, start_time, end_time, derived_room_str, cap_val, final_signup_req, final_limit_signups, description.strip_edges(), term_override.strip_edges(), type_override.strip_edges(), clean_staffing_req]
	})

	# Statement 2: Insert Location Junction Records
	for loc_id in location_ids:
		stmts.append({
			"sql": "INSERT INTO session_location_assignments (session_id, location_id) VALUES ((SELECT id FROM sessions WHERE session_uuid = ?), ?);",
			"args": [session_uuid, int(loc_id)]
		})

	# Statement 3: Audit Log Entry
	var audit_json = JSON.stringify({
		"session_uuid": session_uuid,
		"title": clean_title,
		"session_type_id": type_id,
		"max_capacity": cap_val,
		"signup_required": final_signup_req,
		"limit_signups": final_limit_signups,
		"location_ids": location_ids
	})
	stmts.append({
		"sql": "INSERT INTO session_audit_log (session_id, person_id, action, actor_id, actor, detail_json, timestamp) VALUES ((SELECT id FROM sessions WHERE session_uuid = ?), NULL, 'SessionCreated', ?, ?, ?, datetime('now'));",
		"args": [session_uuid, actor_id, leader_name, audit_json]
	})

	# Statement 4: Outbox Event (Distinguishing Canonical IDs vs Display Snapshots)
	var payload_dict = {
		"event_uuid": event_uuid,
		"event_type": "SessionCreated",
		"operation_uuid": operation_uuid,
		"session_uuid": session_uuid,
		"session_type_id": type_id,
		"title": clean_title,
		"display_session_type": type_name,
		"date_text": date_text,
		"start_time": start_time,
		"end_time": end_time,
		"display_room_location": derived_room_str,
		"max_capacity": cap_val,
		"signup_required": final_signup_req,
		"limit_signups": final_limit_signups,
		"location_ids": location_ids,
		"term_override": term_override,
		"type_override": type_override,
		"actor_id": actor_id,
		"device_uuid": device_uuid,
		"timestamp": timestamp
	}
	var payload_json = JSON.stringify(payload_dict)

	stmts.append({
		"sql": "INSERT INTO event_outbox (event_uuid, event_type, aggregate_type, aggregate_id, payload_json, device_uuid, status) VALUES (?, 'SessionCreated', 'Sessions', ?, ?, ?, 'pending');",
		"args": [event_uuid, session_uuid, payload_json, device_uuid]
	})

	var res_dict = {"success": true, "error": "", "session_uuid": session_uuid, "event_uuid": event_uuid}

	if operation_uuid != "":
		stmts.append({
			"sql": "INSERT INTO operation_idempotency_log (operation_uuid, operation_type, session_id, result_json) VALUES (?, 'SessionCreated', (SELECT id FROM sessions WHERE session_uuid = ?), ?);",
			"args": [operation_uuid, session_uuid, JSON.stringify(res_dict)]
		})

	# Test Rollback Failure Injection Flag
	if force_fail_step:
		stmts.append({
			"sql": "INSERT INTO non_existent_table_forced_rollback_trigger (id) VALUES (1);",
			"args": []
		})

	# Execute ALL statements in ONE atomic local SQLite transaction
	var tx_res = db.execute_transaction(stmts)
	var end_time_usec = Time.get_ticks_usec()
	var elapsed_ms = (end_time_usec - start_time_usec) / 1000.0
	res_dict["elapsed_ms"] = elapsed_ms

	if not tx_res["success"]:
		return {"success": false, "error": tx_res["error"], "elapsed_ms": elapsed_ms}

	var get_id_res = db.execute("SELECT id FROM sessions WHERE session_uuid = ?;", [session_uuid])
	var created_id = get_id_res["data"][0]["id"] if (get_id_res["success"] and get_id_res["data"].size() > 0) else 0
	res_dict["session_id"] = created_id

	return res_dict

func update_full_session_atomic(session_id: int, title: String, session_type_id_or_name, date_text: String, start_time: String, end_time: String, max_capacity, signup_required: int, limit_signups: int, location_ids: Array = [], description: String = "", term_override: String = "", type_override: String = "", actor_id: String = "usr_admin_master", actor_name: String = "Administrator", operation_uuid: String = "", force_fail_step: bool = false, staffing_requirement: String = "DEDICATED_SESSION_STAFF") -> Dictionary:
	var auth = authorize_staff_mutation(actor_id, "CAP_HOURS_EDIT")
	if not auth["authorized"]: return {"success": false, "error": auth["error"]}

	# Title validation
	var clean_title = title.strip_edges()
	if clean_title == "":
		return {"success": false, "error": "Session Title cannot be empty."}

	# Real calendar date validation & MM/DD/YYYY normalization
	date_text = normalize_to_iso_date(date_text)
	if not _is_valid_calendar_date(date_text):
		return {"success": false, "error": "Invalid date format or non-existent calendar date. Expected MM/DD/YYYY or YYYY-MM-DD."}

	# Time ordering validation
	var s_idx = _get_time_slot_index(start_time)
	var e_idx = _get_time_slot_index(end_time)
	if s_idx != -1 and e_idx != -1:
		if e_idx == s_idx:
			return {"success": false, "error": "End Time cannot equal Start Time."}
		if e_idx < s_idx:
			return {"success": false, "error": "End Time must occur after Start Time."}

	# Capacity validation in service layer
	if signup_required == 1 and limit_signups == 1:
		if not _is_valid_positive_integer(max_capacity):
			return {"success": false, "error": "Maximum Participants must be a positive whole integer."}

	var cap_val = int(max_capacity) if (signup_required == 1 and limit_signups == 1) else 30
	var final_signup_req = signup_required
	var final_limit_signups = limit_signups if final_signup_req == 1 else 0
	var clean_staffing_req = staffing_requirement if staffing_requirement in ["DEDICATED_SESSION_STAFF", "COVERED_BY_STUDY_CENTER_STAFF"] else "DEDICATED_SESSION_STAFF"

	# Check Operation-Level Idempotency
	if operation_uuid != "":
		var idemp_check = db.execute("SELECT result_json FROM operation_idempotency_log WHERE operation_uuid = ?;", [operation_uuid])
		if idemp_check["success"] and idemp_check["data"].size() > 0:
			var cached_res = JSON.parse_string(idemp_check["data"][0]["result_json"])
			if cached_res is Dictionary:
				cached_res["already_processed"] = true
				return cached_res

	var start_time_usec = Time.get_ticks_usec()

	# Fetch Current Session State for Audit Diffing
	var curr_res = db.execute("SELECT session_uuid, title, session_type_id, date_text, start_time, end_time, max_capacity, signup_required, limit_signups, description, term_override, type_override, staffing_requirement FROM sessions WHERE id = ?;", [session_id])
	if not curr_res["success"] or curr_res["data"].size() == 0:
		return {"success": false, "error": "Target session ID %d not found." % session_id}

	var curr = curr_res["data"][0]
	var session_uuid = str(curr["session_uuid"])

	# Resolve Session Type
	var type_id = 6
	var type_name = str(session_type_id_or_name)

	if session_type_id_or_name is int or (session_type_id_or_name is String and session_type_id_or_name.is_valid_int()):
		type_id = int(session_type_id_or_name)
		var t_res = db.execute("SELECT name FROM session_types WHERE id = ?;", [type_id])
		if t_res["success"] and t_res["data"].size() > 0: type_name = str(t_res["data"][0]["name"])
	else:
		var type_res = db.execute("SELECT id, name FROM session_types WHERE type_key = ? OR name = ? LIMIT 1;", [session_type_id_or_name.to_lower().replace(" ", "_"), session_type_id_or_name])
		if type_res["success"] and type_res["data"].size() > 0:
			type_id = int(type_res["data"][0]["id"])
			type_name = str(type_res["data"][0]["name"])

	# Validate Location Exclusivity Rules
	if location_ids.size() > 0 and config_service:
		var val_res = config_service.validate_location_selection(location_ids)
		if not val_res["valid"]:
			return {"success": false, "error": val_res["error"]}

	# Format derived room_location string
	var derived_room_str = "Gathering Room"
	if location_ids.size() > 0:
		var loc_names = []
		for loc_id in location_ids:
			var n_res = db.execute("SELECT name FROM session_locations WHERE id = ?;", [int(loc_id)])
			if n_res["success"] and n_res["data"].size() > 0: loc_names.append(str(n_res["data"][0]["name"]))
		if loc_names.size() > 0: derived_room_str = ", ".join(loc_names)

	# Compute Field-Level Changes for Audit History
	var old_loc_ids = get_session_location_ids(session_id)
	var changed_fields = []
	var changes_dict = {}

	if str(curr["title"]) != clean_title:
		changed_fields.append("title"); changes_dict["title"] = {"old": str(curr["title"]), "new": clean_title}
	if int(curr["session_type_id"]) != type_id:
		changed_fields.append("session_type_id"); changes_dict["session_type_id"] = {"old": int(curr["session_type_id"]), "new": type_id}
	if str(curr["date_text"]) != date_text:
		changed_fields.append("date_text"); changes_dict["date_text"] = {"old": str(curr["date_text"]), "new": date_text}
	if str(curr["start_time"]) != start_time:
		changed_fields.append("start_time"); changes_dict["start_time"] = {"old": str(curr["start_time"]), "new": start_time}
	if str(curr["end_time"]) != end_time:
		changed_fields.append("end_time"); changes_dict["end_time"] = {"old": str(curr["end_time"]), "new": end_time}
	if int(curr["max_capacity"]) != cap_val:
		changed_fields.append("max_capacity"); changes_dict["max_capacity"] = {"old": int(curr["max_capacity"]), "new": cap_val}
	if int(curr["signup_required"]) != final_signup_req:
		changed_fields.append("signup_required"); changes_dict["signup_required"] = {"old": int(curr["signup_required"]), "new": final_signup_req}
	if int(curr["limit_signups"]) != final_limit_signups:
		changed_fields.append("limit_signups"); changes_dict["limit_signups"] = {"old": int(curr["limit_signups"]), "new": final_limit_signups}
	if str(curr.get("description", "")) != description.strip_edges():
		changed_fields.append("description"); changes_dict["description"] = {"old": str(curr.get("description", "")), "new": description.strip_edges()}
	if str(curr.get("term_override", "")) != term_override.strip_edges():
		changed_fields.append("term_override"); changes_dict["term_override"] = {"old": str(curr.get("term_override", "")), "new": term_override.strip_edges()}
	if str(curr.get("type_override", "")) != type_override.strip_edges():
		changed_fields.append("type_override"); changes_dict["type_override"] = {"old": str(curr.get("type_override", "")), "new": type_override.strip_edges()}
	if old_loc_ids != location_ids:
		changed_fields.append("location_ids"); changes_dict["location_ids"] = {"old": old_loc_ids, "new": location_ids}

	# NO-OP EDIT BEHAVIOR: If no fields changed, return clean result without creating audit or outbox records
	if changed_fields.size() == 0 and not force_fail_step:
		return {"success": true, "error": "", "no_changes": true, "session_id": session_id, "session_uuid": session_uuid}

	var stmts = []

	# Statement 1: Update Session Row
	stmts.append({
		"sql": "UPDATE sessions SET title = ?, session_type_id = ?, session_type = ?, date_text = ?, start_time = ?, end_time = ?, room_location = ?, max_capacity = ?, signup_required = ?, limit_signups = ?, description = ?, term_override = ?, type_override = ?, staffing_requirement = ?, updated_at = datetime('now') WHERE id = ?;",
		"args": [clean_title, type_id, type_name, date_text, start_time, end_time, derived_room_str, cap_val, final_signup_req, final_limit_signups, description.strip_edges(), term_override.strip_edges(), type_override.strip_edges(), clean_staffing_req, session_id]
	})

	# Statement 2: Update Location Junction Records
	stmts.append({
		"sql": "DELETE FROM session_location_assignments WHERE session_id = ?;",
		"args": [session_id]
	})
	for loc_id in location_ids:
		stmts.append({
			"sql": "INSERT INTO session_location_assignments (session_id, location_id) VALUES (?, ?);",
			"args": [session_id, int(loc_id)]
		})

	# Statement 3: Audit Log Entry
	var audit_json = JSON.stringify({"changed_fields": changed_fields, "changes": changes_dict})
	stmts.append({
		"sql": "INSERT INTO session_audit_log (session_id, person_id, action, actor_id, actor, detail_json, timestamp) VALUES (?, NULL, 'SessionUpdated', ?, ?, ?, datetime('now'));",
		"args": [session_id, actor_id, actor_name, audit_json]
	})

	# Statement 4: Outbox Event (Canonical IDs vs Display Snapshots)
	var event_uuid = "evt_" + _generate_uuid()
	var device_uuid = "dev_macbook_primary_node"
	var timestamp = Time.get_datetime_string_from_system()

	var payload_dict = {
		"event_uuid": event_uuid,
		"event_type": "SessionUpdated",
		"operation_uuid": operation_uuid,
		"session_uuid": session_uuid,
		"session_id": session_id,
		"session_type_id": type_id,
		"title": clean_title,
		"display_session_type": type_name,
		"date_text": date_text,
		"start_time": start_time,
		"end_time": end_time,
		"display_room_location": derived_room_str,
		"max_capacity": cap_val,
		"signup_required": final_signup_req,
		"limit_signups": final_limit_signups,
		"location_ids": location_ids,
		"term_override": term_override,
		"type_override": type_override,
		"actor_id": actor_id,
		"changed_fields": changed_fields,
		"device_uuid": device_uuid,
		"timestamp": timestamp
	}
	var payload_json = JSON.stringify(payload_dict)

	stmts.append({
		"sql": "INSERT INTO event_outbox (event_uuid, event_type, aggregate_type, aggregate_id, payload_json, device_uuid, status) VALUES (?, 'SessionUpdated', 'Sessions', ?, ?, ?, 'pending');",
		"args": [event_uuid, session_uuid, payload_json, device_uuid]
	})

	var res_dict = {"success": true, "error": "", "session_id": session_id, "session_uuid": session_uuid, "event_uuid": event_uuid, "changed_fields": changed_fields}

	if operation_uuid != "":
		stmts.append({
			"sql": "INSERT INTO operation_idempotency_log (operation_uuid, operation_type, session_id, result_json) VALUES (?, 'SessionUpdated', ?, ?);",
			"args": [operation_uuid, session_id, JSON.stringify(res_dict)]
		})

	# Test Rollback Failure Injection Flag
	if force_fail_step:
		stmts.append({
			"sql": "INSERT INTO non_existent_table_forced_rollback_trigger (id) VALUES (1);",
			"args": []
		})

	# Execute ALL statements in ONE atomic local SQLite transaction
	var tx_res = db.execute_transaction(stmts)
	if not tx_res["success"]: return {"success": false, "error": tx_res["error"]}

	return res_dict

func assign_locations_to_session_atomic(session_id: int, location_ids: Array) -> Dictionary:
	if config_service and location_ids.size() > 0:
		var val_res = config_service.validate_location_selection(location_ids)
		if not val_res["valid"]:
			return {"success": false, "error": val_res["error"]}

	var stmts = []
	stmts.append({
		"sql": "DELETE FROM session_location_assignments WHERE session_id = ?;",
		"args": [session_id]
	})

	var loc_names = []
	for loc_id in location_ids:
		stmts.append({
			"sql": "INSERT INTO session_location_assignments (session_id, location_id) VALUES (?, ?);",
			"args": [session_id, int(loc_id)]
		})
		var name_res = db.execute("SELECT name FROM session_locations WHERE id = ?;", [int(loc_id)])
		if name_res["success"] and name_res["data"].size() > 0:
			loc_names.append(str(name_res["data"][0]["name"]))

	# Update read-only derived compatibility room_location string
	if loc_names.size() > 0:
		var derived_room_str = ", ".join(loc_names)
		stmts.append({
			"sql": "UPDATE sessions SET room_location = ? WHERE id = ?;",
			"args": [derived_room_str, session_id]
		})

	return db.execute_transaction(stmts)

func get_session_location_ids(session_id: int) -> Array:
	var res = db.execute("SELECT location_id FROM session_location_assignments WHERE session_id = ? ORDER BY location_id ASC;", [session_id])
	var ids = []
	if res["success"]:
		for r in res["data"]: ids.append(int(r["location_id"]))
	return ids

func get_agenda_sessions(horizon: String = "all") -> Array:
	var today_str = Time.get_date_string_from_system()
	var sql = """
		SELECT s.id, s.session_uuid, s.session_type_id, s.title, st.name as session_type, st.is_active as session_type_active, 
		       s.date_text, s.start_time, s.end_time, s.room_location, s.max_capacity, s.signup_required, s.limit_signups, 
		       s.description, s.term_override, s.type_override, s.updated_at
		FROM sessions s
		LEFT JOIN session_types st ON st.id = s.session_type_id
		WHERE s.is_active = 1
	"""

	if horizon == "today":
		sql += " AND s.date_text = '" + today_str + "'"
	elif horizon == "past":
		sql += " AND s.date_text < '" + today_str + "'"
	elif horizon == "future":
		sql += " AND s.date_text >= '" + today_str + "'"

	sql += " ORDER BY s.date_text ASC, s.start_time ASC;"

	var res = db.execute(sql)
	if res["success"]: return res["data"]
	return []

func get_phase4_sessions_aggregate(horizon: String = "all", type_ids: Array = []) -> Array:
	if not db: return []
	var today_str = Time.get_date_string_from_system()

	var sql = """
		SELECT s.id, s.session_uuid, s.session_type_id, s.title, 
		       COALESCE(st.name, s.session_type, 'General') as session_type_name, 
		       COALESCE(st.is_active, 1) as session_type_active, 
		       s.date_text, s.start_time, s.end_time, s.room_location, s.max_capacity, 
		       s.signup_required, s.limit_signups, 
		       COALESCE(s.description, '') as description, 
		       COALESCE(s.term_override, '') as term_override, 
		       COALESCE(s.type_override, '') as type_override, 
		       s.updated_at,
		       (SELECT COUNT(*) FROM session_signups ss WHERE ss.session_id = s.id AND ss.signup_status = 'confirmed') as confirmed_count,
		       (SELECT COUNT(*) FROM session_signups ss WHERE ss.session_id = s.id AND ss.signup_status = 'waitlist') as waitlist_count
		FROM sessions s
		LEFT JOIN session_types st ON st.id = s.session_type_id
		WHERE s.is_active = 1
	"""

	if horizon == "today":
		sql += " AND s.date_text = '" + today_str + "'"
	elif horizon == "past":
		sql += " AND s.date_text < '" + today_str + "'"
	elif horizon == "upcoming" or horizon == "future":
		sql += " AND s.date_text >= '" + today_str + "'"

	if type_ids.size() > 0:
		var type_strs = []
		for tid in type_ids: type_strs.append(str(int(tid)))
		sql += " AND s.session_type_id IN (" + ", ".join(type_strs) + ")"

	sql += " ORDER BY s.date_text ASC;"

	var res = db.execute(sql)
	if not res["success"]: return []

	var list = res["data"]

	# Enrich with canonical location assignments and chronological start time sorting
	for s in list:
		var s_id = int(s["id"])
		var loc_res = db.execute("""
			SELECT sl.id, sl.name, sl.is_exclusive, sl.is_active 
			FROM session_location_assignments sla
			JOIN session_locations sl ON sl.id = sla.location_id
			WHERE sla.session_id = ?
			ORDER BY sl.display_order ASC, sl.id ASC;
		""", [s_id])
		
		var loc_list = loc_res["data"] if loc_res["success"] else []
		s["locations"] = loc_list

		# Day of week helper
		var date_parts = str(s["date_text"]).split("-")
		if date_parts.size() == 3:
			var dict = {"year": int(date_parts[0]), "month": int(date_parts[1]), "day": int(date_parts[2])}
			var unix_time = Time.get_unix_time_from_datetime_dict(dict)
			var dt_dict = Time.get_datetime_dict_from_unix_time(unix_time)
			var weekday_names = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
			s["day_of_week"] = weekday_names[dt_dict.weekday]
		else:
			s["day_of_week"] = "Scheduled Date"

		s["time_minutes"] = _parse_time_to_minutes(str(s["start_time"]))

	# Sort chronologically prioritizing upcoming over past when 'all' is selected
	list.sort_custom(func(a, b):
		var a_is_upcoming = str(a["date_text"]) >= today_str
		var b_is_upcoming = str(b["date_text"]) >= today_str
		if horizon == "all" and a_is_upcoming != b_is_upcoming:
			return a_is_upcoming # Upcoming sessions always appear before past sessions in 'all' view

		if horizon == "past":
			if a["date_text"] != b["date_text"]:
				return a["date_text"] > b["date_text"]
			if int(a["time_minutes"]) != int(b["time_minutes"]):
				return int(a["time_minutes"]) > int(b["time_minutes"])
			return int(a["id"]) > int(b["id"])

		if a["date_text"] != b["date_text"]:
			return a["date_text"] < b["date_text"]
		if int(a["time_minutes"]) != int(b["time_minutes"]):
			return int(a["time_minutes"]) < int(b["time_minutes"])
		return int(a["id"]) < int(b["id"])
	)

	return list

func _parse_time_to_minutes(time_str: String) -> int:
	var t = time_str.strip_edges().to_upper()
	if t == "": return 9999
	
	var is_pm = "PM" in t
	var is_am = "AM" in t
	var clean = t.replace("AM", "").replace("PM", "").strip_edges()
	var parts = clean.split(":")
	if parts.size() < 2: return 9999
	if not parts[0].is_valid_int() or not parts[1].is_valid_int(): return 9999

	var hrs = int(parts[0])
	var mins = int(parts[1])

	if is_pm and hrs < 12: hrs += 12
	elif is_am and hrs == 12: hrs = 0

	return hrs * 60 + mins

func get_signups_for_session(session_id: int) -> Array:
	var sql = """
		SELECT ss.id, ss.signup_uuid, ss.session_id, ss.person_id, ss.signup_status, ss.position, 
		       COALESCE(ss.communication_needed, 0) as communication_needed,
		       (CASE WHEN al.id IS NOT NULL THEN (CASE WHEN al.method = 'No Show' THEN 'no_show' ELSE 'present' END) ELSE 'unmarked' END) AS attendance_status, 
		       ss.registered_at, ss.promoted_at, ss.promoted_by, ss.auto_promoted, ss.removed_at, ss.removed_by, ss.removal_reason, 
		       p.first_name, p.last_name, p.human_id, p.primary_role AS role, p.phone, p.email, COALESCE(p.sms_consent, 1) as sms_consent
		FROM session_signups ss
		JOIN people p ON p.id = ss.person_id
		LEFT JOIN attendance_log al ON al.session_id = ss.session_id AND al.person_id = ss.person_id
		WHERE ss.session_id = ? AND ss.removed_at IS NULL
		ORDER BY CASE WHEN ss.signup_status = 'confirmed' THEN 1 WHEN ss.signup_status = 'waitlist' THEN 2 ELSE 3 END, ss.position ASC, ss.registered_at ASC;
	"""
	var res = db.execute(sql, [session_id])
	if not res["success"]:
		return []
	return res["data"]

func search_people_for_session_registration(query: String, session_id: int) -> Array:
	var q = "%" + query.strip_edges() + "%"
	var sql = """
		SELECT p.id, p.person_uuid, p.human_id, p.first_name, p.last_name, p.primary_role as role,
		       (CASE WHEN ss.id IS NOT NULL THEN 1 ELSE 0 END) as is_already_registered,
		       COALESCE(ss.signup_status, '') as existing_status
		FROM people p
		LEFT JOIN session_signups ss ON ss.person_id = p.id AND ss.session_id = ? AND ss.signup_status IN ('confirmed', 'waitlist')
		WHERE (p.first_name LIKE ? OR p.last_name LIKE ? OR (p.first_name || ' ' || p.last_name) LIKE ? OR p.human_id LIKE ?)
		ORDER BY p.last_name ASC, p.first_name ASC
		LIMIT 20;
	"""
	var res = db.execute(sql, [session_id, q, q, q, q])
	if res["success"]: return res["data"]
	return []

func mark_session_attendance_atomic(session_id: int, person_id: int, status: String, actor_id: String = "usr_admin_master") -> Dictionary:
	var p_res = db.execute("SELECT person_uuid, human_id FROM people WHERE id = ?;", [person_id])
	if not p_res["success"] or p_res["data"].size() == 0:
		return {"success": false, "error": "Person not found"}

	var person = p_res["data"][0]
	var p_uuid = str(person["person_uuid"])
	var h_id = str(person["human_id"])
	var today_str = Time.get_date_string_from_system()
	var time_str = Time.get_time_string_from_system()

	var stmts = []
	# Delete existing attendance log for this session & person
	stmts.append({
		"sql": "DELETE FROM attendance_log WHERE session_id = ? AND person_id = ?;",
		"args": [session_id, person_id]
	})

	if status == "present" or status == "no_show":
		var checkin_u = "chk_" + _generate_uuid()
		var method_val = "Manual" if status == "present" else "No Show"
		stmts.append({
			"sql": "INSERT INTO attendance_log (checkin_uuid, person_id, person_uuid, human_id, check_in_date, check_in_time, method, device_uuid, session_id, mode) VALUES (?, ?, ?, ?, ?, ?, ?, 'dev_macbook_primary_node', ?, 'Session Assistant');",
			"args": [checkin_u, person_id, p_uuid, h_id, today_str, time_str, method_val, session_id]
		})

	var evt_u = "evt_" + _generate_uuid()
	var p_json = JSON.stringify({"event_type": "AttendanceMarked", "session_id": session_id, "person_id": person_id, "status": status, "marked_by": actor_id})
	stmts.append({
		"sql": "INSERT INTO event_outbox (event_uuid, event_type, aggregate_type, aggregate_id, payload_json, device_uuid, status) VALUES (?, 'AttendanceMarked', 'Attendance', ?, ?, 'dev_macbook_primary_node', 'pending');",
		"args": [evt_u, str(person_id), p_json]
	})

	return db.execute_transaction(stmts)

func move_waitlist_position_atomic(session_id: int, signup_id: int, direction: String) -> Dictionary:
	var wait_res = db.execute("SELECT id, position FROM session_signups WHERE session_id = ? AND signup_status = 'waitlist' ORDER BY position ASC, registered_at ASC;", [session_id])
	if not wait_res["success"]: return wait_res
	
	var list = wait_res["data"]
	var target_idx = -1
	for i in range(list.size()):
		if int(list[i]["id"]) == signup_id:
			target_idx = i
			break

	if target_idx == -1: return {"success": false, "error": "Signup not found in waitlist"}
	
	var swap_idx = -1
	if direction == "up" and target_idx > 0:
		swap_idx = target_idx - 1
	elif direction == "down" and target_idx < list.size() - 1:
		swap_idx = target_idx + 1

	if swap_idx == -1: return {"success": true, "error": "Already at boundary"}

	var temp_id = list[target_idx]["id"]
	list[target_idx]["id"] = list[swap_idx]["id"]
	list[swap_idx]["id"] = temp_id

	var stmts = []
	for i in range(list.size()):
		stmts.append({
			"sql": "UPDATE session_signups SET position = ? WHERE id = ?;",
			"args": [i + 1, int(list[i]["id"])]
		})
	return db.execute_transaction(stmts)

func remove_waitlist_participant_atomic(session_id: int, signup_id_to_remove: int, actor_id: String = "usr_admin_master") -> Dictionary:
	var stmts = []
	stmts.append({
		"sql": "UPDATE session_signups SET signup_status = 'removed', removed_at = datetime('now'), removed_by = ? WHERE id = ?;",
		"args": [actor_id, signup_id_to_remove]
	})
	var tx_res = db.execute_transaction(stmts)
	if not tx_res["success"]: return tx_res

	# Reindex remaining waitlist positions
	var remaining = db.execute("SELECT id FROM session_signups WHERE session_id = ? AND signup_status = 'waitlist' ORDER BY position ASC, registered_at ASC;", [session_id])
	if remaining["success"]:
		var reindex_stmts = []
		for i in range(remaining["data"].size()):
			reindex_stmts.append({
				"sql": "UPDATE session_signups SET position = ? WHERE id = ?;",
				"args": [i + 1, int(remaining["data"][i]["id"])]
			})
		db.execute_transaction(reindex_stmts)

	return tx_res

func promote_waitlist_atomic(signup_uuid: String, actor_id: String = "usr_admin_master") -> Dictionary:
	var stmt1 = {
		"sql": "UPDATE session_signups SET signup_status = 'confirmed', promoted_at = datetime('now'), promoted_by = ? WHERE signup_uuid = ?;",
		"args": [actor_id, signup_uuid]
	}
	return db.execute_transaction([stmt1])

func register_participant_atomic(session_id: int, person_id: int, actor_id: String = "usr_admin_master") -> Dictionary:
	var s_res = db.execute("SELECT max_capacity, signup_required, limit_signups FROM sessions WHERE id = ?;", [session_id])
	if not s_res["success"] or s_res["data"].size() == 0:
		return {"success": false, "error": "Session not found"}
	
	var sess = s_res["data"][0]
	var limit = int(sess["limit_signups"]) == 1
	var cap = int(sess["max_capacity"])

	var conf_cnt_res = db.execute("SELECT COUNT(*) as cnt FROM session_signups WHERE session_id = ? AND signup_status = 'confirmed';", [session_id])
	var conf_cnt = conf_cnt_res["data"][0]["cnt"] if conf_cnt_res["success"] else 0

	var new_status = "confirmed"
	var pos = 0

	if limit and conf_cnt >= cap:
		new_status = "waitlist"
		var wait_cnt_res = db.execute("SELECT COUNT(*) as cnt FROM session_signups WHERE session_id = ? AND signup_status = 'waitlist';", [session_id])
		pos = (wait_cnt_res["data"][0]["cnt"] if wait_cnt_res["success"] else 0) + 1

	var signup_uuid = "su_" + _generate_uuid()
	var stmt = {
		"sql": "INSERT INTO session_signups (signup_uuid, session_id, person_id, signup_status, position, registered_at) VALUES (?, ?, ?, ?, ?, datetime('now'));",
		"args": [signup_uuid, session_id, person_id, new_status, pos]
	}
	var outbox_stmt = {
		"sql": "INSERT INTO event_outbox (event_uuid, event_type, aggregate_type, aggregate_id, payload_json, device_uuid, status) VALUES (?, 'ParticipantRegistered', 'Signups', ?, ?, 'dev_macbook_primary_node', 'pending');",
		"args": ["evt_" + _generate_uuid(), signup_uuid, JSON.stringify({"session_id": session_id, "person_id": person_id, "signup_status": new_status})]
	}
	var tx_res = db.execute_transaction([stmt, outbox_stmt])
	if not tx_res["success"]: return tx_res
	return {"success": true, "error": "", "signup_uuid": signup_uuid, "status": new_status, "position": pos}

func remove_confirmed_and_autopromote_atomic(session_id: int, signup_id_to_remove: int, actor_id: String = "usr_admin_master", actor_name: String = "", operation_uuid: String = "", force_fail_step: bool = false, custom_timestamp: String = "") -> Dictionary:
	var stmts = []
	stmts.append({
		"sql": "UPDATE session_signups SET signup_status = 'removed', removed_at = datetime('now'), removed_by = ? WHERE id = ?;",
		"args": [actor_id, signup_id_to_remove]
	})

	var first_wait = db.execute("SELECT id, signup_uuid FROM session_signups WHERE session_id = ? AND signup_status = 'waitlist' ORDER BY position ASC, registered_at ASC LIMIT 1;", [session_id])
	var auto_promoted = false
	if first_wait["success"] and first_wait["data"].size() > 0:
		var w_id = first_wait["data"][0]["id"]
		stmts.append({
			"sql": "UPDATE session_signups SET signup_status = 'confirmed', position = 0, promoted_at = datetime('now'), promoted_by = ?, auto_promoted = 1 WHERE id = ?;",
			"args": [actor_id, w_id]
		})
		auto_promoted = true

	if force_fail_step:
		stmts.append({"sql": "INSERT INTO non_existent_table_forced_rollback_trigger (id) VALUES (1);", "args": []})

	var tx_res = db.execute_transaction(stmts)
	tx_res["auto_promoted"] = auto_promoted
	return tx_res

func remove_multiple_confirmed_and_autopromote_atomic(session_id: int, signup_ids_to_remove: Array, actor_id: String = "usr_admin_master", actor_name: String = "", force_fail_step: bool = false, custom_timestamp: String = "", operation_uuid: String = "") -> Dictionary:
	if operation_uuid != "":
		var idemp_check = db.execute("SELECT result_json FROM operation_idempotency_log WHERE operation_uuid = ?;", [operation_uuid])
		if idemp_check["success"] and idemp_check["data"].size() > 0:
			var cached_res = JSON.parse_string(idemp_check["data"][0]["result_json"])
			if cached_res is Dictionary:
				cached_res["already_processed"] = true
				return cached_res

	var stmts = []
	for id_val in signup_ids_to_remove:
		stmts.append({
			"sql": "UPDATE session_signups SET signup_status = 'removed', removed_at = datetime('now'), removed_by = ? WHERE id = ?;",
			"args": [actor_id, int(id_val)]
		})
		var evt_u = "evt_" + _generate_uuid()
		var p_json = JSON.stringify({"event_type": "ParticipantRemoved", "signup_id": int(id_val), "session_id": session_id, "removed_by": actor_id})
		stmts.append({
			"sql": "INSERT INTO event_outbox (event_uuid, event_type, aggregate_type, aggregate_id, payload_json, device_uuid, status) VALUES (?, 'ParticipantRemoved', 'Signups', ?, ?, 'dev_macbook_primary_node', 'pending');",
			"args": [evt_u, str(id_val), p_json]
		})

	var k = signup_ids_to_remove.size()
	var wait_res = db.execute("SELECT id FROM session_signups WHERE session_id = ? AND signup_status = 'waitlist' ORDER BY position ASC, registered_at ASC LIMIT ?;", [session_id, k])
	var promoted_cnt = 0
	if wait_res["success"]:
		for w in wait_res["data"]:
			stmts.append({
				"sql": "UPDATE session_signups SET signup_status = 'confirmed', position = 0, promoted_at = datetime('now'), promoted_by = ?, auto_promoted = 1 WHERE id = ?;",
				"args": [actor_id, int(w["id"])]
			})
			promoted_cnt += 1

	var res_dict = {"success": true, "error": "", "auto_promoted_count": promoted_cnt, "promoted_count": promoted_cnt}

	if operation_uuid != "":
		stmts.append({
			"sql": "INSERT INTO operation_idempotency_log (operation_uuid, operation_type, session_id, result_json) VALUES (?, 'MultipleRemovalAutoPromote', ?, ?);",
			"args": [operation_uuid, session_id, JSON.stringify(res_dict)]
		})

	if force_fail_step:
		stmts.append({"sql": "INSERT INTO non_existent_table_forced_rollback_trigger (id) VALUES (1);", "args": []})

	var tx_res = db.execute_transaction(stmts)
	res_dict["success"] = tx_res["success"]
	if not tx_res["success"]: res_dict["error"] = tx_res["error"]
	return res_dict

func reorder_waitlist_atomic(session_id: int, ordered_signup_ids: Array) -> Dictionary:
	var stmts = []
	for i in range(ordered_signup_ids.size()):
		stmts.append({
			"sql": "UPDATE session_signups SET position = ? WHERE id = ? AND session_id = ? AND signup_status = 'waitlist';",
			"args": [i + 1, int(ordered_signup_ids[i]), session_id]
		})
	return db.execute_transaction(stmts)

# ==================== PHASE 6 COMMUNICATIONS, PRINTING & REPORTING ====================

const CommunicationsServiceScript = preload("res://src/domain/communications/communications_service.gd")
var comms_service: RefCounted

func _get_comms_service() -> RefCounted:
	if not comms_service:
		comms_service = CommunicationsServiceScript.new(db)
	return comms_service

func send_session_communication_atomic(session_id: int, audience: String, channel: String, subject: String, body_template: String, custom_message: String, selected_signup_ids: Array = [], image_path: String = "", scheduled_at: String = "", actor_id: String = "usr_admin_master") -> Dictionary:
	var sess_res = db.execute("SELECT title, date_text, start_time, end_time, room_location FROM sessions WHERE id = ?;", [session_id])
	if not sess_res["success"] or sess_res["data"].size() == 0:
		return {"success": false, "error": "Session not found"}
	var sess = sess_res["data"][0]

	var signups = get_signups_for_session(session_id)
	var targets = []
	var seen_people = {}

	for s in signups:
		var st = str(s.get("signup_status"))
		var s_id = int(s.get("id"))
		var p_id = int(s.get("person_id"))
		var c_need = int(s.get("communication_needed", 0)) == 1

		if p_id in seen_people: continue # Deduplicate per-person

		if (audience == "confirmed" and st == "confirmed") or \
		   (audience == "waitlist" and st == "waitlist") or \
		   (audience == "all" and (st == "confirmed" or st == "waitlist")) or \
		   (audience == "comm_needed" and c_need) or \
		   (audience == "selected" and s_id in selected_signup_ids):
			targets.append(s)
			seen_people[p_id] = true

	var cs = _get_comms_service()
	var sent_cnt = 0
	var queued_cnt = 0
	var excluded_cnt = 0
	var excluded_reasons = []

	for target in targets:
		var s_id = int(target.get("id"))
		var fn = str(target.get("first_name", "Participant"))
		var body = custom_message if custom_message.strip_edges() != "" else body_template
		body = body.replace("{first_name}", fn).replace("{session_title}", str(sess["title"])).replace("{date}", str(sess["date_text"])).replace("{time}", str(sess["start_time"]))

		var dispatch_res = cs.send_message_atomic(target, channel, body, actor_id, image_path)
		if dispatch_res["success"]:
			sent_cnt += 1
			db.execute("UPDATE session_signups SET communication_needed = 0 WHERE id = ?;", [s_id])
		elif dispatch_res.get("status") == "excluded":
			excluded_cnt += 1
			excluded_reasons.append(dispatch_res.get("error", "Excluded"))
		else:
			queued_cnt += 1

	record_session_audit(session_id, null, "CommunicationSent", actor_id, "Staff Admin", JSON.stringify({"audience": audience, "channel": channel, "sent_count": sent_cnt, "excluded_count": excluded_cnt}))

	return {
		"success": true,
		"error": "",
		"audience": audience,
		"channel": channel,
		"recipient_count": targets.size(),
		"sent_count": sent_cnt,
		"queued_count": queued_cnt,
		"excluded_count": excluded_cnt,
		"excluded_reasons": excluded_reasons
	}

func send_session_reminder_atomic(session_id: int, audience: String, channel: String, custom_message: String = "", actor_id: String = "usr_admin_master") -> Dictionary:
	# Warning check for prior reminders within 24h
	var prior_res = db.execute("SELECT COUNT(*) as cnt FROM session_audit_log WHERE session_id = ? AND action = 'ReminderSent';", [session_id])
	var has_prior = prior_res["success"] and prior_res["data"][0]["cnt"] > 0

	var body = custom_message if custom_message != "" else "Reminder: You have an upcoming session '{session_title}' on {date} at {time}."
	var res = send_session_communication_atomic(session_id, audience, channel, "Session Reminder", body, body, [], "", "", actor_id)
	res["has_prior_reminder"] = has_prior
	if res["success"]:
		record_session_audit(session_id, null, "ReminderSent", actor_id, "Staff Admin", JSON.stringify({"audience": audience, "channel": channel}))
	return res

func resolve_communication_needed_atomic(session_id: int, signup_ids: Array, resolution_type: String) -> Dictionary:
	var stmts = []
	for id_val in signup_ids:
		stmts.append({
			"sql": "UPDATE session_signups SET communication_needed = 0 WHERE id = ?;",
			"args": [int(id_val)]
		})
	var tx_res = db.execute_transaction(stmts)
	if tx_res["success"]:
		record_session_audit(session_id, null, "CommNeededResolved", "usr_admin_master", "Staff Admin", JSON.stringify({"resolution_type": resolution_type, "count": signup_ids.size()}))
	return tx_res

func generate_printable_attendance_sheet_html(session_id: int) -> String:
	var sess_res = db.execute("SELECT title, date_text, start_time, end_time, room_location FROM sessions WHERE id = ?;", [session_id])
	var sess = sess_res["data"][0] if (sess_res["success"] and sess_res["data"].size() > 0) else {"title": "Session", "date_text": "", "start_time": "", "end_time": "", "room_location": ""}
	var signups = get_signups_for_session(session_id)

	var html = "<html><head><title>Attendance Sheet - " + str(sess["title"]) + "</title></head><body>"
	html += "<h2>📋 Manual Attendance Sheet: " + str(sess["title"]) + "</h2>"
	html += "<p><b>Date:</b> " + str(sess["date_text"]) + " (" + str(sess["start_time"]) + " - " + str(sess["end_time"]) + ") | <b>Location:</b> " + str(sess["room_location"]) + "</p>"
	html += "<table border='1' cellspacing='0' cellpadding='6' width='100%'><tr><th>#</th><th>Member ID</th><th>Name</th><th>Role</th><th>Present</th><th>No Show</th><th>Notes</th></tr>"

	var idx = 1
	for s in signups:
		if str(s.get("signup_status")) == "confirmed":
			var fn = str(s.get("first_name", ""))
			var ln = str(s.get("last_name", ""))
			var name = (fn + " " + ln).strip_edges()
			html += "<tr><td>" + str(idx) + "</td><td>" + str(s.get("human_id", "")) + "</td><td>" + name + "</td><td>" + str(s.get("role", "")) + "</td><td>[  ]</td><td>[  ]</td><td></td></tr>"
			idx += 1

	html += "</table></body></html>"

	# Save file to user://prints/ and prepare OS preview launch
	var print_dir = "user://prints"
	if not DirAccess.dir_exists_absolute(print_dir):
		DirAccess.make_dir_recursive_absolute(print_dir)
	var file_path = print_dir + "/attendance_sheet_session_" + str(session_id) + ".html"
	var f = FileAccess.open(file_path, FileAccess.WRITE)
	if f:
		f.store_string(html)
		f.close()

	return html

func generate_printable_participant_roster_html(session_id: int) -> String:
	var sess_res = db.execute("SELECT title, date_text, start_time, end_time FROM sessions WHERE id = ?;", [session_id])
	var sess = sess_res["data"][0] if (sess_res["success"] and sess_res["data"].size() > 0) else {"title": "Session", "date_text": "", "start_time": "", "end_time": ""}
	var signups = get_signups_for_session(session_id)

	var html = "<html><head><title>Participant Roster - " + str(sess["title"]) + "</title></head><body>"
	html += "<h2>👥 Session Participant Roster: " + str(sess["title"]) + "</h2>"
	html += "<p><b>Date:</b> " + str(sess["date_text"]) + " (" + str(sess["start_time"]) + ")</p>"
	html += "<table border='1' cellspacing='0' cellpadding='6' width='100%'><tr><th>Status</th><th>Pos #</th><th>Member ID</th><th>Name</th><th>Role</th><th>Registered At</th></tr>"

	for s in signups:
		var st = str(s.get("signup_status", "")).capitalize()
		var pos = str(int(s.get("position", 0)))
		var fn = str(s.get("first_name", ""))
		var ln = str(s.get("last_name", ""))
		var name = (fn + " " + ln).strip_edges()
		html += "<tr><td>" + st + "</td><td>" + (pos if st == "Waitlist" else "-") + "</td><td>" + str(s.get("human_id", "")) + "</td><td>" + name + "</td><td>" + str(s.get("role", "")) + "</td><td>" + str(s.get("registered_at", "")) + "</td></tr>"

	html += "</table></body></html>"

	var print_dir = "user://prints"
	if not DirAccess.dir_exists_absolute(print_dir):
		DirAccess.make_dir_recursive_absolute(print_dir)
	var file_path = print_dir + "/participant_roster_session_" + str(session_id) + ".html"
	var f = FileAccess.open(file_path, FileAccess.WRITE)
	if f:
		f.store_string(html)
		f.close()

	return html

func _escape_csv_field(text: String) -> String:
	var val = text.replace('"', '""')
	if val.contains(",") or val.contains('"') or val.contains("\n"):
		return '"' + val + '"'
	return val

func export_session_attendance_csv(session_id: int) -> String:
	var csv = "Human_ID,First_Name,Last_Name,Role,Signup_Status,Attendance_Status,Registered_At\n"
	var signups = get_signups_for_session(session_id)
	for s in signups:
		var hid = _escape_csv_field(str(s.get("human_id", "")))
		var fn = _escape_csv_field(str(s.get("first_name", "")))
		var ln = _escape_csv_field(str(s.get("last_name", "")))
		var role = _escape_csv_field(str(s.get("role", "")))
		var st = _escape_csv_field(str(s.get("signup_status", "")))
		var att = _escape_csv_field(str(s.get("attendance_status", "")))
		var reg = _escape_csv_field(str(s.get("registered_at", "")))
		csv += "%s,%s,%s,%s,%s,%s,%s\n" % [hid, fn, ln, role, st, att, reg]

	var export_dir = "user://exports"
	if not DirAccess.dir_exists_absolute(export_dir):
		DirAccess.make_dir_recursive_absolute(export_dir)
	var file_path = export_dir + "/session_attendance_" + str(session_id) + ".csv"
	var f = FileAccess.open(file_path, FileAccess.WRITE)
	if f:
		f.store_string(csv)
		f.close()

	return csv

func export_session_waitlist_csv(session_id: int) -> String:
	var csv = "Position,Human_ID,First_Name,Last_Name,Role,Signup_Timestamp\n"
	var signups = get_signups_for_session(session_id)
	for s in signups:
		if str(s.get("signup_status")) == "waitlist":
			var pos = _escape_csv_field(str(int(s.get("position", 0))))
			var hid = _escape_csv_field(str(s.get("human_id", "")))
			var fn = _escape_csv_field(str(s.get("first_name", "")))
			var ln = _escape_csv_field(str(s.get("last_name", "")))
			var role = _escape_csv_field(str(s.get("role", "")))
			var reg = _escape_csv_field(str(s.get("registered_at", "")))
			csv += "%s,%s,%s,%s,%s,%s\n" % [pos, hid, fn, ln, role, reg]

	var export_dir = "user://exports"
	if not DirAccess.dir_exists_absolute(export_dir):
		DirAccess.make_dir_recursive_absolute(export_dir)
	var file_path = export_dir + "/session_waitlist_" + str(session_id) + ".csv"
	var f = FileAccess.open(file_path, FileAccess.WRITE)
	if f:
		f.store_string(csv)
		f.close()

	return csv

func get_session_operational_report(session_id: int) -> Dictionary:
	var sess_res = db.execute("SELECT id, session_uuid, title, date_text, start_time, end_time, max_capacity, signup_required, limit_signups FROM sessions WHERE id = ?;", [session_id])
	if not sess_res["success"] or sess_res["data"].size() == 0:
		return {}
	var sess = sess_res["data"][0]
	var signups = get_signups_for_session(session_id)

	var conf_cnt = 0
	var wait_cnt = 0
	var pres_cnt = 0
	var noshow_cnt = 0
	var unmark_cnt = 0
	var comm_needed_cnt = 0

	for s in signups:
		var st = str(s.get("signup_status"))
		if st == "confirmed":
			conf_cnt += 1
			var att = str(s.get("attendance_status"))
			if att == "present": pres_cnt += 1
			elif att == "no_show": noshow_cnt += 1
			else: unmark_cnt += 1
		elif st == "waitlist":
			wait_cnt += 1

		if int(s.get("communication_needed", 0)) == 1:
			comm_needed_cnt += 1

	var comm_log_res = db.execute("SELECT COUNT(*) as cnt FROM communications_log;")
	var total_comms_sent = comm_log_res["data"][0]["cnt"] if comm_log_res["success"] else 0

	return {
		"session_id": session_id,
		"session_uuid": str(sess["session_uuid"]),
		"title": str(sess["title"]),
		"date_text": str(sess["date_text"]),
		"time_text": str(sess["start_time"]) + " - " + str(sess["end_time"]),
		"max_capacity": int(sess["max_capacity"]),
		"signup_required": int(sess["signup_required"]),
		"confirmed_count": conf_cnt,
		"waitlist_count": wait_cnt,
		"present_count": pres_cnt,
		"noshow_count": noshow_cnt,
		"unmarked_count": unmark_cnt,
		"communications_sent": total_comms_sent,
		"communications_pending": comm_needed_cnt
	}

# ==================== AUDIT LOGGING SERVICE ====================

func record_session_audit(session_id: int, person_id, action: String, actor_id: String, actor: String, detail_json: String = "") -> Dictionary:
	var sql = "INSERT INTO session_audit_log (session_id, person_id, action, actor_id, actor, detail_json, timestamp) VALUES (?, ?, ?, ?, ?, ?, datetime('now'));"
	return db.execute(sql, [session_id, person_id, action, actor_id, actor, detail_json])

func get_session_audit_log(session_id: int) -> Array:
	var sql = "SELECT id, session_id, person_id, action, actor_id, actor, detail_json, timestamp FROM session_audit_log WHERE session_id = ? ORDER BY id DESC;"
	var res = db.execute(sql, [session_id])
	if res["success"]: return res["data"]
	return []

func get_open_hours() -> Array:
	if not db: return []
	var res = db.execute("SELECT day_of_week, open_time, close_time, is_closed, has_split_shift, session2_start, session2_end FROM center_open_hours;")
	if res["success"]: return res["data"]
	return []

# ==================== HELPER FUNCTIONS ====================

func _generate_uuid() -> String:
	var b1 = "%08X" % (randi() % 4294967295)
	var b2 = "%04X" % (randi() % 65536)
	var b3 = "%04X" % (randi() % 65536)
	return (b1 + "-" + b2 + "-" + b3).to_lower()
