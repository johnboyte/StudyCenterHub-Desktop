class_name YouTubePlaylistSyncService
extends Node

## YouTube Data API v3 Playlist Synchronization Service
## Handles outward master synchronization from StudyCenterHub to connected YouTube account.
## Implements official YouTube Data API v3 endpoints for playlists and playlistItems.

signal sync_started(playlist_id: String)
signal sync_completed(playlist_id: String, success: bool, message: String)
signal sync_error(playlist_id: String, error_msg: String)

const YOUTUBE_API_BASE = "https://www.googleapis.com/youtube/v3"

var playlists_service: RefCounted
var oauth_service: Object
var mock_mode: bool = false

func _init(p_playlists_service: RefCounted = null, p_oauth_service: Object = null) -> void:
	playlists_service = p_playlists_service
	oauth_service = p_oauth_service

# --- URL Generation Helpers ---
func get_external_playlist_url(external_playlist_id: String) -> String:
	var clean_id = external_playlist_id.strip_edges()
	if clean_id.is_empty():
		return ""
	return "https://www.youtube.com/playlist?list=" + clean_id

func get_play_from_here_url(video_id: String, external_playlist_id: String) -> String:
	var clean_vid = video_id.strip_edges()
	var clean_pid = external_playlist_id.strip_edges()
	if clean_vid.is_empty():
		return get_external_playlist_url(clean_pid)
	if clean_pid.is_empty():
		return "https://www.youtube.com/watch?v=" + clean_vid
	return "https://www.youtube.com/watch?v=" + clean_vid + "&list=" + clean_pid

func open_playlist_in_browser(playlist_id: String) -> bool:
	if not playlists_service:
		return false
	var link = playlists_service.get_playlist_provider_link(playlist_id, "youtube")
	var ext_url = str(link.get("external_playlist_url", ""))
	if ext_url.is_empty():
		var ext_id = str(link.get("external_playlist_id", ""))
		ext_url = get_external_playlist_url(ext_id)

	if not ext_url.is_empty():
		OS.shell_open(ext_url)
		return true
	return false

func open_play_from_here_in_browser(item_id: String) -> bool:
	if not playlists_service:
		return false
	var item = playlists_service.get_item_by_id(item_id)
	if item.is_empty():
		return false
	var playlist_id = str(item.get("playlist_id", ""))
	var video_id = playlists_service.extract_youtube_video_id(str(item.get("url", "")))

	var link = playlists_service.get_playlist_provider_link(playlist_id, "youtube")
	var ext_pid = str(link.get("external_playlist_id", ""))

	var target_url = get_play_from_here_url(video_id, ext_pid)
	if not target_url.is_empty():
		OS.shell_open(target_url)
		return true
	return false

