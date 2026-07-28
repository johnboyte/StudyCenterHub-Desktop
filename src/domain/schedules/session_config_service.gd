extends RefCounted

## Domain Service for Session Types & Locations Configuration (PD-007)
## Manages relational taxonomy, exclusive location rules, multi-location assignments, ordering, and archival state.

var db: RefCounted

func _init(database: RefCounted) -> void:
	db = database

# ==================== SERVICE-LAYER AUTHORIZATION ====================

func authorize_admin_mutation(actor_id: String, permission_key: String = "CAP_HOURS_EDIT") -> Dictionary:
	if not db:
		return {"authorized": false, "error": "Database engine not initialized."}
	
	if actor_id.strip_edges() == "":
		return {"authorized": false, "error": "Unauthenticated access rejected: actor ID is required."}

	# Check app_settings for role capability permission flag
	var cap_key = permission_key + "_SUPERVISOR"
	var res = db.execute("SELECT setting_value FROM app_settings WHERE setting_key = ?;", [cap_key])
	if res["success"] and res["data"].size() > 0:
		var val = str(res["data"][0].get("setting_value", "true")).to_lower()
		if val == "false" and actor_id != "usr_admin_master":
			return {"authorized": false, "error": "User '%s' lacks administrative capability '%s'." % [actor_id, permission_key]}

	return {"authorized": true, "error": ""}

# ==================== SESSION TYPES MANAGEMENT ====================

func get_all_session_types(include_inactive: bool = true) -> Array:
	var sql = "SELECT id, type_key, name, description, display_order, is_active, is_migrated, created_at FROM session_types "
	if not include_inactive:
		sql += "WHERE is_active = 1 "
	sql += "ORDER BY display_order ASC, name ASC;"
	var res = db.execute(sql)
	if res["success"]: return res["data"]
	return []

func add_session_type(name: String, description: String = "", actor_id: String = "usr_admin_master", actor_name: String = "Administrator") -> Dictionary:
	var auth = authorize_admin_mutation(actor_id, "CAP_HOURS_EDIT")
	if not auth["authorized"]: return {"success": false, "error": auth["error"]}

	var clean_name = name.strip_edges()
	if clean_name == "":
		return {"success": false, "error": "Session Type name cannot be empty."}

	# Case-insensitive, whitespace-trimmed duplicate active check
	var dup_res = db.execute("SELECT id FROM session_types WHERE lower(trim(name)) = lower(trim(?)) AND is_active = 1;", [clean_name])
	if dup_res["success"] and dup_res["data"].size() > 0:
		return {"success": false, "error": "An active Session Type with the name '%s' already exists." % clean_name}

	# Collision-resistant stable key generation
	var type_key = _generate_stable_key(clean_name, "session_types", "type_key")

	var max_order_res = db.execute("SELECT MAX(display_order) as m FROM session_types;")
	var next_order = 1
	if max_order_res["success"] and max_order_res["data"].size() > 0 and max_order_res["data"][0]["m"] != null:
		next_order = int(max_order_res["data"][0]["m"]) + 1

	var event_uuid = "evt_" + _generate_uuid()
	var device_uuid = "dev_macbook_primary_node"
	var timestamp = Time.get_datetime_string_from_system()

	var stmt1 = {
		"sql": "INSERT INTO session_types (type_key, name, description, display_order, is_active, is_migrated) VALUES (?, ?, ?, ?, 1, 0);",
		"args": [type_key, clean_name, description.strip_edges(), next_order]
	}

	var payload_dict = {
		"event_uuid": event_uuid,
		"entity_type": "SessionType",
		"action": "Created",
		"type_key": type_key,
		"name": clean_name,
		"description": description.strip_edges(),
		"display_order": next_order,
		"actor_id": actor_id,
		"occurred_at": timestamp,
		"device_uuid": device_uuid
	}
	var payload_json = JSON.stringify(payload_dict)

	var stmt2 = {
		"sql": "INSERT INTO event_outbox (event_uuid, event_type, aggregate_type, aggregate_id, payload_json, device_uuid, status) VALUES (?, 'SessionTypeCreated', 'Taxonomy', ?, ?, ?, 'pending');",
		"args": [event_uuid, type_key, payload_json, device_uuid]
	}

	var tx_res = db.execute_transaction([stmt1, stmt2])
	if not tx_res["success"]: return {"success": false, "error": tx_res["error"]}

	var get_id = db.execute("SELECT id FROM session_types WHERE type_key = ?;", [type_key])
	var new_id = get_id["data"][0]["id"] if (get_id["success"] and get_id["data"].size() > 0) else 0

	_record_taxonomy_audit("SessionType", new_id, "Created", actor_id, actor_name, JSON.stringify({"name": clean_name, "type_key": type_key}))

	return {"success": true, "error": "", "id": new_id, "type_key": type_key}

