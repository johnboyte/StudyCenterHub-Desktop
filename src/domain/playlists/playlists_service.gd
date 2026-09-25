extends RefCounted

## Playlists Subsystem Service
## Manages playlist creation, items, generic source types, reordering, duplicate checks, search, and YouTube metadata.

var db: RefCounted

func _init(database: RefCounted) -> void:
	db = database
	_ensure_tables()

func _ensure_tables() -> void:
	if not db:
		return
	db.execute("""
		CREATE TABLE IF NOT EXISTS playlists (
			id TEXT PRIMARY KEY,
			name TEXT NOT NULL,
			description TEXT DEFAULT '',
			sort_order INTEGER NOT NULL DEFAULT 0,
			item_count INTEGER NOT NULL DEFAULT 0,
			created_at TEXT NOT NULL DEFAULT (datetime('now')),
			updated_at TEXT NOT NULL DEFAULT (datetime('now'))
		);
	""")
	db.execute("""
		CREATE TABLE IF NOT EXISTS playlist_items (
			id TEXT PRIMARY KEY,
			playlist_id TEXT NOT NULL,
			title TEXT NOT NULL,
			artist TEXT DEFAULT '',
			source_type TEXT NOT NULL DEFAULT 'youtube',
			url TEXT DEFAULT '',
			duration_seconds INTEGER DEFAULT 0,
			notes TEXT DEFAULT '',
			sort_order INTEGER NOT NULL DEFAULT 0,
			thumbnail_url TEXT DEFAULT '',
			created_at TEXT NOT NULL DEFAULT (datetime('now')),
			updated_at TEXT NOT NULL DEFAULT (datetime('now')),
			FOREIGN KEY (playlist_id) REFERENCES playlists(id) ON DELETE CASCADE
		);
	""")
	_ensure_default_seed()

func _ensure_default_seed() -> void:
	if not db: return
	if db.has_method("_is_test_execution_context") and db._is_test_execution_context():
		return
	var check_res = db.execute("SELECT COUNT(*) AS cnt FROM playlists")
	var rows = check_res.get("rows", [])
	var cnt = 0
	if rows.size() > 0:
		cnt = int(rows[0].get("cnt", 0))
		
	if cnt == 0:
		print("[PlaylistsService] Initializing default playlists for fresh database...")
		var p1 = create_playlist("Sunday Morning Gathering", "Worship & Praise Songs for Sunday Service")
		var p1_id = str(p1.get("id", ""))
		if p1_id != "":
			add_playlist_item(p1_id, "10,000 Reasons (Bless the Lord)", "Matt Redman", "youtube", "https://www.youtube.com/watch?v=XtwIT8JtIJg", 345, "Opening Praise", "https://img.youtube.com/vi/XtwIT8JtIJg/hqdefault.jpg")
			add_playlist_item(p1_id, "Way Maker", "Sinach", "youtube", "https://www.youtube.com/watch?v=n4XWfwLHeLM", 304, "Worship Song", "https://img.youtube.com/vi/n4XWfwLHeLM/hqdefault.jpg")
			
		var p2 = create_playlist("College Study", "Acoustic & Instrumental Focus Music")
		var p2_id = str(p2.get("id", ""))
		if p2_id != "":
			add_playlist_item(p2_id, "Lofi Hip Hop Radio - Beats to Relax/Study to", "Lofi Girl", "youtube", "https://www.youtube.com/watch?v=jfKfPfyJRdk", 300, "Background Beats", "https://img.youtube.com/vi/jfKfPfyJRdk/hqdefault.jpg")
			add_playlist_item(p2_id, "Goodness of God", "Bethel Music", "youtube", "https://www.youtube.com/watch?v=n0FBb6hnwTo", 298, "Acoustic Worship", "https://img.youtube.com/vi/n0FBb6hnwTo/hqdefault.jpg")



func _generate_uuid(prefix: String) -> String:
	var b1 = "%08X" % (randi() % 4294967295)
	var b2 = "%04X" % (randi() % 65536)
	return (prefix + "_" + b1 + "-" + b2).to_lower()

# ==============================================================================
# PLAYLIST MANAGEMENT
# ==============================================================================

