extends CanvasLayer

## Card Print Queue Dialog & Batch Card Manager for StudyCenterHub
## Manages persistent card print queue in SQLite table `card_print_queue`.

const SQLiteDatabaseScript = preload("res://src/infrastructure/database/sqlite_database.gd")
const QrGenerator = preload("res://src/domain/sync/qr_code_generator.gd")
const MembershipCardEngine = preload("res://src/domain/sync/membership_card_engine.gd")
const WorkQueueHeaderBarScene = preload("res://app/scenes/components/work_queue_header_bar.tscn")
const QueueControllerScript = preload("res://src/domain/work_queue/queue_controller.gd")

var db: RefCounted
var parent_node: Node
var current_filter: String = "pending" # "pending", "printed", "needs_reprint", "all"

var is_queue_mode: bool = false
var queue_controller: RefCounted = null
var header_bar_instance: Node = null

var root_panel: PanelContainer
var item_container: VBoxContainer
var filter_pending_btn: Button
var filter_printed_btn: Button
var filter_reprint_btn: Button
var filter_all_btn: Button
var status_summary_lbl: Label

func _init(p_parent: Node = null, p_db: RefCounted = null) -> void:
	parent_node = p_parent
	if p_db != null:
		db = p_db
	elif parent_node and "db" in parent_node and parent_node.db:
		db = parent_node.db
	else:
		db = SQLiteDatabaseScript.new()

func receive_navigation_context(params: Dictionary) -> void:
	if params.get("queue_mode", false) == true:
		configure_queue_mode(params)

func configure_queue_mode(params: Dictionary = {}) -> void:
	is_queue_mode = true
	if params.has("queue_controller") and params["queue_controller"] != null:
		queue_controller = params["queue_controller"]
	else:
		queue_controller = QueueControllerScript.new(db)

	if queue_controller:
		if db:
			queue_controller.db = db
		if queue_controller.active_items.size() == 0:
			queue_controller.start_queue("pending_member_cards")

	if root_panel and not header_bar_instance:
		_attach_header_bar()

func _attach_header_bar() -> void:
	if not root_panel or header_bar_instance: return
	var main_vbox = root_panel.get_child(0) if root_panel.get_child_count() > 0 else null
	if main_vbox:
		header_bar_instance = WorkQueueHeaderBarScene.instantiate()
		main_vbox.add_child(header_bar_instance)
		main_vbox.move_child(header_bar_instance, 0)
		
		var cur_idx = queue_controller.current_index if queue_controller else 0
		var rem_count = queue_controller.get_remaining_count() if queue_controller else 0
		header_bar_instance.configure_header("Pending Member Cards", cur_idx, rem_count)
		header_bar_instance.pause_requested.connect(_on_queue_pause)
		header_bar_instance.exit_requested.connect(_on_queue_exit)

func _on_queue_pause() -> void:
	if header_bar_instance and queue_controller:
		header_bar_instance.update_progress(queue_controller.current_index, queue_controller.get_remaining_count())

func _on_queue_exit() -> void:
	if queue_controller:
		queue_controller.end_session()
	if header_bar_instance:
		header_bar_instance.queue_free()
		header_bar_instance = null
	is_queue_mode = false
	queue_free()

