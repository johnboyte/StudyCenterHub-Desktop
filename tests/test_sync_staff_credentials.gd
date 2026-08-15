extends Node

## Script to trigger and verify publish_staff_credentials_index to SiteGround Gateway

const SQLiteDatabaseScript = preload("res://src/infrastructure/database/sqlite_database.gd")
const GatewaySyncScript = preload("res://src/domain/sync/gateway_sync_service.gd")

func _ready() -> void:
	print("==========================================================")
	print("PUBLISHING & VERIFYING STAFF CREDENTIALS INDEX TO GATEWAY")
	print("==========================================================")

	var db_path = ProjectSettings.globalize_path("user://studycenterhub_production.db")
	var db = SQLiteDatabaseScript.new(db_path)

	var sync_svc = GatewaySyncScript.new(db, self)

	sync_svc.publish_staff_credentials_index(func(res: Dictionary):
		print("Gateway Sync Response: ", res)
		if res.get("success", false):
			print("PASS: Successfully published ", res.get("synced_count", 0), " staff credential(s) to SiteGround.")
			get_tree().quit(0)
		else:
			print("FAIL: Sync error: ", res.get("error", "Unknown"))
			get_tree().quit(1)
	)