func create_playlist(name: String, description: String = "", provider_type: String = "general") -> Dictionary:
	if not db:
		return {"success": false, "error": "Database reference missing."}
	
	var clean_name = name.strip_edges()
	if clean_name.is_empty():
		return {"success": false, "error": "Playlist name cannot be empty."}

	var valid_providers = ["general", "youtube", "spotify", "apple_music"]
	var p_type = provider_type.to_lower().strip_edges()
	if not p_type in valid_providers:
		p_type = "general"

	# Get max sort_order
	var max_res = db.execute("SELECT MAX(sort_order) as max_ord FROM playlists;")
	var next_ord = 0
	if max_res["success"] and max_res["data"].size() > 0 and max_res["data"][0].get("max_ord") != null:
		next_ord = int(max_res["data"][0]["max_ord"]) + 1

	var new_id = _generate_uuid("pl")
	var res = db.execute(
		"INSERT INTO playlists (id, name, description, provider_type, sort_order, item_count, created_at, updated_at) VALUES (?, ?, ?, ?, ?, 0, datetime('now'), datetime('now'));",
		[new_id, clean_name, description.strip_edges(), p_type, next_ord]
	)
	if not res["success"]:
		return {"success": false, "error": res.get("error", "Insert failed.")}

	return {
		"success": true,
		"playlist": {
			"id": new_id,
			"name": clean_name,
			"description": description.strip_edges(),
			"provider_type": p_type,
			"sort_order": next_ord,
			"item_count": 0
		}
	}

func get_all_playlists() -> Array:
	if not db:
		return []
	_refresh_item_counts()
	var res = db.execute("SELECT * FROM playlists ORDER BY sort_order ASC, created_at ASC;")
	if res["success"]:
		return res["data"]
	return []

func get_playlist_by_id(playlist_id: String) -> Dictionary:
	if not db or playlist_id.is_empty():
		return {}
	_refresh_item_counts()
	var res = db.execute("SELECT * FROM playlists WHERE id = ? LIMIT 1;", [playlist_id])
	if res["success"] and res["data"].size() > 0:
		return res["data"][0]
	return {}

func update_playlist(playlist_id: String, name: String, description: String = "") -> bool:
	if not db or playlist_id.is_empty():
		return false
	var clean_name = name.strip_edges()
	if clean_name.is_empty():
		return false
	var res = db.execute(
		"UPDATE playlists SET name = ?, description = ?, updated_at = datetime('now') WHERE id = ?;",
		[clean_name, description.strip_edges(), playlist_id]
	)
	return res["success"]

func duplicate_playlist(playlist_id: String) -> Dictionary:
	if not db or playlist_id.is_empty():
		return {"success": false, "error": "Invalid playlist ID"}
	
	var orig = get_playlist_by_id(playlist_id)
	if orig.is_empty():
		return {"success": false, "error": "Original playlist not found."}

	var new_name = str(orig.get("name", "Playlist")) + " (Copy)"
	var new_pl_res = create_playlist(new_name, str(orig.get("description", "")))
	if not new_pl_res["success"]:
		return new_pl_res

	var new_pl = new_pl_res["playlist"]
	var new_pl_id = str(new_pl["id"])

	# Copy items preserving sort_order
	var items = get_playlist_items(playlist_id)
	for item in items:
		add_playlist_item(
			new_pl_id,
			str(item.get("title", "")),
			str(item.get("artist", "")),
			str(item.get("source_type", "youtube")),
			str(item.get("url", "")),
			int(item.get("duration_seconds", 0)),
			str(item.get("notes", "")),
			str(item.get("thumbnail_url", ""))
		)

	return {
		"success": true,
		"playlist": get_playlist_by_id(new_pl_id)
	}

func delete_playlist(playlist_id: String) -> bool:
	if not db or playlist_id.is_empty():
		return false
	db.execute("DELETE FROM playlist_items WHERE playlist_id = ?;", [playlist_id])
	var res = db.execute("DELETE FROM playlists WHERE id = ?;", [playlist_id])
	return res["success"]

func reorder_playlists(ordered_ids: Array) -> bool:
	if not db:
		return false
	for i in range(ordered_ids.size()):
		var pl_id = str(ordered_ids[i])
		db.execute("UPDATE playlists SET sort_order = ?, updated_at = datetime('now') WHERE id = ?;", [i, pl_id])
	return true

func move_playlist_order(playlist_id: String, direction: String) -> bool:
	var playlists = get_all_playlists()
	var current_index = -1
	for i in range(playlists.size()):
		if str(playlists[i].get("id", "")) == playlist_id:
			current_index = i
			break

	if current_index == -1:
		return false

	var target_index = current_index
	if direction == "up" and current_index > 0:
		target_index = current_index - 1
	elif direction == "down" and current_index < playlists.size() - 1:
		target_index = current_index + 1
	else:
		return false

	var temp = playlists[current_index]
	playlists[current_index] = playlists[target_index]
	playlists[target_index] = temp

	var ids = []
	for p in playlists:
		ids.append(str(p.get("id", "")))
	return reorder_playlists(ids)

