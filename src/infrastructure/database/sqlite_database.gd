extends RefCounted

## SQLite Database Engine Adapter for StudyCenterHub Next Generation
## Classification: TEMPORARY PROOF-OF-ARCHITECTURE IMPLEMENTATION DETAIL
## Manages local operational database operations in WAL mode using system sqlite3 CLI.

var db_path: String = ""
var sqlite_binary: String = "/usr/bin/sqlite3"

func _init(path: String = "") -> void:
	if path != "":
		db_path = ProjectSettings.globalize_path(path) if path.begins_with("user://") else path
		print("[Database] Explicit override path used: ", db_path)
	else:
		var env = OS.get_environment("STUDYCENTERHUB_ENV").to_lower().strip_edges()
		var db_name = "studycenterhub_development.db"
		if env == "production":
			db_name = "studycenterhub_production.db"
		elif env == "staging":
			db_name = "studycenterhub_staging.db"
		else:
			env = "development" # default
		
		db_path = ProjectSettings.globalize_path("user://" + db_name)
		print("[Database] Active Environment: ", env.to_upper())
		print("[Database] Resolved Database Path: ", db_path)
	_ensure_db_dir()

func _ensure_db_dir() -> void:
	var dir = db_path.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)

func execute(sql: String, args: Array = []) -> Dictionary:
	var formatted_sql = _format_sql(sql, args)
	if formatted_sql.to_upper().contains("UPDATE ") and not formatted_sql.to_upper().contains("SELECT "):
		formatted_sql += ";\nSELECT changes() AS affected_rows;"
	
	var tmp_path = ProjectSettings.globalize_path("user://tmp_exec_" + str(Time.get_ticks_usec()) + ".sql")
	var f = FileAccess.open(tmp_path, FileAccess.WRITE)
	if f:
		f.store_string(formatted_sql)
		f.close()

	var output = []
	var exit_code = OS.execute(sqlite_binary, ["-json", db_path, ".read '" + tmp_path + "'"], output, true)
	DirAccess.remove_absolute(tmp_path)

	if exit_code != 0:
		var err_msg = output[0] if output.size() > 0 else "Unknown SQLite error"
		return {"success": false, "error": err_msg, "data": []}
		
	var data = []
	if output.size() > 0 and output[0].strip_edges() != "":
		var json = JSON.new()
		var parse_result = json.parse(output[0])
		if parse_result == OK and json.data is Array:
			data = json.data
			
	return {"success": true, "error": "", "data": data}

func execute_transaction(statements: Array) -> Dictionary:
	var pragma_block = ".bail on\nPRAGMA foreign_keys = ON;\n"
	var sql_block = "BEGIN TRANSACTION;\n"
	for stmt in statements:
		if stmt is String:
			var s = stmt.replace("PRAGMA journal_mode = WAL;", "").replace("PRAGMA journal_mode=WAL;", "")
			sql_block += s + ";\n"
		elif stmt is Dictionary and stmt.has("sql"):
			var sql = stmt["sql"]
			var args = stmt.get("args", [])
			var formatted = _format_sql(sql, args).replace("PRAGMA journal_mode = WAL;", "").replace("PRAGMA journal_mode=WAL;", "")
			sql_block += formatted + ";\n"
	sql_block += "COMMIT;\n"

	var full_script = pragma_block + sql_block

	var tmp_path = ProjectSettings.globalize_path("user://tmp_tx_" + str(Time.get_ticks_usec()) + ".sql")
	var f = FileAccess.open(tmp_path, FileAccess.WRITE)
	if f:
		f.store_string(full_script)
		f.close()

	var output = []
	var exit_code = OS.execute(sqlite_binary, ["-json", db_path, ".read '" + tmp_path + "'"], output, true)
	DirAccess.remove_absolute(tmp_path)

	if exit_code != 0:
		var err_msg = output[0] if output.size() > 0 else "Transaction failed"
		return {"success": false, "error": err_msg, "data": []}

	var data = []
	if output.size() > 0 and output[0].strip_edges() != "":
		var json = JSON.new()
		if json.parse(output[0]) == OK and json.data is Array:
			data = json.data

	return {"success": true, "error": "", "data": data}

func _format_sql(sql: String, args: Array) -> String:
	if args.size() == 0:
		return sql
	var formatted = sql
	for arg in args:
		var val_str = ""
		if arg == null:
			val_str = "NULL"
		elif arg is String:
			val_str = "'" + arg.replace("'", "''") + "'"
		elif arg is bool:
			val_str = "1" if arg else "0"
		else:
			val_str = str(arg)
		var pos = formatted.find("?")
		if pos != -1:
			formatted = formatted.left(pos) + val_str + formatted.substr(pos + 1)
	return formatted