func rename_session_type(id: int, new_name: String, description: String = "", actor_id: String = "usr_admin_master", actor_name: String = "Administrator") -> Dictionary:
	var auth = authorize_admin_mutation(actor_id, "CAP_HOURS_EDIT")
	if not auth["authorized"]: return {"success": false, "error": auth["error"]}

	var clean_name = new_name.strip_edges()
	if clean_name == "":
		return {"success": false, "error": "Session Type name cannot be empty."}

	var dup_res = db.execute("SELECT id FROM session_types WHERE lower(trim(name)) = lower(trim(?)) AND id != ? AND is_active = 1;", [clean_name, id])
	if dup_res["success"] and dup_res["data"].size() > 0:
		return {"success": false, "error": "Another active Session Type already uses the name '%s'." % clean_name}

	var curr_res = db.execute("SELECT type_key, name FROM session_types WHERE id = ?;", [id])
	if not curr_res["success"] or curr_res["data"].size() == 0:
		return {"success": false, "error": "Session Type record not found."}

	var old_name = str(curr_res["data"][0]["name"])
	var type_key = str(curr_res["data"][0]["type_key"])

	var event_uuid = "evt_" + _generate_uuid()
	var device_uuid = "dev_macbook_primary_node"
	var timestamp = Time.get_datetime_string_from_system()

	var stmt1 = {
		"sql": "UPDATE session_types SET name = ?, description = ? WHERE id = ?;",
		"args": [clean_name, description.strip_edges(), id]
	}

	var payload_dict = {
		"event_uuid": event_uuid,
		"entity_type": "SessionType",
		"action": "Updated",
		"id": id,
		"type_key": type_key,
		"old_name": old_name,
		"new_name": clean_name,
		"actor_id": actor_id,
		"occurred_at": timestamp,
		"device_uuid": device_uuid
	}
	var payload_json = JSON.stringify(payload_dict)

	var stmt2 = {
		"sql": "INSERT INTO event_outbox (event_uuid, event_type, aggregate_type, aggregate_id, payload_json, device_uuid, status) VALUES (?, 'SessionTypeUpdated', 'Taxonomy', ?, ?, ?, 'pending');",
		"args": [event_uuid, type_key, payload_json, device_uuid]
	}

	var tx_res = db.execute_transaction([stmt1, stmt2])
	if not tx_res["success"]: return {"success": false, "error": tx_res["error"]}

	_record_taxonomy_audit("SessionType", id, "Renamed", actor_id, actor_name, JSON.stringify({"old_name": old_name, "new_name": clean_name}))

	return {"success": true, "error": ""}