func show_dialog() -> void:
	layer = 100
	
	var overlay = ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.65)
	overlay.anchors_preset = Control.PRESET_FULL_RECT
	add_child(overlay)

	root_panel = PanelContainer.new()
	root_panel.custom_minimum_size = Vector2(860, 600)
	root_panel.anchors_preset = Control.PRESET_CENTER
	root_panel.anchor_left = 0.5
	root_panel.anchor_top = 0.5
	root_panel.anchor_right = 0.5
	root_panel.anchor_bottom = 0.5
	root_panel.offset_left = -430
	root_panel.offset_top = -300
	root_panel.offset_right = 430
	root_panel.offset_bottom = 300

	var panel_st = StyleBoxFlat.new()
	panel_st.bg_color = Color(0.12, 0.15, 0.20, 1.0)
	panel_st.corner_radius_top_left = 12
	panel_st.corner_radius_top_right = 12
	panel_st.corner_radius_bottom_left = 12
	panel_st.corner_radius_bottom_right = 12
	panel_st.content_margin_left = 24
	panel_st.content_margin_top = 24
	panel_st.content_margin_right = 24
	panel_st.content_margin_bottom = 24
	root_panel.add_theme_stylebox_override("panel", panel_st)
	add_child(root_panel)

	var main_vbox = VBoxContainer.new()
	main_vbox.add_theme_constant_override("separation", 16)
	root_panel.add_child(main_vbox)

	# Header HBox
	var header_hbox = HBoxContainer.new()
	var title_lbl = Label.new()
	title_lbl.text = "🎴 Membership Card Print Queue"
	title_lbl.add_theme_font_size_override("font_size", 22)
	title_lbl.add_theme_color_override("font_color", Color(0.95, 0.6, 0.2, 1.0))
	title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_hbox.add_child(title_lbl)

	var close_btn = Button.new()
	close_btn.text = " ✕ "
	close_btn.custom_minimum_size = Vector2(36, 36)
	close_btn.pressed.connect(func(): queue_free())
	header_hbox.add_child(close_btn)
	main_vbox.add_child(header_hbox)

	# Filter Bar HBox
	var filter_hbox = HBoxContainer.new()
	filter_hbox.add_theme_constant_override("separation", 10)

	filter_pending_btn = Button.new()
	filter_pending_btn.text = "Pending Queue"
	filter_pending_btn.pressed.connect(func(): _set_filter("pending"))
	filter_hbox.add_child(filter_pending_btn)

	filter_printed_btn = Button.new()
	filter_printed_btn.text = "Printed Cards"
	filter_printed_btn.pressed.connect(func(): _set_filter("printed"))
	filter_hbox.add_child(filter_printed_btn)

	filter_reprint_btn = Button.new()
	filter_reprint_btn.text = "Needs Reprint"
	filter_reprint_btn.pressed.connect(func(): _set_filter("needs_reprint"))
	filter_hbox.add_child(filter_reprint_btn)

	filter_all_btn = Button.new()
	filter_all_btn.text = "All Items"
	filter_all_btn.pressed.connect(func(): _set_filter("all"))
	filter_hbox.add_child(filter_all_btn)

	status_summary_lbl = Label.new()
	status_summary_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status_summary_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	status_summary_lbl.add_theme_color_override("font_color", Color(0.7, 0.75, 0.8, 1.0))
	filter_hbox.add_child(status_summary_lbl)

	main_vbox.add_child(filter_hbox)

	# Scrollable Item List
	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0, 320)
	main_vbox.add_child(scroll)

	item_container = VBoxContainer.new()
	item_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	item_container.add_theme_constant_override("separation", 8)
	scroll.add_child(item_container)

	# Bottom Action Bar
	var action_hbox = HBoxContainer.new()
	action_hbox.add_theme_constant_override("separation", 12)

	var btn_print_all = Button.new()
	btn_print_all.text = "🖨️ Print / Export All Pending"
	btn_print_all.custom_minimum_size = Vector2(210, 42)
	btn_print_all.pressed.connect(func(): _print_all_pending())
	action_hbox.add_child(btn_print_all)

	var btn_mark_printed = Button.new()
	btn_mark_printed.text = "✅ Mark All as Printed"
	btn_mark_printed.custom_minimum_size = Vector2(180, 42)
	btn_mark_printed.pressed.connect(func(): _mark_all_printed())
	action_hbox.add_child(btn_mark_printed)

	var btn_clear_queue = Button.new()
	btn_clear_queue.text = "🗑️ Clear Printed Items"
	btn_clear_queue.custom_minimum_size = Vector2(160, 42)
	btn_clear_queue.pressed.connect(func(): _clear_printed_items())
	action_hbox.add_child(btn_clear_queue)

	main_vbox.add_child(action_hbox)

	if parent_node:
		parent_node.add_child(self)

	if is_queue_mode:
		_attach_header_bar()

	refresh_queue_list()

func _set_filter(f: String) -> void:
	current_filter = f
	refresh_queue_list()

