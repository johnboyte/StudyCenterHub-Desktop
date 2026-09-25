extends SceneTree

const SQLiteDatabaseScript = preload("res://src/infrastructure/database/sqlite_database.gd")
const YouTubeOAuthServiceScript = preload("res://src/domain/playlists/youtube_oauth_service.gd")

func _initialize() -> void:
	print("\n============================================================")
	print("--- READ-ONLY YOUTUBE CHANNEL VERIFICATION ---")
	print("============================================================\n")

	var user_data_dir = OS.get_user_data_dir()
	var dev_db_path = user_data_dir.path_join("studycenterhub_development.db")

	var db = SQLiteDatabaseScript.new(dev_db_path)
	var oauth_svc = YouTubeOAuthServiceScript.new(db)
	root.add_child(oauth_svc)
	oauth_svc._ready()

	if not oauth_svc.is_account_connected():
		print("❌ Account is not connected!")
		quit(1)
		return

	var token = await oauth_svc.get_valid_access_token()
	if token.is_empty():
		print("❌ Access token is empty!")
		quit(1)
		return

	var url = "https://www.googleapis.com/youtube/v3/channels?mine=true&part=snippet"
	var headers = [
		"Authorization: Bearer " + token,
		"Accept: application/json"
	]

	var res = await oauth_svc._execute_http_sync(url, headers, HTTPClient.METHOD_GET, "")

	var http_status = res.get("status_code", 0)
	var res_dict = res.get("data", {})
	var total_results = 0
	var channel_title = ""
	var channel_id = ""

	if res_dict is Dictionary:
		var page_info = res_dict.get("pageInfo", {})
		total_results = int(page_info.get("totalResults", 0))

		if res_dict.has("items"):
			var items = res_dict.get("items", [])
			if items.size() > 0:
				var first_item = items[0]
				channel_id = str(first_item.get("id", ""))
				var snippet = first_item.get("snippet", {})
				channel_title = str(snippet.get("title", ""))

	print("HTTP STATUS:\n" + str(http_status))
	print("\nTOTAL RESULTS:\n" + str(total_results))
	print("\nCHANNEL TITLE:\n" + (channel_title if not channel_title.is_empty() else "None"))
	print("\nCHANNEL ID:\n" + (channel_id if not channel_id.is_empty() else "None"))

	if total_results >= 1 and not channel_title.is_empty():
		# Persist actual channel title in app_settings
		db.execute("INSERT OR REPLACE INTO app_settings (setting_key, setting_value) VALUES ('YOUTUBE_CHANNEL_TITLE', ?);", [channel_title])
		print("\n✅ Successfully updated StudyCenterHub connected-channel metadata with channel title: '" + channel_title + "'")

	quit(0)