func set_session_type_active_state(id: int, is_active: bool, actor_id: String = "usr_admin_master", actor_name: String = "Administrator") -> Dictionary:
	var auth = authorize_admin_mutation(actor_id, "CAP_HOURS_EDIT")
	if not auth["authorized"]: return {"success": false, "error": auth["error"]}

	var curr_res = db.execute("SELECT name FROM session_types WHERE id = ?;", [id])
	if not curr_res["success"] or curr_res["data"].size() == 0:
		return {"success": false, "error": "Session Type record not found."}

	var type_name = str(curr_res["data"][0]["name"])

	# If restoring to Active, verify no active conflict exists
	if is_active:
		var dup_res = db.execute("SELECT id FROM session_types WHERE lower(trim(name)) = lower(trim(?)) AND id != ? AND is_active = 1;", [type_name, id])
		if dup_res["success"] and dup_res["data"].size() > 0:
			return {"success": false, "error": "Cannot activate: another active Session Type already uses the name '%s'. Rename this item first." % type_name}

	var new_state_int = 1 if is_active else 0
	var event_uuid = "evt_" + _generate_uuid()
	var device_uuid = "dev_macbook_primary_node"
	var timestamp = Time.get_datetime_string_from_system()

	var stmt1 = {
		"sql": "UPDATE session_types SET is_active = ? WHERE id = ?;",
		"args": [new_state_int, id]
	}

	var payload_dict = {
		"event_uuid": event_uuid,
		"entity_type": "SessionType",
		"action": "StateChanged",
		"id": id,
		"is_active": new_state_int,
		"actor_id": actor_id,
		"occurred_at": timestamp,
		"device_uuid": device_uuid
	}
	var payload_json = JSON.stringify(payload_dict)

	var stmt2 = {
		"sql": "INSERT INTO event_outbox (event_uuid, event_type, aggregate_type, aggregate_id, payload_json, device_uuid, status) VALUES (?, 'SessionTypeStateChanged', 'Taxonomy', ?, ?, ?, 'pending');",
		"args": [event_uuid, str(id), payload_json, device_uuid]
	}

	var tx_res = db.execute_transaction([stmt1, stmt2])
	if not tx_res["success"]: return {"success": false, "error": tx_res["error"]}

	_record_taxonomy_audit("SessionType", id, "StateChanged", actor_id, actor_name, JSON.stringify({"is_active": is_active, "name": type_name}))

	return {"success": true, "error": ""}

func reorder_session_types_atomic(ordered_ids: Array, actor_id: String = "usr_admin_master", actor_name: String = "Administrator") -> Dictionary:
	var auth = authorize_admin_mutation(actor_id, "CAP_HOURS_EDIT")
	if not auth["authorized"]: return {"success": false, "error": auth["error"]}

	if ordered_ids.size() == 0:
		return {"success": true, "error": ""}

	var stmts = []
	for i in range(ordered_ids.size()):
		stmts.append({
			"sql": "UPDATE session_types SET display_order = ? WHERE id = ?;",
			"args": [i + 1, int(ordered_ids[i])]
		})

	var event_uuid = "evt_" + _generate_uuid()
	var device_uuid = "dev_macbook_primary_node"
	var timestamp = Time.get_datetime_string_from_system()

	var payload_dict = {
		"event_uuid": event_uuid,
		"entity_type": "SessionType",
		"action": "Reordered",
		"taxonomy_type": "SessionTypes",
		"ordered_ids": ordered_ids,
		"actor_id": actor_id,
		"occurred_at": timestamp,
		"device_uuid": device_uuid
	}
	stmts.append({
		"sql": "INSERT INTO event_outbox (event_uuid, event_type, aggregate_type, aggregate_id, payload_json, device_uuid, status) VALUES (?, 'SessionTaxonomyReordered', 'Taxonomy', 'SessionTypes', ?, ?, 'pending');",
		"args": [event_uuid, JSON.stringify(payload_dict), device_uuid]
	})

	var tx_res = db.execute_transaction(stmts)
	if tx_res["success"]:
		_record_taxonomy_audit("SessionType", 0, "Reordered", actor_id, actor_name, JSON.stringify({"ordered_ids": ordered_ids}))
	return tx_res

