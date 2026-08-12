extends RefCounted

## Domain Service for Campus & Community Master Institutions, Merging & Major Normalization
## Complies with [PD-001] (Offline Storage & Outbox) and [PD-002] (Read Isolation).

var db: RefCounted

func _init(database: RefCounted) -> void:
	db = database

static func normalize_string(input_str: String) -> String:
	var s = input_str.to_lower().strip_edges()
	for c in [".", ",", "-", "_", "/", "\\", "(", ")"]:
		s = s.replace(c, " ")
	var raw_words = s.split(" ", false)
	var norm_words = []
	for w in raw_words:
		if w == "univ" or w == "u":
			norm_words.append("university")
		elif w == "coll" or w == "c":
			norm_words.append("college")
		elif w == "tech":
			norm_words.append("technical")
		elif w == "hs":
			norm_words.append("high")
			norm_words.append("school")
		else:
			norm_words.append(w)
	return " ".join(norm_words)

func find_duplicate_institutions() -> Array:
	if not db: return []
	var res = db.execute("SELECT id, uuid, name, short_name, institution_type, is_active FROM institutions ORDER BY name ASC;")
	if not res["success"]: return []
	
	var inst_list = res["data"]
	var duplicates = []
	var seen = {}

	for i in range(inst_list.size()):
		var item1 = inst_list[i]
		var norm1 = normalize_string(str(item1.get("name", "")))
		if seen.has(norm1):
			duplicates.append({
				"primary": seen[norm1],
				"duplicate": item1,
				"reason": "Normalized name similarity: '" + norm1 + "'"
			})
		else:
			seen[norm1] = item1
	return duplicates

func get_unlinked_custom_institution_names() -> Array:
	if not db: return []
	var res = db.execute("SELECT institution_other_name, COUNT(*) AS count FROM people WHERE (institution_id IS NULL OR institution_id = 0) AND institution_other_name IS NOT NULL AND TRIM(institution_other_name) != '' GROUP BY institution_other_name ORDER BY count DESC;")
	return res["data"] if res["success"] else []

func get_institution_merge_preview(source_id_or_name: Variant, target_inst_id: int) -> Dictionary:
	if not db: return {"success": false, "error": "Database not initialized."}

	var target_q = db.execute("SELECT * FROM institutions WHERE id = ? LIMIT 1;", [target_inst_id])
	if not target_q["success"] or target_q["data"].size() == 0:
		return {"success": false, "error": "Destination master institution not found."}
	var target_inst = target_q["data"][0]
	var target_name = str(target_inst.get("name", ""))
	var target_type = str(target_inst.get("institution_type", "college_university"))

	var source_type = ""
	var source_name = ""
	var source_inst_id: int = 0
	var is_custom_name = (typeof(source_id_or_name) == TYPE_STRING)

	if is_custom_name:
		source_name = String(source_id_or_name)
	else:
		source_inst_id = int(source_id_or_name)
		var sq = db.execute("SELECT * FROM institutions WHERE id = ? LIMIT 1;", [source_inst_id])
		if sq["success"] and sq["data"].size() > 0:
			source_name = str(sq["data"][0].get("name", ""))
			source_type = str(sq["data"][0].get("institution_type", ""))

	# Count affected constituents
	var p_cnt = 0
	if is_custom_name:
		var pq = db.execute("SELECT COUNT(*) AS cnt FROM people WHERE (institution_id IS NULL OR institution_id = 0) AND LOWER(TRIM(institution_other_name)) = LOWER(TRIM(?));", [source_name])
		p_cnt = int(pq["data"][0]["cnt"]) if pq["success"] and pq["data"].size() > 0 else 0
	else:
		var pq = db.execute("SELECT COUNT(*) AS cnt FROM people WHERE institution_id = ?;", [source_inst_id])
		p_cnt = int(pq["data"][0]["cnt"]) if pq["success"] and pq["data"].size() > 0 else 0

	# Count affected academic history records
	var h_cnt = 0
	if is_custom_name:
		var hq = db.execute("SELECT COUNT(*) AS cnt FROM person_academic_history WHERE (institution_id IS NULL OR institution_id = 0) AND LOWER(TRIM(institution_other_name)) = LOWER(TRIM(?));", [source_name])
		h_cnt = int(hq["data"][0]["cnt"]) if hq["success"] and hq["data"].size() > 0 else 0
	else:
		var hq = db.execute("SELECT COUNT(*) AS cnt FROM person_academic_history WHERE institution_id = ?;", [source_inst_id])
		h_cnt = int(hq["data"][0]["cnt"]) if hq["success"] and hq["data"].size() > 0 else 0

	# Check for incompatible institution-type conflict
	var has_type_mismatch = false
	if source_type != "" and source_type != target_type:
		has_type_mismatch = true

	return {
		"success": true,
		"source_name": source_name,
		"source_inst_id": source_inst_id,
		"target_name": target_name,
		"target_inst_id": target_inst_id,
		"affected_people_count": p_cnt,
		"affected_history_count": h_cnt,
		"has_type_mismatch": has_type_mismatch,
		"source_type": source_type,
		"target_type": target_type
	}

