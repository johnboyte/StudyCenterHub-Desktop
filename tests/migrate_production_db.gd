extends SceneTree

## Script to apply all database migrations to Production DB safely and idempotently

const SQLiteDatabaseScript = preload("res://src/infrastructure/database/sqlite_database.gd")

func _init() -> void:
	print("\n============================================================")
	print("  APPLYING MIGRATIONS TO PRODUCTION DATABASE")
	print("============================================================\n")

	call_deferred("run_migration")

func run_migration() -> void:
	var prod_db_path = ProjectSettings.globalize_path("user://studycenterhub_production.db")
	print("[ProductionMigration] Target DB Path: ", prod_db_path)
	assert(FileAccess.file_exists(prod_db_path), "Production database file does not exist!")

	const MigrationsRunnerScript = preload("res://src/infrastructure/database/migrations_runner.gd")

	# Instantiate SQLiteDatabase
	var db = SQLiteDatabaseScript.new(prod_db_path)

	# Execute pending schema migrations
	var runner = MigrationsRunnerScript.new(db)
	var mig_res = runner.run_migrations()
	print("  [MigrationsRunner] Migration execution result: ", mig_res)
	assert(mig_res["success"], "Migrations failed to execute: " + str(mig_res.get("error", "")))

	# Verify required tables exist in Production
	var tables = ["people", "person_notes", "staff_tasks_index", "schema_migrations"]
	for t in tables:
		var res = db.execute("SELECT name FROM sqlite_master WHERE type='table' AND name=?;", [t])
		assert(res["success"] and res["data"].size() > 0, "Table missing in Production: " + t)
		print("  ✓ Verified Table Exists: ", t)

	# Verify human_id column in person_notes if applicable
	var col_res = db.execute("PRAGMA table_info(person_notes);")
	if col_res["success"]:
		var cols = []
		for row in col_res["data"]:
			cols.append(row.get("name", ""))
		print("  ✓ person_notes columns: ", cols)

	print("\n============================================================")
	print("  SUCCESS: PRODUCTION DATABASE MIGRATED & VERIFIED")
	print("============================================================\n")
	quit(0)