func reorder_playlist_to_index(playlist_id: String, target_index: int) -> bool:
	var playlists = get_all_playlists()
	var current_index = -1
	for i in range(playlists.size()):
		if str(playlists[i].get("id", "")) == playlist_id:
			current_index = i
			break

	if current_index == -1:
		return false

	var item = playlists.pop_at(current_index)
	var clamped_target = clampi(target_index, 0, playlists.size())
	playlists.insert(clamped_target, item)

	var ids = []
	for p in playlists:
		ids.append(str(p.get("id", "")))
	return reorder_playlists(ids)

func _refresh_item_counts() -> void:
	if not db:
		return
	db.execute("""
		UPDATE playlists
		SET item_count = (
			SELECT COUNT(*) FROM playlist_items WHERE playlist_items.playlist_id = playlists.id
		);
	""")

# ==============================================================================
# PLAYLIST PROVIDER LINKS MANAGEMENT
# ==============================================================================

func get_playlist_provider_link(playlist_id: String, provider: String = "youtube") -> Dictionary:
	if not db or playlist_id.is_empty():
		return {}
	var res = db.execute("SELECT * FROM playlist_provider_links WHERE playlist_id = ? AND provider = ? LIMIT 1;", [playlist_id, provider])
	if res["success"] and res["data"].size() > 0:
		return res["data"][0]
	return {}

func save_playlist_provider_link(
	playlist_id: String,
	provider: String,
	external_playlist_id: String,
	external_playlist_url: String,
	sync_status: String = "synced",
	last_sync_error: String = ""
) -> bool:
	if not db or playlist_id.is_empty():
		return false
	var existing = get_playlist_provider_link(playlist_id, provider)
	if existing.is_empty():
		var new_id = _generate_uuid("ppl")
		var res = db.execute(
			"""INSERT INTO playlist_provider_links
			(id, playlist_id, provider, external_playlist_id, external_playlist_url, sync_enabled, sync_status, last_synced_at, last_sync_error, created_at, updated_at)
			VALUES (?, ?, ?, ?, ?, 1, ?, datetime('now'), ?, datetime('now'), datetime('now'));""",
			[new_id, playlist_id, provider, external_playlist_id, external_playlist_url, sync_status, last_sync_error]
		)
		return res["success"]
	else:
		var link_id = str(existing.get("id", ""))
		var res = db.execute(
			"""UPDATE playlist_provider_links
			SET external_playlist_id = ?, external_playlist_url = ?, sync_status = ?, last_synced_at = datetime('now'), last_sync_error = ?, updated_at = datetime('now')
			WHERE id = ?;""",
			[external_playlist_id, external_playlist_url, sync_status, last_sync_error, link_id]
		)
		return res["success"]

func update_playlist_sync_status(playlist_id: String, provider: String, sync_status: String, last_error: String = "") -> bool:
	if not db or playlist_id.is_empty():
		return false
	var link = get_playlist_provider_link(playlist_id, provider)
	if link.is_empty():
		return false
	var res = db.execute(
		"UPDATE playlist_provider_links SET sync_status = ?, last_sync_error = ?, updated_at = datetime('now') WHERE id = ?;",
		[sync_status, last_error, str(link.get("id", ""))]
	)
	return res["success"]

func delete_playlist_provider_link(playlist_id: String, provider: String = "youtube") -> bool:
	if not db or playlist_id.is_empty():
		return false
	var res = db.execute("DELETE FROM playlist_provider_links WHERE playlist_id = ? AND provider = ?;", [playlist_id, provider])
	return res["success"]

func get_item_provider_link(item_id: String, provider: String = "youtube") -> Dictionary:
	if not db or item_id.is_empty():
		return {}
	var res = db.execute("SELECT * FROM playlist_item_provider_links WHERE playlist_item_id = ? AND provider = ? LIMIT 1;", [item_id, provider])
	if res["success"] and res["data"].size() > 0:
		return res["data"][0]
	return {}

