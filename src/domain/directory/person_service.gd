extends RefCounted

## Directory Service for Person Management
## Manages Person lifecycle with stable internal person_uuid and customer-visible human_id.
## Individual-Driven Product: Governs independent Person records, notes, emergency contacts,
## medical info, status transitions, and atomic event_outbox commits.

const QRCredentialServiceScript = preload("res://src/domain/security/qr_credential_service.gd")
const CommunicationsServiceScript = preload("res://src/domain/communications/communications_service.gd")

const STATUS_ACTIVE = "active"
const STATUS_PENDING = "pending"
const STATUS_TO_BE_CONFIRMED = "To Be Confirmed"
const STATUS_INACTIVE = "inactive"

const VALID_STATUSES = [
	STATUS_ACTIVE,
	STATUS_PENDING,
	STATUS_TO_BE_CONFIRMED,
	STATUS_INACTIVE
]

const IMMUTABLE_FIELDS = ["id", "person_uuid", "human_id", "created_at"]

var db

func _init(database) -> void:
	db = database

# --- PRESERVED PUBLIC METHODS ---

func create_test_person(first_name: String = "Test", last_name: String = "Participant", phone: String = "555-0199") -> Dictionary:
	return create_person({
		"first_name": first_name,
		"last_name": last_name,
		"phone": phone,
		"status": STATUS_ACTIVE
	})

func get_latest_person() -> Dictionary:
	var res = db.execute("SELECT * FROM people ORDER BY id DESC LIMIT 1;")
	if res["success"] and res["data"].size() > 0:
		return res["data"][0]
	return {}

# --- DOMAIN METHODS FOR DIR-SPR1-001B ---

func create_person(person_data: Dictionary, device_uuid: String = "dev_macbook_primary_node") -> Dictionary:
	var first_name = String(person_data.get("first_name", "")).strip_edges()
	var last_name = String(person_data.get("last_name", "")).strip_edges()
	if first_name == "" or last_name == "":
		return {"success": false, "error": "First name and last name are required.", "person": {}}

	var date_str = Time.get_date_string_from_system().replace("-", "")
	var rand_hex = "%04X" % (randi() % 65536)
	var human_id = String(person_data.get("human_id", ""))
	if human_id == "":
		human_id = "P-" + date_str + "-" + rand_hex

	var person_uuid = String(person_data.get("person_uuid", ""))
	if person_uuid == "":
		person_uuid = "usr_" + _generate_uuid()

	var status = String(person_data.get("status", STATUS_ACTIVE))
	if not status in VALID_STATUSES:
		return {"success": false, "error": "Invalid status value: " + status, "person": {}}

	var phone = person_data.get("phone", null)
	var grade = person_data.get("grade", null)
	var notes = person_data.get("notes", null)
	var emergency_contact_name = person_data.get("emergency_contact_name", null)
	var emergency_contact_phone = person_data.get("emergency_contact_phone", null)
	var medical_notes = person_data.get("medical_notes", null)

	var event_uuid = "evt_" + _generate_uuid()
	var payload_dict = {
		"event_uuid": event_uuid,
		"event_type": "PersonCreated",
		"person_uuid": person_uuid,
		"human_id": human_id,
		"first_name": first_name,
		"last_name": last_name,
		"phone": phone,
		"status": status,
		"device_uuid": device_uuid,
		"timestamp": Time.get_datetime_string_from_system()
	}

	var stmt1 = {
		"sql": "INSERT INTO people (person_uuid, human_id, first_name, last_name, phone, status, grade, notes, emergency_contact_name, emergency_contact_phone, medical_notes) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);",
		"args": [person_uuid, human_id, first_name, last_name, phone, status, grade, notes, emergency_contact_name, emergency_contact_phone, medical_notes]
	}

	var stmt2 = {
		"sql": "INSERT INTO event_outbox (event_uuid, event_type, aggregate_type, aggregate_id, payload_json, device_uuid, status) VALUES (?, ?, ?, ?, ?, ?, ?);",
		"args": [event_uuid, "PersonCreated", "Person", person_uuid, JSON.stringify(payload_dict), device_uuid, "pending"]
	}

	var tx_res = db.execute_transaction([stmt1, stmt2])
	if not tx_res["success"]:
		print("[DEBUG create_person FAIL] tx_res=", tx_res)
		return {"success": false, "error": tx_res["error"], "person": {}}

	var created_res = get_person_by_uuid(person_uuid)
	if created_res["success"] and status == STATUS_ACTIVE:
		var p = created_res["person"]
		var person_id = int(p.get("id", 0))
		if person_id > 0:
			var cred_svc = QRCredentialServiceScript.new(db)
			cred_svc.issue_credential(person_id, person_uuid)
			var com_svc = CommunicationsServiceScript.new(db)
			com_svc.email_digital_member_pass(person_id, "Staff Administrator")

	return created_res

