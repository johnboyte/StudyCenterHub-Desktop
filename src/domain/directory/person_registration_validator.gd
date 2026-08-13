extends RefCounted

## Centralized Person Registration Validator for StudyCenterHub
## Enforces shared minimum registration policies consistently across Desktop Add Member and Public Self-Registration.

class_name PersonRegistrationValidator

static func normalize_phone(raw_phone: String) -> String:
	var digits = ""
	for c in raw_phone:
		if c >= '0' and c <= '9':
			digits += c
	if digits.length() == 10:
		return "(" + digits.substr(0, 3) + ") " + digits.substr(3, 3) + "-" + digits.substr(6, 4)
	elif digits.length() == 11 and digits.begins_with("1"):
		return "(" + digits.substr(1, 3) + ") " + digits.substr(4, 3) + "-" + digits.substr(7, 4)
	return raw_phone.strip_edges()

static func normalize_phone_e164(raw_phone: String) -> String:
	var digits = ""
	for c in raw_phone:
		if c >= '0' and c <= '9':
			digits += c
	if digits.length() == 10:
		return "+1" + digits
	elif digits.length() == 11 and digits.begins_with("1"):
		return "+" + digits
	return raw_phone.strip_edges()

static func is_valid_phone(raw_phone: String) -> bool:
	var digits = ""
	for c in raw_phone:
		if c >= '0' and c <= '9':
			digits += c
	return digits.length() >= 10

static func normalize_email(raw_email: String) -> String:
	return raw_email.strip_edges().to_lower()

static func is_valid_email(raw_email: String) -> bool:
	var cleaned = normalize_email(raw_email)
	if cleaned == "" or not "@" in cleaned:
		return false
	var parts = cleaned.split("@")
	if parts.size() != 2 or parts[0] == "" or parts[1] == "":
		return false
	return "." in parts[1] and not parts[1].ends_with(".")

static func parse_date_to_iso(raw_date: String) -> String:
	var s = raw_date.strip_edges()
	if s == "":
		return ""
	
	# Check ISO format YYYY-MM-DD
	var iso_parts = s.split("-")
	if iso_parts.size() == 3 and iso_parts[0].length() == 4:
		var y = int(iso_parts[0])
		var m = int(iso_parts[1])
		var d = int(iso_parts[2])
		if y >= 1900 and y <= 2100 and m >= 1 and m <= 12 and d >= 1 and d <= 31:
			return str(y) + "-" + str(m).lpad(2, "0") + "-" + str(d).lpad(2, "0")
			
	# Check US format MM/DD/YYYY or M/D/YY
	var us_parts = s.split("/")
	if us_parts.size() == 3:
		var m = int(us_parts[0])
		var d = int(us_parts[1])
		var y_str = us_parts[2]
		if y_str.length() == 2:
			y_str = "20" + y_str
		var y = int(y_str)
		if y >= 1900 and y <= 2100 and m >= 1 and m <= 12 and d >= 1 and d <= 31:
			return str(y) + "-" + str(m).lpad(2, "0") + "-" + str(d).lpad(2, "0")
			
	return ""

static func calculate_age(iso_date: String, relative_date_dict: Dictionary = {}) -> int:
	if iso_date == "":
		return -1
	var parts = iso_date.split("-")
	if parts.size() != 3:
		return -1
		
	var birth_year = int(parts[0])
	var birth_month = int(parts[1])
	var birth_day = int(parts[2])
	
	var cur_year = int(relative_date_dict.get("year", Time.get_date_dict_from_system().get("year", 2026)))
	var cur_month = int(relative_date_dict.get("month", Time.get_date_dict_from_system().get("month", 8)))
	var cur_day = int(relative_date_dict.get("day", Time.get_date_dict_from_system().get("day", 13)))
	
	var age = cur_year - birth_year
	if cur_month < birth_month or (cur_month == birth_month and cur_day < birth_day):
		age -= 1
	return age