func merge_institutions_atomic(source_id_or_name: Variant, target_inst_id: int, admin_user: String, reason: String) -> Dictionary:
	var prev = get_institution_merge_preview(source_id_or_name, target_inst_id)
	if not prev.get("success", false):
		return prev

	var is_custom_name = (typeof(source_id_or_name) == TYPE_STRING)
	var source_name = String(prev["source_name"])
	var source_inst_id = int(prev["source_inst_id"])

	# Reassign people records
	if is_custom_name:
		db.execute("UPDATE people SET institution_id = ?, institution_other_name = '', updated_at = datetime('now') WHERE (institution_id IS NULL OR institution_id = 0) AND LOWER(TRIM(institution_other_name)) = LOWER(TRIM(?));", [target_inst_id, source_name])
		db.execute("UPDATE person_academic_history SET institution_id = ? WHERE (institution_id IS NULL OR institution_id = 0) AND LOWER(TRIM(institution_other_name)) = LOWER(TRIM(?));", [target_inst_id, source_name])
	else:
		db.execute("UPDATE people SET institution_id = ?, updated_at = datetime('now') WHERE institution_id = ?;", [target_inst_id, source_inst_id])
		db.execute("UPDATE person_academic_history SET institution_id = ? WHERE institution_id = ?;", [target_inst_id, source_inst_id])
		db.execute("UPDATE institutions SET is_active = 0, updated_at = datetime('now') WHERE id = ?;", [source_inst_id])

	# Record audit log event
	var audit_msg = "Merged institution '%s' into '%s' (%d constituents affected). Reason: %s" % [source_name, prev["target_name"], prev["affected_people_count"], reason]
	var event_uuid = "evt_merge_" + str(Time.get_ticks_msec()) + "_" + str(randi() % 100000)
	db.execute("INSERT INTO event_outbox (event_uuid, event_type, aggregate_type, aggregate_id, payload_json, device_uuid, created_at) VALUES (?, 'institution.merged', 'institution', ?, ?, 'dev_local', datetime('now'));",
		[event_uuid, str(target_inst_id), audit_msg])

	return {
		"success": true,
		"affected_people_count": prev["affected_people_count"],
		"message": audit_msg
	}

# --- ACADEMIC MAJORS MANAGEMENT ---

func get_canonical_majors() -> Array:
	if not db: return []
	var res = db.execute("SELECT * FROM academic_majors ORDER BY display_order ASC, canonical_name ASC;")
	return res["data"] if res["success"] else []

func normalize_major_name(input_text: String) -> String:
	var raw = input_text.strip_edges()
	if raw == "": return ""

	var majors = get_canonical_majors()
	for m in majors:
		var cname = str(m.get("canonical_name", ""))
		if cname.to_lower() == raw.to_lower():
			return cname
		var aliases_str = str(m.get("aliases", ""))
		var alias_list = aliases_str.split(",")
		for al in alias_list:
			if al.strip_edges().to_lower() == raw.to_lower():
				return cname
	return raw

func get_major_merge_preview(source_major: String, target_canonical_name: String) -> Dictionary:
	if not db: return {"success": false, "error": "Database not initialized."}

	var pq = db.execute("SELECT COUNT(*) AS cnt FROM people WHERE LOWER(TRIM(major)) = LOWER(TRIM(?));", [source_major])
	var p_cnt = int(pq["data"][0]["cnt"]) if pq["success"] and pq["data"].size() > 0 else 0

	var hq = db.execute("SELECT COUNT(*) AS cnt FROM person_academic_history WHERE LOWER(TRIM(major)) = LOWER(TRIM(?));", [source_major])
	var h_cnt = int(hq["data"][0]["cnt"]) if hq["success"] and hq["data"].size() > 0 else 0

	return {
		"success": true,
		"source_major": source_major,
		"target_canonical_name": target_canonical_name,
		"affected_people_count": p_cnt,
		"affected_history_count": h_cnt
	}

func merge_majors_atomic(source_major: String, target_canonical_name: String, admin_user: String) -> Dictionary:
	var prev = get_major_merge_preview(source_major, target_canonical_name)
	if not prev.get("success", false): return prev

	db.execute("UPDATE people SET major = ?, updated_at = datetime('now') WHERE LOWER(TRIM(major)) = LOWER(TRIM(?));", [target_canonical_name, source_major])
	db.execute("UPDATE person_academic_history SET major = ? WHERE LOWER(TRIM(major)) = LOWER(TRIM(?));", [target_canonical_name, source_major])

	var audit_msg = "Merged major '%s' into canonical major '%s' by %s (%d constituents affected)." % [source_major, target_canonical_name, admin_user, prev["affected_people_count"]]
	var event_uuid = "evt_major_" + str(Time.get_ticks_msec()) + "_" + str(randi() % 100000)
	db.execute("INSERT INTO event_outbox (event_uuid, event_type, aggregate_type, aggregate_id, payload_json, device_uuid, created_at) VALUES (?, 'major.merged', 'major', '0', ?, 'dev_local', datetime('now'));",
		[event_uuid, audit_msg])

	return {
		"success": true,
		"affected_people_count": prev["affected_people_count"],
		"message": audit_msg
	}