func move_session_type_order(id: int, direction: String, actor_id: String = "usr_admin_master", actor_name: String = "Administrator") -> Dictionary:
	var types = get_all_session_types(true)
	var curr_idx = -1
	for i in range(types.size()):
		if int(types[i]["id"]) == id:
			curr_idx = i
			break

	if curr_idx == -1: return {"success": false, "error": "Item not found."}

	var target_idx = curr_idx - 1 if direction == "up" else curr_idx + 1
	if target_idx < 0 or target_idx >= types.size():
		return {"success": true, "error": ""} # Already at edge boundary

	var temp = types[curr_idx]
	types[curr_idx] = types[target_idx]
	types[target_idx] = temp

	var new_ids = []
	for t in types: new_ids.append(int(t["id"]))

	return reorder_session_types_atomic(new_ids, actor_id, actor_name)

# ==================== SESSION LOCATIONS MANAGEMENT ====================

func get_all_session_locations(include_inactive: bool = true) -> Array:
	var sql = "SELECT id, location_key, name, capacity, is_exclusive, display_order, is_active, is_migrated, created_at FROM session_locations "
	if not include_inactive:
		sql += "WHERE is_active = 1 "
	sql += "ORDER BY display_order ASC, name ASC;"
	var res = db.execute(sql)
	if res["success"]: return res["data"]
	return []

func add_session_location(name: String, is_exclusive: bool = false, actor_id: String = "usr_admin_master", actor_name: String = "Administrator") -> Dictionary:
	var auth = authorize_admin_mutation(actor_id, "CAP_HOURS_EDIT")
	if not auth["authorized"]: return {"success": false, "error": auth["error"]}

	var clean_name = name.strip_edges()
	if clean_name == "":
		return {"success": false, "error": "Session Location name cannot be empty."}

	# Case-insensitive, whitespace-trimmed duplicate active check
	var dup_res = db.execute("SELECT id FROM session_locations WHERE lower(trim(name)) = lower(trim(?)) AND is_active = 1;", [clean_name])
	if dup_res["success"] and dup_res["data"].size() > 0:
		return {"success": false, "error": "An active Session Location with the name '%s' already exists." % clean_name}

	# Collision-resistant stable key generation
	var loc_key = _generate_stable_key(clean_name, "session_locations", "location_key")

	var max_order_res = db.execute("SELECT MAX(display_order) as m FROM session_locations;")
	var next_order = 1
	if max_order_res["success"] and max_order_res["data"].size() > 0 and max_order_res["data"][0]["m"] != null:
		next_order = int(max_order_res["data"][0]["m"]) + 1

	var event_uuid = "evt_" + _generate_uuid()
	var device_uuid = "dev_macbook_primary_node"
	var timestamp = Time.get_datetime_string_from_system()

	var stmt1 = {
		"sql": "INSERT INTO session_locations (location_key, name, capacity, is_exclusive, display_order, is_active, is_migrated) VALUES (?, ?, NULL, ?, ?, 1, 0);",
		"args": [loc_key, clean_name, 1 if is_exclusive else 0, next_order]
	}

	var payload_dict = {
		"event_uuid": event_uuid,
		"entity_type": "SessionLocation",
		"action": "Created",
		"location_key": loc_key,
		"name": clean_name,
		"is_exclusive": 1 if is_exclusive else 0,
		"display_order": next_order,
		"actor_id": actor_id,
		"occurred_at": timestamp,
		"device_uuid": device_uuid
	}
	var payload_json = JSON.stringify(payload_dict)

	var stmt2 = {
		"sql": "INSERT INTO event_outbox (event_uuid, event_type, aggregate_type, aggregate_id, payload_json, device_uuid, status) VALUES (?, 'SessionLocationCreated', 'Taxonomy', ?, ?, ?, 'pending');",
		"args": [event_uuid, loc_key, payload_json, device_uuid]
	}

	var tx_res = db.execute_transaction([stmt1, stmt2])
	if not tx_res["success"]: return {"success": false, "error": tx_res["error"]}

	var get_id = db.execute("SELECT id FROM session_locations WHERE location_key = ?;", [loc_key])
	var new_id = get_id["data"][0]["id"] if (get_id["success"] and get_id["data"].size() > 0) else 0

	_record_taxonomy_audit("SessionLocation", new_id, "Created", actor_id, actor_name, JSON.stringify({"name": clean_name, "is_exclusive": is_exclusive}))

	return {"success": true, "error": "", "id": new_id, "location_key": loc_key}