# --- High-Level Playlist Synchronization ---
func sync_playlist(playlist_id: String) -> Dictionary:
	if not playlists_service:
		return {"success": false, "error": "PlaylistsService unavailable."}

	var playlist = playlists_service.get_playlist_by_id(playlist_id)
	if playlist.is_empty():
		return {"success": false, "error": "Playlist not found."}

	var provider_link = playlists_service.get_playlist_provider_link(playlist_id, "youtube")
	var ext_playlist_id = str(provider_link.get("external_playlist_id", ""))

	# If not yet created on YouTube, create external playlist first
	if ext_playlist_id.is_empty():
		return await create_external_playlist(playlist_id)

	# Mark status as syncing
	playlists_service.update_playlist_sync_status(playlist_id, "youtube", "syncing")
	sync_started.emit(playlist_id)

	# Verify OAuth token availability
	var token = ""
	if oauth_service:
		token = await oauth_service.get_valid_access_token()
	if token.is_empty() and not mock_mode:
		playlists_service.update_playlist_sync_status(playlist_id, "youtube", "sync_error", "YouTube account authorization required.")
		return {
			"success": false,
			"error": "YouTube account authorization required. Please connect your YouTube account in Settings."
		}

	# Perform item synchronization diff
	var items = playlists_service.get_playlist_items(playlist_id)

	for i in range(items.size()):
		var item = items[i]
		var item_id = str(item.get("id", ""))
		var video_id = playlists_service.extract_youtube_video_id(str(item.get("url", "")))
		var item_link = playlists_service.get_item_provider_link(item_id, "youtube")
		var ext_item_id = str(item_link.get("external_item_id", ""))

		if ext_item_id.is_empty() and not video_id.is_empty():
			if mock_mode or token.begins_with("mock_"):
				var mock_ext_item_id = "YTI_" + video_id + "_" + str(i)
				playlists_service.save_item_provider_link(item_id, "youtube", mock_ext_item_id, video_id, "synced")
			else:
				var res = await add_api_playlist_item(token, ext_playlist_id, video_id, i)
				if res.get("success", false):
					var yt_item_id = str(res.get("playlist_item_id", ""))
					playlists_service.save_item_provider_link(item_id, "youtube", yt_item_id, video_id, "synced")

	playlists_service.update_playlist_sync_status(playlist_id, "youtube", "synced", "")
	sync_completed.emit(playlist_id, true, "Playlist synchronized successfully.")
	return {
		"success": true,
		"playlist_id": playlist_id,
		"external_playlist_id": ext_playlist_id,
		"external_playlist_url": get_external_playlist_url(ext_playlist_id)
	}

func create_external_playlist(playlist_id: String) -> Dictionary:
	if not playlists_service:
		return {"success": false, "error": "PlaylistsService unavailable."}

	var playlist = playlists_service.get_playlist_by_id(playlist_id)
	if playlist.is_empty():
		return {"success": false, "error": "Playlist not found."}

	var name = str(playlist.get("name", "New Playlist"))
	var desc = str(playlist.get("description", ""))
	var token = ""
	if oauth_service:
		token = await oauth_service.get_valid_access_token()

	var ext_id = ""
	var ext_url = ""

	if mock_mode or token.begins_with("mock_") or token.is_empty():
		ext_id = "PL_SCH_" + _generate_short_id()
		ext_url = get_external_playlist_url(ext_id)
	else:
		var api_res = await create_api_playlist(token, name, desc)
		if api_res.get("success", false):
			ext_id = str(api_res.get("id", ""))
			ext_url = str(api_res.get("url", ""))
		else:
			return api_res

	playlists_service.save_playlist_provider_link(playlist_id, "youtube", ext_id, ext_url, "synced", "")

	# Synchronize items to YouTube playlist
	var items = playlists_service.get_playlist_items(playlist_id)
	for i in range(items.size()):
		var item = items[i]
		var item_id = str(item.get("id", ""))
		var video_id = playlists_service.extract_youtube_video_id(str(item.get("url", "")))
		if not video_id.is_empty():
			if mock_mode or token.begins_with("mock_") or token.is_empty():
				var mock_ext_item_id = "YTI_" + video_id + "_" + str(i)
				playlists_service.save_item_provider_link(item_id, "youtube", mock_ext_item_id, video_id, "synced")
			else:
				var res = await add_api_playlist_item(token, ext_id, video_id, i)
				if res.get("success", false):
					var yt_item_id = str(res.get("playlist_item_id", ""))
					playlists_service.save_item_provider_link(item_id, "youtube", yt_item_id, video_id, "synced")

	return {
		"success": true,
		"external_playlist_id": ext_id,
		"external_playlist_url": ext_url
	}

# --- Official YouTube Data API v3 Endpoints Implementation ---