func refresh_queue_list() -> void:
	if not item_container:
		return
		
	for c in item_container.get_children():
		c.queue_free()

	# Query items from card_print_queue joined with people
	var sql = """
		SELECT q.queue_uuid, q.person_id, q.person_uuid, q.status, q.added_at, q.printed_at,
		       p.first_name, p.last_name, p.human_id, p.profile_photo as photo_url
		FROM card_print_queue q
		LEFT JOIN people p ON (q.person_id = p.id OR (q.person_uuid IS NOT NULL AND q.person_uuid != '' AND q.person_uuid = p.person_uuid))
	"""
	if current_filter == "pending":
		sql += " WHERE q.status = 'pending'"
	elif current_filter == "printed":
		sql += " WHERE q.status = 'printed'"
	elif current_filter == "needs_reprint":
		sql += " WHERE q.status = 'needs_reprint'"

	sql += " ORDER BY q.id DESC;"

	var res = db.execute(sql)
	var items = res.get("data", []) if res["success"] else []

	# Update summary text
	var total_pending = 0
	var count_res = db.execute("SELECT COUNT(*) as cnt FROM card_print_queue WHERE status = 'pending';")
	if count_res["success"] and count_res["data"].size() > 0:
		total_pending = int(count_res["data"][0].get("cnt", 0))
	status_summary_lbl.text = "Pending Cards in Queue: " + str(total_pending)

	if items.size() == 0:
		var empty_lbl = Label.new()
		empty_lbl.text = "No cards found in queue matching current filter ('" + current_filter + "')."
		empty_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty_lbl.add_theme_color_override("font_color", Color(0.6, 0.65, 0.7, 1.0))
		empty_lbl.custom_minimum_size = Vector2(0, 100)
		item_container.add_child(empty_lbl)
		return

	for item in items:
		var row = PanelContainer.new()
		var row_st = StyleBoxFlat.new()
		row_st.bg_color = Color(0.18, 0.22, 0.28, 1.0)
		row_st.corner_radius_top_left = 6
		row_st.corner_radius_top_right = 6
		row_st.corner_radius_bottom_left = 6
		row_st.corner_radius_bottom_right = 6
		row_st.content_margin_left = 12
		row_st.content_margin_top = 8
		row_st.content_margin_right = 12
		row_st.content_margin_bottom = 8
		row.add_theme_stylebox_override("panel", row_st)

		var r_hbox = HBoxContainer.new()
		r_hbox.add_theme_constant_override("separation", 12)

		var fn = str(item.get("first_name", ""))
		var ln = str(item.get("last_name", ""))
		if fn == "<null>" or fn == "null": fn = ""
		if ln == "<null>" or ln == "null": ln = ""
		var name_str = (fn + " " + ln).strip_edges()
		if name_str == "":
			name_str = "Participant #" + str(item.get("person_id", ""))
		var human_id = str(item.get("human_id", "PRT-0000"))
		if human_id == "<null>" or human_id == "null": human_id = "PRT-0000"
		var item_status = str(item.get("status", "pending"))

		var info_lbl = Label.new()
		info_lbl.text = name_str + " (" + human_id + ")  - Added: " + str(item.get("added_at", "")).left(10)
		info_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info_lbl.add_theme_font_size_override("font_size", 15)
		r_hbox.add_child(info_lbl)

		var status_badge = Label.new()
		if item_status == "pending":
			status_badge.text = "🟡 Pending Print"
			status_badge.add_theme_color_override("font_color", Color(0.9, 0.7, 0.2, 1.0))
		elif item_status == "printed":
			status_badge.text = "🟢 Printed"
			status_badge.add_theme_color_override("font_color", Color(0.3, 0.8, 0.4, 1.0))
		else:
			status_badge.text = "🔴 Needs Reprint"
			status_badge.add_theme_color_override("font_color", Color(0.9, 0.3, 0.3, 1.0))
		r_hbox.add_child(status_badge)

		# Row Action Buttons
		var btn_preview = Button.new()
		btn_preview.text = "👁️ Preview"
		var q_uuid = str(item.get("queue_uuid"))
		var p_id = int(item.get("person_id"))
		btn_preview.pressed.connect(func(): _preview_card_for_person(p_id))
		r_hbox.add_child(btn_preview)

		var btn_remove = Button.new()
		btn_remove.text = "🗑️ Remove"
		btn_remove.pressed.connect(func():
			db.execute("DELETE FROM card_print_queue WHERE queue_uuid = ?;", [q_uuid])
			refresh_queue_list()
		)
		r_hbox.add_child(btn_remove)

		row.add_child(r_hbox)
		item_container.add_child(row)

func _preview_card_for_person(person_id: int) -> void:
	var p_res = db.execute("SELECT * FROM people WHERE id = ? LIMIT 1;", [person_id])
	if p_res["success"] and p_res["data"].size() > 0:
		var p = p_res["data"][0]
		var token = ""
		var qr_res = db.execute("SELECT token_hint FROM participant_qr_credentials WHERE person_id = ? AND status = 'active' LIMIT 1;", [person_id])
		if qr_res["success"] and qr_res["data"].size() > 0:
			token = str(qr_res["data"][0].get("token_hint", ""))
		_open_card_preview(p, token)