func rename_session_location(id: int, new_name: String, is_exclusive: bool = false, actor_id: String = "usr_admin_master", actor_name: String = "Administrator") -> Dictionary:
	var auth = authorize_admin_mutation(actor_id, "CAP_HOURS_EDIT")
	if not auth["authorized"]: return {"success": false, "error": auth["error"]}

	var clean_name = new_name.strip_edges()
	if clean_name == "":
		return {"success": false, "error": "Session Location name cannot be empty."}

	var dup_res = db.execute("SELECT id FROM session_locations WHERE lower(trim(name)) = lower(trim(?)) AND id != ? AND is_active = 1;", [clean_name, id])
	if dup_res["success"] and dup_res["data"].size() > 0:
		return {"success": false, "error": "Another active Session Location already uses the name '%s'." % clean_name}

	var curr_res = db.execute("SELECT location_key, name FROM session_locations WHERE id = ?;", [id])
	if not curr_res["success"] or curr_res["data"].size() == 0:
		return {"success": false, "error": "Session Location record not found."}

	var old_name = str(curr_res["data"][0]["name"])
	var loc_key = str(curr_res["data"][0]["location_key"])

	var event_uuid = "evt_" + _generate_uuid()
	var device_uuid = "dev_macbook_primary_node"
	var timestamp = Time.get_datetime_string_from_system()

	var stmt1 = {
		"sql": "UPDATE session_locations SET name = ?, is_exclusive = ? WHERE id = ?;",
		"args": [clean_name, 1 if is_exclusive else 0, id]
	}

	var payload_dict = {
		"event_uuid": event_uuid,
		"entity_type": "SessionLocation",
		"action": "Updated",
		"id": id,
		"location_key": loc_key,
		"old_name": old_name,
		"new_name": clean_name,
		"is_exclusive": 1 if is_exclusive else 0,
		"actor_id": actor_id,
		"occurred_at": timestamp,
		"device_uuid": device_uuid
	}
	var payload_json = JSON.stringify(payload_dict)

	var stmt2 = {
		"sql": "INSERT INTO event_outbox (event_uuid, event_type, aggregate_type, aggregate_id, payload_json, device_uuid, status) VALUES (?, 'SessionLocationUpdated', 'Taxonomy', ?, ?, ?, 'pending');",
		"args": [event_uuid, loc_key, payload_json, device_uuid]
	}

	var tx_res = db.execute_transaction([stmt1, stmt2])
	if not tx_res["success"]: return {"success": false, "error": tx_res["error"]}

	_record_taxonomy_audit("SessionLocation", id, "Renamed", actor_id, actor_name, JSON.stringify({"old_name": old_name, "new_name": clean_name, "is_exclusive": is_exclusive}))

	return {"success": true, "error": ""}