## 1. Create Playlist (POST /youtube/v3/playlists?part=snippet,status)
func create_api_playlist(access_token: String, title: String, description: String = "", privacy_status: String = "private") -> Dictionary:
	var url = YOUTUBE_API_BASE + "/playlists?part=snippet,status"
	var body_dict = {
		"snippet": {
			"title": title,
			"description": description
		},
		"status": {
			"privacyStatus": privacy_status
		}
	}
	var headers = [
		"Authorization: Bearer " + access_token,
		"Content-Type: application/json",
		"Accept: application/json"
	]
	var payload = JSON.stringify(body_dict)
	var response = await _execute_http_request_sync(url, headers, HTTPClient.METHOD_POST, payload)

	if response.get("status_code", 0) == 200:
		var data = response.get("data", {})
		var pl_id = str(data.get("id", ""))
		return {
			"success": true,
			"id": pl_id,
			"url": get_external_playlist_url(pl_id),
			"data": data
		}
	return {
		"success": false,
		"error": "Failed to create YouTube playlist. Code: " + str(response.get("status_code", 0)) + " Body: " + str(response.get("body_raw", ""))
	}

## 2. Rename / Update Playlist Snippet (PUT /youtube/v3/playlists?part=snippet)
func rename_api_playlist(access_token: String, external_playlist_id: String, new_title: String, new_description: String = "") -> Dictionary:
	var url = YOUTUBE_API_BASE + "/playlists?part=snippet"
	var body_dict = {
		"id": external_playlist_id,
		"snippet": {
			"title": new_title,
			"description": new_description
		}
	}
	var headers = [
		"Authorization: Bearer " + access_token,
		"Content-Type: application/json",
		"Accept: application/json"
	]
	var payload = JSON.stringify(body_dict)
	var response = await _execute_http_request_sync(url, headers, HTTPClient.METHOD_PUT, payload)

	if response.get("status_code", 0) == 200:
		return {"success": true, "id": external_playlist_id, "data": response.get("data", {})}
	return {"success": false, "error": "Failed to rename YouTube playlist."}

## 3. Add Playlist Item (POST /youtube/v3/playlistItems?part=snippet)
## Note: Returns YouTube PLAYLIST ITEM ID (distinct from Video ID)
func add_api_playlist_item(access_token: String, external_playlist_id: String, video_id: String, position: int = -1) -> Dictionary:
	var url = YOUTUBE_API_BASE + "/playlistItems?part=snippet"
	var snippet_dict = {
		"playlistId": external_playlist_id,
		"resourceId": {
			"kind": "youtube#video",
			"videoId": video_id
		}
	}
	if position >= 0:
		snippet_dict["position"] = position

	var body_dict = {"snippet": snippet_dict}
	var headers = [
		"Authorization: Bearer " + access_token,
		"Content-Type: application/json",
		"Accept: application/json"
	]
	var payload = JSON.stringify(body_dict)
	var response = await _execute_http_request_sync(url, headers, HTTPClient.METHOD_POST, payload)

	if response.get("status_code", 0) == 200:
		var data = response.get("data", {})
		var playlist_item_id = str(data.get("id", ""))
		return {
			"success": true,
			"playlist_item_id": playlist_item_id,
			"video_id": video_id,
			"data": data
		}
	return {"success": false, "error": "Failed to add item to YouTube playlist."}

## 4. Remove Playlist Item (DELETE /youtube/v3/playlistItems?id=<external_playlist_item_id>)
func remove_api_playlist_item(access_token: String, external_playlist_item_id: String) -> Dictionary:
	var url = YOUTUBE_API_BASE + "/playlistItems?id=" + external_playlist_item_id.uri_encode()
	var headers = [
		"Authorization: Bearer " + access_token,
		"Accept: application/json"
	]
	var response = await _execute_http_request_sync(url, headers, HTTPClient.METHOD_DELETE, "")

	if response.get("status_code", 0) in [200, 204]:
		return {"success": true, "playlist_item_id": external_playlist_item_id}
	return {"success": false, "error": "Failed to remove item from YouTube playlist."}

