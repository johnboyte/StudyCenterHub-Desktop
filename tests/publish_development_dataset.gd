extends SceneTree

## Publisher Script for Development Dataset
## Reads studycenterhub_development.db and publishes directory, sessions, operating hours, attendance, and staff credentials to dev-gateway.reallife-studycenter.org.

const SQLiteDatabaseScript = preload("res://src/infrastructure/database/sqlite_database.gd")
const GatewaySyncServiceScript = preload("res://src/domain/sync/gateway_sync_service.gd")

func _init() -> void:
	print("==========================================================")
	print("PUBLISHING DEVELOPMENT SEED DATASET TO DEV GATEWAY")
	print("==========================================================")

	OS.set_environment("STUDYCENTERHUB_ENV", "development")
	
	var db = SQLiteDatabaseScript.new()
	print("[PublishDev] Database Path: ", db.db_path)

	# Ensure GATEWAY_SERVER_URL setting points to dev-gateway
	db.execute("INSERT OR REPLACE INTO app_settings (setting_key, setting_value) VALUES ('GATEWAY_SERVER_URL', 'https://dev-gateway.reallife-studycenter.org');")
	db.execute("INSERT OR REPLACE INTO app_settings (setting_key, setting_value) VALUES ('GATEWAY_SYNC_API_KEY', 'SCH_SYNC_KEY_PLACEHOLDER_8f3d');")

	var sync_svc = GatewaySyncServiceScript.new(db, null)
	print("[PublishDev] Target Gateway URL: ", sync_svc.get_gateway_url())

	print("[PublishDev] 1. Publishing Directory Index (30 people)...")
	sync_svc.publish_directory_index(func(res_dir):
		print("[PublishDev] Directory Publish Result: ", res_dir)
		
		print("[PublishDev] 2. Publishing Session Index (8 sessions)...")
		sync_svc.publish_session_index(func(res_sess):
			print("[PublishDev] Session Publish Result: ", res_sess)
			
			print("[PublishDev] 3. Publishing Operating Hours...")
			sync_svc.publish_operating_hours(func(res_hrs):
				print("[PublishDev] Operating Hours Publish Result: ", res_hrs)
				
				print("[PublishDev] 4. Publishing Today Attendance Index...")
				sync_svc.publish_today_attendance_index(func(res_att):
					print("[PublishDev] Attendance Index Publish Result: ", res_att)
					
					print("[PublishDev] 5. Publishing Staff Credentials...")
					sync_svc.publish_staff_credentials_index(func(res_cred):
						print("[PublishDev] Staff Credentials Publish Result: ", res_cred)
						print("==========================================================")
						print("SUCCESS: ALL DEVELOPMENT DATA PUBLISHED TO DEV GATEWAY")
						print("==========================================================")
						quit(0)
					)
				)
			)
		)
	)
