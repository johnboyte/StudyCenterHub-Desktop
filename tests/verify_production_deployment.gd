extends SceneTree

## Production Deployment Read-Only Verification Script
## Strictly complies with Production Read-Only Safety Protocol:
## Performs 0 INSERT, 0 UPDATE, and 0 DELETE operations against Production DB.

const SQLiteDatabaseScript = preload("res://src/infrastructure/database/sqlite_database.gd")
const SpellingAssistanceHelperScript = preload("res://src/ui/components/spelling_assistance_helper.gd")

func _init() -> void:
	print("\n============================================================")
	print("  VERIFYING PRODUCTION DEPLOYMENT (STRICT READ-ONLY)")
	print("============================================================\n")

	call_deferred("verify_production")

func verify_production() -> void:
	var prod_db_path = ProjectSettings.globalize_path("user://studycenterhub_production.db")
	print("[ProductionVerification] Target Database: ", prod_db_path)
	assert(FileAccess.file_exists(prod_db_path), "Production DB missing!")

	var db = SQLiteDatabaseScript.new(prod_db_path)

	# 1. Read-Only check: Existing Production people intact
	var p_res = db.execute("SELECT id, person_uuid, human_id, first_name, last_name FROM people WHERE status != 'archived' LIMIT 1;")
	assert(p_res["success"] and p_res["data"].size() > 0, "Production people missing!")
	var p = p_res["data"][0]
	var p_id = int(p.get("id", 0))
	var h_id = str(p.get("human_id", ""))
	print("  ✓ 1. Read-Only: Production constituent intact: %s %s (ID: %d, HumanID: %s)" % [p.get("first_name", ""), p.get("last_name", ""), p_id, h_id])

	# 2. Read-Only check: person_notes table query capability
	var n_res = db.execute("SELECT count(*) AS total_notes FROM person_notes;")
	assert(n_res["success"], "Failed to query person_notes table in Production!")
	var total_notes = int(n_res["data"][0].get("total_notes", 0)) if n_res["data"].size() > 0 else 0
	print("  ✓ 2. Read-Only: person_notes query verified (Total notes: %d)" % total_notes)

	# 3. Read-Only check: staff_tasks_index table query capability
	var t_res = db.execute("SELECT count(*) AS total_tasks FROM staff_tasks_index;")
	assert(t_res["success"], "Failed to query staff_tasks_index table in Production!")
	var total_tasks = int(t_res["data"][0].get("total_tasks", 0)) if t_res["data"].size() > 0 else 0
	print("  ✓ 3. Read-Only: staff_tasks_index query verified (Total tasks: %d)" % total_tasks)

	# 4. Read-Only check: communications_log table query capability
	var c_res = db.execute("SELECT count(*) AS total_comms FROM communications_log;")
	assert(c_res["success"], "Failed to query communications_log table in Production!")
	var total_comms = int(c_res["data"][0].get("total_comms", 0)) if c_res["data"].size() > 0 else 0
	print("  ✓ 4. Read-Only: communications_log query verified (Total comms: %d)" % total_comms)

	# 5. Read-Only check: scheduled_communications table query capability
	var s_res = db.execute("SELECT count(*) AS total_sched FROM scheduled_communications;")
	assert(s_res["success"], "Failed to query scheduled_communications table in Production!")
	var total_sched = int(s_res["data"][0].get("total_sched", 0)) if s_res["data"].size() > 0 else 0
	print("  ✓ 5. Read-Only: scheduled_communications query verified (Total scheduled: %d)" % total_sched)

	# 6. Read-Only check: sessions table query capability
	var sess_res = db.execute("SELECT count(*) AS total_sess FROM sessions;")
	assert(sess_res["success"], "Failed to query sessions table in Production!")
	var total_sess = int(sess_res["data"][0].get("total_sess", 0)) if sess_res["data"].size() > 0 else 0
	print("  ✓ 6. Read-Only: sessions query verified (Total sessions: %d)" % total_sess)

	# 7. Read-Only check: Spelling assistance engine suggestions
	var spell_issues = SpellingAssistanceHelperScript.check_text("I definately recieve seperate calender adress wierd")
	assert(spell_issues.size() == 6, "Expected 6 spelling suggestions in Production test")
	print("  ✓ 7. Read-Only: Spelling assistance engine verified in Production mode.")

	print("\n============================================================")
	print("  SUCCESS: PRODUCTION READ-ONLY DEPLOYMENT VERIFIED 100%")
	print("============================================================\n")
	quit(0)
