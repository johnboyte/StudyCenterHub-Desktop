extends RefCounted

## Birthday Recognition & Notification Domain Service
## Complies with [PD-001] (Offline Storage) and [PD-008] (Warm & Welcoming Design System).

const TwilioGatewayScript = preload("res://src/infrastructure/messaging/twilio_gateway_service.gd")

var db: RefCounted
var twilio_service: RefCounted

func _init(p_db: RefCounted = null) -> void:
	db = p_db
	if db:
		twilio_service = TwilioGatewayScript.new(db)

func is_center_open_on_date(date_dict: Dictionary) -> bool:
	if not db: return true
	var date_str = "%04d-%02d-%02d" % [date_dict["year"], date_dict["month"], date_dict["day"]]

	# 1. Check Date Overrides table
	var ov_res = db.execute("SELECT is_closed FROM center_hour_overrides WHERE override_date = ? LIMIT 1;", [date_str])
	if ov_res["success"] and ov_res["data"].size() > 0:
		return int(ov_res["data"][0].get("is_closed", 0)) == 0

	# 2. Check Weekly Standard Hours
	var day_names = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
	var wday = day_names[int(date_dict.get("weekday", 0))]

	var std_res = db.execute("SELECT is_closed FROM center_open_hours WHERE day_of_week = ? LIMIT 1;", [wday])
	if std_res["success"] and std_res["data"].size() > 0:
		return int(std_res["data"][0].get("is_closed", 0)) == 0

	return true

func evaluate_checkin_birthday(person: Dictionary, check_in_unix: int = 0) -> Dictionary:
	if not db: return {"trigger_alert": false}

	var bm = person.get("birth_month")
	var bd = person.get("birth_day")
	if bm == null or bd == null or int(bm) <= 0 or int(bd) <= 0:
		return {"trigger_alert": false}

	var birth_month = int(bm)
	var birth_day = int(bd)

	if check_in_unix == 0:
		check_in_unix = int(Time.get_unix_time_from_system())

	var cur_date = Time.get_date_dict_from_unix_time(check_in_unix)
	var cur_m = int(cur_date["month"])
	var cur_d = int(cur_date["day"])
	var cur_y = int(cur_date["year"])

	var max_advance_days = 7
	var max_res = db.execute("SELECT setting_value FROM app_settings WHERE setting_key = 'MAX_ADVANCE_BDAY_DAYS' LIMIT 1;")
	if max_res["success"] and max_res["data"].size() > 0:
		max_advance_days = int(max_res["data"][0].get("setting_value", 7))

	var is_today_bday = (cur_m == birth_month and cur_d == birth_day)
	var notif_type = ""

	if is_today_bday:
		notif_type = "birthday_today"
	else:
		# Check if today is the LAST OPEN DAY before birthday
		var bday_target_year = cur_y
		if birth_month < cur_m or (birth_month == cur_m and birth_day < cur_d):
			bday_target_year += 1

		var bday_dict = {"year": bday_target_year, "month": birth_month, "day": birth_day}
		var bday_unix = Time.get_unix_time_from_datetime_dict(bday_dict)
		var diff_days = int(round((bday_unix - check_in_unix) / 86400.0))

		if diff_days > 0 and diff_days <= max_advance_days:
			var all_intermediate_closed = true
			for step in range(1, diff_days):
				var eval_unix = check_in_unix + (step * 86400)
				var eval_date = Time.get_date_dict_from_unix_time(eval_unix)
				if is_center_open_on_date(eval_date):
					all_intermediate_closed = false
					break

			if all_intermediate_closed:
				notif_type = "last_open_day_before_birthday"

	if notif_type == "":
		return {"trigger_alert": false}

	var person_id = int(person.get("id", 0))

	# Transactional Deduplication Check
	var log_res = db.execute("SELECT id, on_screen_alert_acknowledged_at, sms_attempted_at FROM birthday_notification_log WHERE person_id = ? AND birthday_year = ? AND notification_type = ? LIMIT 1;", [person_id, cur_y, notif_type])

	if log_res["success"] and log_res["data"].size() > 0:
		var existing_id = int(log_res["data"][0].get("id"))
		return {
			"trigger_alert": true,
			"already_logged": true,
			"log_id": existing_id,
			"notification_type": notif_type,
			"birth_month": birth_month,
			"birth_day": birth_day
		}

	var ins_res = db.execute("INSERT INTO birthday_notification_log (person_id, birthday_year, notification_type, triggered_at) VALUES (?, ?, ?, datetime('now')); SELECT last_insert_rowid() as id;", [person_id, cur_y, notif_type])

	var new_log_id = 0
	if ins_res["success"] and ins_res["data"].size() > 0:
		new_log_id = int(ins_res["data"][0].get("id", 0))

	return {
		"trigger_alert": true,
		"already_logged": false,
		"log_id": new_log_id,
		"notification_type": notif_type,
		"birth_month": birth_month,
		"birth_day": birth_day
	}