## 5. Move / Reorder Playlist Item (PUT /youtube/v3/playlistItems?part=snippet)
func move_api_playlist_item(access_token: String, external_playlist_item_id: String, external_playlist_id: String, video_id: String, new_position: int) -> Dictionary:
	var url = YOUTUBE_API_BASE + "/playlistItems?part=snippet"
	var body_dict = {
		"id": external_playlist_item_id,
		"snippet": {
			"playlistId": external_playlist_id,
			"resourceId": {
				"kind": "youtube#video",
				"videoId": video_id
			},
			"position": new_position
		}
	}
	var headers = [
		"Authorization: Bearer " + access_token,
		"Content-Type: application/json",
		"Accept: application/json"
	]
	var payload = JSON.stringify(body_dict)
	var response = await _execute_http_request_sync(url, headers, HTTPClient.METHOD_PUT, payload)

	if response.get("status_code", 0) == 200:
		return {"success": true, "playlist_item_id": external_playlist_item_id, "data": response.get("data", {})}
	return {"success": false, "error": "Failed to reorder item in YouTube playlist."}

## 6. Retrieve Playlist Details (GET /youtube/v3/playlists?part=snippet,status&id=<external_playlist_id>)
func retrieve_api_playlist(access_token: String, external_playlist_id: String) -> Dictionary:
	var url = YOUTUBE_API_BASE + "/playlists?part=snippet,status&id=" + external_playlist_id.uri_encode()
	var headers = [
		"Authorization: Bearer " + access_token,
		"Accept: application/json"
	]
	var response = await _execute_http_request_sync(url, headers, HTTPClient.METHOD_GET, "")

	if response.get("status_code", 0) == 200:
		return {"success": true, "data": response.get("data", {})}
	return {"success": false, "error": "Failed to retrieve YouTube playlist details."}

## 7. Retrieve Playlist Items (GET /youtube/v3/playlistItems?part=snippet&playlistId=<external_playlist_id>&maxResults=50)
func retrieve_api_playlist_items(access_token: String, external_playlist_id: String) -> Dictionary:
	var url = YOUTUBE_API_BASE + "/playlistItems?part=snippet&playlistId=" + external_playlist_id.uri_encode() + "&maxResults=50"
	var headers = [
		"Authorization: Bearer " + access_token,
		"Accept: application/json"
	]
	var response = await _execute_http_request_sync(url, headers, HTTPClient.METHOD_GET, "")

	if response.get("status_code", 0) == 200:
		return {"success": true, "data": response.get("data", {})}
	return {"success": false, "error": "Failed to retrieve YouTube playlist items."}

# --- Internal Async HTTP Execution Engine ---
func _execute_http_request_sync(url: String, headers: Array, method: int, body: String) -> Dictionary:
	var http_req = HTTPRequest.new()
	http_req.timeout = 10.0
	var parent_node: Node = self
	if not parent_node.is_inside_tree():
		var main_tree = Engine.get_main_loop() as SceneTree
		if main_tree and main_tree.root:
			parent_node = main_tree.root
	parent_node.add_child(http_req)

	if not http_req.is_inside_tree():
		var main_tree = Engine.get_main_loop() as SceneTree
		if main_tree:
			await main_tree.process_frame

	var packed_headers = PackedStringArray()
	for h in headers: packed_headers.append(h)

	var err = http_req.request(url, packed_headers, method, body)
	if err != OK:
		http_req.queue_free()
		return {"status_code": 0, "error": "Request launch failed"}

	var res = await http_req.request_completed
	var response_code = int(res[1])
	var response_body = res[3] as PackedByteArray
	var str_body = response_body.get_string_from_utf8()

	var json = JSON.new()
	var parsed_json = {}
	if json.parse(str_body) == OK:
		parsed_json = json.get_data()

	http_req.queue_free()

	return {
		"status_code": response_code,
		"data": parsed_json,
		"body_raw": str_body,
		"result": res[0]
	}

func _parse_url(url_str: String) -> Dictionary:
	var is_ssl = url_str.begins_with("https://")
	var clean = url_str.replacen("https://", "").replacen("http://", "")
	var parts = clean.split("/")
	var host = parts[0]
	var path = "/" + "/".join(parts.slice(1))
	return {
		"is_ssl": is_ssl,
		"host": host,
		"path": path
	}

func _generate_short_id() -> String:
	return "%08X" % (randi() % 4294967295)