func save_item_provider_link(
	item_id: String,
	provider: String,
	external_item_id: String,
	external_media_id: String,
	sync_status: String = "synced",
	last_sync_error: String = ""
) -> bool:
	if not db or item_id.is_empty():
		return false
	var existing = get_item_provider_link(item_id, provider)
	if existing.is_empty():
		var new_id = _generate_uuid("pipl")
		var res = db.execute(
			"""INSERT INTO playlist_item_provider_links
			(id, playlist_item_id, provider, external_item_id, external_media_id, sync_status, last_synced_at, last_sync_error, created_at, updated_at)
			VALUES (?, ?, ?, ?, ?, ?, datetime('now'), ?, datetime('now'), datetime('now'));""",
			[new_id, item_id, provider, external_item_id, external_media_id, sync_status, last_sync_error]
		)
		return res["success"]
	else:
		var link_id = str(existing.get("id", ""))
		var res = db.execute(
			"""UPDATE playlist_item_provider_links
			SET external_item_id = ?, external_media_id = ?, sync_status = ?, last_synced_at = datetime('now'), last_sync_error = ?, updated_at = datetime('now')
			WHERE id = ?;""",
			[external_item_id, external_media_id, sync_status, last_sync_error, link_id]
		)
		return res["success"]

func delete_item_provider_link(item_id: String, provider: String = "youtube") -> bool:
	if not db or item_id.is_empty():
		return false
	var res = db.execute("DELETE FROM playlist_item_provider_links WHERE playlist_item_id = ? AND provider = ?;", [item_id, provider])
	return res["success"]

func convert_playlist_provider(playlist_id: String, target_provider: String) -> Dictionary:
	if not db or playlist_id.is_empty():
		return {"success": false, "error": "Invalid playlist ID"}

	var target = target_provider.to_lower().strip_edges()
	var valid_providers = ["general", "youtube", "spotify", "apple_music"]
	if not target in valid_providers:
		return {"success": false, "error": "Unsupported provider type: " + target_provider}

	var items = get_playlist_items(playlist_id)
	if target == "youtube":
		var incompatible = []
		for item in items:
			var url = str(item.get("url", ""))
			var vid = extract_youtube_video_id(url)
			if vid.is_empty():
				incompatible.append({
					"id": str(item.get("id", "")),
					"title": str(item.get("title", "")),
					"url": url
				})
		if incompatible.size() > 0:
			return {
				"success": false,
				"error": "Cannot convert to YouTube playlist. Incompatible items found.",
				"incompatible_items": incompatible
			}

	var res = db.execute("UPDATE playlists SET provider_type = ?, updated_at = datetime('now') WHERE id = ?;", [target, playlist_id])
	if not res["success"]:
		return {"success": false, "error": "Failed to update playlist provider."}

	return {
		"success": true,
		"playlist": get_playlist_by_id(playlist_id)
	}

# ==============================================================================
# PLAYLIST ITEMS MANAGEMENT
# ==============================================================================

func get_playlist_items(playlist_id: String) -> Array:
	if not db or playlist_id.is_empty():
		return []
	var res = db.execute("SELECT * FROM playlist_items WHERE playlist_id = ? ORDER BY sort_order ASC, created_at ASC;", [playlist_id])
	if res["success"]:
		return res["data"]
	return []

func get_item_by_id(item_id: String) -> Dictionary:
	if not db or item_id.is_empty():
		return {}
	var res = db.execute("SELECT * FROM playlist_items WHERE id = ? LIMIT 1;", [item_id])
	if res["success"] and res["data"].size() > 0:
		return res["data"][0]
	return {}

func add_playlist_item(
	playlist_id: String,
	title: String,
	artist: String = "",
	source_type: String = "other",
	url: String = "",
	duration_seconds: int = 0,
	notes: String = "",
	thumbnail_url: String = ""
) -> Dictionary:
	if not db or playlist_id.is_empty():
		return {"success": false, "error": "Invalid playlist ID"}

	var clean_url = url.strip_edges()
	var clean_title = title.strip_edges()

	# Strict URL Validation Rule: If URL is provided, it MUST be valid!
	if clean_url != "":
		var val = validate_and_extract_url(clean_url)
		if not val["is_valid"]:
			return {"success": false, "error": "Invalid media URL: " + val.get("error", "No valid media URL found.")}
		clean_url = str(val["canonical_url"])
		source_type = str(val["source_type"])
		if clean_title.is_empty() or clean_title == "Untitled Media":
			clean_title = str(val["title"])
	elif source_type in ["youtube", "spotify", "apple_music"]:
		if clean_title.is_empty() or clean_title == "Untitled Media":
			return {"success": false, "error": "Media URL required for " + source_type}

	if clean_title.is_empty():
		clean_title = "Untitled Media"

	# Get max sort_order in this playlist
	var max_res = db.execute("SELECT MAX(sort_order) as max_ord FROM playlist_items WHERE playlist_id = ?;", [playlist_id])
	var next_ord = 0
	if max_res["success"] and max_res["data"].size() > 0 and max_res["data"][0].get("max_ord") != null:
		next_ord = int(max_res["data"][0]["max_ord"]) + 1

	var new_id = _generate_uuid("pli")
	var res = db.execute(
		"""INSERT INTO playlist_items
		(id, playlist_id, title, artist, source_type, url, duration_seconds, notes, sort_order, thumbnail_url, created_at, updated_at)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, datetime('now'), datetime('now'));""",
		[new_id, playlist_id, clean_title, artist.strip_edges(), source_type, clean_url, duration_seconds, notes.strip_edges(), next_ord, thumbnail_url.strip_edges()]
	)

	if not res["success"]:
		return {"success": false, "error": res.get("error", "Failed to add playlist item.")}

	_refresh_item_counts()

	return {
		"success": true,
		"item": get_item_by_id(new_id)
	}

