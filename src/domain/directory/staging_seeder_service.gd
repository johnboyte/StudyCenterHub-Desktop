extends RefCounted

## Staging-only Test Member Seeder Service
## Seeds the test constituent (John Boyte) idempotent logic.

const QRCredentialServiceScript = preload("res://src/domain/security/qr_credential_service.gd")

var db: RefCounted

func _init(database: RefCounted) -> void:
	db = database

func seed_staging_test_member() -> void:
	var env = OS.get_environment("STUDYCENTERHUB_ENV").to_lower().strip_edges()
	if env == "":
		var exec_path = OS.get_executable_path().to_lower()
		if exec_path.contains("rc1") or exec_path.contains("staging"):
			env = "staging"
		else:
			env = "development"

	if env != "staging":
		print("Staging seed skipped: non-staging environment")
		return

	if not db:
		return

	var email_to_check = "johnboytejr@gmail.com"
	var check_q = db.execute("SELECT id FROM people WHERE email = ? LIMIT 1;", [email_to_check])
	if check_q["success"] and check_q["data"].size() > 0:
		print("Staging test member already exists")
		return

	print("Staging test member not found. Seeding now...")
	var person_uuid = "usr_john_boyte_staging_seed_9999"
	var human_id = "P-20260801-5AC9"

	# Insert the person record with actual schema and consent fields
	var insert_person_sql = """
	INSERT INTO people (
		person_uuid, human_id, first_name, last_name, phone, status,
		emergency_contact_name, emergency_contact_phone, email, birthday,
		sms_consent, sms_consent_given, primary_role, qr_status, pin_status,
		academic_year, review_status, created_at, updated_at
	) VALUES (
		?, ?, 'John', 'Boyte', '(864) 934-4080', 'active',
		'Cheryl Boyte', '(864) 934-5017', 'johnboytejr@gmail.com', '1965-08-22',
		1, 1, 'Participant', 'Not Issued', 'Not Set',
		'None', 'reviewed', datetime('now'), datetime('now')
	);
	"""
	
	var res = db.execute(insert_person_sql, [person_uuid, human_id])
	if not res["success"]:
		print("Error seeding John Boyte person record: ", res["error"])
		return

	var get_id_q = db.execute("SELECT id FROM people WHERE email = ? LIMIT 1;", [email_to_check])
	if get_id_q["success"] and get_id_q["data"].size() > 0:
		var new_person_id = int(get_id_q["data"][0]["id"])
		
		# Generate the QR credential through the application's normal credential-generation service
		var cred_service = QRCredentialServiceScript.new(db)
		var cred_res = cred_service.issue_credential(new_person_id, person_uuid)
		if cred_res.get("success", false):
			print("Staging test member created")
		else:
			print("Staging test member created, but failed to generate QR credential: ", cred_res.get("error"))
	else:
		print("Staging test member created, but failed to retrieve new person ID")
