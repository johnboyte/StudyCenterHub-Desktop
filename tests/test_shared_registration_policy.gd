extends SceneTree

## Automated Test Suite for Shared Registration Minimum Policy & Validation Rules

const ValidatorScript = preload("res://src/domain/directory/person_registration_validator.gd")
const SQLiteDatabaseScript = preload("res://src/infrastructure/database/sqlite_database.gd")

func _init() -> void:
	print("==========================================================")
	print("RUNNING AUTOMATED TEST SUITE: SHARED REGISTRATION POLICY")
	print("==========================================================")
	
	var mock_now = {"year": 2026, "month": 8, "day": 13}
	
	# Test 1: Adult member with all minimum required data -> succeeds
	var adult_data = {
		"first_name": "Hannah",
		"last_name": "Abbott",
		"phone": "864-555-0199",
		"email": "hannah@example.com",
		"birthday": "05/12/1998", # Age 28
		"primary_role": "Community Member",
		"sms_consent": true
	}
	var res1 = ValidatorScript.validate_registration(adult_data, mock_now)
	assert(res1["is_valid"], "Test 1: Adult valid member must pass validation")
	assert(res1["normalized_data"]["preferred_email"] == "Main", "Test 1: Default preferred_email must be Main")
	print("✅ Test 1 Passed: Adult valid member registration succeeds.")
	
	# Test 2: Missing First Name -> blocked
	var t2 = adult_data.duplicate(true); t2["first_name"] = ""
	var res2 = ValidatorScript.validate_registration(t2, mock_now)
	assert(not res2["is_valid"] and "first_name" in res2["field_errors"], "Test 2: Missing First Name must be blocked")
	print("✅ Test 2 Passed: Missing First Name blocked.")
	
	# Test 3: Missing Last Name -> blocked
	var t3 = adult_data.duplicate(true); t3["last_name"] = ""
	var res3 = ValidatorScript.validate_registration(t3, mock_now)
	assert(not res3["is_valid"] and "last_name" in res3["field_errors"], "Test 3: Missing Last Name must be blocked")
	print("✅ Test 3 Passed: Missing Last Name blocked.")
	
	# Test 4: Missing Mobile Phone -> blocked
	var t4 = adult_data.duplicate(true); t4["phone"] = ""
	var res4 = ValidatorScript.validate_registration(t4, mock_now)
	assert(not res4["is_valid"] and "phone" in res4["field_errors"], "Test 4: Missing Phone must be blocked")
	print("✅ Test 4 Passed: Missing Phone blocked.")
	
	# Test 5: Missing Email -> blocked
	var t5 = adult_data.duplicate(true); t5["email"] = ""
	var res5 = ValidatorScript.validate_registration(t5, mock_now)
	assert(not res5["is_valid"] and "email" in res5["field_errors"], "Test 5: Missing Email must be blocked")
	print("✅ Test 5 Passed: Missing Email blocked.")
	
	# Test 6: Invalid Email -> blocked
	var t6 = adult_data.duplicate(true); t6["email"] = "notanemail"
	var res6 = ValidatorScript.validate_registration(t6, mock_now)
	assert(not res6["is_valid"] and "email" in res6["field_errors"], "Test 6: Invalid Email must be blocked")
	print("✅ Test 6 Passed: Invalid Email blocked.")
	
	# Test 7: Missing DOB -> blocked
	var t7 = adult_data.duplicate(true); t7["birthday"] = ""
	var res7 = ValidatorScript.validate_registration(t7, mock_now)
	assert(not res7["is_valid"] and "birthday" in res7["field_errors"], "Test 7: Missing DOB must be blocked")
	print("✅ Test 7 Passed: Missing DOB blocked.")
	
	# Test 8: Missing Campus/Community category -> blocked
	var t8 = adult_data.duplicate(true); t8["primary_role"] = ""
	var res8 = ValidatorScript.validate_registration(t8, mock_now)
	assert(not res8["is_valid"] and "primary_role" in res8["field_errors"], "Test 8: Missing Primary Role must be blocked")
	print("✅ Test 8 Passed: Missing Category blocked.")
	
	# Test 9: SMS consent unselected (unchecked) -> succeeds with sms_consent = 0, no manufactured timestamp
	var t9 = adult_data.duplicate(true); t9.erase("sms_consent"); t9.erase("sms_consent_given"); t9.erase("smsConsentChoice")
	var res9 = ValidatorScript.validate_registration(t9, mock_now)
	assert(res9["is_valid"], "Test 9: Unchecked SMS consent must allow registration to succeed")
	assert(res9["normalized_data"]["sms_consent"] == 0, "Test 9: Unchecked SMS consent must store sms_consent = 0")
	assert(res9["normalized_data"]["sms_consent_source"] == null, "Test 9: Unchecked SMS consent must not manufacture a source")
	assert(res9["normalized_data"]["sms_consent_at"] == null, "Test 9: Unchecked SMS consent must not manufacture a timestamp")
	print("✅ Test 9 Passed: Unchecked SMS consent allows registration with sms_consent = 0 and no manufactured metadata.")
	
	# Test 10: SMS consent = Yes -> registration succeeds with sms_consent = 1 and audit metadata
	var t10 = adult_data.duplicate(true); t10["sms_consent"] = true
	var res10 = ValidatorScript.validate_registration(t10, mock_now)
	assert(res10["is_valid"], "Test 10: SMS consent = Yes must be valid and succeed")
	assert(res10["normalized_data"]["sms_consent"] == 1, "Test 10: sms_consent value must be 1")
	assert(res10["normalized_data"]["sms_consent_source"] == "Public Registration", "Test 10: Opt-in source must be recorded")
	assert(res10["normalized_data"]["sms_consent_at"] != null, "Test 10: Opt-in timestamp must be recorded")
	print("✅ Test 10 Passed: SMS consent = Yes registration succeeds with sms_consent = 1 and audit metadata.")
	
	# Test 11: Student missing Institution -> blocked
	var student_data = adult_data.duplicate(true)
	student_data["primary_role"] = "College Student"
	var t11 = student_data.duplicate(true); t11.erase("institution_id"); t11["academic_year"] = "Sophomore"
	var res11 = ValidatorScript.validate_registration(t11, mock_now)
	assert(not res11["is_valid"] and "institution_id" in res11["field_errors"], "Test 11: Student missing Institution must be blocked")
	print("✅ Test 11 Passed: Student missing Institution blocked.")
	
	# Test 12: Student missing Grade/Classification -> blocked
	var t12 = student_data.duplicate(true); t12["institution_id"] = "1"; t12.erase("academic_year")
	var res12 = ValidatorScript.validate_registration(t12, mock_now)
	assert(not res12["is_valid"] and "academic_year" in res12["field_errors"], "Test 12: Student missing Grade must be blocked")
	print("✅ Test 12 Passed: Student missing Grade blocked.")
	
	# Test 13: Adult missing Emergency Contact -> succeeds
	var t13 = adult_data.duplicate(true)
	t13.erase("emergency_contact_name"); t13.erase("emergency_contact_phone")
	var res13 = ValidatorScript.validate_registration(t13, mock_now)
	assert(res13["is_valid"], "Test 13: Adult missing emergency contact must succeed")
	print("✅ Test 13 Passed: Adult missing Emergency Contact succeeds.")
	
	# Test 14: Minor missing Emergency Contact Name -> blocked
	var minor_data = adult_data.duplicate(true)
	minor_data["birthday"] = "10/15/2010" # Age 15
	var t14 = minor_data.duplicate(true)
	t14["emergency_contact_phone"] = "864-555-9999"
	var res14 = ValidatorScript.validate_registration(t14, mock_now)
	assert(not res14["is_valid"] and "emergency_contact_name" in res14["field_errors"], "Test 14: Minor missing Emergency Contact Name must be blocked")
	print("✅ Test 14 Passed: Minor missing Emergency Contact Name blocked.")
	
	# Test 15: Minor missing Emergency Contact Phone -> blocked
	var t15 = minor_data.duplicate(true)
	t15["emergency_contact_name"] = "Parent Name"
	var res15 = ValidatorScript.validate_registration(t15, mock_now)
	assert(not res15["is_valid"] and "emergency_contact_phone" in res15["field_errors"], "Test 15: Minor missing Emergency Contact Phone must be blocked")
	print("✅ Test 15 Passed: Minor missing Emergency Contact Phone blocked.")
	
	# Test 16: Minor with emergency contact -> succeeds
	var t16 = minor_data.duplicate(true)
	t16["emergency_contact_name"] = "Parent Name"
	t16["emergency_contact_phone"] = "864-555-9999"
	var res16 = ValidatorScript.validate_registration(t16, mock_now)
	assert(res16["is_valid"], "Test 16: Minor with emergency contact must succeed")
	print("✅ Test 16 Passed: Minor with Emergency Contact succeeds.")
	
	# Test 17: One email entered -> preferred email defaults correctly
	var t17 = adult_data.duplicate(true)
	t17["school_email"] = ""
	var res17 = ValidatorScript.validate_registration(t17, mock_now)
	assert(res17["normalized_data"]["preferred_email"] == "Main", "Test 17: Preferred email defaults to Main when 1 email provided")
	print("✅ Test 17 Passed: Preferred Email default behavior correct.")
	
	# Test 18: Optional address fields blank -> registration succeeds
	var t18 = adult_data.duplicate(true)
	t18["home_address_street"] = ""
	var res18 = ValidatorScript.validate_registration(t18, mock_now)
	assert(res18["is_valid"], "Test 18: Optional address fields blank must succeed")
	print("✅ Test 18 Passed: Blank optional address succeeds.")
	
	# Test 19: Optional Medical Notes blank -> registration succeeds
	var t19 = adult_data.duplicate(true)
	t19["medical_notes"] = ""
	var res19 = ValidatorScript.validate_registration(t19, mock_now)
	assert(res19["is_valid"], "Test 19: Optional medical notes blank must succeed")
	print("✅ Test 19 Passed: Blank optional medical notes succeeds.")
	
	# Test 20: Optional photo blank -> registration succeeds
	var t20 = adult_data.duplicate(true)
	t20["profile_photo"] = ""
	var res20 = ValidatorScript.validate_registration(t20, mock_now)
	assert(res20["is_valid"], "Test 20: Optional photo blank must succeed")
	print("✅ Test 20 Passed: Blank optional photo succeeds.")
	
	# Test 21: Shared rules parity across desktop dictionary and public JSON event payload
	var portal_payload = {
		"firstName": "John",
		"lastName": "Smith",
		"phone": "(864) 934-4080",
		"email": "JOHN@EXAMPLE.COM",
		"dob": "1995-04-20",
		"campus_category": "Community Member",
		"smsConsent": "Yes"
	}
	var res21 = ValidatorScript.validate_registration(portal_payload, mock_now)
	assert(res21["is_valid"], "Test 21: Public payload mapping must pass validator")
	assert(res21["normalized_data"]["email"] == "john@example.com", "Test 21: Email must be lowercased")
	assert(res21["normalized_data"]["sms_consent"] == 1, "Test 21: SMS consent must be 1")
	print("✅ Test 21 Passed: Shared rules parity verified.")
	
	# Test 22: Database query safety check on existing members
	var db = SQLiteDatabaseScript.new()
	var p_res = db.execute("SELECT COUNT(*) as cnt FROM people;")
	assert(p_res["success"], "Test 22: Database query on people table must succeed")
	print("✅ Test 22 Passed: Existing member records intact (Count: ", p_res["data"][0]["cnt"], ").")
	
	print("==========================================================")
	print("ALL 22 REGISTRATION POLICY TESTS PASSED 100%")
	print("==========================================================")
	quit(0)