func insert_playlist_item_at_index(
	playlist_id: String,
	target_index: int,
	title: String,
	artist: String = "",
	source_type: String = "youtube",
	url: String = "",
	duration_seconds: int = 0,
	notes: String = "",
	thumbnail_url: String = ""
) -> Dictionary:
	var add_res = add_playlist_item(playlist_id, title, artist, source_type, url, duration_seconds, notes, thumbnail_url)
	if not add_res["success"]:
		return add_res

	var new_item = add_res["item"]
	var item_id = str(new_item["id"])
	reorder_song_to_index(item_id, target_index)
	return {
		"success": true,
		"item": get_item_by_id(item_id)
	}

func update_playlist_item(
	item_id: String,
	title: String,
	artist: String,
	source_type: String,
	url: String,
	notes: String,
	duration_seconds: int = 0,
	thumbnail_url: String = ""
) -> bool:
	if not db or item_id.is_empty():
		return false
	var clean_title = title.strip_edges()
	if clean_title.is_empty():
		clean_title = "Untitled Media"

	var res = db.execute(
		"""UPDATE playlist_items
		SET title = ?, artist = ?, source_type = ?, url = ?, notes = ?, duration_seconds = ?, thumbnail_url = ?, updated_at = datetime('now')
		WHERE id = ?;""",
		[clean_title, artist.strip_edges(), source_type, url.strip_edges(), notes.strip_edges(), duration_seconds, thumbnail_url.strip_edges(), item_id]
	)
	return res["success"]

func delete_playlist_item(item_id: String) -> bool:
	if not db or item_id.is_empty():
		return false
	var res = db.execute("DELETE FROM playlist_items WHERE id = ?;", [item_id])
	_refresh_item_counts()
	return res["success"]

func reorder_playlist_items(playlist_id: String, ordered_item_ids: Array) -> bool:
	if not db or playlist_id.is_empty():
		return false
	for i in range(ordered_item_ids.size()):
		var item_id = str(ordered_item_ids[i])
		db.execute("UPDATE playlist_items SET sort_order = ?, updated_at = datetime('now') WHERE id = ? AND playlist_id = ?;", [i, item_id, playlist_id])
	return true

func move_item_order(item_id: String, action_type: String) -> bool:
	var item = get_item_by_id(item_id)
	if item.is_empty():
		return false
	var playlist_id = str(item.get("playlist_id", ""))
	var items = get_playlist_items(playlist_id)
	var current_index = -1
	for i in range(items.size()):
		if str(items[i].get("id", "")) == item_id:
			current_index = i
			break

	if current_index == -1:
		return false

	var item_to_move = items.pop_at(current_index)

	if action_type == "up":
		var new_idx = max(0, current_index - 1)
		items.insert(new_idx, item_to_move)
	elif action_type == "down":
		var new_idx = min(items.size(), current_index + 1)
		items.insert(new_idx, item_to_move)
	elif action_type == "top":
		items.insert(0, item_to_move)
	elif action_type == "bottom":
		items.append(item_to_move)
	else:
		return false

	var ids = []
	for it in items:
		ids.append(str(it.get("id", "")))
	return reorder_playlist_items(playlist_id, ids)