func _open_card_preview(person_data: Dictionary, token: String) -> void:
	var preview_layer = CanvasLayer.new()
	preview_layer.layer = 110

	var overlay = ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.75)
	overlay.anchors_preset = Control.PRESET_FULL_RECT
	preview_layer.add_child(overlay)

	var dialog_panel = PanelContainer.new()
	dialog_panel.custom_minimum_size = Vector2(900, 620)
	dialog_panel.anchors_preset = Control.PRESET_CENTER
	dialog_panel.anchor_left = 0.5
	dialog_panel.anchor_top = 0.5
	dialog_panel.anchor_right = 0.5
	dialog_panel.anchor_bottom = 0.5
	dialog_panel.offset_left = -450
	dialog_panel.offset_top = -310
	dialog_panel.offset_right = 450
	dialog_panel.offset_bottom = 310

	var st = StyleBoxFlat.new()
	st.bg_color = Color(0.14, 0.17, 0.22, 1.0)
	st.corner_radius_top_left = 12
	st.corner_radius_top_right = 12
	st.corner_radius_bottom_left = 12
	st.corner_radius_bottom_right = 12
	st.content_margin_left = 20
	st.content_margin_top = 20
	st.content_margin_right = 20
	st.content_margin_bottom = 20
	dialog_panel.add_theme_stylebox_override("panel", st)
	preview_layer.add_child(dialog_panel)

	var dvbox = VBoxContainer.new()
	dvbox.add_theme_constant_override("separation", 14)
	dialog_panel.add_child(dvbox)

	var name_str = (str(person_data.get("first_name", "")) + " " + str(person_data.get("last_name", ""))).strip_edges()
	var title = Label.new()
	title.text = "🎴 Membership Card Preview: " + name_str + " (" + str(person_data.get("human_id", "PRT-0000")) + ")"
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color(0.95, 0.6, 0.2, 1.0))
	dvbox.add_child(title)

	# Card Graphic TextureRect
	var card_img = MembershipCardEngine.render_membership_card(person_data, token)
	var card_tex = ImageTexture.create_from_image(card_img)

	var tex_rect = TextureRect.new()
	tex_rect.texture = card_tex
	tex_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tex_rect.custom_minimum_size = Vector2(800, 440)
	dvbox.add_child(tex_rect)

	# Action Buttons HBox
	var btn_hbox = HBoxContainer.new()
	btn_hbox.add_theme_constant_override("separation", 12)

	var btn_export_png = Button.new()
	btn_export_png.text = "🖼️ Export PNG"
	btn_export_png.custom_minimum_size = Vector2(140, 40)
	btn_export_png.pressed.connect(func():
		var user_dir = OS.get_system_dir(OS.SYSTEM_DIR_DESKTOP)
		var file_path = user_dir + "/MembershipCard_" + str(person_data.get("human_id", "PRT")) + ".png"
		var err = MembershipCardEngine.export_image_to_png(card_img, file_path)
		if err == OK:
			title.text = "✅ Saved to Desktop: " + file_path.get_file()
	)
	btn_hbox.add_child(btn_export_png)

	var btn_export_pdf = Button.new()
	btn_export_pdf.text = "📄 Export PDF"
	btn_export_pdf.custom_minimum_size = Vector2(140, 40)
	btn_export_pdf.pressed.connect(func():
		var user_dir = OS.get_system_dir(OS.SYSTEM_DIR_DESKTOP)
		var file_path = user_dir + "/MembershipCard_" + str(person_data.get("human_id", "PRT")) + ".png"
		MembershipCardEngine.export_image_to_png(card_img, file_path)
		title.text = "✅ Saved PDF/Image to Desktop: " + file_path.get_file()
	)
	btn_hbox.add_child(btn_export_pdf)

	var btn_print = Button.new()
	btn_print.text = "🖨️ Print Card"
	btn_print.custom_minimum_size = Vector2(140, 40)
	btn_print.pressed.connect(func():
		if is_queue_mode and queue_controller:
			queue_controller.complete_current_item([person_data.get("id")])
			if header_bar_instance and header_bar_instance.has_method("update_progress"):
				header_bar_instance.update_progress(queue_controller.current_index, queue_controller.get_remaining_count())
		else:
			db.execute("UPDATE card_print_queue SET status = 'printed', printed_at = datetime('now') WHERE person_id = ?;", [person_data.get("id")])
		title.text = "✅ Print Job Sent Successfully (Status: Printed)"
		refresh_queue_list()
	)
	btn_hbox.add_child(btn_print)

	var spacer = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_hbox.add_child(spacer)

	var btn_close = Button.new()
	btn_close.text = "Close"
	btn_close.custom_minimum_size = Vector2(100, 40)
	btn_close.pressed.connect(func(): preview_layer.queue_free())
	btn_hbox.add_child(btn_close)

	dvbox.add_child(btn_hbox)
	add_child(preview_layer)

func _print_all_pending() -> void:
	db.execute("UPDATE card_print_queue SET status = 'printed', printed_at = datetime('now') WHERE status = 'pending';")
	refresh_queue_list()

func _mark_all_printed() -> void:
	db.execute("UPDATE card_print_queue SET status = 'printed', printed_at = datetime('now');")
	refresh_queue_list()

func _clear_printed_items() -> void:
	db.execute("DELETE FROM card_print_queue WHERE status = 'printed';")
	refresh_queue_list()
