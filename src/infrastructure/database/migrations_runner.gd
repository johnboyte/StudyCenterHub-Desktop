extends RefCounted

## Schema Migration Runner for StudyCenterHub Next Generation

var db

func _init(database) -> void:
	db = database

func run_migrations() -> Dictionary:
	# Ensure schema_migrations table exists
	var init_sql = """
	CREATE TABLE IF NOT EXISTS schema_migrations (
		version TEXT PRIMARY KEY,
		name TEXT NOT NULL,
		executed_at TEXT NOT NULL DEFAULT (datetime('now'))
	);
	"""
	var res = db.execute(init_sql)
	if not res["success"]:
		return {"success": false, "error": "Failed to initialize migrations table: " + res["error"]}

	# Load migration files
	var migration_path = "res://src/infrastructure/database/migrations/"
	var dir = DirAccess.open(migration_path)
	if not dir:
		return {"success": false, "error": "Migrations directory not found."}

	dir.list_dir_begin()
	var file_name = dir.get_next()
	var migration_files = []
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".sql"):
			migration_files.append(file_name)
		file_name = dir.get_next()
	dir.list_dir_end()

	migration_files.sort()

	# Get executed migrations
	var query_res = db.execute("SELECT version FROM schema_migrations;")
	var executed_versions = []
	if query_res["success"]:
		for row in query_res["data"]:
			executed_versions.append(row.get("version", ""))

	var newly_executed = 0
	for file in migration_files:
		var version = file.left(4) # e.g. "0001"
		if version in executed_versions:
			continue

		var full_path = migration_path + file
		var f = FileAccess.open(full_path, FileAccess.READ)
		if not f:
			return {"success": false, "error": "Could not read migration file: " + file}

		var sql_content = f.get_as_text()
		f.close()

		var statements = [
			sql_content,
			"INSERT INTO schema_migrations (version, name) VALUES ('" + version + "', '" + file + "')"
		]

		var tx_res = db.execute_transaction(statements)
		if not tx_res["success"]:
			var err_msg = str(tx_res.get("error", ""))
			if "duplicate column name" in err_msg.to_lower():
				db.execute("INSERT INTO schema_migrations (version, name) VALUES (?, ?);", [version, file])
			else:
				return {"success": false, "error": "Migration failed for " + file + ": " + err_msg}

		newly_executed += 1

	return {"success": true, "newly_executed": newly_executed, "error": ""}