func reorder_song_to_index(item_id: String, target_index: int) -> bool:
	var item = get_item_by_id(item_id)
	if item.is_empty():
		return false
	var playlist_id = str(item.get("playlist_id", ""))
	var items = get_playlist_items(playlist_id)
	var current_index = -1
	for i in range(items.size()):
		if str(items[i].get("id", "")) == item_id:
			current_index = i
			break

	if current_index == -1:
		return false

	var moved_item = items.pop_at(current_index)
	var clamped_target = clampi(target_index, 0, items.size())
	items.insert(clamped_target, moved_item)

	var ids = []
	for it in items:
		ids.append(str(it.get("id", "")))
	return reorder_playlist_items(playlist_id, ids)

func move_item_to_playlist(item_id: String, target_playlist_id: String) -> bool:
	var item = get_item_by_id(item_id)
	if item.is_empty() or target_playlist_id.is_empty():
		return false

	var orig_playlist_id = str(item.get("playlist_id", ""))
	if orig_playlist_id == target_playlist_id:
		return true

	var max_res = db.execute("SELECT MAX(sort_order) as max_ord FROM playlist_items WHERE playlist_id = ?;", [target_playlist_id])
	var next_ord = 0
	if max_res["success"] and max_res["data"].size() > 0 and max_res["data"][0].get("max_ord") != null:
		next_ord = int(max_res["data"][0]["max_ord"]) + 1

	var res = db.execute(
		"UPDATE playlist_items SET playlist_id = ?, sort_order = ?, updated_at = datetime('now') WHERE id = ?;",
		[target_playlist_id, next_ord, item_id]
	)
	_refresh_item_counts()
	return res["success"]

func copy_item_to_playlist(item_id: String, target_playlist_id: String) -> Dictionary:
	var item = get_item_by_id(item_id)
	if item.is_empty() or target_playlist_id.is_empty():
		return {"success": false, "error": "Invalid item or target playlist"}

	return add_playlist_item(
		target_playlist_id,
		str(item.get("title", "")),
		str(item.get("artist", "")),
		str(item.get("source_type", "youtube")),
		str(item.get("url", "")),
		int(item.get("duration_seconds", 0)),
		str(item.get("notes", "")),
		str(item.get("thumbnail_url", ""))
	)

func _normalize_and_unescape_url(raw_input: String) -> String:
	var clean_str = raw_input.strip_edges()
	if clean_str.is_empty():
		return ""

	if "%3a" in clean_str.to_lower() or "%2f" in clean_str.to_lower():
		clean_str = clean_str.uri_decode()

	if "google.com/url" in clean_str.to_lower():
		var u_idx = clean_str.find("url=")
		if u_idx != -1:
			var sub = clean_str.substr(u_idx + 4)
			var amp_idx = sub.find("&")
			var target_url = sub.substr(0, amp_idx) if amp_idx != -1 else sub
			clean_str = target_url.uri_decode()
		elif "q=" in clean_str.to_lower():
			var q_idx = clean_str.find("q=")
			if q_idx != -1:
				var sub = clean_str.substr(q_idx + 2)
				var amp_idx = sub.find("&")
				var target_url = sub.substr(0, amp_idx) if amp_idx != -1 else sub
				clean_str = target_url.uri_decode()

	return clean_str.strip_edges()

func extract_youtube_video_id(raw_input: String) -> String:
	var clean_str = _normalize_and_unescape_url(raw_input)
	var lower_url = clean_str.to_lower()
	var video_id = ""

	if "youtube.com/watch" in lower_url:
		var v_idx = clean_str.find("v=")
		if v_idx != -1:
			var sub = clean_str.substr(v_idx + 2)
			var amp_idx = sub.find("&")
			video_id = sub.substr(0, amp_idx) if amp_idx != -1 else sub
	elif "youtu.be/" in lower_url:
		var parts = clean_str.split("youtu.be/")
		if parts.size() > 1:
			var sub = parts[1]
			var q_idx = sub.find("?")
			video_id = sub.substr(0, q_idx) if q_idx != -1 else sub
	elif "youtube.com/embed/" in lower_url:
		var parts = clean_str.split("youtube.com/embed/")
		if parts.size() > 1:
			var sub = parts[1]
			var q_idx = sub.find("?")
			video_id = sub.substr(0, q_idx) if q_idx != -1 else sub
	elif "youtube.com/shorts/" in lower_url:
		var parts = clean_str.split("youtube.com/shorts/")
		if parts.size() > 1:
			var sub = parts[1]
			var q_idx = sub.find("?")
			video_id = sub.substr(0, q_idx) if q_idx != -1 else sub

	return video_id.strip_edges()