func dispatch_team_birthday_sms(person: Dictionary, notification_type: String, log_id: int) -> Dictionary:
	if not db or not twilio_service: return {"success": false, "reason": "No DB or Twilio service"}

	var first = str(person.get("first_name", ""))
	var last = str(person.get("last_name", ""))
	var full_name = (first + " " + last).strip_edges()

	var recipient_phones = []

	# 1. Fetch Shift Lead Phone
	var lead_name = "John Boyte"
	var lead_res = db.execute("SELECT setting_value FROM app_settings WHERE setting_key = 'ACTIVE_SUPERVISOR' LIMIT 1;")
	if lead_res["success"] and lead_res["data"].size() > 0:
		lead_name = lead_res["data"][0].get("setting_value", "John Boyte")

	var lead_p_res = db.execute("SELECT phone FROM people WHERE (first_name || ' ' || last_name) = ? LIMIT 1;", [lead_name])
	if lead_p_res["success"] and lead_p_res["data"].size() > 0:
		var raw_ph = lead_p_res["data"][0].get("phone")
		if raw_ph != null:
			var ph = str(raw_ph).strip_edges()
			if ph != "" and ph != "<null>" and not ph in recipient_phones:
				recipient_phones.append(ph)

	# 2. Fetch Active Scheduled Workers for Today
	var today_str = Time.get_date_string_from_system()
	var sch_res = db.execute("SELECT s.person_id, p.phone FROM schedule_entries s LEFT JOIN people p ON p.id = s.person_id WHERE s.shift_date = ?;", [today_str])
	if sch_res["success"] and sch_res["data"].size() > 0:
		for row in sch_res["data"]:
			var raw_ph = row.get("phone")
			if raw_ph != null:
				var ph = str(raw_ph).strip_edges()
				if ph != "" and ph != "<null>" and not ph in recipient_phones:
					recipient_phones.append(ph)

	# Fallback recipient phone if none configured
	if recipient_phones.size() == 0 or (recipient_phones.size() == 1 and (recipient_phones[0] == "" or recipient_phones[0] == "<null>")):
		recipient_phones = ["864 934-4080"]

	var month_names = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]
	var bm_name = month_names[int(person.get("birth_month", 1)) - 1]
	var bday_str = "%s %d" % [bm_name, int(person.get("birth_day", 1))]

	var body_text = ""
	if notification_type == "birthday_today":
		body_text = "StudyCenter birthday reminder: " + full_name + "'s birthday is today. She has just checked in. Please help us recognize and celebrate her."
	else:
		body_text = "StudyCenter birthday reminder: " + full_name + "'s birthday is " + bday_str + ". Today is the last open day before her birthday, and she has just checked in."

	var success_count = 0
	var fail_count = 0

	for phone in recipient_phones:
		var sms_res = twilio_service.simulate_twilio_sms(phone, body_text)
		if sms_res.get("success", false):
			success_count += 1
		else:
			fail_count += 1

	if log_id > 0:
		db.execute("UPDATE birthday_notification_log SET sms_attempted_at = datetime('now'), sms_recipient_count = ?, sms_success_count = ?, sms_failure_count = ?, status = 'sent' WHERE id = ?;", [recipient_phones.size(), success_count, fail_count, log_id])

	return {"success": true, "recipients": recipient_phones.size(), "sent": success_count}

func acknowledge_birthday_alert(log_id: int, user_id: int = 1) -> void:
	if not db or log_id <= 0: return
	db.execute("UPDATE birthday_notification_log SET on_screen_alert_acknowledged_at = datetime('now'), acknowledged_by_user_id = ? WHERE id = ?;", [user_id, log_id])