static func is_student_category(primary_role: String) -> bool:
	var role_lower = primary_role.strip_edges().to_lower()
	if role_lower == "" or role_lower == "none" or role_lower == "n/a":
		return false
	if "student" in role_lower or "undergrad" in role_lower or "grad" in role_lower or "freshman" in role_lower or "sophomore" in role_lower or "junior" in role_lower or "senior" in role_lower or "high school" in role_lower or role_lower == "college student":
		return true
	return false

static func validate_registration(data: Dictionary, relative_date_dict: Dictionary = {}) -> Dictionary:
	var errors: Array = []
	var field_errors: Dictionary = {}
	var normalized: Dictionary = data.duplicate(true)
	
	# 1. First Name (Required)
	var first_name = str(data.get("first_name", data.get("firstName", ""))).strip_edges()
	if first_name == "":
		errors.append("First Name is required.")
		field_errors["first_name"] = "First Name is required."
	normalized["first_name"] = first_name
	
	# 2. Last Name (Required)
	var last_name = str(data.get("last_name", data.get("lastName", ""))).strip_edges()
	if last_name == "":
		errors.append("Last Name is required.")
		field_errors["last_name"] = "Last Name is required."
	normalized["last_name"] = last_name
	
	# 3. Mobile Phone (Required & Valid)
	var raw_phone = str(data.get("phone", data.get("mobile_phone", ""))).strip_edges()
	if raw_phone == "":
		errors.append("Mobile Phone is required.")
		field_errors["phone"] = "Mobile Phone is required."
	elif not is_valid_phone(raw_phone):
		errors.append("Mobile Phone must contain at least 10 valid digits.")
		field_errors["phone"] = "Mobile Phone must contain at least 10 valid digits."
	else:
		normalized["phone"] = normalize_phone(raw_phone)
		normalized["phone_e164"] = normalize_phone_e164(raw_phone)
		
	# 4. Email (Required & Valid)
	var main_email = str(data.get("email", data.get("primary_email", ""))).strip_edges()
	var school_email = str(data.get("school_email", "")).strip_edges()
	
	if main_email == "" and school_email == "":
		errors.append("At least one valid Email address is required.")
		field_errors["email"] = "At least one valid Email address is required."
	else:
		if main_email != "":
			if not is_valid_email(main_email):
				errors.append("Primary Email is invalid.")
				field_errors["email"] = "Primary Email is invalid."
			else:
				normalized["email"] = normalize_email(main_email)
		if school_email != "":
			if not is_valid_email(school_email):
				errors.append("School Email is invalid.")
				field_errors["school_email"] = "School Email is invalid."
			else:
				normalized["school_email"] = normalize_email(school_email)
				
	# Preferred Email Logic
	var pref_email = str(data.get("preferred_email", "")).strip_edges()
	if normalized.get("email", "") != "" and normalized.get("school_email", "") == "":
		normalized["preferred_email"] = "Main"
	elif normalized.get("email", "") == "" and normalized.get("school_email", "") != "":
		normalized["preferred_email"] = "School"
	elif pref_email != "":
		normalized["preferred_email"] = pref_email
	else:
		normalized["preferred_email"] = "Main"
		
	# 5. Date of Birth (Required & Valid ISO Date)
	var raw_dob = str(data.get("birthday", data.get("birth_date", data.get("dob", "")))).strip_edges()
	var iso_dob = parse_date_to_iso(raw_dob)
	if raw_dob == "" or iso_dob == "":
		errors.append("Date of Birth (MM/DD/YYYY) is required.")
		field_errors["birthday"] = "Date of Birth (MM/DD/YYYY) is required."
	else:
		normalized["birthday"] = iso_dob
		var dob_parts = iso_dob.split("-")
		normalized["birth_month"] = int(dob_parts[1])
		normalized["birth_day"] = int(dob_parts[2])
		
	# 6. Primary Member Classification (Required)
	var primary_role = str(data.get("primary_role", data.get("primaryRole", data.get("relationship", data.get("campus_category", ""))))).strip_edges()
	if primary_role == "" or primary_role.to_lower() == "none":
		errors.append("Campus / Community classification category is required.")
		field_errors["primary_role"] = "Campus / Community classification category is required."
	normalized["primary_role"] = primary_role
	normalized["relationship"] = primary_role
	
	# 7. SMS Consent Choice (Voluntary Affirmative Opt-In Checkbox)
	var sms_choice = data.get("sms_consent", data.get("sms_consent_given", data.get("smsConsentChoice", data.get("smsConsent", null))))
	var consent_bool = false
	if sms_choice != null:
		if typeof(sms_choice) == TYPE_BOOL:
			consent_bool = sms_choice
		elif typeof(sms_choice) == TYPE_INT or typeof(sms_choice) == TYPE_FLOAT:
			consent_bool = (int(sms_choice) == 1)
		elif typeof(sms_choice) == TYPE_STRING:
			var s_val = str(sms_choice).strip_edges().to_lower()
			if s_val in ["yes", "true", "1", "consent", "opt-in", "opt_in"]:
				consent_bool = true

	normalized["sms_consent"] = 1 if consent_bool else 0
	normalized["sms_consent_given"] = 1 if consent_bool else 0
	if consent_bool:
		normalized["sms_consent_source"] = str(data.get("sms_consent_source", "Public Registration")).strip_edges()
		normalized["sms_consent_at"] = str(data.get("sms_consent_at", Time.get_datetime_string_from_system())).strip_edges()
	else:
		normalized["sms_consent_source"] = null
		normalized["sms_consent_at"] = null

	# ----------------------------------------------------
	# CONDITIONAL REQUIREMENTS
	# ----------------------------------------------------
	
	# Conditional Requirement 1: Students (Institution + Grade)
	if is_student_category(primary_role):
		var inst_val = str(data.get("institution_id", data.get("institution_name", data.get("institution", "")))).strip_edges()
		if inst_val == "" or inst_val == "0" or inst_val.to_lower() == "none":
			errors.append("Institution / School is required for student members.")
			field_errors["institution_id"] = "Institution / School is required for student members."
		normalized["institution_id"] = inst_val
		
		var grade_val = str(data.get("academic_year", data.get("grade", ""))).strip_edges()
		if grade_val == "" or grade_val.to_lower() == "none":
			errors.append("Academic Grade / Classification is required for student members.")
			field_errors["academic_year"] = "Academic Grade / Classification is required for student members."
		normalized["academic_year"] = grade_val
		normalized["grade"] = grade_val
		
	# Conditional Requirement 2: Minors under 18 (Emergency Contact Name + Phone)
	if iso_dob != "":
		var age = calculate_age(iso_dob, relative_date_dict)
		normalized["calculated_age"] = age
		if age >= 0 and age < 18:
			var em_name = str(data.get("emergency_contact_name", "")).strip_edges()
			var em_phone = str(data.get("emergency_contact_phone", "")).strip_edges()
			
			if em_name == "":
				errors.append("Emergency Contact Name is required for minor members under 18.")
				field_errors["emergency_contact_name"] = "Emergency Contact Name is required for minor members under 18."
			normalized["emergency_contact_name"] = em_name
			
			if em_phone == "":
				errors.append("Emergency Contact Phone is required for minor members under 18.")
				field_errors["emergency_contact_phone"] = "Emergency Contact Phone is required for minor members under 18."
			elif not is_valid_phone(em_phone):
				errors.append("Emergency Contact Phone must contain at least 10 valid digits.")
				field_errors["emergency_contact_phone"] = "Emergency Contact Phone must contain at least 10 valid digits."
			else:
				normalized["emergency_contact_phone"] = normalize_phone(em_phone)

	# Safe Default Registration Status
	if not "flag_status" in normalized or normalized["flag_status"] == "":
		normalized["flag_status"] = "Clear"
	if not "status" in normalized or normalized["status"] == "":
		normalized["status"] = "active"
		
	return {
		"is_valid": errors.size() == 0,
		"errors": errors,
		"field_errors": field_errors,
		"normalized_data": normalized
	}