func check_duplicate_in_playlist(playlist_id: String, url: String, title: String = "") -> bool:
	if not db or playlist_id.is_empty():
		return false
	var clean_url = url.strip_edges()
	var clean_title = title.strip_edges()

	var vid_id = extract_youtube_video_id(clean_url)
	if vid_id != "":
		var term = "%" + vid_id + "%"
		var q_vid = db.execute("SELECT id FROM playlist_items WHERE playlist_id = ? AND url LIKE ? LIMIT 1;", [playlist_id, term])
		if q_vid["success"] and q_vid["data"].size() > 0:
			return true
	elif clean_url != "":
		var q_url = db.execute("SELECT id FROM playlist_items WHERE playlist_id = ? AND url = ? LIMIT 1;", [playlist_id, clean_url])
		if q_url["success"] and q_url["data"].size() > 0:
			return true

	if clean_title != "":
		var q_title = db.execute("SELECT id FROM playlist_items WHERE playlist_id = ? AND LOWER(title) = LOWER(?) LIMIT 1;", [playlist_id, clean_title])
		if q_title["success"] and q_title["data"].size() > 0:
			return true

	return false

func search_library(query: String) -> Array:
	if not db or query.strip_edges().is_empty():
		return []

	var term = "%" + query.strip_edges().to_lower() + "%"
	var sql = """
		SELECT pi.*, p.name as playlist_name
		FROM playlist_items pi
		JOIN playlists p ON pi.playlist_id = p.id
		WHERE LOWER(pi.title) LIKE ?
		   OR LOWER(pi.artist) LIKE ?
		   OR LOWER(pi.notes) LIKE ?
		   OR LOWER(pi.url) LIKE ?
		   OR LOWER(p.name) LIKE ?
		ORDER BY p.name ASC, pi.sort_order ASC;
	"""
	var res = db.execute(sql, [term, term, term, term, term])
	if res["success"]:
		return res["data"]
	return []

# ==============================================================================
# URL RECOGNITION & METADATA HELPERS
# ==============================================================================

func validate_and_extract_url(raw_input: String) -> Dictionary:
	var clean_input = raw_input.strip_edges()
	var result = {
		"is_valid": false,
		"url": "",
		"canonical_url": "",
		"source_type": "other",
		"video_id": "",
		"thumbnail_url": "",
		"title": "",
		"artist": "",
		"error": "No valid media URL found."
	}

	if clean_input.is_empty():
		return result

	# Check if input is a local shortcut file (e.g. macOS .webloc or Windows .url) or readable text file containing a URL
	if FileAccess.file_exists(clean_input) or clean_input.to_lower().ends_with(".webloc") or clean_input.to_lower().ends_with(".url"):
		var content = FileAccess.get_file_as_string(clean_input)
		if not content.is_empty():
			var file_url = _extract_first_url_from_text(content)
			if not file_url.is_empty():
				clean_input = file_url

	var candidate_str = clean_input
	if "\n" in candidate_str or "\r" in candidate_str:
		candidate_str = _extract_first_url_from_text(clean_input)
	else:
		var extracted = _extract_first_url_from_text(clean_input)
		if extracted != "":
			candidate_str = extracted

	if candidate_str.is_empty():
		if _is_valid_local_file_path(clean_input):
			candidate_str = clean_input
		else:
			return result

	var meta = detect_url_metadata(candidate_str)
	var src_type = str(meta.get("source_type", "other"))

	if src_type == "other":
		return result

	result["is_valid"] = true
	result["url"] = str(meta.get("url", candidate_str))
	result["canonical_url"] = str(meta.get("canonical_url", candidate_str))
	result["source_type"] = src_type
	result["video_id"] = str(meta.get("video_id", ""))
	result["title"] = str(meta.get("title", ""))
	result["artist"] = str(meta.get("artist", ""))
	result["thumbnail_url"] = str(meta.get("thumbnail_url", ""))
	result["error"] = ""

	return result

func _extract_first_url_from_text(text: String) -> String:
	var regex = RegEx.new()
	regex.compile("(https?://|file://)[^\\s\"'<>()\\[\\]{}]+")
	var match_res = regex.search(text)
	if match_res:
		var found_url = match_res.get_string().strip_edges()
		while found_url.ends_with(".") or found_url.ends_with(",") or found_url.ends_with(";") or found_url.ends_with(")") or found_url.ends_with("]"):
			found_url = found_url.substr(0, found_url.length() - 1).strip_edges()
		return found_url
	return ""