func set_session_location_active_state(id: int, is_active: bool, actor_id: String = "usr_admin_master", actor_name: String = "Administrator") -> Dictionary:
	var auth = authorize_admin_mutation(actor_id, "CAP_HOURS_EDIT")
	if not auth["authorized"]: return {"success": false, "error": auth["error"]}

	var curr_res = db.execute("SELECT name FROM session_locations WHERE id = ?;", [id])
	if not curr_res["success"] or curr_res["data"].size() == 0:
		return {"success": false, "error": "Session Location record not found."}

	var loc_name = str(curr_res["data"][0]["name"])

	# If restoring to Active, verify no active conflict exists
	if is_active:
		var dup_res = db.execute("SELECT id FROM session_locations WHERE lower(trim(name)) = lower(trim(?)) AND id != ? AND is_active = 1;", [loc_name, id])
		if dup_res["success"] and dup_res["data"].size() > 0:
			return {"success": false, "error": "Cannot activate: another active Session Location already uses the name '%s'. Rename this item first." % loc_name}

	var new_state_int = 1 if is_active else 0
	var event_uuid = "evt_" + _generate_uuid()
	var device_uuid = "dev_macbook_primary_node"
	var timestamp = Time.get_datetime_string_from_system()

	var stmt1 = {
		"sql": "UPDATE session_locations SET is_active = ? WHERE id = ?;",
		"args": [new_state_int, id]
	}

	var payload_dict = {
		"event_uuid": event_uuid,
		"entity_type": "SessionLocation",
		"action": "StateChanged",
		"id": id,
		"is_active": new_state_int,
		"actor_id": actor_id,
		"occurred_at": timestamp,
		"device_uuid": device_uuid
	}
	var payload_json = JSON.stringify(payload_dict)

	var stmt2 = {
		"sql": "INSERT INTO event_outbox (event_uuid, event_type, aggregate_type, aggregate_id, payload_json, device_uuid, status) VALUES (?, 'SessionLocationStateChanged', 'Taxonomy', ?, ?, ?, 'pending');",
		"args": [event_uuid, str(id), payload_json, device_uuid]
	}

	var tx_res = db.execute_transaction([stmt1, stmt2])
	if not tx_res["success"]: return {"success": false, "error": tx_res["error"]}

	_record_taxonomy_audit("SessionLocation", id, "StateChanged", actor_id, actor_name, JSON.stringify({"is_active": is_active, "name": loc_name}))

	return {"success": true, "error": ""}

func set_location_exclusive_state(id: int, is_exclusive: bool, actor_id: String = "usr_admin_master", actor_name: String = "Administrator") -> Dictionary:
	var auth = authorize_admin_mutation(actor_id, "CAP_HOURS_EDIT")
	if not auth["authorized"]: return {"success": false, "error": auth["error"]}

	var sql = "UPDATE session_locations SET is_exclusive = ? WHERE id = ?;"
	var res = db.execute(sql, [1 if is_exclusive else 0, id])
	if res["success"]:
		_record_taxonomy_audit("SessionLocation", id, "ExclusiveToggled", actor_id, actor_name, JSON.stringify({"is_exclusive": is_exclusive}))
	return res

func reorder_session_locations_atomic(ordered_ids: Array, actor_id: String = "usr_admin_master", actor_name: String = "Administrator") -> Dictionary:
	var auth = authorize_admin_mutation(actor_id, "CAP_HOURS_EDIT")
	if not auth["authorized"]: return {"success": false, "error": auth["error"]}

	if ordered_ids.size() == 0:
		return {"success": true, "error": ""}

	var stmts = []
	for i in range(ordered_ids.size()):
		stmts.append({
			"sql": "UPDATE session_locations SET display_order = ? WHERE id = ?;",
			"args": [i + 1, int(ordered_ids[i])]
		})

	var event_uuid = "evt_" + _generate_uuid()
	var device_uuid = "dev_macbook_primary_node"
	var timestamp = Time.get_datetime_string_from_system()

	var payload_dict = {
		"event_uuid": event_uuid,
		"entity_type": "SessionLocation",
		"action": "Reordered",
		"taxonomy_type": "SessionLocations",
		"ordered_ids": ordered_ids,
		"actor_id": actor_id,
		"occurred_at": timestamp,
		"device_uuid": device_uuid
	}
	stmts.append({
		"sql": "INSERT INTO event_outbox (event_uuid, event_type, aggregate_type, aggregate_id, payload_json, device_uuid, status) VALUES (?, 'SessionTaxonomyReordered', 'Taxonomy', 'SessionLocations', ?, ?, 'pending');",
		"args": [event_uuid, JSON.stringify(payload_dict), device_uuid]
	})

	var tx_res = db.execute_transaction(stmts)
	if tx_res["success"]:
		_record_taxonomy_audit("SessionLocation", 0, "Reordered", actor_id, actor_name, JSON.stringify({"ordered_ids": ordered_ids}))
	return tx_res

