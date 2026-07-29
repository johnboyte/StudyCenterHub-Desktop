extends SceneTree

## Test DirectoryView DB Wiring from AppShell.
## Verifies that AppShell correctly passes active db to DirectoryView when switching to 'people'.

const SQLiteDatabaseScript = preload("res://src/infrastructure/database/sqlite_database.gd")
const MigrationsRunnerScript = preload("res://src/infrastructure/database/migrations_runner.gd")

func _init():
	print("==========================================================")
	print("TESTING PEOPLE VIEW DB WIRING FROM APPSHELL")
	print("==========================================================")
	var db = SQLiteDatabaseScript.new("user://test_people_db_wiring.db")
	var mig = MigrationsRunnerScript.new(db)
	mig.run_migrations()

	# Insert test person
	db.execute("INSERT INTO people (person_uuid, first_name, last_name, status) VALUES ('p-101', 'Jane', 'Doe', 'active');")

	var app_shell_script = load("res://app/scenes/app_shell.gd")
	var shell = app_shell_script.new()
	shell.db = db

	var success = shell.switch_view("people")
	if not success or shell.current_view_node == null:
		print("FAIL: Failed to switch to people view.")
		quit(1); return

	if shell.current_view_node.db != db:
		print("FAIL: DirectoryView db property was not set to AppShell db.")
		quit(1); return

	print("PASS: DirectoryView receives AppShell db property correctly.")
	print("==========================================================")
	quit(0)
