extends Node

const SQLiteDatabaseScript = preload("res://src/infrastructure/database/sqlite_database.gd")
const GatewaySyncServiceScript = preload("res://src/domain/sync/gateway_sync_service.gd")

func _ready() -> void:
	print("==========================================================")
	print("PUBLISHING DIRECTORY INDEX FROM PRODUCTION DB TO SITEGROUND")
	print("==========================================================")

	var db_path = ProjectSettings.globalize_path("user://studycenterhub_production.db")
	var db = SQLiteDatabaseScript.new(db_path)
	var sync_svc = GatewaySyncServiceScript.new(db, self)
	
	sync_svc.publish_directory_index(func(res):
		print("Directory Index Publish Result: ", res)
		get_tree().quit(0)
	)