func move_session_location_order(id: int, direction: String, actor_id: String = "usr_admin_master", actor_name: String = "Administrator") -> Dictionary:
	var locs = get_all_session_locations(true)
	var curr_idx = -1
	for i in range(locs.size()):
		if int(locs[i]["id"]) == id:
			curr_idx = i
			break

	if curr_idx == -1: return {"success": false, "error": "Item not found."}

	var target_idx = curr_idx - 1 if direction == "up" else curr_idx + 1
	if target_idx < 0 or target_idx >= locs.size():
		return {"success": true, "error": ""} # Already at edge boundary

	var temp = locs[curr_idx]
	locs[curr_idx] = locs[target_idx]
	locs[target_idx] = temp

	var new_ids = []
	for l in locs: new_ids.append(int(l["id"]))

	return reorder_session_locations_atomic(new_ids, actor_id, actor_name)

# ==================== EXCLUSIVE LOCATION RULE VALIDATION ====================

func validate_location_selection(location_ids: Array) -> Dictionary:
	if location_ids.size() == 0:
		return {"valid": false, "error": "At least one location must be selected."}

	var placeholders = []
	for i in range(location_ids.size()): placeholders.append("?")
	var sql = "SELECT id, name, is_exclusive FROM session_locations WHERE id IN (" + ",".join(placeholders) + ");"
	var res = db.execute(sql, location_ids)

	if not res["success"]:
		return {"valid": false, "error": "Database validation query failed: " + res["error"]}

	var exclusive_count = 0
	var standard_count = 0
	var excl_name = ""

	for loc in res["data"]:
		if int(loc.get("is_exclusive", 0)) == 1:
			exclusive_count += 1
			excl_name = str(loc.get("name"))
		else:
			standard_count += 1

	if exclusive_count > 0 and standard_count > 0:
		return {"valid": false, "error": "An Exclusive Location (" + excl_name + ") cannot be combined with standard locations."}

	return {"valid": true, "error": ""}

# ==================== HELPER METHODS ====================

func _generate_stable_key(base_name: String, table_name: String, column_name: String) -> String:
	var clean = base_name.to_lower().strip_edges().replace(" ", "_").replace("-", "_").replace("&", "and")
	var sanitized = ""
	for i in range(clean.length()):
		var ch = clean[i]
		if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9") or ch == "_":
			sanitized += ch

	if sanitized == "":
		sanitized = "item"

	var key_candidate = sanitized
	var suffix = 1

	while true:
		var q = "SELECT id FROM " + table_name + " WHERE " + column_name + " = ?;"
		var check = db.execute(q, [key_candidate])
		if check["success"] and check["data"].size() > 0:
			suffix += 1
			key_candidate = sanitized + "_" + str(suffix)
		else:
			break

	return key_candidate

func _record_taxonomy_audit(entity_type: String, entity_id: int, action: String, actor_id: String, actor_name: String, detail_json: String = "") -> void:
	if db:
		db.execute("INSERT INTO taxonomy_audit_log (entity_type, entity_id, action, actor_id, actor_name, detail_json, timestamp) VALUES (?, ?, ?, ?, ?, ?, datetime('now'));", [entity_type, entity_id, action, actor_id, actor_name, detail_json])

func _generate_uuid() -> String:
	var b1 = "%08X" % (randi() % 4294967295)
	var b2 = "%04X" % (randi() % 65536)
	var b3 = "%04X" % (randi() % 65536)
	return (b1 + "-" + b2 + "-" + b3).to_lower()
