extends SceneTree

const SQLiteDatabaseScript = preload("res://src/infrastructure/database/sqlite_database.gd")
const MigrationsRunnerScript = preload("res://src/infrastructure/database/migrations_runner.gd")

func _init() -> void:
	print("--- Running Production DB Migrations ---")
	var prod_db_path = ProjectSettings.globalize_path("user://studycenterhub_production.db")
	assert(FileAccess.file_exists(prod_db_path), "Production DB file must exist")
	
	var db = SQLiteDatabaseScript.new(prod_db_path)
	var mig = MigrationsRunnerScript.new(db)
	var res = mig.run_migrations()
	print("Migration runner result: ", res)
	assert(res["success"], "Migration runner MUST succeed")
	print("--- Production DB Migrations Completed Successfully ---")
	quit()