func _is_valid_local_file_path(text: String) -> bool:
	var clean = text.strip_edges()
	if clean.begins_with("file://") or clean.begins_with("/") or (clean.length() > 2 and clean[1] == ':' and clean[2] == '\\'):
		var ext = clean.get_extension().to_lower()
		var media_exts = ["mp3", "wav", "mp4", "m4a", "aac", "flac", "ogg", "mov", "avi", "mkv", "webm"]
		if ext in media_exts or FileAccess.file_exists(clean):
			return true
	return false

func detect_url_metadata(raw_input: String) -> Dictionary:
	var clean_str = _normalize_and_unescape_url(raw_input)
	var result = {
		"source_type": "other",
		"url": clean_str,
		"canonical_url": clean_str,
		"video_id": "",
		"thumbnail_url": "",
		"title": "",
		"artist": ""
	}

	if clean_str.is_empty():
		return result

	# Local File checking
	if clean_str.begins_with("file://") or clean_str.begins_with("/") or (clean_str.length() > 2 and clean_str[1] == ':' and clean_str[2] == '\\'):
		result["source_type"] = "local_file"
		var filename = clean_str.get_file().get_basename()
		if filename != "":
			result["title"] = filename.capitalize()
		return result

	# YouTube URL checking
	var video_id = extract_youtube_video_id(clean_str)
	if video_id != "":
		var canonical = "https://www.youtube.com/watch?v=" + video_id
		result["source_type"] = "youtube"
		result["video_id"] = video_id
		result["url"] = canonical
		result["canonical_url"] = canonical
		result["thumbnail_url"] = "https://img.youtube.com/vi/" + video_id + "/hqdefault.jpg"
		result["title"] = "YouTube Video (" + video_id + ")"
		return result

	# Spotify checking
	var lower_url = clean_str.to_lower()
	if "spotify.com" in lower_url:
		result["source_type"] = "spotify"
		result["title"] = "Spotify Link"
		return result

	# Apple Music checking
	if "apple.com" in lower_url and "music" in lower_url:
		result["source_type"] = "apple_music"
		result["title"] = "Apple Music Link"
		return result

	# Generic Web checking
	if lower_url.begins_with("http://") or lower_url.begins_with("https://"):
		result["source_type"] = "web"
		var host_part = lower_url.replacen("https://", "").replacen("http://", "").split("/")[0]
		result["title"] = "Web Link (" + host_part + ")"
		return result

	return result

func fetch_youtube_oembed(video_id: String, parent_node: Node, callback: Callable) -> void:
	if video_id.is_empty() or not parent_node:
		callback.call({"success": false, "error": "Invalid video ID or parent node"})
		return

	var http_node = HTTPRequest.new()
	http_node.timeout = 8.0
	parent_node.add_child(http_node)

	var oembed_url = "https://www.youtube.com/oembed?url=https://www.youtube.com/watch?v=" + video_id + "&format=json"
	var headers = PackedStringArray(["User-Agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"])

	http_node.request_completed.connect(func(_res: int, code: int, _headers: PackedStringArray, body: PackedByteArray):
		if code == 200:
			var json_str = body.get_string_from_utf8()
			var json = JSON.parse_string(json_str)
			if json and typeof(json) == TYPE_DICTIONARY:
				var v_title = str(json.get("title", "")).strip_edges()
				var v_artist = str(json.get("author_name", "")).strip_edges()
				var v_thumb = str(json.get("thumbnail_url", "")).strip_edges()
				if v_thumb.is_empty():
					v_thumb = "https://i.ytimg.com/vi/" + video_id + "/hqdefault.jpg"
				callback.call({
					"success": true,
					"title": v_title,
					"artist": v_artist,
					"thumbnail_url": v_thumb,
					"video_id": video_id,
					"canonical_url": "https://www.youtube.com/watch?v=" + video_id
				})
				http_node.queue_free()
				return

		callback.call({"success": false, "error": "oEmbed request failed with HTTP " + str(code)})
		http_node.queue_free()
	)

	var err = http_node.request(oembed_url, headers)
	if err != OK:
		callback.call({"success": false, "error": "Failed to launch HTTP request"})
		http_node.queue_free()

func get_youtube_api_key() -> String:
	if not db:
		return OS.get_environment("YOUTUBE_API_KEY")
	var res = db.execute("SELECT setting_value FROM app_settings WHERE setting_key = 'YOUTUBE_API_KEY' LIMIT 1;")
	if res["success"] and res["data"].size() > 0:
		var val = str(res["data"][0].get("setting_value", "")).strip_edges()
		if val != "":
			return val
	return OS.get_environment("YOUTUBE_API_KEY")