func get_person_by_uuid(person_uuid: String) -> Dictionary:
	if person_uuid == "":
		return {"success": false, "error": "person_uuid cannot be empty.", "person": {}}
	var res = db.execute("SELECT * FROM people WHERE person_uuid = ?;", [person_uuid])
	if res["success"] and res["data"].size() > 0:
		return {"success": true, "error": "", "person": res["data"][0]}
	return {"success": false, "error": "Person not found.", "person": {}}

func get_person_by_human_id(human_id: String) -> Dictionary:
	if human_id == "":
		return {"success": false, "error": "human_id cannot be empty.", "person": {}}
	var res = db.execute("SELECT * FROM people WHERE human_id = ?;", [human_id])
	if res["success"] and res["data"].size() > 0:
		return {"success": true, "error": "", "person": res["data"][0]}
	return {"success": false, "error": "Person not found.", "person": {}}

func get_person_by_id(id: int) -> Dictionary:
	if id <= 0:
		return {"success": false, "error": "Invalid person ID.", "person": {}}
	var res = db.execute("SELECT * FROM people WHERE id = ?;", [id])
	if res["success"] and res["data"].size() > 0:
		return {"success": true, "error": "", "person": res["data"][0]}
	return {"success": false, "error": "Person not found.", "person": {}}

func list_people(options: Dictionary = {}) -> Dictionary:
	var sql = "SELECT * FROM people"
	var args = []

	var status_filter = options.get("status", "")
	if status_filter != "":
		sql += " WHERE status = ?"
		args.append(status_filter)

	sql += " ORDER BY last_name ASC, first_name ASC, id ASC;"
	var res = db.execute(sql, args)
	if not res["success"]:
		return {"success": false, "error": res["error"], "people": []}
	return {"success": true, "error": "", "people": res["data"]}

func update_person_profile(person_uuid: String, updates: Dictionary, device_uuid: String = "dev_macbook_primary_node") -> Dictionary:
	var existing_res = get_person_by_uuid(person_uuid)
	if not existing_res["success"]:
		return {"success": false, "error": "Person not found.", "person": {}}

	for field in IMMUTABLE_FIELDS:
		if updates.has(field):
			return {"success": false, "error": "Cannot modify immutable field: " + field, "person": {}}

	var allowed_fields = [
		"first_name", "last_name", "phone", "status", "grade",
		"notes", "emergency_contact_name", "emergency_contact_phone", "medical_notes"
	]

	var set_clauses = []
	var args = []

	for key in updates.keys():
		if key in allowed_fields:
			if key == "status" and not updates[key] in VALID_STATUSES:
				return {"success": false, "error": "Invalid status value: " + str(updates[key]), "person": {}}
			set_clauses.append(key + " = ?")
			args.append(updates[key])

	if set_clauses.size() == 0:
		return {"success": true, "error": "", "person": existing_res["person"]}

	set_clauses.append("updated_at = (datetime('now'))")
	args.append(person_uuid)

	var sql = "UPDATE people SET " + ", ".join(set_clauses) + " WHERE person_uuid = ?;"

	var event_uuid = "evt_" + _generate_uuid()
	var payload_dict = {
		"event_uuid": event_uuid,
		"event_type": "PersonUpdated",
		"person_uuid": person_uuid,
		"human_id": existing_res["person"].get("human_id", ""),
		"updates": updates,
		"device_uuid": device_uuid,
		"timestamp": Time.get_datetime_string_from_system()
	}

	var stmt1 = {"sql": sql, "args": args}
	var stmt2 = {
		"sql": "INSERT INTO event_outbox (event_uuid, event_type, aggregate_type, aggregate_id, payload_json, device_uuid, status) VALUES (?, ?, ?, ?, ?, ?, ?);",
		"args": [event_uuid, "PersonUpdated", "Person", person_uuid, JSON.stringify(payload_dict), device_uuid, "pending"]
	}

	var tx_res = db.execute_transaction([stmt1, stmt2])
	if not tx_res["success"]:
		return {"success": false, "error": tx_res["error"], "person": {}}

	var updated_res = get_person_by_uuid(person_uuid)
	if updated_res["success"] and updates.has("status"):
		var p_dict = updated_res["person"]
		var p_id = int(p_dict.get("id", 0))
		var new_st = str(updates["status"]).to_lower()
		if p_id > 0:
			var cred_svc = QRCredentialServiceScript.new(db)
			if new_st in ["inactive", "suspended", "banned", "archived"]:
				cred_svc.revoke_credential(p_id)
			elif new_st == STATUS_ACTIVE:
				cred_svc.issue_credential(p_id, person_uuid)
				var com_svc = CommunicationsServiceScript.new(db)
				com_svc.email_digital_member_pass(p_id, "Staff Administrator")
				com_svc.sms_digital_member_pass(p_id, "Staff Administrator")
				var q_uuid = "queue_" + _generate_uuid()
				db.execute("INSERT OR IGNORE INTO card_print_queue (queue_uuid, person_id, person_uuid, status, added_at) VALUES (?, ?, ?, 'pending', datetime('now'));", [q_uuid, p_id, person_uuid])

	return updated_res

func update_notes(person_uuid: String, notes: String, device_uuid: String = "dev_macbook_primary_node") -> Dictionary:
	return update_person_profile(person_uuid, {"notes": notes}, device_uuid)

func update_emergency_contacts(person_uuid: String, contact_name: String, contact_phone: String, device_uuid: String = "dev_macbook_primary_node") -> Dictionary:
	return update_person_profile(person_uuid, {
		"emergency_contact_name": contact_name,
		"emergency_contact_phone": contact_phone
	}, device_uuid)

func update_medical_notes(person_uuid: String, medical_notes: String, device_uuid: String = "dev_macbook_primary_node") -> Dictionary:
	return update_person_profile(person_uuid, {"medical_notes": medical_notes}, device_uuid)

func change_person_status(person_uuid: String, new_status: String, device_uuid: String = "dev_macbook_primary_node") -> Dictionary:
	if not new_status in VALID_STATUSES:
		return {"success": false, "error": "Invalid status value: " + new_status, "person": {}}
	return update_person_profile(person_uuid, {"status": new_status}, device_uuid)

func approve_person(person_uuid: String, device_uuid: String = "dev_macbook_primary_node") -> Dictionary:
	var existing_res = get_person_by_uuid(person_uuid)
	if not existing_res["success"]:
		return {"success": false, "error": "Person not found.", "person": {}}

	var person = existing_res["person"]
	var orig_human_id = person.get("human_id", "")
	var orig_uuid = person.get("person_uuid", "")

	var update_res = update_person_profile(person_uuid, {"status": STATUS_ACTIVE}, device_uuid)
	if not update_res["success"]:
		return update_res

	# Verify human_id and person_uuid were strictly preserved
	var check_res = get_person_by_uuid(person_uuid)
	if check_res["success"]:
		var p = check_res["person"]
		if p.get("human_id", "") != orig_human_id or p.get("person_uuid", "") != orig_uuid:
			return {"success": false, "error": "Approval regenerated immutable identifiers!", "person": {}}

	return check_res

func inactivate_person(person_uuid: String, device_uuid: String = "dev_macbook_primary_node") -> Dictionary:
	var existing_res = get_person_by_uuid(person_uuid)
	if not existing_res["success"]:
		return {"success": false, "error": "Person not found.", "person": {}}

	return update_person_profile(person_uuid, {"status": STATUS_INACTIVE}, device_uuid)

func _generate_uuid() -> String:
	var b1 = "%08X" % (randi() % 4294967295)
	var b2 = "%04X" % (randi() % 65536)
	var b3 = "%04X" % (randi() % 65536)
	return (b1 + "-" + b2 + "-" + b3).to_lower()
