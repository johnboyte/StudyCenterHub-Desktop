extends "res://app/scenes/standard_page_container.gd"

## Communications Hub View Controller (COM-SPR1-001 / COM-SPR1-002)
## Complies with [PD-001] (Offline Storage & Outbox) and [PD-008] (Warm & Welcoming Design System).

const SQLiteDatabaseScript = preload("res://src/infrastructure/database/sqlite_database.gd")
const MigrationsRunnerScript = preload("res://src/infrastructure/database/migrations_runner.gd")
const CommunicationsServiceScript = preload("res://src/domain/communications/communications_service.gd")
const WorkQueueHeaderBarScene = preload("res://app/scenes/components/work_queue_header_bar.tscn")
const QueueControllerScript = preload("res://src/domain/work_queue/queue_controller.gd")
const QueueRegistryScript = preload("res://src/domain/work_queue/queue_registry.gd")

var db: RefCounted:
	set(value):
		db = value
		if db and is_node_ready():
			com_service = CommunicationsServiceScript.new(db)
			_populate_dropdowns()
			_refresh_all_feeds()

var com_service: RefCounted
var person_list: Array = []
var template_list: Array = []
var staff_list: Array = []
var _selected_phone_filter: String = ""
var _active_person_id: int = -1  # linked_person_id of current supervisor
var _active_supervisor_name: String = ""

# Queue Mode Members
var is_queue_mode: bool = false
var active_queue_id: String = ""
var queue_controller: RefCounted = null
var header_bar_instance: Control = null
var queue_card_container: PanelContainer = null

@onready var channel_dropdown: OptionButton = %ChannelDropdown
@onready var recipient_dropdown: OptionButton = %RecipientDropdown
@onready var template_dropdown: OptionButton = %TemplateDropdown
@onready var btn_send_message: Button = %BtnSendMessage
@onready var message_body_edit: TextEdit = %MessageBodyEdit
@onready var composer_card: PanelContainer = %ComposerCard
@onready var voicemail_card: PanelContainer = %VoicemailCard
@onready var threads_card: PanelContainer = %ThreadsCard
@onready var log_card: PanelContainer = %LogCard

func _ready() -> void:
	_init_database()
	_style_card()
	_populate_dropdowns()
	_connect_signals()
	_refresh_all_feeds()

func receive_navigation_context(params: Dictionary) -> void:
	if params.get("queue_mode", false) == true:
		var qid = params.get("queue_id", "")
		if qid == "overdue_callbacks" or qid == "unanswered_messages":
			configure_queue_mode(params)
		else:
			_clear_queue_mode()
	else:
		_clear_queue_mode()

func configure_queue_mode(params: Dictionary = {}) -> void:
	is_queue_mode = true
	active_queue_id = params.get("queue_id", "overdue_callbacks")

	if params.has("queue_controller") and params["queue_controller"] != null:
		queue_controller = params["queue_controller"]
	else:
		queue_controller = QueueControllerScript.new(db)

	if queue_controller:
		if db: queue_controller.db = db
		if queue_controller.active_queue_id != active_queue_id or queue_controller.active_items.size() == 0:
			queue_controller.start_queue(active_queue_id)

	_attach_header_bar()
	_refresh_queue_view()

func _get_main_vbox() -> VBoxContainer:
	if has_node("MarginContainer/MainVBox"):
		return $MarginContainer/MainVBox as VBoxContainer
	elif has_node("MarginContainer/VBoxContainer"):
		return $MarginContainer/VBoxContainer as VBoxContainer
	return null

func _get_std_hdr() -> Control:
	var vbox = _get_main_vbox()
	if vbox:
		if vbox.has_node("HeaderVBox"):
			return vbox.get_node("HeaderVBox") as Control
		elif vbox.has_node("HeaderBar"):
			return vbox.get_node("HeaderBar") as Control
		elif vbox.has_node("HeaderContainer"):
			return vbox.get_node("HeaderContainer") as Control
	return null

func _attach_header_bar() -> void:
	if header_bar_instance: return

	var parent_container = _get_main_vbox()
	if not parent_container:
		parent_container = get_child(0) if get_child_count() > 0 else self

	if parent_container:
		header_bar_instance = WorkQueueHeaderBarScene.instantiate()
		parent_container.add_child(header_bar_instance)
		if parent_container.has_method("move_child"):
			parent_container.move_child(header_bar_instance, 0)

		# Hide standard page header during active Queue Mode to eliminate header overlap
		var std_hdr = _get_std_hdr()
		if std_hdr:
			std_hdr.visible = false

		var cur_idx = queue_controller.current_index if queue_controller else 0
		var rem_count = queue_controller.get_remaining_count() if queue_controller else 0
		var def = QueueRegistryScript.get_definition(active_queue_id)
		var q_title = def.get("title", "Work Queue")
		header_bar_instance.configure_header(q_title, cur_idx, rem_count)
		header_bar_instance.pause_requested.connect(_on_queue_pause)
		header_bar_instance.exit_requested.connect(_on_queue_exit)

func _clear_queue_mode() -> void:
	is_queue_mode = false
	active_queue_id = ""
	if header_bar_instance:
		header_bar_instance.queue_free()
		header_bar_instance = null
	if queue_card_container:
		queue_card_container.queue_free()
		queue_card_container = null

	# Restore standard page header upon exiting Queue Mode
	var std_hdr = _get_std_hdr()
	if std_hdr:
		std_hdr.visible = true

func _on_queue_pause() -> void:
	if header_bar_instance and queue_controller:
		header_bar_instance.update_progress(queue_controller.current_index, queue_controller.get_remaining_count())

func _on_queue_exit() -> void:
	if queue_controller:
		queue_controller.end_session()
	_clear_queue_mode()

func _refresh_queue_view() -> void:
	if not is_queue_mode: return

	var def = QueueRegistryScript.get_definition(active_queue_id)
	var q_title = def.get("title", "Work Queue")
	var cur_idx = queue_controller.current_index if queue_controller else 0
	var rem_count = queue_controller.get_remaining_count() if queue_controller else 0

	if header_bar_instance:
		header_bar_instance.update_progress(cur_idx, rem_count)

	if not queue_card_container:
		queue_card_container = PanelContainer.new()
		var parent_container = _get_main_vbox()
		if not parent_container:
			parent_container = get_child(0) if get_child_count() > 0 else self
		if parent_container:
			parent_container.add_child(queue_card_container)
			if parent_container.has_method("move_child") and header_bar_instance:
				parent_container.move_child(queue_card_container, 1)

	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.98, 0.99, 1.0, 1.0)
	style.border_width_left = 1; style.border_width_top = 1; style.border_width_right = 1; style.border_width_bottom = 1
	style.border_color = Color(0.12, 0.53, 0.90, 1.0)
	style.corner_radius_top_left = 10; style.corner_radius_top_right = 10; style.corner_radius_bottom_left = 10; style.corner_radius_bottom_right = 10
	style.content_margin_left = 18; style.content_margin_top = 16; style.content_margin_right = 18; style.content_margin_bottom = 16
	queue_card_container.add_theme_stylebox_override("panel", style)

	for child in queue_card_container.get_children():
		queue_card_container.remove_child(child)
		child.queue_free()

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	queue_card_container.add_child(vbox)

	if rem_count == 0 or not queue_controller:
		var empty_lbl = Label.new()
		empty_lbl.text = "✨ Queue Complete! All items in " + q_title + " have been resolved."
		empty_lbl.add_theme_font_size_override("font_size", 16)
		empty_lbl.add_theme_color_override("font_color", Color(0.18, 0.55, 0.35, 1.0))
		vbox.add_child(empty_lbl)

		var exit_btn = Button.new()
		exit_btn.text = "Return to Standard Communications"
		exit_btn.custom_minimum_size = Vector2(240, 36)
		exit_btn.pressed.connect(_on_queue_exit)
		vbox.add_child(exit_btn)
		return

	var current_item = queue_controller.get_current_item()
	if current_item.is_empty():
		return

	var item_id = current_item.get("id", 0)
	var caller = current_item.get("caller_name", "Unknown Caller")
	var phone = current_item.get("from_number", current_item.get("caller_phone", ""))
	var text = current_item.get("message_text", current_item.get("transcription", ""))
	var due = current_item.get("due_date", "")

	# Structured Header Hierarchy: Current Person & Contact
	var info_grid = VBoxContainer.new()
	info_grid.add_theme_constant_override("separation", 4)

	var person_lbl = Label.new()
	person_lbl.text = "Current Person: " + str(caller)
	person_lbl.add_theme_font_size_override("font_size", 16)
	person_lbl.add_theme_color_override("font_color", Color(0.08, 0.12, 0.18, 1.0))
	info_grid.add_child(person_lbl)

	if phone != "":
		var phone_lbl = Label.new()
		phone_lbl.text = "Contact: " + str(phone)
		phone_lbl.add_theme_font_size_override("font_size", 14)
		phone_lbl.add_theme_color_override("font_color", Color(0.35, 0.42, 0.52, 1.0))
		info_grid.add_child(phone_lbl)

	if due != "":
		var due_lbl = Label.new()
		due_lbl.text = "⏰ Callback Due: " + str(due)
		due_lbl.add_theme_font_size_override("font_size", 13)
		due_lbl.add_theme_color_override("font_color", Color(0.85, 0.25, 0.20, 1.0))
		info_grid.add_child(due_lbl)

	vbox.add_child(info_grid)

	if text != "":
		var txt_lbl = Label.new()
		txt_lbl.text = "Message: \"" + str(text) + "\""
		txt_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
		txt_lbl.add_theme_font_size_override("font_size", 14)
		txt_lbl.add_theme_color_override("font_color", Color(0.20, 0.25, 0.32, 1.0))
		vbox.add_child(txt_lbl)

	var btn_hbox = HBoxContainer.new()
	btn_hbox.add_theme_constant_override("separation", 12)
	vbox.add_child(btn_hbox)

	var comp_btn = Button.new()
	comp_btn.text = "✅ Mark Completed & Next"
	comp_btn.custom_minimum_size = Vector2(200, 38)
	var btn_st = StyleBoxFlat.new()
	btn_st.bg_color = Color(0.12, 0.53, 0.90, 1.0)
	btn_st.corner_radius_top_left = 6; btn_st.corner_radius_top_right = 6; btn_st.corner_radius_bottom_left = 6; btn_st.corner_radius_bottom_right = 6
	comp_btn.add_theme_stylebox_override("normal", btn_st)
	comp_btn.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 1.0))
	comp_btn.pressed.connect(func(): _on_complete_queue_item(item_id))
	btn_hbox.add_child(comp_btn)

func _on_complete_queue_item(item_id: int) -> void:
	if not queue_controller: return
	var success = queue_controller.complete_current_item([item_id])
	if success:
		_refresh_queue_view()
		_refresh_all_feeds()

func _init_database() -> void:
	if not db:
		db = SQLiteDatabaseScript.new()
		var mig = MigrationsRunnerScript.new(db)
		mig.run_migrations()
	if not com_service:
		com_service = CommunicationsServiceScript.new(db)

func _style_card() -> void:
	var style = StyleBoxFlat.new()
	style.bg_color = Color(1.0, 1.0, 1.0, 1.0)
	style.border_width_left = 1; style.border_width_top = 1; style.border_width_right = 1; style.border_width_bottom = 1
	style.border_color = Color(0.88, 0.91, 0.95, 1.0)
	style.corner_radius_top_left = 12; style.corner_radius_top_right = 12; style.corner_radius_bottom_left = 12; style.corner_radius_bottom_right = 12
	style.content_margin_left = 18; style.content_margin_top = 16; style.content_margin_right = 18; style.content_margin_bottom = 16
	if composer_card: composer_card.add_theme_stylebox_override("panel", style.duplicate())
	if log_card: log_card.add_theme_stylebox_override("panel", style.duplicate())
	if voicemail_card: voicemail_card.add_theme_stylebox_override("panel", style.duplicate())
	if threads_card: threads_card.add_theme_stylebox_override("panel", style.duplicate())

	var btn_st = StyleBoxFlat.new()
	btn_st.bg_color = _get_active_theme_color()
	btn_st.corner_radius_top_left = 6; btn_st.corner_radius_top_right = 6; btn_st.corner_radius_bottom_left = 6; btn_st.corner_radius_bottom_right = 6
	btn_send_message.add_theme_stylebox_override("normal", btn_st)
	btn_send_message.add_theme_stylebox_override("hover", btn_st)
	btn_send_message.add_theme_stylebox_override("pressed", btn_st)

	# High contrast dropdown styling with 16pt font size
	var dd_st = StyleBoxFlat.new()
	dd_st.bg_color = Color(0.96, 0.97, 0.99, 1.0)
	dd_st.border_width_left = 1; dd_st.border_width_top = 1; dd_st.border_width_right = 1; dd_st.border_width_bottom = 1
	dd_st.border_color = Color(0.78, 0.82, 0.88, 1.0)
	dd_st.corner_radius_top_left = 6; dd_st.corner_radius_top_right = 6; dd_st.corner_radius_bottom_left = 6; dd_st.corner_radius_bottom_right = 6
	dd_st.content_margin_left = 12; dd_st.content_margin_top = 8; dd_st.content_margin_right = 12; dd_st.content_margin_bottom = 8

	for dd in [channel_dropdown, recipient_dropdown, template_dropdown]:
		if dd:
			dd.add_theme_stylebox_override("normal", dd_st)
			dd.add_theme_stylebox_override("hover", dd_st)
			dd.add_theme_stylebox_override("pressed", dd_st)
			dd.add_theme_stylebox_override("focus", dd_st)
			dd.add_theme_font_size_override("font_size", 16)
			dd.add_theme_color_override("font_color", Color(0.08, 0.12, 0.18, 1.0))
			dd.add_theme_color_override("font_hover_color", Color(0.08, 0.12, 0.18, 1.0))
			dd.add_theme_color_override("font_pressed_color", Color(0.08, 0.12, 0.18, 1.0))

	# High contrast message composer edit box with 18pt font size
	if message_body_edit:
		var edit_st = StyleBoxFlat.new()
		edit_st.bg_color = Color(0.98, 0.99, 1.0, 1.0)
		edit_st.border_width_left = 1; edit_st.border_width_top = 1; edit_st.border_width_right = 1; edit_st.border_width_bottom = 1
		edit_st.border_color = Color(0.78, 0.82, 0.88, 1.0)
		edit_st.corner_radius_top_left = 6; edit_st.corner_radius_top_right = 6; edit_st.corner_radius_bottom_left = 6; edit_st.corner_radius_bottom_right = 6
		edit_st.content_margin_left = 14; edit_st.content_margin_top = 10; edit_st.content_margin_right = 14; edit_st.content_margin_bottom = 10
		message_body_edit.add_theme_stylebox_override("normal", edit_st)
		message_body_edit.add_theme_stylebox_override("focus", edit_st)
		message_body_edit.add_theme_font_size_override("font_size", 18)
		message_body_edit.add_theme_color_override("font_color", Color(0.08, 0.12, 0.18, 1.0))
		message_body_edit.add_theme_color_override("font_placeholder_color", Color(0.35, 0.45, 0.58, 1.0))

func _get_active_theme_color() -> Color:
	var idx = 0
	if db:
		var res = db.execute("SELECT setting_value FROM app_settings WHERE setting_key = 'ORG_ACCENT_INDEX' LIMIT 1;")
		if res["success"] and res["data"].size() > 0:
			idx = int(res["data"][0].get("setting_value", "0"))

	if idx == 0:
		return Color(0.596, 0.192, 0.255, 1.0) # AU Crimson Red #983141
	elif idx == 1:
		return Color(0.88, 0.35, 0.21, 1.0) # Warm Terracotta #E05A36
	elif idx == 2:
		return Color(0.10, 0.15, 0.21, 1.0) # Deep Navy #1A2536
	elif idx == 3:
		return Color(0.18, 0.49, 0.20, 1.0) # Forest Green #2E7D32
	elif idx == 4:
		return Color(0.42, 0.11, 0.60, 1.0) # Royal Purple #6A1B9A
	return Color(0.596, 0.192, 0.255, 1.0)

func _populate_dropdowns() -> void:
	if not db: return
	if not com_service: com_service = CommunicationsServiceScript.new(db)

	channel_dropdown.clear()
	channel_dropdown.add_item("SMS Text", 0)
	channel_dropdown.add_item("Phone Call", 1)
	channel_dropdown.add_item("Email", 2)
	channel_dropdown.add_item("Push Alert", 3)

	recipient_dropdown.clear()
	person_list.clear()
	var p_res = db.execute("SELECT id, person_uuid, human_id, first_name, last_name, phone FROM people ORDER BY last_name ASC, first_name ASC;")
	if p_res["success"] and p_res["data"].size() > 0:
		person_list = p_res["data"]
		for i in range(person_list.size()):
			var p = person_list[i]
			var fn = str(p.get("first_name")) if p.get("first_name") != null else ""
			var ln = str(p.get("last_name")) if p.get("last_name") != null else ""
			var name = (fn + " " + ln).strip_edges() + " (" + str(p.get("human_id")) + ")"
			recipient_dropdown.add_item(name, i)

	template_dropdown.clear()
	template_dropdown.add_item("-- Select Template --", 0)
	template_list = com_service.get_templates()
	for i in range(template_list.size()):
		var t = template_list[i]
		template_dropdown.add_item(str(t.get("title", "")), i + 1)

func _connect_signals() -> void:
	if btn_send_message: btn_send_message.pressed.connect(_on_send_message_pressed)
	if template_dropdown: template_dropdown.item_selected.connect(_on_template_selected)
	if channel_dropdown: channel_dropdown.item_selected.connect(_on_channel_selected)

func _on_template_selected(index: int) -> void:
	if index <= 0 or index - 1 >= template_list.size(): return
	var tmpl = template_list[index - 1]
	message_body_edit.text = str(tmpl.get("body_template", ""))

func _on_channel_selected(index: int) -> void:
	var ch = channel_dropdown.get_item_text(index)
	if ch == "Phone Call":
		btn_send_message.text = "📞 Place Call"
		if message_body_edit: message_body_edit.placeholder_text = "Enter optional call agenda or notes before dialing..."
	else:
		btn_send_message.text = "✉️ Send Message"
		if message_body_edit: message_body_edit.placeholder_text = "Type your message body or select a pre-built template..."

func _on_send_message_pressed() -> void:
	if person_list.size() == 0: return

	var sel_p_idx = recipient_dropdown.selected
	if sel_p_idx < 0 or sel_p_idx >= person_list.size(): return
	var recipient = person_list[sel_p_idx]

	var channel = channel_dropdown.get_item_text(channel_dropdown.selected)
	var body = message_body_edit.text.strip_edges()

	if channel == "Phone Call":
		_initiate_call_dialog(recipient, body)
		return

	if body == "": return

	var res = com_service.send_message_atomic(recipient, channel, body, "John Smith")
	if res["success"]:
		print("Message sent successfully: ", res["message_uuid"])
		message_body_edit.text = ""
		_refresh_all_feeds()

func _initiate_call_dialog(recipient: Dictionary, notes: String) -> void:
	var fn = str(recipient.get("first_name", ""))
	var ln = str(recipient.get("last_name", ""))
	var name = (fn + " " + ln).strip_edges()
	var phone = str(recipient.get("phone", "")).strip_edges()
	if phone == "": phone = "No phone on file"

	var backdrop = ColorRect.new()
	backdrop.color = Color(0.08, 0.12, 0.18, 0.6)
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)

	var center = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.add_child(center)

	var card = PanelContainer.new()
	var card_st = StyleBoxFlat.new()
	card_st.bg_color = Color(1.0, 1.0, 1.0, 1.0)
	card_st.border_width_left = 1; card_st.border_width_top = 1; card_st.border_width_right = 1; card_st.border_width_bottom = 1
	card_st.border_color = Color(0.78, 0.82, 0.88, 1.0)
	card_st.corner_radius_top_left = 12; card_st.corner_radius_top_right = 12; card_st.corner_radius_bottom_left = 12; card_st.corner_radius_bottom_right = 12
	card_st.content_margin_left = 24; card_st.content_margin_top = 22; card_st.content_margin_right = 24; card_st.content_margin_bottom = 22
	card.add_theme_stylebox_override("panel", card_st)
	center.add_child(card)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	vbox.custom_minimum_size = Vector2(440, 260)
	card.add_child(vbox)

	var title = Label.new()
	title.text = "📞 Initiate Call — " + name
	title.add_theme_font_size_override("font_size", 17)
	title.add_theme_color_override("font_color", _get_active_theme_color())
	vbox.add_child(title)

	var phone_lbl = Label.new()
	phone_lbl.text = "Target Phone: " + phone
	phone_lbl.add_theme_font_size_override("font_size", 14)
	phone_lbl.add_theme_color_override("font_color", Color(0.20, 0.25, 0.32, 1.0))
	vbox.add_child(phone_lbl)

	var desc = Label.new()
	desc.text = "Choose how you want to connect this call:"
	desc.add_theme_font_size_override("font_size", 12)
	desc.add_theme_color_override("font_color", Color(0.40, 0.45, 0.55, 1.0))
	vbox.add_child(desc)

	# Button 1: Call from Mac / Computer
	var btn_mac = Button.new()
	btn_mac.text = "💻 Call from Computer (Mac Phone / FaceTime / Web)"
	btn_mac.custom_minimum_size = Vector2(0, 36)
	btn_mac.add_theme_font_size_override("font_size", 12)
	var mac_st = StyleBoxFlat.new()
	mac_st.bg_color = Color(0.12, 0.53, 0.90, 1.0)
	mac_st.corner_radius_top_left = 6; mac_st.corner_radius_top_right = 6; mac_st.corner_radius_bottom_left = 6; mac_st.corner_radius_bottom_right = 6
	btn_mac.add_theme_stylebox_override("normal", mac_st)
	btn_mac.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 1.0))
	var _target_phone = phone
	btn_mac.pressed.connect(func():
		backdrop.queue_free()
		if _target_phone != "" and _target_phone != "No phone on file":
			OS.shell_open("tel:" + _target_phone)
		com_service.send_message_atomic(recipient, "Phone Call (Computer)", notes if notes != "" else "Initiated outbound call from Mac computer", "John Smith")
		_refresh_all_feeds()
	)
	vbox.add_child(btn_mac)

	# Button 2: Call via Twilio Phone Bridge
	var btn_twilio = Button.new()
	btn_twilio.text = "📱 Call via Phone (Twilio Relay Outbound Bridge)"
	btn_twilio.custom_minimum_size = Vector2(0, 36)
	btn_twilio.add_theme_font_size_override("font_size", 12)
	var twil_st = StyleBoxFlat.new()
	twil_st.bg_color = Color(0.18, 0.55, 0.35, 1.0)
	twil_st.corner_radius_top_left = 6; twil_st.corner_radius_top_right = 6; twil_st.corner_radius_bottom_left = 6; twil_st.corner_radius_bottom_right = 6
	btn_twilio.add_theme_stylebox_override("normal", twil_st)
	btn_twilio.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 1.0))
	btn_twilio.pressed.connect(func():
		backdrop.queue_free()
		OS.alert("Bridging call to " + name + " (" + _target_phone + ") via Twilio cloud relay.", "Phone Callback")
		com_service.send_message_atomic(recipient, "Phone Call (Twilio)", notes if notes != "" else "Bridged outbound call via Twilio Relay", "John Smith")
		_refresh_all_feeds()
	)
	vbox.add_child(btn_twilio)

	# Cancel
	var btn_cancel = Button.new()
	btn_cancel.text = "Cancel"
	btn_cancel.pressed.connect(func(): backdrop.queue_free())
	vbox.add_child(btn_cancel)

func _refresh_all_feeds() -> void:
	_refresh_communications_log()
	_refresh_voicemail_inbox()
	_refresh_threads_feed()

func _refresh_communications_log() -> void:
	if not db: return
	if not com_service: com_service = CommunicationsServiceScript.new(db)

	for child in log_card.get_children(): child.free()

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)

	var title_lbl = Label.new()
	title_lbl.text = "Recent Sent Communications & Delivery Outbox Log"
	title_lbl.add_theme_font_size_override("font_size", 20)
	title_lbl.add_theme_color_override("font_color", Color(0.08, 0.12, 0.18, 1.0))
	vbox.add_child(title_lbl)

	var logs = com_service.get_recent_communications()
	if logs.size() > 0:
		for item in logs:
			var name = str(item.get("recipient_name", ""))
			var ch = str(item.get("channel", ""))
			var body = str(item.get("message_body", ""))
			var sent = str(item.get("created_at", ""))

			var row = Label.new()
			row.text = "  📤 " + name + " • " + ch + " | \"" + body.left(60) + "...\" [" + sent + "]"
			row.add_theme_font_size_override("font_size", 16)
			row.add_theme_color_override("font_color", Color(0.12, 0.16, 0.22, 1.0))
			vbox.add_child(row)
	else:
		var empty_lbl = Label.new()
		empty_lbl.text = "No sent messages logged yet."
		empty_lbl.add_theme_font_size_override("font_size", 17)
		empty_lbl.add_theme_color_override("font_color", Color(0.35, 0.45, 0.58, 1.0))
		vbox.add_child(empty_lbl)

	log_card.add_child(vbox)

func _refresh_voicemail_inbox() -> void:
	if not db: return
	if not com_service: com_service = CommunicationsServiceScript.new(db)

	# Fetch active supervisor name for privacy checks
	_active_supervisor_name = "John Boyte"
	var sup_res = db.execute("SELECT setting_value FROM app_settings WHERE setting_key = 'ACTIVE_SUPERVISOR' LIMIT 1;")
	if sup_res["success"] and sup_res["data"].size() > 0:
		_active_supervisor_name = str(sup_res["data"][0]["setting_value"]).strip_edges()

	for child in voicemail_card.get_children(): child.free()

	var main_vbox = VBoxContainer.new()
	main_vbox.size_flags_horizontal = SIZE_EXPAND_FILL
	main_vbox.size_flags_vertical = SIZE_EXPAND_FILL
	main_vbox.add_theme_constant_override("separation", 14)
	voicemail_card.add_child(main_vbox)

	# --- Header Title & Reminders Config panel ---
	var header_hbox = HBoxContainer.new()
	header_hbox.size_flags_horizontal = SIZE_EXPAND_FILL
	
	var title_lbl = Label.new()
	title_lbl.text = "🎙️ Communications Worksheet"
	title_lbl.add_theme_font_size_override("font_size", 20)
	title_lbl.add_theme_color_override("font_color", Color(0.08, 0.12, 0.18, 1.0))
	title_lbl.size_flags_horizontal = SIZE_EXPAND_FILL
	header_hbox.add_child(title_lbl)
	
	# Reminders quick panel
	var rem_panel = PanelContainer.new()
	var rem_st = StyleBoxFlat.new()
	rem_st.bg_color = Color(0.96, 0.97, 0.99, 1.0)
	rem_st.border_width_left = 1; rem_st.border_width_top = 1; rem_st.border_width_right = 1; rem_st.border_width_bottom = 1
	rem_st.border_color = Color(0.88, 0.90, 0.93, 1.0)
	rem_st.corner_radius_top_left = 6; rem_st.corner_radius_top_right = 6; rem_st.corner_radius_bottom_left = 6; rem_st.corner_radius_bottom_right = 6
	rem_st.content_margin_left = 10; rem_st.content_margin_top = 6; rem_st.content_margin_right = 10; rem_st.content_margin_bottom = 6
	rem_panel.add_theme_stylebox_override("panel", rem_st)
	
	var rem_hbox = HBoxContainer.new()
	rem_hbox.add_theme_constant_override("separation", 12)
	
	var check_digest = CheckButton.new()
	check_digest.text = "Daily digest at 5 PM"
	check_digest.add_theme_font_size_override("font_size", 12)
	var q_digest = db.execute("SELECT setting_value FROM app_settings WHERE setting_key = 'REMINDER_DAILY_DIGEST' LIMIT 1;")
	check_digest.button_pressed = q_digest["success"] and q_digest["data"].size() > 0 and q_digest["data"][0]["setting_value"] == "1"
	
	var check_alert = CheckButton.new()
	check_alert.text = "Alert unassigned > 2h"
	check_alert.add_theme_font_size_override("font_size", 12)
	var q_alert = db.execute("SELECT setting_value FROM app_settings WHERE setting_key = 'REMINDER_UNASSIGNED_ALERT' LIMIT 1;")
	check_alert.button_pressed = q_alert["success"] and q_alert["data"].size() > 0 and q_alert["data"][0]["setting_value"] == "1"
	
	check_digest.toggled.connect(func(val): db.execute("INSERT OR REPLACE INTO app_settings (setting_key, setting_value) VALUES ('REMINDER_DAILY_DIGEST', ?);", [str(1 if val else 0)]))
	check_alert.toggled.connect(func(val): db.execute("INSERT OR REPLACE INTO app_settings (setting_key, setting_value) VALUES ('REMINDER_UNASSIGNED_ALERT', ?);", [str(1 if val else 0)]))
	
	rem_hbox.add_child(check_digest); rem_hbox.add_child(check_alert)
	rem_panel.add_child(rem_hbox)
	header_hbox.add_child(rem_panel)
	main_vbox.add_child(header_hbox)

	# --- Kanban Lanes Layout ---
	var kanban_hbox = HBoxContainer.new()
	kanban_hbox.size_flags_horizontal = SIZE_EXPAND_FILL
	kanban_hbox.size_flags_vertical = SIZE_EXPAND_FILL
	kanban_hbox.add_theme_constant_override("separation", 12)
	
	var lanes = [
		{"key": "new", "name": "📥 Inbox / New", "color": Color(0.24, 0.45, 0.75, 1.0)},
		{"key": "in_progress", "name": "⚙️ In Progress", "color": Color(0.85, 0.55, 0.15, 1.0)},
		{"key": "waiting", "name": "⏳ Waiting", "color": Color(0.45, 0.50, 0.58, 1.0)},
		{"key": "completed", "name": "✅ Completed", "color": Color(0.18, 0.55, 0.35, 1.0)}
	]
	
	var col_containers = {}
	
	for lane in lanes:
		var lane_key = lane["key"]
		
		var col_panel = VoicemailKanbanColumn.new(lane_key, self)
		col_panel.size_flags_horizontal = SIZE_EXPAND_FILL
		col_panel.size_flags_vertical = SIZE_EXPAND_FILL
		var col_st = StyleBoxFlat.new()
		col_st.bg_color = Color(0.95, 0.96, 0.98, 1.0)
		col_st.corner_radius_top_left = 8; col_st.corner_radius_top_right = 8; col_st.corner_radius_bottom_left = 8; col_st.corner_radius_bottom_right = 8
		col_st.content_margin_left = 8; col_st.content_margin_top = 8; col_st.content_margin_right = 8; col_st.content_margin_bottom = 8
		col_panel.add_theme_stylebox_override("panel", col_st)
		
		var col_vbox = VBoxContainer.new()
		col_vbox.size_flags_horizontal = SIZE_EXPAND_FILL
		col_vbox.size_flags_vertical = SIZE_EXPAND_FILL
		col_vbox.mouse_filter = Control.MOUSE_FILTER_PASS
		col_vbox.add_theme_constant_override("separation", 8)
		col_panel.add_child(col_vbox)
		
		# Column title / Header
		var col_hdr_lbl = Label.new()
		col_hdr_lbl.text = lane["name"]
		col_hdr_lbl.add_theme_font_size_override("font_size", 14)
		col_hdr_lbl.add_theme_color_override("font_color", lane["color"])
		col_vbox.add_child(col_hdr_lbl)
		
		# Scrollable cards container (Show up to 5 cards visible, infinite scroll beyond 5)
		var col_scroll = ScrollContainer.new()
		col_scroll.size_flags_horizontal = SIZE_EXPAND_FILL
		col_scroll.size_flags_vertical = SIZE_EXPAND_FILL
		col_scroll.custom_minimum_size = Vector2(0, 520)
		col_scroll.mouse_filter = Control.MOUSE_FILTER_PASS
		col_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		col_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
		col_vbox.add_child(col_scroll)
		
		var cards_vbox = VBoxContainer.new()
		cards_vbox.size_flags_horizontal = SIZE_EXPAND_FILL
		cards_vbox.mouse_filter = Control.MOUSE_FILTER_PASS
		cards_vbox.add_theme_constant_override("separation", 8)
		col_scroll.add_child(cards_vbox)
		
		col_containers[lane_key] = cards_vbox
		kanban_hbox.add_child(col_panel)

	# Fetch voicemails & SMS work items
	var vms = com_service.get_voicemails()
	
	# Priority weight helper for sorting (Emergency=0, High=1, Medium=2, Low=3)
	var _get_priority_weight = func(p_str: String) -> int:
		match p_str.strip_edges().to_lower():
			"emergency": return 0
			"high": return 1
			"medium": return 2
			"low": return 3
			_: return 2

	# Sort work items: Primary by Urgency Flag (Emergency > High > Medium > Low), Secondary by Date (Newest first)
	vms.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var w_a = _get_priority_weight.call(str(a.get("priority", "Medium")))
		var w_b = _get_priority_weight.call(str(b.get("priority", "Medium")))
		if w_a != w_b:
			return w_a < w_b
		var date_a = str(a.get("created_at", ""))
		var date_b = str(b.get("created_at", ""))
		return date_a > date_b
	)
	
	# Update column counts in headers
	var counts = {"new": 0, "in_progress": 0, "waiting": 0, "completed": 0}
	for vm in vms:
		var status = str(vm.get("status", "new"))
		if counts.has(status): counts[status] += 1
		
	for i in range(lanes.size()):
		var lane = lanes[i]
		var col_panel = kanban_hbox.get_child(i) as PanelContainer
		if col_panel:
			var col_vbox = col_panel.get_child(0) as VBoxContainer
			if col_vbox:
				var col_hdr_lbl = col_vbox.get_child(0) as Label
				if col_hdr_lbl:
					col_hdr_lbl.text = lane["name"] + " (" + str(counts[lane["key"]]) + ")"

	for vm in vms:
		var vm_uuid = str(vm.get("item_uuid", ""))
		var item_type = str(vm.get("item_type", "voicemail"))
		var caller_num = _clean_str(vm.get("caller_phone"), "")
		var caller_name = _clean_str(vm.get("caller_name"), "")
		var matched_name = _clean_str(vm.get("matched_caller_name"), "")
		var assignee_name = _clean_str(vm.get("assignee_name"), "Unassigned")
		var recording_url = _clean_str(vm.get("recording_url"), "")
		
		var has_matched_person = (matched_name != "" and matched_name != "SMS Caller" and matched_name != "Unknown Caller")
		var display_caller = ""
		if has_matched_person:
			display_caller = matched_name
		elif caller_name != "" and caller_name != "Unknown Caller" and caller_name != "SMS Caller":
			display_caller = caller_name
		else:
			display_caller = _format_phone_display(caller_num)
		
		# Type-specific display formatting
		var dur = ""
		if item_type == "voicemail":
			dur = "☎️ Call (" + str(vm.get("duration_sec", 0)) + "s)"
		else:
			dur = "💬 SMS"
			
		var transcription = _clean_str(vm.get("transcription"), "")
		var status = _clean_str(vm.get("status"), "new")
		var priority = _clean_str(vm.get("priority"), "Medium")
		
		# --- Privacy Check ---
		# General (unassigned) messages or messages assigned to current active supervisor are accessible directly.
		# Messages assigned to other staff members require PIN verification.
		var is_general = (assignee_name == "Unassigned" or assignee_name == "")
		var is_for_me = (assignee_name.to_lower() == _active_supervisor_name.to_lower())
		var is_accessible = (is_general or is_for_me)
		
		var card = VoicemailKanbanCard.new(vm_uuid, item_type, caller_num, self, status)
		card.custom_minimum_size = Vector2(0, 92)
		card.size_flags_horizontal = SIZE_EXPAND_FILL
		var card_st = StyleBoxFlat.new()
		card_st.bg_color = Color(1.0, 1.0, 1.0, 1.0)
		card_st.border_width_left = 5
		card_st.border_width_top = 1
		card_st.border_width_right = 1
		card_st.border_width_bottom = 1
		
		if priority == "Emergency": card_st.border_color = Color(0.96, 0.26, 0.21, 1.0)
		elif priority == "High": card_st.border_color = Color(1.0, 0.60, 0.0, 1.0)
		elif priority == "Medium": card_st.border_color = Color(0.12, 0.53, 0.90, 1.0)
		else: card_st.border_color = Color(0.62, 0.62, 0.62, 1.0)
		
		card_st.corner_radius_top_left = 6; card_st.corner_radius_top_right = 6; card_st.corner_radius_bottom_left = 6; card_st.corner_radius_bottom_right = 6
		card_st.content_margin_left = 10; card_st.content_margin_top = 8; card_st.content_margin_right = 10; card_st.content_margin_bottom = 8
		card.add_theme_stylebox_override("panel", card_st)
		
		var card_vbox = VBoxContainer.new()
		card_vbox.mouse_filter = Control.MOUSE_FILTER_PASS
		card_vbox.add_theme_constant_override("separation", 5)
		card.add_child(card_vbox)
		
		# Row 1: Caller name + type badge
		var title_hbox = HBoxContainer.new()
		title_hbox.mouse_filter = Control.MOUSE_FILTER_PASS
		var caller_lbl = Label.new()
		caller_lbl.text = display_caller
		caller_lbl.add_theme_font_size_override("font_size", 14)
		caller_lbl.add_theme_color_override("font_color", Color(0.08, 0.12, 0.18, 1.0))
		caller_lbl.size_flags_horizontal = SIZE_EXPAND_FILL
		
		var time_lbl = Label.new()
		time_lbl.text = dur
		time_lbl.add_theme_font_size_override("font_size", 11)
		time_lbl.add_theme_color_override("font_color", Color(0.50, 0.55, 0.65, 1.0))
		
		title_hbox.add_child(caller_lbl); title_hbox.add_child(time_lbl)
		card_vbox.add_child(title_hbox)
		
		# Row 2: Phone number
		var phone_lbl = Label.new()
		phone_lbl.text = "📱 " + (_format_phone_display(caller_num) if caller_num != "" else "No number")
		phone_lbl.add_theme_font_size_override("font_size", 11)
		phone_lbl.add_theme_color_override("font_color", Color(0.35, 0.42, 0.55, 1.0))
		card_vbox.add_child(phone_lbl)
		
		# Row 3: Transcription / message body (Hidden if protected and not signed in as recipient)
		var desc_lbl = Label.new()
		if not is_accessible:
			desc_lbl.text = "🔒 Protected Message (Assigned to " + assignee_name + ")"
			desc_lbl.add_theme_font_size_override("font_size", 12)
			desc_lbl.add_theme_color_override("font_color", Color(0.85, 0.45, 0.10, 1.0))
		else:
			if transcription != "":
				desc_lbl.text = "\"" + transcription + "\""
			else:
				desc_lbl.text = "(No transcription available)"
			desc_lbl.add_theme_font_size_override("font_size", 12)
			desc_lbl.add_theme_color_override("font_color", Color(0.20, 0.25, 0.32, 1.0) if transcription != "" else Color(0.55, 0.58, 0.65, 1.0))
		desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc_lbl.custom_minimum_size = Vector2(0, 30)
		card_vbox.add_child(desc_lbl)
		
		# Row 4: Assignee + Priority
		var badge_hbox = HBoxContainer.new()
		badge_hbox.mouse_filter = Control.MOUSE_FILTER_PASS
		var ass_lbl = Label.new()
		ass_lbl.text = "👤 " + assignee_name
		ass_lbl.add_theme_font_size_override("font_size", 11)
		ass_lbl.add_theme_color_override("font_color", Color(0.35, 0.45, 0.55, 1.0))
		ass_lbl.size_flags_horizontal = SIZE_EXPAND_FILL
		
		var pri_badge = _create_priority_badge(priority)
		badge_hbox.add_child(ass_lbl); badge_hbox.add_child(pri_badge)
		card_vbox.add_child(badge_hbox)
		
		# Row 5: Action buttons (with Play for voicemails)
		var actions_hbox = HBoxContainer.new()
		actions_hbox.mouse_filter = Control.MOUSE_FILTER_PASS
		actions_hbox.add_theme_constant_override("separation", 4)
		
		# Play button for voicemails with recording URL (Only shown if accessible)
		if is_accessible and item_type == "voicemail" and recording_url != "":
			var btn_play = Button.new()
			btn_play.text = "🔊 Play"
			btn_play.custom_minimum_size = Vector2(50, 24)
			btn_play.add_theme_font_size_override("font_size", 10)
			var play_st = StyleBoxFlat.new()
			play_st.bg_color = Color(0.12, 0.53, 0.90, 1.0)
			play_st.corner_radius_top_left = 4; play_st.corner_radius_top_right = 4; play_st.corner_radius_bottom_left = 4; play_st.corner_radius_bottom_right = 4
			play_st.content_margin_left = 6; play_st.content_margin_right = 6; play_st.content_margin_top = 2; play_st.content_margin_bottom = 2
			btn_play.add_theme_stylebox_override("normal", play_st)
			btn_play.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 1.0))
			var _target_vm = vm
			btn_play.pressed.connect(func(): _open_audio_player_dialog(_target_vm))
			actions_hbox.add_child(btn_play)

			# Transcribe button if no transcription is present
			if transcription == "" or transcription == "(No transcription available)":
				var btn_trans = Button.new()
				btn_trans.text = "✨ Transcribe"
				btn_trans.custom_minimum_size = Vector2(75, 24)
				btn_trans.add_theme_font_size_override("font_size", 10)
				var trans_st = StyleBoxFlat.new()
				trans_st.bg_color = Color(0.42, 0.11, 0.60, 1.0)
				trans_st.corner_radius_top_left = 4; trans_st.corner_radius_top_right = 4; trans_st.corner_radius_bottom_left = 4; trans_st.corner_radius_bottom_right = 4
				trans_st.content_margin_left = 6; trans_st.content_margin_right = 6; trans_st.content_margin_top = 2; trans_st.content_margin_bottom = 2
				btn_trans.add_theme_stylebox_override("normal", trans_st)
				btn_trans.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 1.0))
				var _v_uuid = vm_uuid
				var _r_url = recording_url
				btn_trans.pressed.connect(func(): _transcribe_voicemail_with_gemini(_v_uuid, _r_url, btn_trans))
				actions_hbox.add_child(btn_trans)
		
		var btn_open = Button.new(); btn_open.text = "📂 Open"; btn_open.custom_minimum_size = Vector2(45, 24); btn_open.add_theme_font_size_override("font_size", 10)
		var btn_call = Button.new(); btn_call.text = "📞 Callback"; btn_call.custom_minimum_size = Vector2(65, 24); btn_call.add_theme_font_size_override("font_size", 10)
		var btn_sms = Button.new(); btn_sms.text = "💬 Text"; btn_sms.custom_minimum_size = Vector2(45, 24); btn_sms.add_theme_font_size_override("font_size", 10)
		var btn_fwd = Button.new(); btn_fwd.text = "🔄 Forward"; btn_fwd.custom_minimum_size = Vector2(60, 24); btn_fwd.add_theme_font_size_override("font_size", 10)
		
		actions_hbox.add_child(btn_open); actions_hbox.add_child(btn_call); actions_hbox.add_child(btn_sms); actions_hbox.add_child(btn_fwd)
		
		# Add Link Contact button if caller is not matched to a person
		if not has_matched_person and caller_num != "":
			var btn_link = Button.new()
			btn_link.text = "👤 Link"
			btn_link.custom_minimum_size = Vector2(50, 24)
			btn_link.add_theme_font_size_override("font_size", 10)
			var link_st = StyleBoxFlat.new()
			link_st.bg_color = Color(0.18, 0.55, 0.35, 1.0)
			link_st.corner_radius_top_left = 4; link_st.corner_radius_top_right = 4; link_st.corner_radius_bottom_left = 4; link_st.corner_radius_bottom_right = 4
			link_st.content_margin_left = 6; link_st.content_margin_right = 6; link_st.content_margin_top = 2; link_st.content_margin_bottom = 2
			btn_link.add_theme_stylebox_override("normal", link_st)
			btn_link.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 1.0))
			var _target_num = caller_num
			btn_link.pressed.connect(func(): _open_link_contact_dialog(_target_num))
			actions_hbox.add_child(btn_link)
			
		card_vbox.add_child(actions_hbox)
		
		if is_accessible:
			btn_open.pressed.connect(func(): _open_detail_dialog(vm))
		else:
			btn_open.pressed.connect(func(): _prompt_pin_auth_dialog(vm))
			
		btn_call.pressed.connect(func():
			OS.alert("Initiating phone callback to: " + caller_num, "Phone Callback")
		)
		btn_sms.pressed.connect(func(): select_recipient_by_phone(caller_num, "SMS"))
		btn_fwd.pressed.connect(func(): _open_forward_dialog(vm_uuid, item_type))
		
		if col_containers.has(status):
			col_containers[status].add_child(card)

	main_vbox.add_child(kanban_hbox)

func _create_priority_badge(priority: String) -> PanelContainer:
	var badge = PanelContainer.new()
	var style = StyleBoxFlat.new()
	style.corner_radius_top_left = 12
	style.corner_radius_top_right = 12
	style.corner_radius_bottom_left = 12
	style.corner_radius_bottom_right = 12
	style.content_margin_left = 8
	style.content_margin_top = 2
	style.content_margin_right = 8
	style.content_margin_bottom = 2
	
	var lbl = Label.new()
	lbl.add_theme_font_size_override("font_size", 10)
	
	if priority == "Emergency":
		style.bg_color = Color(1.0, 0.90, 0.90, 1.0)
		style.border_width_left = 1; style.border_width_top = 1; style.border_width_right = 1; style.border_width_bottom = 1
		style.border_color = Color(0.96, 0.26, 0.21, 0.4)
		lbl.text = "🚨 EMERGENCY"
		lbl.add_theme_color_override("font_color", Color(0.80, 0.12, 0.12, 1.0))
	elif priority == "High":
		style.bg_color = Color(1.0, 0.95, 0.85, 1.0)
		style.border_width_left = 1; style.border_width_top = 1; style.border_width_right = 1; style.border_width_bottom = 1
		style.border_color = Color(1.0, 0.60, 0.0, 0.4)
		lbl.text = "⚠️ HIGH"
		lbl.add_theme_color_override("font_color", Color(0.75, 0.40, 0.0, 1.0))
	elif priority == "Medium":
		style.bg_color = Color(0.90, 0.95, 1.0, 1.0)
		style.border_width_left = 1; style.border_width_top = 1; style.border_width_right = 1; style.border_width_bottom = 1
		style.border_color = Color(0.12, 0.53, 0.90, 0.4)
		lbl.text = "Medium"
		lbl.add_theme_color_override("font_color", Color(0.08, 0.40, 0.70, 1.0))
	else:
		style.bg_color = Color(0.95, 0.96, 0.97, 1.0)
		style.border_width_left = 1; style.border_width_top = 1; style.border_width_right = 1; style.border_width_bottom = 1
		style.border_color = Color(0.62, 0.62, 0.62, 0.4)
		lbl.text = "Low"
		lbl.add_theme_color_override("font_color", Color(0.40, 0.40, 0.40, 1.0))
		
	badge.add_theme_stylebox_override("panel", style)
	badge.add_child(lbl)
	return badge

func set_selected_phone_filter(phone: String) -> void:
	_selected_phone_filter = phone
	_refresh_threads_feed()

func _refresh_threads_feed() -> void:
	if not db: return
	if not com_service: com_service = CommunicationsServiceScript.new(db)

	for child in threads_card.get_children(): child.free()

	var scroll = ScrollContainer.new()
	scroll.size_flags_horizontal = SIZE_EXPAND_FILL
	scroll.size_flags_vertical = SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED

	var vbox = VBoxContainer.new()
	vbox.size_flags_horizontal = SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 12)

	var title_hbox = HBoxContainer.new()
	title_hbox.size_flags_horizontal = SIZE_EXPAND_FILL
	
	var title_lbl = Label.new()
	if _selected_phone_filter != "":
		title_lbl.text = "💬 Threads: " + _selected_phone_filter
	else:
		title_lbl.text = "💬 2-Way Message Threads"
	title_lbl.add_theme_font_size_override("font_size", 20)
	title_lbl.add_theme_color_override("font_color", Color(0.08, 0.12, 0.18, 1.0))
	title_lbl.size_flags_horizontal = SIZE_EXPAND_FILL
	title_hbox.add_child(title_lbl)

	if _selected_phone_filter != "":
		var clear_btn = Button.new()
		clear_btn.text = "Clear Filter"
		clear_btn.custom_minimum_size = Vector2(80, 24)
		clear_btn.add_theme_font_size_override("font_size", 10)
		clear_btn.pressed.connect(func():
			_selected_phone_filter = ""
			_refresh_threads_feed()
		)
		title_hbox.add_child(clear_btn)
		
	vbox.add_child(title_hbox)

	var threads = com_service.get_threaded_messages()
	if _selected_phone_filter != "":
		var filtered = []
		var clean_filter = _selected_phone_filter.replace("-", "").replace(" ", "").replace("+", "")
		if clean_filter.length() > 10:
			clean_filter = clean_filter.substr(clean_filter.length() - 10)
			
		for th in threads:
			var p = str(th.get("caller_phone", "")).replace("-", "").replace(" ", "").replace("+", "")
			if p.length() > 10:
				p = p.substr(p.length() - 10)
			if p == clean_filter or clean_filter in p:
				filtered.append(th)
		threads = filtered

	if threads.size() > 0:
		for th in threads:
			var phone = str(th.get("caller_phone", ""))
			var dir_s = "📥 Inbound" if str(th.get("direction")) == "inbound" else "📤 Outbound"
			var text = str(th.get("message_text", ""))

			var row_vbox = VBoxContainer.new()
			row_vbox.size_flags_horizontal = SIZE_EXPAND_FILL
			row_vbox.add_theme_constant_override("separation", 2)

			var header_lbl = Label.new()
			header_lbl.text = dir_s + " (" + phone + ")"
			header_lbl.add_theme_font_size_override("font_size", 17)
			header_lbl.add_theme_color_override("font_color", Color(0.08, 0.12, 0.18, 1.0))
			row_vbox.add_child(header_lbl)

			var body_lbl = Label.new()
			body_lbl.text = "  \"" + text + "\""
			body_lbl.add_theme_font_size_override("font_size", 16)
			body_lbl.add_theme_color_override("font_color", Color(0.12, 0.16, 0.22, 1.0))
			body_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			body_lbl.size_flags_horizontal = SIZE_EXPAND_FILL
			row_vbox.add_child(body_lbl)

			vbox.add_child(row_vbox)
	else:
		var empty_lbl = Label.new()
		empty_lbl.text = "No active threads."
		empty_lbl.add_theme_font_size_override("font_size", 17)
		empty_lbl.add_theme_color_override("font_color", Color(0.35, 0.45, 0.58, 1.0))
		vbox.add_child(empty_lbl)

	scroll.add_child(vbox)
	threads_card.add_child(scroll)

func select_recipient_by_phone(phone: String, channel_name: String) -> void:
	for i in range(person_list.size()):
		var p = person_list[i]
		if str(p.get("phone")) == phone:
			recipient_dropdown.selected = i
			break
	if channel_name == "SMS":
		channel_dropdown.selected = 0
	elif channel_name == "Email":
		channel_dropdown.selected = 1
	message_body_edit.grab_focus()

func move_voicemail_to_status(uuid: String, status: String, item_type: String = "voicemail") -> void:
	if item_type == "sms":
		var q = "UPDATE inbound_sms_log SET follow_up_status = ? WHERE message_sid = ? OR ('sms_' || id) = ?;"
		db.execute(q, [status, uuid, uuid])
	else:
		var q = "UPDATE voicemails SET status = ? WHERE voicemail_uuid = ?;"
		db.execute(q, [status, uuid])
	_refresh_all_feeds()

func _open_forward_dialog(vm_uuid: String, item_type: String = "voicemail") -> void:
	var backdrop = ColorRect.new()
	backdrop.color = Color(0.08, 0.12, 0.18, 0.6) # Premium dark transparent backdrop
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)
	
	var center = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.add_child(center)
	
	var card = PanelContainer.new()
	var card_st = StyleBoxFlat.new()
	card_st.bg_color = Color(1.0, 1.0, 1.0, 1.0)
	card_st.border_width_left = 1; card_st.border_width_top = 1; card_st.border_width_right = 1; card_st.border_width_bottom = 1
	card_st.border_color = Color(0.78, 0.82, 0.88, 1.0)
	card_st.corner_radius_top_left = 12; card_st.corner_radius_top_right = 12; card_st.corner_radius_bottom_left = 12; card_st.corner_radius_bottom_right = 12
	card_st.content_margin_left = 22; card_st.content_margin_top = 20; card_st.content_margin_right = 22; card_st.content_margin_bottom = 20
	card.add_theme_stylebox_override("panel", card_st)
	center.add_child(card)
	
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 16)
	vbox.custom_minimum_size = Vector2(420, 240)
	card.add_child(vbox)
	
	var title = Label.new()
	title.text = "🔄 Forward Work Item"
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", _get_active_theme_color())
	vbox.add_child(title)
	
	# Dropdown styling for assignee selection
	var dd_st = StyleBoxFlat.new()
	dd_st.bg_color = Color(0.96, 0.97, 0.99, 1.0)
	dd_st.border_width_left = 1; dd_st.border_width_top = 1; dd_st.border_width_right = 1; dd_st.border_width_bottom = 1
	dd_st.border_color = Color(0.78, 0.82, 0.88, 1.0)
	dd_st.corner_radius_top_left = 6; dd_st.corner_radius_top_right = 6; dd_st.corner_radius_bottom_left = 6; dd_st.corner_radius_bottom_right = 6
	dd_st.content_margin_left = 12; dd_st.content_margin_top = 8; dd_st.content_margin_right = 12; dd_st.content_margin_bottom = 8
	
	# Assignee Picker (Role-filtered Auto-lookup: Staff, Volunteer, Intern)
	var asg_hbox = HBoxContainer.new()
	var asg_lbl = Label.new(); asg_lbl.text = "Assign To: "; asg_lbl.custom_minimum_size = Vector2(100, 0); asg_lbl.add_theme_font_size_override("font_size", 14); asg_lbl.add_theme_color_override("font_color", Color(0.12, 0.16, 0.22, 1.0))
	asg_hbox.add_child(asg_lbl)
	var asg_opt = _build_role_filtered_assignee_picker(asg_hbox, null, "", 13)
	vbox.add_child(asg_hbox)
	
	# Input field styling for notes
	var edit_st = StyleBoxFlat.new()
	edit_st.bg_color = Color(0.98, 0.99, 1.0, 1.0)
	edit_st.border_width_left = 1; edit_st.border_width_top = 1; edit_st.border_width_right = 1; edit_st.border_width_bottom = 1
	edit_st.border_color = Color(0.78, 0.82, 0.88, 1.0)
	edit_st.corner_radius_top_left = 6; edit_st.corner_radius_top_right = 6; edit_st.corner_radius_bottom_left = 6; edit_st.corner_radius_bottom_right = 6
	edit_st.content_margin_left = 12; edit_st.content_margin_top = 8; edit_st.content_margin_right = 12; edit_st.content_margin_bottom = 8
	
	var notes_lbl = Label.new(); notes_lbl.text = "Assignment Notes: "; notes_lbl.add_theme_font_size_override("font_size", 14); notes_lbl.add_theme_color_override("font_color", Color(0.12, 0.16, 0.22, 1.0))
	var notes_edit = LineEdit.new()
	notes_edit.placeholder_text = "e.g. Intern Jane, please call back Dorothy."
	notes_edit.custom_minimum_size = Vector2(0, 38)
	notes_edit.add_theme_font_size_override("font_size", 13)
	notes_edit.add_theme_color_override("font_color", Color(0.12, 0.16, 0.22, 1.0))
	notes_edit.add_theme_color_override("font_placeholder_color", Color(0.50, 0.55, 0.65, 1.0))
	notes_edit.add_theme_stylebox_override("normal", edit_st)
	notes_edit.add_theme_stylebox_override("focus", edit_st)
	vbox.add_child(notes_lbl); vbox.add_child(notes_edit)
	
	# Action buttons row
	var action_hbox = HBoxContainer.new()
	action_hbox.alignment = BoxContainer.ALIGNMENT_END
	action_hbox.add_theme_constant_override("separation", 12)
	
	var cancel_st = StyleBoxFlat.new()
	cancel_st.bg_color = Color(0.92, 0.93, 0.96, 1.0)
	cancel_st.corner_radius_top_left = 6; cancel_st.corner_radius_top_right = 6; cancel_st.corner_radius_bottom_left = 6; cancel_st.corner_radius_bottom_right = 6
	cancel_st.content_margin_left = 16; cancel_st.content_margin_top = 8; cancel_st.content_margin_right = 16; cancel_st.content_margin_bottom = 8
	
	var cancel_btn = Button.new(); cancel_btn.text = "Cancel"; cancel_btn.custom_minimum_size = Vector2(90, 36); cancel_btn.add_theme_font_size_override("font_size", 13)
	cancel_btn.add_theme_stylebox_override("normal", cancel_st)
	cancel_btn.add_theme_stylebox_override("hover", cancel_st)
	cancel_btn.add_theme_stylebox_override("pressed", cancel_st)
	cancel_btn.add_theme_color_override("font_color", Color(0.25, 0.32, 0.40, 1.0))
	cancel_btn.add_theme_color_override("font_hover_color", Color(0.08, 0.12, 0.18, 1.0))
	
	var save_st = StyleBoxFlat.new()
	save_st.bg_color = _get_active_theme_color()
	save_st.corner_radius_top_left = 6; save_st.corner_radius_top_right = 6; save_st.corner_radius_bottom_left = 6; save_st.corner_radius_bottom_right = 6
	save_st.content_margin_left = 16; save_st.content_margin_top = 8; save_st.content_margin_right = 16; save_st.content_margin_bottom = 8
	
	var save_btn = Button.new(); save_btn.text = "Forward Item"; save_btn.custom_minimum_size = Vector2(120, 36); save_btn.add_theme_font_size_override("font_size", 13)
	save_btn.add_theme_stylebox_override("normal", save_st)
	save_btn.add_theme_stylebox_override("hover", save_st)
	save_btn.add_theme_stylebox_override("pressed", save_st)
	save_btn.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	
	action_hbox.add_child(cancel_btn); action_hbox.add_child(save_btn)
	vbox.add_child(action_hbox)
	
	cancel_btn.pressed.connect(func(): backdrop.queue_free())
	save_btn.pressed.connect(func():
		var assigned_person_id = null
		if asg_opt.selected > 0:
			assigned_person_id = int(asg_opt.get_item_id(asg_opt.selected))
			
		var notes = notes_edit.text.strip_edges()
		
		var status = "assigned" if assigned_person_id != null else "new"
		com_service.update_voicemail_workflow(vm_uuid, assigned_person_id, status, "Medium", "", notes, item_type)
		backdrop.queue_free()
		_refresh_all_feeds()
	)

func open_detail_dialog_by_uuid(uuid: String) -> void:
	var vms = com_service.get_voicemails()
	for vm in vms:
		if str(vm.get("item_uuid")) == uuid:
			_open_detail_dialog(vm)
			break

func _open_detail_dialog(vm: Dictionary) -> void:
	var vm_uuid = str(vm.get("item_uuid", ""))
	var item_type = str(vm.get("item_type", "voicemail"))
	var caller_num = _clean_str(vm.get("caller_phone"), "")
	var caller_name = _clean_str(vm.get("caller_name"), "")
	var matched_name = _clean_str(vm.get("matched_caller_name"), "")
	
	var display_caller = ""
	if matched_name != "" and matched_name != "SMS Caller" and matched_name != "Unknown Caller":
		display_caller = matched_name
	elif caller_name != "" and caller_name != "Unknown Caller" and caller_name != "SMS Caller":
		display_caller = caller_name
	else:
		display_caller = _format_phone_display(caller_num)
	
	var transcription = _clean_str(vm.get("transcription"), "")
	var cur_status = _clean_str(vm.get("status"), "new")
	var cur_priority = _clean_str(vm.get("priority"), "Medium")
	var cur_due = _clean_str(vm.get("due_date"), "")
	var cur_notes = _clean_str(vm.get("internal_notes"), "")
	var cur_assignee_id = vm.get("assigned_person_id")
	var cur_assignee_name = _clean_str(vm.get("assignee_name"), "Unassigned")

	var backdrop = ColorRect.new()
	backdrop.color = Color(0.08, 0.12, 0.18, 0.6) # Premium dark transparent backdrop
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)
	
	var center = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.add_child(center)
	
	var card = PanelContainer.new()
	card.custom_minimum_size = Vector2(740, 560)
	var card_st = StyleBoxFlat.new()
	card_st.bg_color = Color(1.0, 1.0, 1.0, 1.0)
	card_st.border_width_left = 1; card_st.border_width_top = 1; card_st.border_width_right = 1; card_st.border_width_bottom = 1
	card_st.border_color = Color(0.78, 0.82, 0.88, 1.0)
	card_st.corner_radius_top_left = 12; card_st.corner_radius_top_right = 12; card_st.corner_radius_bottom_left = 12; card_st.corner_radius_bottom_right = 12
	card_st.content_margin_left = 24; card_st.content_margin_top = 22; card_st.content_margin_right = 24; card_st.content_margin_bottom = 22
	card.add_theme_stylebox_override("panel", card_st)
	center.add_child(card)
	
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 16)
	vbox.custom_minimum_size = Vector2(740, 560)
	card.add_child(vbox)
	
	# Header
	var title = Label.new()
	title.text = "📋 Edit Work Item — " + display_caller
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", _get_active_theme_color())
	vbox.add_child(title)
	
	# Grid Layout for details
	var grid = GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 12)
	grid.size_flags_vertical = SIZE_EXPAND_FILL
	vbox.add_child(grid)
	
	# Left Side (Read-only info)
	var left_vbox = VBoxContainer.new()
	left_vbox.custom_minimum_size = Vector2(270, 0)
	left_vbox.size_flags_horizontal = SIZE_EXPAND_FILL
	left_vbox.add_theme_constant_override("separation", 10)
	grid.add_child(left_vbox)
	
	var info_lbl = Label.new()
	info_lbl.text = "Source: " + ("☎️ Call / Voicemail" if item_type == "voicemail" else "💬 SMS Text") + "\nPhone: " + caller_num + "\nReceived: " + str(vm.get("created_at", ""))
	info_lbl.add_theme_font_size_override("font_size", 12)
	info_lbl.add_theme_color_override("font_color", Color(0.35, 0.42, 0.52, 1.0))
	left_vbox.add_child(info_lbl)
	
	# Integrated Audio Control for Voicemails
	var detail_rec_url = str(vm.get("recording_url", ""))
	if item_type == "voicemail" and detail_rec_url != "":
		var audio_player = AudioStreamPlayer.new()
		left_vbox.add_child(audio_player)

		var audio_box = HBoxContainer.new()
		audio_box.add_theme_constant_override("separation", 10)
		left_vbox.add_child(audio_box)

		var btn_inline_play = Button.new()
		btn_inline_play.text = "▶ Play Message"
		btn_inline_play.custom_minimum_size = Vector2(135, 32)
		btn_inline_play.add_theme_font_size_override("font_size", 12)
		var play_st = StyleBoxFlat.new()
		play_st.bg_color = Color(0.12, 0.53, 0.90, 1.0)
		play_st.corner_radius_top_left = 6; play_st.corner_radius_top_right = 6; play_st.corner_radius_bottom_left = 6; play_st.corner_radius_bottom_right = 6
		btn_inline_play.add_theme_stylebox_override("normal", play_st)
		btn_inline_play.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 1.0))
		audio_box.add_child(btn_inline_play)

		var time_lbl = Label.new()
		time_lbl.text = "0:00"
		time_lbl.add_theme_font_size_override("font_size", 11)
		time_lbl.add_theme_color_override("font_color", Color(0.40, 0.45, 0.55, 1.0))
		audio_box.add_child(time_lbl)

		var is_loaded = false
		btn_inline_play.pressed.connect(func():
			if not is_loaded:
				btn_inline_play.text = "⏳ Loading..."
				btn_inline_play.disabled = true
				_fetch_twilio_audio.call(detail_rec_url, func(code: int, body: PackedByteArray):
					btn_inline_play.disabled = false
					if code == 200 and body.size() > 0:
						var stream = AudioStreamMP3.new()
						var file_path = "user://temp_inline_" + vm_uuid + ".mp3"
						var f = FileAccess.open(file_path, FileAccess.WRITE)
						if f:
							f.store_buffer(body)
							f.close()
						var fr = FileAccess.open(file_path, FileAccess.READ)
						if fr:
							stream.data = fr.get_buffer(fr.get_length())
							fr.close()
						audio_player.stream = stream
						is_loaded = true
						audio_player.play()
						btn_inline_play.text = "⏸ Pause Message"
					else:
						btn_inline_play.text = "🔇 Empty Audio"
				)
				return

			if audio_player.playing and not audio_player.stream_paused:
				audio_player.stream_paused = true
				btn_inline_play.text = "▶ Resume Message"
			elif audio_player.stream_paused:
				audio_player.stream_paused = false
				btn_inline_play.text = "⏸ Pause Message"
			else:
				audio_player.stream_paused = false
				audio_player.play()
				btn_inline_play.text = "⏸ Pause Message"
		)

		audio_player.finished.connect(func():
			btn_inline_play.text = "▶ Play Message"
		)
	
	var body_title = Label.new()
	body_title.text = "Message Content / Transcript:"
	body_title.add_theme_font_size_override("font_size", 12)
	body_title.add_theme_color_override("font_color", Color(0.12, 0.16, 0.22, 1.0))
	left_vbox.add_child(body_title)
	
	var txt_scroll = ScrollContainer.new()
	txt_scroll.custom_minimum_size = Vector2(0, 180)
	txt_scroll.size_flags_vertical = SIZE_EXPAND_FILL
	left_vbox.add_child(txt_scroll)
	
	var txt_lbl = Label.new()
	txt_lbl.text = "\"" + transcription + "\""
	txt_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	txt_lbl.size_flags_horizontal = SIZE_EXPAND_FILL
	txt_lbl.add_theme_font_size_override("font_size", 13)
	txt_lbl.add_theme_color_override("font_color", Color(0.20, 0.25, 0.32, 1.0))
	txt_scroll.add_child(txt_lbl)
	
	# Right Side (Editable controls)
	var right_vbox = VBoxContainer.new()
	right_vbox.custom_minimum_size = Vector2(330, 0)
	right_vbox.size_flags_horizontal = SIZE_EXPAND_FILL
	right_vbox.add_theme_constant_override("separation", 10)
	grid.add_child(right_vbox)
	
	# Dropdown styles
	var dd_st = StyleBoxFlat.new()
	dd_st.bg_color = Color(0.96, 0.97, 0.99, 1.0)
	dd_st.border_width_left = 1; dd_st.border_width_top = 1; dd_st.border_width_right = 1; dd_st.border_width_bottom = 1
	dd_st.border_color = Color(0.78, 0.82, 0.88, 1.0)
	dd_st.corner_radius_top_left = 6; dd_st.corner_radius_top_right = 6; dd_st.corner_radius_bottom_left = 6; dd_st.corner_radius_bottom_right = 6
	dd_st.content_margin_left = 12; dd_st.content_margin_top = 6; dd_st.content_margin_right = 12; dd_st.content_margin_bottom = 6
	
	# Status
	var stat_hbox = HBoxContainer.new()
	var stat_lbl = Label.new(); stat_lbl.text = "Status: "; stat_lbl.custom_minimum_size = Vector2(80, 0); stat_lbl.add_theme_font_size_override("font_size", 13); stat_lbl.add_theme_color_override("font_color", Color(0.12, 0.16, 0.22, 1.0))
	var stat_opt = OptionButton.new()
	stat_opt.size_flags_horizontal = SIZE_EXPAND_FILL
	stat_opt.add_theme_stylebox_override("normal", dd_st)
	stat_opt.add_theme_font_size_override("font_size", 12)
	stat_opt.add_theme_color_override("font_color", Color(0.12, 0.16, 0.22, 1.0))
	stat_opt.add_item("Inbox / New", 0)
	stat_opt.add_item("In Progress", 1)
	stat_opt.add_item("Waiting on Caller", 2)
	stat_opt.add_item("Completed / Closed", 3)
	
	if cur_status == "in_progress": stat_opt.selected = 1
	elif cur_status == "waiting": stat_opt.selected = 2
	elif cur_status == "completed": stat_opt.selected = 3
	else: stat_opt.selected = 0
	
	stat_hbox.add_child(stat_lbl); stat_hbox.add_child(stat_opt)
	right_vbox.add_child(stat_hbox)
	
	# Priority
	var pri_hbox = HBoxContainer.new()
	var pri_lbl = Label.new(); pri_lbl.text = "Priority: "; pri_lbl.custom_minimum_size = Vector2(80, 0); pri_lbl.add_theme_font_size_override("font_size", 13); pri_lbl.add_theme_color_override("font_color", Color(0.12, 0.16, 0.22, 1.0))
	var pri_opt = OptionButton.new()
	pri_opt.size_flags_horizontal = SIZE_EXPAND_FILL
	pri_opt.add_theme_stylebox_override("normal", dd_st)
	pri_opt.add_theme_font_size_override("font_size", 12)
	pri_opt.add_theme_color_override("font_color", Color(0.12, 0.16, 0.22, 1.0))
	pri_opt.add_item("Low", 0)
	pri_opt.add_item("Medium", 1)
	pri_opt.add_item("High", 2)
	pri_opt.add_item("Emergency", 3)
	
	if cur_priority == "Low": pri_opt.selected = 0
	elif cur_priority == "High": pri_opt.selected = 2
	elif cur_priority == "Emergency": pri_opt.selected = 3
	else: pri_opt.selected = 1
	
	pri_hbox.add_child(pri_lbl); pri_hbox.add_child(pri_opt)
	right_vbox.add_child(pri_hbox)
	
	# Assignee Picker (Role-filtered Auto-lookup: Staff, Volunteer, Intern)
	var asg_hbox = HBoxContainer.new()
	var asg_lbl = Label.new(); asg_lbl.text = "Assign To: "; asg_lbl.custom_minimum_size = Vector2(80, 0); asg_lbl.add_theme_font_size_override("font_size", 13); asg_lbl.add_theme_color_override("font_color", Color(0.12, 0.16, 0.22, 1.0))
	asg_hbox.add_child(asg_lbl)
	var asg_opt = _build_role_filtered_assignee_picker(asg_hbox, cur_assignee_id, cur_assignee_name, 12)
	right_vbox.add_child(asg_hbox)
	
	# Due Date
	var due_hbox = HBoxContainer.new()
	due_hbox.add_theme_constant_override("separation", 6)
	var due_lbl = Label.new(); due_lbl.text = "Due Date: "; due_lbl.custom_minimum_size = Vector2(80, 0); due_lbl.add_theme_font_size_override("font_size", 13); due_lbl.add_theme_color_override("font_color", Color(0.12, 0.16, 0.22, 1.0))
	var due_edit = LineEdit.new()
	due_edit.size_flags_horizontal = SIZE_EXPAND_FILL
	due_edit.placeholder_text = "MM/DD/YYYY"
	due_edit.text = _db_to_ui_date(cur_due)
	_style_input_control(due_edit, 12)
	due_edit.add_theme_stylebox_override("normal", dd_st)
	var date_pick_btn = Button.new()
	date_pick_btn.text = "📅 Pick Date"
	date_pick_btn.custom_minimum_size = Vector2(105, 30)
	date_pick_btn.add_theme_font_size_override("font_size", 11)
	var pick_st = StyleBoxFlat.new()
	pick_st.bg_color = Color(0.90, 0.93, 0.96, 1.0)
	pick_st.border_width_left = 1; pick_st.border_width_top = 1; pick_st.border_width_right = 1; pick_st.border_width_bottom = 1
	pick_st.border_color = Color(0.75, 0.80, 0.88, 1.0)
	pick_st.corner_radius_top_left = 6; pick_st.corner_radius_top_right = 6; pick_st.corner_radius_bottom_left = 6; pick_st.corner_radius_bottom_right = 6
	pick_st.content_margin_left = 8; pick_st.content_margin_right = 8; pick_st.content_margin_top = 4; pick_st.content_margin_bottom = 4
	date_pick_btn.add_theme_stylebox_override("normal", pick_st)
	date_pick_btn.add_theme_color_override("font_color", Color(0.20, 0.28, 0.38, 1.0))
	
	date_pick_btn.pressed.connect(func():
		_open_calendar_picker_dialog(func(sel_date: String):
			due_edit.text = sel_date
		, due_edit.text)
	)

	due_hbox.add_child(due_lbl)
	due_hbox.add_child(due_edit)
	due_hbox.add_child(date_pick_btn)
	right_vbox.add_child(due_hbox)
	
	# Internal Notes
	var notes_lbl = Label.new()
	notes_lbl.text = "Internal Follow-up Notes:"
	notes_lbl.add_theme_font_size_override("font_size", 13)
	notes_lbl.add_theme_color_override("font_color", Color(0.12, 0.16, 0.22, 1.0))
	right_vbox.add_child(notes_lbl)
	
	var edit_st = StyleBoxFlat.new()
	edit_st.bg_color = Color(0.98, 0.99, 1.0, 1.0)
	edit_st.border_width_left = 1; edit_st.border_width_top = 1; edit_st.border_width_right = 1; edit_st.border_width_bottom = 1
	edit_st.border_color = Color(0.78, 0.82, 0.88, 1.0)
	edit_st.corner_radius_top_left = 6; edit_st.corner_radius_top_right = 6; edit_st.corner_radius_bottom_left = 6; edit_st.corner_radius_bottom_right = 6
	edit_st.content_margin_left = 12; edit_st.content_margin_top = 8; edit_st.content_margin_right = 12; edit_st.content_margin_bottom = 8
	
	var notes_edit = TextEdit.new()
	notes_edit.text = cur_notes
	notes_edit.placeholder_text = "Add update notes here..."
	notes_edit.custom_minimum_size = Vector2(0, 110)
	notes_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_style_input_control(notes_edit, 12)
	notes_edit.add_theme_stylebox_override("normal", edit_st)
	notes_edit.add_theme_stylebox_override("focus", edit_st)
	right_vbox.add_child(notes_edit)
	
	# Auto-save helper
	var _auto_save = func():
		var assigned_person_id = null
		if asg_opt.selected > 0:
			assigned_person_id = int(asg_opt.get_item_id(asg_opt.selected))
			
		var notes = notes_edit.text.strip_edges()
		var due = _ui_to_db_date(due_edit.text.strip_edges())
		
		var stat_keys = ["new", "in_progress", "waiting", "completed"]
		var status = stat_keys[stat_opt.selected]
		
		var pri_keys = ["Low", "Medium", "High", "Emergency"]
		var priority = pri_keys[pri_opt.selected]
		
		com_service.update_voicemail_workflow(vm_uuid, assigned_person_id, status, priority, due, notes, item_type)
		_refresh_all_feeds()

	stat_opt.item_selected.connect(func(_i): _auto_save.call())
	pri_opt.item_selected.connect(func(_i): _auto_save.call())
	asg_opt.item_selected.connect(func(_i): _auto_save.call())
	due_edit.text_changed.connect(func(_t): _auto_save.call())
	notes_edit.text_changed.connect(func(_t): _auto_save.call())
	
	# Action buttons row
	var action_hbox = HBoxContainer.new()
	action_hbox.alignment = BoxContainer.ALIGNMENT_END
	action_hbox.add_theme_constant_override("separation", 12)
	
	var save_st = StyleBoxFlat.new()
	save_st.bg_color = _get_active_theme_color()
	save_st.corner_radius_top_left = 6; save_st.corner_radius_top_right = 6; save_st.corner_radius_bottom_left = 6; save_st.corner_radius_bottom_right = 6
	save_st.content_margin_left = 20; save_st.content_margin_top = 8; save_st.content_margin_right = 20; save_st.content_margin_bottom = 8
	
	var close_btn = Button.new(); close_btn.text = "✓ Close"; close_btn.custom_minimum_size = Vector2(110, 36); close_btn.add_theme_font_size_override("font_size", 13)
	close_btn.add_theme_stylebox_override("normal", save_st)
	close_btn.add_theme_stylebox_override("hover", save_st)
	close_btn.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	
	action_hbox.add_child(close_btn)
	vbox.add_child(action_hbox)
	
	close_btn.pressed.connect(func():
		_auto_save.call()
		backdrop.queue_free()
	)

func update_card_status_via_drag(uuid_str: String, new_status: String, item_type: String = "voicemail") -> void:
	if item_type == "sms":
		com_service.update_voicemail_workflow(uuid_str, null, new_status, "Medium", "", "", "sms")
	else:
		var existing_pri = "Medium"
		var existing_due = ""
		var existing_notes = ""
		var existing_asg = null
		
		var db = com_service.db
		if db:
			var res = db.execute("SELECT assigned_person_id, priority, due_date, internal_notes FROM voicemails WHERE voicemail_uuid = ? LIMIT 1;", [uuid_str])
			if res["success"] and res["data"].size() > 0:
				var row = res["data"][0]
				existing_asg = row.get("assigned_person_id", null)
				existing_pri = str(row.get("priority", "Medium"))
				existing_due = str(row.get("due_date", ""))
				existing_notes = str(row.get("internal_notes", ""))
		
		com_service.update_voicemail_workflow(uuid_str, existing_asg, new_status, existing_pri, existing_due, existing_notes, "voicemail")
	
	_refresh_all_feeds()

# --- Godot Drag and Drop Inner Class Implementations ---
class VoicemailKanbanCard extends PanelContainer:
	var vm_uuid: String
	var item_type: String
	var caller_phone: String
	var column_status: String
	var communications_view: Node
	
	func _init(uuid: String, type_str: String, phone: String, parent_view: Node, lane_status: String = "new") -> void:
		vm_uuid = uuid
		item_type = type_str
		caller_phone = phone
		communications_view = parent_view
		column_status = lane_status
		mouse_filter = Control.MOUSE_FILTER_STOP
		
	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			if event.double_click:
				communications_view.open_detail_dialog_by_uuid(vm_uuid)
				accept_event()
			elif not event.pressed:
				communications_view.set_selected_phone_filter(caller_phone)
		
	func _get_drag_data(_at_position: Vector2) -> Variant:
		var preview = PanelContainer.new()
		var pr_st = StyleBoxFlat.new()
		pr_st.bg_color = Color(0.96, 0.97, 0.99, 0.9)
		pr_st.border_width_left = 2; pr_st.border_width_top = 2; pr_st.border_width_right = 2; pr_st.border_width_bottom = 2
		pr_st.border_color = Color(0.12, 0.53, 0.90, 0.9)
		pr_st.corner_radius_top_left = 6; pr_st.corner_radius_top_right = 6; pr_st.corner_radius_bottom_left = 6; pr_st.corner_radius_bottom_right = 6
		pr_st.content_margin_left = 12; pr_st.content_margin_right = 12; pr_st.content_margin_top = 8; pr_st.content_margin_bottom = 8
		preview.add_theme_stylebox_override("panel", pr_st)
		preview.custom_minimum_size = Vector2(220, 60)
		
		var lbl = Label.new()
		lbl.text = "📋 Move Work Item"
		lbl.add_theme_font_size_override("font_size", 13)
		lbl.add_theme_color_override("font_color", Color(0.08, 0.12, 0.18, 1.0))
		preview.add_child(lbl)
		set_drag_preview(preview)
		
		return {"type": "voicemail", "vm_uuid": vm_uuid, "item_type": item_type}

	func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
		return typeof(data) == TYPE_DICTIONARY and data.get("type") == "voicemail"

	func _drop_data(_at_position: Vector2, data: Variant) -> void:
		if typeof(data) == TYPE_DICTIONARY and data.has("vm_uuid"):
			var uuid_str = str(data.get("vm_uuid"))
			var dragged_type = str(data.get("item_type", "voicemail"))
			communications_view.update_card_status_via_drag(uuid_str, column_status, dragged_type)

class VoicemailKanbanColumn extends PanelContainer:
	var status_key: String
	var communications_view: Node
	
	func _init(key: String, parent_view: Node) -> void:
		status_key = key
		communications_view = parent_view
		mouse_filter = Control.MOUSE_FILTER_STOP
		
	func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
		return typeof(data) == TYPE_DICTIONARY and data.get("type") == "voicemail"

	func _drop_data(_at_position: Vector2, data: Variant) -> void:
		if typeof(data) == TYPE_DICTIONARY and data.has("vm_uuid"):
			var uuid_str = str(data.get("vm_uuid"))
			var item_type = str(data.get("item_type", "voicemail"))
			communications_view.update_card_status_via_drag(uuid_str, status_key, item_type)
		
# --- Voicemail Privacy & Proxy Audio Helpers ---
func _get_proxy_recording_url(recording_url: String) -> String:
	var gateway_url = "https://app.reallife-studycenter.org"
	var api_key = "SCH_7wY9Pq4LmX8Nz2RbV5Kd1Hs6Mf3Jc9QaTp8Ux"
	
	if db:
		var g_res = db.execute("SELECT setting_value FROM app_settings WHERE setting_key = 'GATEWAY_SERVER_URL' LIMIT 1;")
		if g_res["success"] and g_res["data"].size() > 0:
			var val = str(g_res["data"][0]["setting_value"]).strip_edges()
			if val != "": gateway_url = val
			
		var k_res = db.execute("SELECT setting_value FROM app_settings WHERE setting_key = 'GATEWAY_SYNC_API_KEY' LIMIT 1;")
		if k_res["success"] and k_res["data"].size() > 0:
			var val = str(k_res["data"][0]["setting_value"]).strip_edges()
			if val != "": api_key = val
			
	return gateway_url + "/api/v1/proxy/recording?sync_api_key=" + api_key + "&url=" + recording_url.uri_encode()

func _verify_staff_pin(staff_name: String, pin_text: String) -> bool:
	if not db: return true
	var p_clean = pin_text.strip_edges()
	if p_clean == "": return false
	
	var res = db.execute("SELECT pin_hash FROM staff_pins WHERE display_name = ? LIMIT 1;", [staff_name])
	if res["success"] and res["data"].size() > 0:
		return str(res["data"][0]["pin_hash"]) == p_clean
	else:
		# First time use: save as initial PIN
		db.execute("INSERT OR REPLACE INTO staff_pins (display_name, pin_hash) VALUES (?, ?);", [staff_name, p_clean])
		return true

func _prompt_pin_auth_dialog(vm: Dictionary) -> void:
	var assignee_name = str(vm.get("assignee_name", "Staff Member"))
	
	var backdrop = ColorRect.new()
	backdrop.color = Color(0.08, 0.12, 0.18, 0.6)
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)
	
	var center = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.add_child(center)
	
	var card = PanelContainer.new()
	var card_st = StyleBoxFlat.new()
	card_st.bg_color = Color(1.0, 1.0, 1.0, 1.0)
	card_st.border_width_left = 1; card_st.border_width_top = 1; card_st.border_width_right = 1; card_st.border_width_bottom = 1
	card_st.border_color = Color(0.78, 0.82, 0.88, 1.0)
	card_st.corner_radius_top_left = 12; card_st.corner_radius_top_right = 12; card_st.corner_radius_bottom_left = 12; card_st.corner_radius_bottom_right = 12
	card_st.content_margin_left = 24; card_st.content_margin_top = 22; card_st.content_margin_right = 24; card_st.content_margin_bottom = 22
	card.add_theme_stylebox_override("panel", card_st)
	center.add_child(card)
	
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	vbox.custom_minimum_size = Vector2(380, 240)
	card.add_child(vbox)
	
	var title = Label.new()
	title.text = "🔒 Protected Voicemail Access"
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", Color(0.08, 0.12, 0.18, 1.0))
	vbox.add_child(title)
	
	var desc = Label.new()
	desc.text = "This message is assigned to " + assignee_name + ". Enter user name and PIN/password to view temporarily."
	desc.add_theme_font_size_override("font_size", 12)
	desc.add_theme_color_override("font_color", Color(0.35, 0.42, 0.52, 1.0))
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(desc)
	
	var user_input = LineEdit.new()
	user_input.placeholder_text = "User Name"
	user_input.text = assignee_name
	vbox.add_child(user_input)
	
	var pin_input = LineEdit.new()
	pin_input.placeholder_text = "4-Digit PIN or Password"
	pin_input.secret = true
	vbox.add_child(pin_input)
	
	var err_lbl = Label.new()
	err_lbl.add_theme_font_size_override("font_size", 11)
	err_lbl.add_theme_color_override("font_color", Color(0.9, 0.2, 0.2, 1.0))
	err_lbl.visible = false
	vbox.add_child(err_lbl)
	
	var btn_hbox = HBoxContainer.new()
	btn_hbox.alignment = BoxContainer.ALIGNMENT_END
	btn_hbox.add_theme_constant_override("separation", 10)
	
	var btn_cancel = Button.new()
	btn_cancel.text = "Cancel"
	btn_cancel.pressed.connect(func(): backdrop.queue_free())
	
	var btn_unlock = Button.new()
	btn_unlock.text = "Unlock & View"
	var unl_st = StyleBoxFlat.new()
	unl_st.bg_color = Color(0.12, 0.53, 0.90, 1.0)
	unl_st.corner_radius_top_left = 6; unl_st.corner_radius_top_right = 6; unl_st.corner_radius_bottom_left = 6; unl_st.corner_radius_bottom_right = 6
	unl_st.content_margin_left = 14; unl_st.content_margin_right = 14; unl_st.content_margin_top = 6; unl_st.content_margin_bottom = 6
	btn_unlock.add_theme_stylebox_override("normal", unl_st)
	btn_unlock.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 1.0))
	
	btn_unlock.pressed.connect(func():
		var u_name = user_input.text.strip_edges()
		var p_code = pin_input.text.strip_edges()
		if u_name == "" or p_code == "":
			err_lbl.text = "Please enter both User Name and PIN."
			err_lbl.visible = true
			return
		if _verify_staff_pin(u_name, p_code):
			backdrop.queue_free()
			_open_detail_dialog(vm)
		else:
			err_lbl.text = "Invalid PIN for " + u_name + "."
			err_lbl.visible = true
	)
	
	btn_hbox.add_child(btn_cancel)
	btn_hbox.add_child(btn_unlock)
	vbox.add_child(btn_hbox)

func _clean_str(val: Variant, fallback: String = "") -> String:
	if val == null: return fallback
	var s = str(val).strip_edges()
	if s == "" or s.to_lower() == "<null>" or s.to_lower() == "null" or s.to_lower() == "none":
		return fallback
	return s

func _format_phone_display(phone_str: String) -> String:
	var clean = _clean_str(phone_str, "")
	if clean == "": return "No phone number"
	var digits = ""
	for c in clean:
		if c >= '0' and c <= '9':
			digits += c
	if digits.length() == 10:
		return "+1 (" + digits.substr(0, 3) + ") " + digits.substr(3, 3) + "-" + digits.substr(6, 4)
	elif digits.length() == 11 and digits.begins_with("1"):
		return "+1 (" + digits.substr(1, 3) + ") " + digits.substr(4, 3) + "-" + digits.substr(7, 4)
	return clean

func _db_to_ui_date(iso_date: String) -> String:
	var s = iso_date.strip_edges()
	if s == "": return ""
	var parts = s.split("-")
	if parts.size() == 3:
		var yyyy = parts[0]
		var mm = parts[1]
		var dd = parts[2].left(2)
		return mm + "/" + dd + "/" + yyyy
	return s

func _ui_to_db_date(ui_date: String) -> String:
	var s = ui_date.strip_edges()
	if s == "": return ""
	var parts = s.split("/")
	if parts.size() == 3:
		var mm = parts[0].pad_zeros(2)
		var dd = parts[1].pad_zeros(2)
		var yyyy = parts[2]
		return yyyy + "-" + mm + "-" + dd
	return s

func _style_input_control(control: Control, font_size: int = 12) -> void:
	if not control: return
	control.add_theme_font_size_override("font_size", font_size)
	control.add_theme_color_override("font_color", Color(0.12, 0.16, 0.22, 1.0))
	control.add_theme_color_override("font_placeholder_color", Color(0.55, 0.60, 0.68, 1.0))
	control.add_theme_color_override("font_selected_color", Color(0.12, 0.16, 0.22, 1.0))
	
	if control is LineEdit:
		control.caret_blink = true
		control.caret_blink_interval = 0.5
		control.add_theme_color_override("caret_color", Color(0.12, 0.16, 0.22, 1.0))
		control.add_theme_color_override("font_uneditable_color", Color(0.35, 0.40, 0.50, 1.0))
	elif control is TextEdit:
		control.caret_blink = true
		control.caret_blink_interval = 0.5
		control.add_theme_color_override("caret_color", Color(0.12, 0.16, 0.22, 1.0))

func _open_calendar_picker_dialog(on_date_selected: Callable, current_ui_date: String = "") -> void:
	var init_year = 2026
	var init_month = 7
	var init_day = 23
	
	var parts = current_ui_date.strip_edges().split("/")
	if parts.size() == 3:
		init_month = int(parts[0])
		init_day = int(parts[1])
		init_year = int(parts[2])
	else:
		var sys_dt = Time.get_datetime_dict_from_system()
		init_year = int(sys_dt.get("year", 2026))
		init_month = int(sys_dt.get("month", 7))
		init_day = int(sys_dt.get("day", 23))

	var backdrop = ColorRect.new()
	backdrop.color = Color(0.08, 0.12, 0.18, 0.65)
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)

	var center = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.add_child(center)

	var card = PanelContainer.new()
	var card_st = StyleBoxFlat.new()
	card_st.bg_color = Color(1.0, 1.0, 1.0, 1.0)
	card_st.border_width_left = 1; card_st.border_width_top = 1; card_st.border_width_right = 1; card_st.border_width_bottom = 1
	card_st.border_color = Color(0.78, 0.82, 0.88, 1.0)
	card_st.corner_radius_top_left = 12; card_st.corner_radius_top_right = 12; card_st.corner_radius_bottom_left = 12; card_st.corner_radius_bottom_right = 12
	card_st.content_margin_left = 18; card_st.content_margin_top = 16; card_st.content_margin_right = 18; card_st.content_margin_bottom = 16
	card.add_theme_stylebox_override("panel", card_st)
	center.add_child(card)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	vbox.custom_minimum_size = Vector2(320, 340)
	card.add_child(vbox)

	var state = {
		"year": init_year,
		"month": init_month,
		"day": init_day
	}

	# Header (Month Year + Nav Arrows)
	var month_names = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]
	var nav_hbox = HBoxContainer.new()
	nav_hbox.size_flags_horizontal = SIZE_EXPAND_FILL
	
	var prev_btn = Button.new(); prev_btn.text = "◀"
	var month_lbl = Label.new()
	month_lbl.size_flags_horizontal = SIZE_EXPAND_FILL
	month_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	month_lbl.add_theme_font_size_override("font_size", 14)
	month_lbl.add_theme_color_override("font_color", Color(0.12, 0.16, 0.22, 1.0))
	var next_btn = Button.new(); next_btn.text = "▶"
	
	nav_hbox.add_child(prev_btn)
	nav_hbox.add_child(month_lbl)
	nav_hbox.add_child(next_btn)
	vbox.add_child(nav_hbox)

	# Weekday Labels
	var week_grid = GridContainer.new()
	week_grid.columns = 7
	var day_names = ["Su", "Mo", "Tu", "We", "Th", "Fr", "Sa"]
	for dn in day_names:
		var d_lbl = Label.new()
		d_lbl.text = dn
		d_lbl.custom_minimum_size = Vector2(38, 24)
		d_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		d_lbl.add_theme_font_size_override("font_size", 11)
		d_lbl.add_theme_color_override("font_color", Color(0.45, 0.50, 0.60, 1.0))
		week_grid.add_child(d_lbl)
	vbox.add_child(week_grid)

	# Calendar Days Grid
	var days_grid = GridContainer.new()
	days_grid.columns = 7
	vbox.add_child(days_grid)

	var _render_calendar = [null]
	_render_calendar[0] = func():
		var m_idx = clamp(state["month"] - 1, 0, 11)
		month_lbl.text = month_names[m_idx] + " " + str(state["year"])
		for child in days_grid.get_children():
			child.queue_free()
			
		# First day of month offset
		var temp_dict = {"year": state["year"], "month": state["month"], "day": 1, "hour": 12, "minute": 0, "second": 0}
		var temp_unix = Time.get_unix_time_from_datetime_dict(temp_dict)
		var day_of_week = Time.get_datetime_dict_from_unix_time(temp_unix).get("weekday", 0)
		
		var days_in_m = 31
		if state["month"] in [4, 6, 9, 11]: days_in_m = 30
		elif state["month"] == 2:
			var y = state["year"]
			days_in_m = 29 if (y % 4 == 0 and (y % 100 != 0 or y % 400 == 0)) else 28
			
		for i in range(day_of_week):
			var blank = Control.new()
			blank.custom_minimum_size = Vector2(38, 34)
			days_grid.add_child(blank)
			
		for d in range(1, days_in_m + 1):
			var d_btn = Button.new()
			d_btn.text = str(d)
			d_btn.custom_minimum_size = Vector2(38, 34)
			d_btn.add_theme_font_size_override("font_size", 12)
			
			var is_selected = (d == state["day"])
			var b_st = StyleBoxFlat.new()
			b_st.corner_radius_top_left = 6; b_st.corner_radius_top_right = 6; b_st.corner_radius_bottom_left = 6; b_st.corner_radius_bottom_right = 6
			
			if is_selected:
				b_st.bg_color = _get_active_theme_color()
				d_btn.add_theme_color_override("font_color", Color(1, 1, 1, 1))
			else:
				b_st.bg_color = Color(0.96, 0.97, 0.99, 1.0)
				d_btn.add_theme_color_override("font_color", Color(0.15, 0.20, 0.28, 1.0))
				
			d_btn.add_theme_stylebox_override("normal", b_st)
			
			var target_d = d
			d_btn.pressed.connect(func():
				var mm_str = str(state["month"]).pad_zeros(2)
				var dd_str = str(target_d).pad_zeros(2)
				var yyyy_str = str(state["year"])
				on_date_selected.call(mm_str + "/" + dd_str + "/" + yyyy_str)
				backdrop.queue_free()
			)
			days_grid.add_child(d_btn)

	_render_calendar[0].call()

	prev_btn.pressed.connect(func():
		state["month"] -= 1
		if state["month"] < 1:
			state["month"] = 12
			state["year"] -= 1
		_render_calendar[0].call()
	)

	next_btn.pressed.connect(func():
		state["month"] += 1
		if state["month"] > 12:
			state["month"] = 1
			state["year"] += 1
		_render_calendar[0].call()
	)

	# Quick Presets Row at bottom
	var presets_hbox = HBoxContainer.new()
	presets_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	presets_hbox.add_theme_constant_override("separation", 6)
	vbox.add_child(presets_hbox)

	var make_preset = func(lbl_text: String, day_offset: int):
		var p_btn = Button.new()
		p_btn.text = lbl_text
		p_btn.add_theme_font_size_override("font_size", 10)
		p_btn.pressed.connect(func():
			var sys_dt = Time.get_datetime_dict_from_system()
			var target_unix = Time.get_unix_time_from_datetime_dict(sys_dt) + (day_offset * 86400)
			var t_dt = Time.get_datetime_dict_from_unix_time(target_unix)
			var mm_str = str(t_dt.month).pad_zeros(2)
			var dd_str = str(t_dt.day).pad_zeros(2)
			var yyyy_str = str(t_dt.year)
			on_date_selected.call(mm_str + "/" + dd_str + "/" + yyyy_str)
			backdrop.queue_free()
		)
		presets_hbox.add_child(p_btn)

	make_preset.call("Today", 0)
	make_preset.call("Tomorrow", 1)
	make_preset.call("+3 Days", 3)
	make_preset.call("+7 Days", 7)

	var clear_btn = Button.new(); clear_btn.text = "Clear"
	clear_btn.add_theme_font_size_override("font_size", 10)
	clear_btn.pressed.connect(func():
		on_date_selected.call("")
		backdrop.queue_free()
	)
	presets_hbox.add_child(clear_btn)

	var cancel_btn = Button.new(); cancel_btn.text = "Close"
	cancel_btn.add_theme_font_size_override("font_size", 10)
	cancel_btn.pressed.connect(func(): backdrop.queue_free())
	presets_hbox.add_child(cancel_btn)

func _open_link_contact_dialog(caller_phone: String) -> void:
	var backdrop = ColorRect.new()
	backdrop.color = Color(0.08, 0.12, 0.18, 0.6)
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)
	
	var center = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.add_child(center)
	
	var card = PanelContainer.new()
	var card_st = StyleBoxFlat.new()
	card_st.bg_color = Color(1.0, 1.0, 1.0, 1.0)
	card_st.border_width_left = 1; card_st.border_width_top = 1; card_st.border_width_right = 1; card_st.border_width_bottom = 1
	card_st.border_color = Color(0.78, 0.82, 0.88, 1.0)
	card_st.corner_radius_top_left = 12; card_st.corner_radius_top_right = 12; card_st.corner_radius_bottom_left = 12; card_st.corner_radius_bottom_right = 12
	card_st.content_margin_left = 24; card_st.content_margin_top = 22; card_st.content_margin_right = 24; card_st.content_margin_bottom = 22
	card.add_theme_stylebox_override("panel", card_st)
	center.add_child(card)
	
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	vbox.custom_minimum_size = Vector2(480, 360)
	card.add_child(vbox)
	
	var title = Label.new()
	title.text = "👤 Link Phone Number: " + _format_phone_display(caller_phone)
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", _get_active_theme_color())
	vbox.add_child(title)
	
	# Tab Switcher (Existing Member vs New Non-Member Profile)
	var mode_opt = OptionButton.new()
	mode_opt.add_item("🔍 Link to Existing Member / Person", 0)
	mode_opt.add_item("➕ Create Quick Non-Member Profile", 1)
	vbox.add_child(mode_opt)
	
	# Mode 1 Container (Search existing)
	var mode1_vbox = VBoxContainer.new()
	mode1_vbox.add_theme_constant_override("separation", 10)
	vbox.add_child(mode1_vbox)
	
	var search_edit = LineEdit.new()
	search_edit.placeholder_text = "Search existing members by name or ID..."
	mode1_vbox.add_child(search_edit)
	
	var person_opt = OptionButton.new()
	mode1_vbox.add_child(person_opt)
	
	var _populate_search_opt = func(filter_text: String):
		person_opt.clear()
		var flt = filter_text.to_lower().strip_edges()
		var count = 0
		for p in person_list:
			var fn = _clean_str(p.get("first_name"))
			var ln = _clean_str(p.get("last_name"))
			var hid = _clean_str(p.get("human_id"))
			var name = (fn + " " + ln).strip_edges() + " (" + hid + ")"
			if flt == "" or name.to_lower().contains(flt) or hid.to_lower().contains(flt):
				person_opt.add_item(name, int(p.get("id", 0)))
				count += 1
		if count == 0:
			person_opt.add_item("-- No matching people found --", -1)
			
	_populate_search_opt.call("")
	search_edit.text_changed.connect(func(new_text): _populate_search_opt.call(new_text))
	
	# Mode 2 Container (Create new non-member)
	var mode2_vbox = VBoxContainer.new()
	mode2_vbox.add_theme_constant_override("separation", 10)
	mode2_vbox.visible = false
	vbox.add_child(mode2_vbox)
	
	var fn_edit = LineEdit.new(); fn_edit.placeholder_text = "First Name (e.g. Jane)"
	var ln_edit = LineEdit.new(); ln_edit.placeholder_text = "Last Name (e.g. Doe)"
	var em_edit = LineEdit.new(); em_edit.placeholder_text = "Email (Optional)"
	mode2_vbox.add_child(fn_edit); mode2_vbox.add_child(ln_edit); mode2_vbox.add_child(em_edit)
	
	mode_opt.item_selected.connect(func(idx):
		mode1_vbox.visible = (idx == 0)
		mode2_vbox.visible = (idx == 1)
	)
	
	var err_lbl = Label.new()
	err_lbl.add_theme_font_size_override("font_size", 11)
	err_lbl.add_theme_color_override("font_color", Color(0.9, 0.2, 0.2, 1.0))
	err_lbl.visible = false
	vbox.add_child(err_lbl)
	
	var btn_hbox = HBoxContainer.new()
	btn_hbox.alignment = BoxContainer.ALIGNMENT_END
	btn_hbox.add_theme_constant_override("separation", 10)
	
	var btn_cancel = Button.new()
	btn_cancel.text = "Cancel"
	btn_cancel.pressed.connect(func(): backdrop.queue_free())
	
	var btn_save = Button.new()
	btn_save.text = "Save & Link Contact"
	var save_st = StyleBoxFlat.new()
	save_st.bg_color = Color(0.18, 0.55, 0.35, 1.0)
	save_st.corner_radius_top_left = 6; save_st.corner_radius_top_right = 6; save_st.corner_radius_bottom_left = 6; save_st.corner_radius_bottom_right = 6
	save_st.content_margin_left = 14; save_st.content_margin_right = 14; save_st.content_margin_top = 6; save_st.content_margin_bottom = 6
	btn_save.add_theme_stylebox_override("normal", save_st)
	btn_save.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 1.0))
	
	var _call_phone = caller_phone
	btn_save.pressed.connect(func():
		if mode_opt.selected == 0:
			var sel_idx = person_opt.selected
			if sel_idx < 0:
				err_lbl.text = "Please select a person to link."
				err_lbl.visible = true
				return
			var p_id = int(person_opt.get_item_id(sel_idx))
			if p_id <= 0:
				err_lbl.text = "Invalid person selected."
				err_lbl.visible = true
				return
			com_service.link_phone_to_person(_call_phone, p_id)
		else:
			var fn = fn_edit.text.strip_edges()
			var ln = ln_edit.text.strip_edges()
			if fn == "" and ln == "":
				err_lbl.text = "Please enter at least a First Name or Last Name."
				err_lbl.visible = true
				return
			com_service.create_non_member_profile(fn, ln, _call_phone, em_edit.text.strip_edges())
			
		backdrop.queue_free()
		_populate_dropdowns()
		_refresh_all_feeds()
	)
	
	btn_hbox.add_child(btn_cancel)
	btn_hbox.add_child(btn_save)
	vbox.add_child(btn_hbox)

func _build_role_filtered_assignee_picker(parent_box: Container, initial_assignee_id: Variant, initial_assignee_name: String, font_sz: int = 12) -> OptionButton:
	var hbox = HBoxContainer.new()
	hbox.size_flags_horizontal = SIZE_EXPAND_FILL
	hbox.add_theme_constant_override("separation", 6)

	var dd_st = StyleBoxFlat.new()
	dd_st.bg_color = Color(0.96, 0.97, 0.99, 1.0)
	dd_st.border_width_left = 1; dd_st.border_width_top = 1; dd_st.border_width_right = 1; dd_st.border_width_bottom = 1
	dd_st.border_color = Color(0.78, 0.82, 0.88, 1.0)
	dd_st.corner_radius_top_left = 6; dd_st.corner_radius_top_right = 6; dd_st.corner_radius_bottom_left = 6; dd_st.corner_radius_bottom_right = 6
	dd_st.content_margin_left = 8; dd_st.content_margin_top = 4; dd_st.content_margin_right = 8; dd_st.content_margin_bottom = 4

	var search_edit = LineEdit.new()
	search_edit.placeholder_text = "🔍 Search Staff..."
	search_edit.custom_minimum_size = Vector2(110, 30)
	search_edit.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_style_input_control(search_edit, font_sz)
	search_edit.add_theme_stylebox_override("normal", dd_st)
	search_edit.add_theme_stylebox_override("focus", dd_st)
	hbox.add_child(search_edit)

	var asg_opt = OptionButton.new()
	asg_opt.fit_to_longest_item = false
	asg_opt.clip_text = true
	asg_opt.custom_minimum_size = Vector2(140, 30)
	asg_opt.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	asg_opt.add_theme_stylebox_override("normal", dd_st)
	asg_opt.add_theme_stylebox_override("hover", dd_st)
	asg_opt.add_theme_font_size_override("font_size", font_sz)
	asg_opt.add_theme_color_override("font_color", Color(0.12, 0.16, 0.22, 1.0))
	hbox.add_child(asg_opt)

	parent_box.add_child(hbox)

	var all_staff = []
	if db:
		var q = "SELECT id, first_name || ' ' || last_name AS name, COALESCE(NULLIF(primary_role, ''), 'Staff') AS role FROM people WHERE LOWER(primary_role) IN ('staff', 'intern', 'volunteer') ORDER BY name ASC;"
		var res = db.execute(q)
		if not res["success"] or res["data"].size() == 0:
			res = db.execute("SELECT id, first_name || ' ' || last_name AS name, COALESCE(NULLIF(primary_role, ''), 'Staff') AS role FROM people ORDER BY name ASC;")
		if res["success"]:
			all_staff = res["data"]

	var cur_clean_name = _clean_str(initial_assignee_name, "")
	var cur_clean_id = int(initial_assignee_id) if initial_assignee_id != null else -1

	var _populate = func(filter_query: String):
		asg_opt.clear()
		asg_opt.add_item("Unassigned", 0)
		
		var q_lower = filter_query.to_lower().strip_edges()
		var sel_idx = 0
		
		for idx in range(all_staff.size()):
			var p = all_staff[idx]
			var p_id = int(p.get("id", 0))
			var p_name = _clean_str(p.get("name"), "Unknown Staff")
			var p_role = _clean_str(p.get("role"), "Staff")
			var label = p_name + " (" + p_role + ")"
			
			if q_lower == "" or p_name.to_lower().contains(q_lower) or p_role.to_lower().contains(q_lower):
				asg_opt.add_item(label, p_id)
				var curr_item_index = asg_opt.item_count - 1
				if cur_clean_id > 0 and p_id == cur_clean_id:
					sel_idx = curr_item_index
				elif cur_clean_name != "" and p_name.to_lower() == cur_clean_name.to_lower():
					sel_idx = curr_item_index

		asg_opt.selected = sel_idx

	_populate.call("")
	search_edit.text_changed.connect(func(new_text): _populate.call(new_text))

	return asg_opt

func _transcribe_voicemail_with_gemini(vm_uuid: String, recording_url: String, btn_node: Button = null) -> void:
	if recording_url == "": return
	
	if btn_node:
		btn_node.text = "⏳ Transcribing..."
		btn_node.disabled = true
		
	var proxy_url = _get_proxy_recording_url(recording_url)
	
	var api_key = ""
	if db:
		var k_res = db.execute("SELECT setting_value FROM app_settings WHERE setting_key = 'GEMINI_API_KEY' LIMIT 1;")
		if k_res["success"] and k_res["data"].size() > 0:
			api_key = str(k_res["data"][0]["setting_value"]).strip_edges()
	if api_key == "":
		api_key = OS.get_environment("GEMINI_API_KEY")
		
	var http = HTTPRequest.new()
	add_child(http)
	
	var url = "https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent?key=" + api_key
	var headers = ["Content-Type: application/json"]
	var req_body = JSON.stringify({
		"contents": [
			{
				"parts": [
					{ "text": "Please provide an accurate text transcription of the voicemail audio file at this URL. Return ONLY the transcription text without extra commentary: " + proxy_url }
				]
			}
		]
	})
	
	http.request_completed.connect(func(_result, response_code, _r_headers, body_bytes):
		var trans_text = ""
		if response_code == 200:
			var json = JSON.parse_string(body_bytes.get_string_from_utf8())
			if json and json.has("candidates") and json["candidates"].size() > 0:
				var cand = json["candidates"][0]
				if cand.has("content") and cand["content"].has("parts") and cand["content"]["parts"].size() > 0:
					trans_text = str(cand["content"]["parts"][0].get("text", "")).strip_edges()
		
		if trans_text == "":
			trans_text = "Voicemail audio recorded. (Listen via 🔊 Play)."
			
		com_service.update_voicemail_transcription(vm_uuid, trans_text)
		http.queue_free()
		_refresh_all_feeds()
	)
	
	http.request(url, headers, HTTPClient.METHOD_POST, req_body)

func _fetch_twilio_audio(url_str: String, done_cb: Callable) -> void:
	var account_sid = "REPLACE_WITH_TWILIO_ACCOUNT_SID"
	var auth_token = "REPLACE_WITH_TWILIO_AUTH_TOKEN"
	var b64_auth = Marshalls.utf8_to_base64(account_sid + ":" + auth_token)

	var target_url = url_str.strip_edges()
	if not target_url.contains(".mp3") and not target_url.contains(".wav"):
		target_url += ".mp3"

	var h1 = HTTPRequest.new()
	add_child(h1)
	h1.max_redirects = 0

	h1.request_completed.connect(func(_res, code, hdrs, body):
		h1.queue_free()
		print("[Audio] Initial fetch code: ", code, " body_sz: ", body.size())
		var redirect_loc = ""
		for h in hdrs:
			if h.to_lower().begins_with("location:"):
				redirect_loc = h.substr(9).strip_edges()
				break
		
		if redirect_loc != "":
			print("[Audio] Following redirect to S3: ", redirect_loc)
			var h2 = HTTPRequest.new()
			add_child(h2)
			h2.max_redirects = 5
			h2.request_completed.connect(func(_r2, code2, _h2, body2):
				h2.queue_free()
				print("[Audio] S3 fetch code: ", code2, " bytes: ", body2.size())
				done_cb.call(code2, body2)
			)
			h2.request(redirect_loc)
			return

		if code == 200 and body.size() > 0:
			done_cb.call(200, body)
		else:
			done_cb.call(code, body)
	)
	h1.request(target_url, ["Authorization: Basic " + b64_auth])

func _open_audio_player_dialog(vm: Dictionary) -> void:
	var vm_uuid = str(vm.get("item_uuid", ""))
	var caller_num = _clean_str(vm.get("caller_phone"), "")
	var caller_name = _clean_str(vm.get("caller_name"), "")
	var matched_name = _clean_str(vm.get("matched_caller_name"), "")
	var recording_url = _clean_str(vm.get("recording_url"), "")
	var transcription = _clean_str(vm.get("transcription"), "")
	
	var display_caller = ""
	if matched_name != "" and matched_name != "SMS Caller" and matched_name != "Unknown Caller":
		display_caller = matched_name
	elif caller_name != "" and caller_name != "Unknown Caller" and caller_name != "SMS Caller":
		display_caller = caller_name
	else:
		display_caller = _format_phone_display(caller_num)

	var backdrop = ColorRect.new()
	backdrop.color = Color(0.08, 0.12, 0.18, 0.65)
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)

	var center = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.add_child(center)

	var card = PanelContainer.new()
	var card_st = StyleBoxFlat.new()
	card_st.bg_color = Color(1.0, 1.0, 1.0, 1.0)
	card_st.border_width_left = 1; card_st.border_width_top = 1; card_st.border_width_right = 1; card_st.border_width_bottom = 1
	card_st.border_color = Color(0.78, 0.82, 0.88, 1.0)
	card_st.corner_radius_top_left = 12; card_st.corner_radius_top_right = 12; card_st.corner_radius_bottom_left = 12; card_st.corner_radius_bottom_right = 12
	card_st.content_margin_left = 24; card_st.content_margin_top = 22; card_st.content_margin_right = 24; card_st.content_margin_bottom = 22
	card.add_theme_stylebox_override("panel", card_st)
	center.add_child(card)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	vbox.custom_minimum_size = Vector2(580, 520)
	card.add_child(vbox)

	# Header Row (Title + Link Contact Button)
	var header_hbox = HBoxContainer.new()
	header_hbox.size_flags_horizontal = SIZE_EXPAND_FILL
	vbox.add_child(header_hbox)

	var title = Label.new()
	title.text = "🎙️ Voicemail Playback — " + display_caller
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", _get_active_theme_color())
	title.size_flags_horizontal = SIZE_EXPAND_FILL
	header_hbox.add_child(title)

	var btn_link_contact = Button.new()
	btn_link_contact.text = "👤 Link Contact"
	btn_link_contact.custom_minimum_size = Vector2(105, 28)
	btn_link_contact.add_theme_font_size_override("font_size", 11)
	var link_st = StyleBoxFlat.new()
	link_st.bg_color = Color(0.18, 0.55, 0.35, 1.0)
	link_st.corner_radius_top_left = 6; link_st.corner_radius_top_right = 6; link_st.corner_radius_bottom_left = 6; link_st.corner_radius_bottom_right = 6
	btn_link_contact.add_theme_stylebox_override("normal", link_st)
	btn_link_contact.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 1.0))
	var _c_num = caller_num
	btn_link_contact.pressed.connect(func(): _open_link_contact_dialog(_c_num))
	header_hbox.add_child(btn_link_contact)

	var phone_lbl = Label.new()
	phone_lbl.text = "📱 Phone: " + _format_phone_display(caller_num) + " • Received: " + str(vm.get("created_at", ""))
	phone_lbl.add_theme_font_size_override("font_size", 12)
	phone_lbl.add_theme_color_override("font_color", Color(0.40, 0.45, 0.55, 1.0))
	vbox.add_child(phone_lbl)

	# Audio Control Container
	var audio_card = PanelContainer.new()
	var ac_st = StyleBoxFlat.new()
	ac_st.bg_color = Color(0.96, 0.97, 0.99, 1.0)
	ac_st.corner_radius_top_left = 8; ac_st.corner_radius_top_right = 8; ac_st.corner_radius_bottom_left = 8; ac_st.corner_radius_bottom_right = 8
	ac_st.content_margin_left = 14; ac_st.content_margin_top = 10; ac_st.content_margin_right = 14; ac_st.content_margin_bottom = 10
	audio_card.add_theme_stylebox_override("panel", ac_st)
	vbox.add_child(audio_card)

	var ac_vbox = VBoxContainer.new()
	ac_vbox.add_theme_constant_override("separation", 8)
	audio_card.add_child(ac_vbox)

	var play_ctrl_hbox = HBoxContainer.new()
	play_ctrl_hbox.add_theme_constant_override("separation", 12)
	ac_vbox.add_child(play_ctrl_hbox)

	var btn_play_pause = Button.new()
	btn_play_pause.text = "▶ Play Audio"
	btn_play_pause.custom_minimum_size = Vector2(110, 36)
	btn_play_pause.add_theme_font_size_override("font_size", 12)
	var pp_st = StyleBoxFlat.new()
	pp_st.bg_color = Color(0.12, 0.53, 0.90, 1.0)
	pp_st.corner_radius_top_left = 6; pp_st.corner_radius_top_right = 6; pp_st.corner_radius_bottom_left = 6; pp_st.corner_radius_bottom_right = 6
	btn_play_pause.add_theme_stylebox_override("normal", pp_st)
	btn_play_pause.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 1.0))
	play_ctrl_hbox.add_child(btn_play_pause)

	# Scrubber / Slider
	var slider_vbox = VBoxContainer.new()
	slider_vbox.size_flags_horizontal = SIZE_EXPAND_FILL
	slider_vbox.add_theme_constant_override("separation", 2)
	play_ctrl_hbox.add_child(slider_vbox)

	var slider = HSlider.new()
	slider.size_flags_horizontal = SIZE_EXPAND_FILL
	slider.min_value = 0.0
	slider.max_value = 100.0
	slider.value = 0.0
	slider_vbox.add_child(slider)

	var time_lbl = Label.new()
	time_lbl.text = "0:00 / 0:00"
	time_lbl.add_theme_font_size_override("font_size", 11)
	time_lbl.add_theme_color_override("font_color", Color(0.45, 0.50, 0.60, 1.0))
	slider_vbox.add_child(time_lbl)

	# Status Label & Key Change Button
	var status_hbox = HBoxContainer.new()
	status_hbox.add_theme_constant_override("separation", 10)
	ac_vbox.add_child(status_hbox)

	var status_lbl = Label.new()
	status_lbl.text = "Ready to play audio."
	status_lbl.size_flags_horizontal = SIZE_EXPAND_FILL
	status_lbl.add_theme_font_size_override("font_size", 11)
	status_lbl.add_theme_color_override("font_color", Color(0.35, 0.40, 0.50, 1.0))
	status_hbox.add_child(status_lbl)

	var btn_change_key = Button.new()
	btn_change_key.text = "🔑 Change API Key"
	btn_change_key.add_theme_font_size_override("font_size", 10)
	btn_change_key.pressed.connect(func():
		_prompt_gemini_api_key_dialog(func(new_k: String):
			status_lbl.text = "API Key updated. Re-Transcribe ready."
		)
	)
	status_hbox.add_child(btn_change_key)

	# Transcription Box
	var trans_title = Label.new()
	trans_title.text = "💬 Transcription:"
	trans_title.add_theme_font_size_override("font_size", 13)
	trans_title.add_theme_color_override("font_color", Color(0.12, 0.16, 0.22, 1.0))
	vbox.add_child(trans_title)

	var trans_scroll = ScrollContainer.new()
	trans_scroll.custom_minimum_size = Vector2(0, 75)
	trans_scroll.size_flags_vertical = SIZE_EXPAND_FILL
	vbox.add_child(trans_scroll)

	var trans_lbl = Label.new()
	trans_lbl.text = "\"" + (transcription if transcription != "" else "(No transcription available. Click ✨ Re-Transcribe below to generate)") + "\""
	trans_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	trans_lbl.size_flags_horizontal = SIZE_EXPAND_FILL
	trans_lbl.add_theme_font_size_override("font_size", 12)
	trans_lbl.add_theme_color_override("font_color", Color(0.20, 0.25, 0.32, 1.0) if transcription != "" else Color(0.55, 0.58, 0.65, 1.0))
	trans_scroll.add_child(trans_lbl)

	# 2-Way Back-and-Forth Discussion Notes Section
	var disc_title = Label.new()
	disc_title.text = "📝 2-Way Discussion Notes Log (Back-and-Forth)"
	disc_title.add_theme_font_size_override("font_size", 13)
	disc_title.add_theme_color_override("font_color", Color(0.12, 0.16, 0.22, 1.0))
	vbox.add_child(disc_title)

	var disc_scroll = ScrollContainer.new()
	disc_scroll.custom_minimum_size = Vector2(0, 100)
	disc_scroll.size_flags_vertical = SIZE_EXPAND_FILL
	vbox.add_child(disc_scroll)

	var disc_vbox = VBoxContainer.new()
	disc_vbox.size_flags_horizontal = SIZE_EXPAND_FILL
	disc_vbox.add_theme_constant_override("separation", 6)
	disc_scroll.add_child(disc_vbox)

	var _refresh_discussion_notes = func():
		for c in disc_vbox.get_children():
			c.queue_free()
		var notes = com_service.get_work_item_notes(vm_uuid)
		if notes.size() == 0:
			var empty_lbl = Label.new()
			empty_lbl.text = "(No discussion notes yet. Add follow-up notes below)"
			empty_lbl.add_theme_font_size_override("font_size", 11)
			empty_lbl.add_theme_color_override("font_color", Color(0.55, 0.60, 0.68, 1.0))
			disc_vbox.add_child(empty_lbl)
		else:
			for n in notes:
				var n_lbl = Label.new()
				var n_author = _clean_str(n.get("author_name"), "Staff")
				var n_text = _clean_str(n.get("note_text"), "")
				var n_time = str(n.get("created_at", "")).left(16)
				n_lbl.text = "[" + n_time + "] " + n_author + ": " + n_text
				n_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				n_lbl.add_theme_font_size_override("font_size", 11)
				n_lbl.add_theme_color_override("font_color", Color(0.22, 0.28, 0.36, 1.0))
				disc_vbox.add_child(n_lbl)

	_refresh_discussion_notes.call()

	# Add Note Input HBox
	var add_note_hbox = HBoxContainer.new()
	add_note_hbox.add_theme_constant_override("separation", 8)
	vbox.add_child(add_note_hbox)

	var note_edit = LineEdit.new()
	note_edit.placeholder_text = "Type follow-up note or update for team..."
	note_edit.size_flags_horizontal = SIZE_EXPAND_FILL
	note_edit.add_theme_font_size_override("font_size", 12)
	add_note_hbox.add_child(note_edit)

	var btn_post_note = Button.new()
	btn_post_note.text = "➕ Post Note"
	btn_post_note.custom_minimum_size = Vector2(90, 30)
	btn_post_note.add_theme_font_size_override("font_size", 11)
	var post_st = StyleBoxFlat.new()
	post_st.bg_color = Color(0.12, 0.53, 0.90, 1.0)
	post_st.corner_radius_top_left = 6; post_st.corner_radius_top_right = 6; post_st.corner_radius_bottom_left = 6; post_st.corner_radius_bottom_right = 6
	btn_post_note.add_theme_stylebox_override("normal", post_st)
	btn_post_note.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 1.0))
	add_note_hbox.add_child(btn_post_note)

	btn_post_note.pressed.connect(func():
		var txt = note_edit.text.strip_edges()
		if txt != "":
			var author = _active_supervisor_name if _active_supervisor_name != "" else "Staff"
			com_service.add_work_item_note(vm_uuid, author, txt)
			note_edit.text = ""
			_refresh_discussion_notes.call()
	)

	# Audio & Transcription Logic
	var audio_player = AudioStreamPlayer.new()
	add_child(audio_player)
	
	var is_audio_loaded = false
	var audio_bytes_cache = PackedByteArray()
	var total_duration_sec = 0.0

	# Helper to format mm:ss
	var _format_time_str = func(sec_val: float) -> String:
		var s = int(sec_val)
		var mins = s / 60
		var secs = s % 60
		return "%d:%02d" % [mins, secs]

	# Redirect-aware Twilio audio downloader
	var _fetch_twilio_audio = func(url_str: String, done_cb: Callable):
		var account_sid = "REPLACE_WITH_TWILIO_ACCOUNT_SID"
		var auth_token = "REPLACE_WITH_TWILIO_AUTH_TOKEN"
		var b64_auth = Marshalls.utf8_to_base64(account_sid + ":" + auth_token)

		var target_url = url_str.strip_edges()
		if not target_url.contains(".mp3") and not target_url.contains(".wav"):
			target_url += ".mp3"

		var h1 = HTTPRequest.new()
		add_child(h1)
		h1.max_redirects = 0 # Intercept 302 redirect location!

		h1.request_completed.connect(func(_res, code, hdrs, body):
			h1.queue_free()
			print("[Audio] Initial fetch code: ", code, " body_sz: ", body.size())
			var redirect_loc = ""
			for h in hdrs:
				if h.to_lower().begins_with("location:"):
					redirect_loc = h.substr(9).strip_edges()
					break
			
			if redirect_loc != "":
				print("[Audio] Following redirect to S3: ", redirect_loc)
				var h2 = HTTPRequest.new()
				add_child(h2)
				h2.max_redirects = 5
				h2.request_completed.connect(func(_r2, code2, _h2, body2):
					h2.queue_free()
					print("[Audio] S3 fetch code: ", code2, " bytes: ", body2.size())
					done_cb.call(code2, body2)
				)
				h2.request(redirect_loc) # Clean S3 request without Basic Auth header
				return

			if code == 200 and body.size() > 0:
				done_cb.call(200, body)
			else:
				done_cb.call(code, body)
		)
		h1.request(target_url, ["Authorization: Basic " + b64_auth])

	# Fetch Audio
	var _load_audio = func(auto_play: bool = true):
		status_lbl.text = "Loading audio stream..."
		btn_play_pause.text = "⏳ Loading..."
		btn_play_pause.disabled = true

		_fetch_twilio_audio.call(recording_url, func(code: int, body: PackedByteArray):
			if code == 200 and body.size() > 0:
				audio_bytes_cache = body
				var file_path = "user://temp_voicemail_" + vm_uuid + ".mp3"
				var f_write = FileAccess.open(file_path, FileAccess.WRITE)
				if f_write:
					f_write.store_buffer(body)
					f_write.close()

				var stream = AudioStreamMP3.new()
				var f_read = FileAccess.open(file_path, FileAccess.READ)
				if f_read:
					stream.data = f_read.get_buffer(f_read.get_length())
					f_read.close()

				audio_player.stream = stream
				audio_player.volume_db = 0.0
				is_audio_loaded = true
				total_duration_sec = stream.get_length()
				if total_duration_sec <= 1.0:
					var vm_dur = float(vm.get("duration_sec", 0))
					if vm_dur > 1.0:
						total_duration_sec = vm_dur
					else:
						total_duration_sec = max(5.0, float(body.size()) / 8000.0)
				slider.max_value = total_duration_sec
				time_lbl.text = "0:00 / " + _format_time_str.call(total_duration_sec)
				status_lbl.text = "Audio loaded (" + _format_time_str.call(total_duration_sec) + ")."
				btn_play_pause.disabled = false

				if auto_play:
					audio_player.play()
					btn_play_pause.text = "⏸ Pause"
					status_lbl.text = "Playing audio..."
				else:
					btn_play_pause.text = "▶ Play Audio"
			elif code == 200 and body.size() == 0:
				btn_play_pause.disabled = true
				btn_play_pause.text = "🔇 Empty Audio"
				status_lbl.text = "⚠️ Empty voicemail (0 bytes recorded by carrier)."
			else:
				btn_play_pause.disabled = false
				btn_play_pause.text = "🌐 Open External"
				status_lbl.text = "Audio stream HTTP " + str(code) + ". Click Open External."
		)

	_load_audio.call(true)

	var current_saved_pos: float = 0.0

	audio_player.finished.connect(func():
		current_saved_pos = 0.0
		slider.value = 0.0
		btn_play_pause.text = "▶ Play Audio"
		status_lbl.text = "Playback finished."
	)

	btn_play_pause.pressed.connect(func():
		if not is_audio_loaded:
			_load_audio.call(true)
			return
		if btn_play_pause.text == "🌐 Open External":
			OS.shell_open(_get_proxy_recording_url(recording_url))
			return

		if audio_player.playing and not audio_player.stream_paused:
			audio_player.stream_paused = true
			btn_play_pause.text = "▶ Resume"
			status_lbl.text = "Audio paused."
		elif audio_player.stream_paused:
			audio_player.stream_paused = false
			btn_play_pause.text = "⏸ Pause"
			status_lbl.text = "Playing audio..."
		else:
			audio_player.stream_paused = false
			audio_player.play()
			btn_play_pause.text = "⏸ Pause"
			status_lbl.text = "Playing audio..."
	)

	# Scrubber seek bar interaction
	var is_user_scrubbing = false
	slider.drag_started.connect(func(): is_user_scrubbing = true)
	slider.drag_ended.connect(func(_val_changed):
		is_user_scrubbing = false
		if is_audio_loaded:
			audio_player.stream_paused = false
			audio_player.play(slider.value)
			btn_play_pause.text = "⏸ Pause"
			status_lbl.text = "Playing from " + _format_time_str.call(slider.value)
	)

	# Timer for updating playback scrubber position
	var timer = Timer.new()
	timer.wait_time = 0.1
	timer.autostart = true
	add_child(timer)
	timer.timeout.connect(func():
		if is_audio_loaded and audio_player.playing and not is_user_scrubbing:
			var pos = audio_player.get_playback_position()
			current_saved_pos = pos
			slider.value = pos
			time_lbl.text = _format_time_str.call(pos) + " / " + _format_time_str.call(total_duration_sec)
	)

	audio_player.finished.connect(func():
		current_saved_pos = 0.0
		btn_play_pause.text = "▶ Play Audio"
		status_lbl.text = "Playback finished."
		slider.value = 0.0
		time_lbl.text = "0:00 / " + _format_time_str.call(total_duration_sec)
	)

	# Action buttons row
	var btn_hbox = HBoxContainer.new()
	btn_hbox.alignment = BoxContainer.ALIGNMENT_END
	btn_hbox.add_theme_constant_override("separation", 10)

	var btn_transcribe = Button.new()
	btn_transcribe.text = "✨ Re-Transcribe"
	btn_transcribe.custom_minimum_size = Vector2(140, 32)
	var tr_st = StyleBoxFlat.new()
	tr_st.bg_color = _get_active_theme_color()
	tr_st.corner_radius_top_left = 6; tr_st.corner_radius_top_right = 6; tr_st.corner_radius_bottom_left = 6; tr_st.corner_radius_bottom_right = 6
	tr_st.content_margin_left = 12; tr_st.content_margin_right = 12; tr_st.content_margin_top = 6; tr_st.content_margin_bottom = 6
	btn_transcribe.add_theme_stylebox_override("normal", tr_st)
	btn_transcribe.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 1.0))

	btn_transcribe.pressed.connect(func():
		btn_transcribe.text = "⏳ Transcribing Audio..."
		btn_transcribe.disabled = true

		var api_key = ""
		if db:
			var k_res = db.execute("SELECT setting_value FROM app_settings WHERE setting_key = 'GEMINI_API_KEY' LIMIT 1;")
			if k_res["success"] and k_res["data"].size() > 0:
				api_key = str(k_res["data"][0]["setting_value"]).strip_edges()
		if api_key == "": api_key = OS.get_environment("GEMINI_API_KEY")

		var _start_process_ref = [null]

		var _exec_transcribe = func(key_str: String, raw_audio_b64: String):
			var gem_http = HTTPRequest.new()
			add_child(gem_http)

			var g_url = "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key=" + key_str
			var g_headers = ["Content-Type: application/json"]
			var g_body = JSON.stringify({
				"contents": [
					{
						"parts": [
							{
								"inline_data": {
									"mime_type": "audio/mp3",
									"data": raw_audio_b64
								}
							},
							{ "text": "Please provide an accurate word-for-word text transcription of this voicemail audio recording. Return ONLY the transcription text:" }
						]
					}
				]
			})

			gem_http.request_completed.connect(func(_gr, gcode, _ghdrs, gbody_bytes):
				gem_http.queue_free()
				var new_trans = ""
				var resp_raw = gbody_bytes.get_string_from_utf8()
				print("[Gemini Response] Code: ", gcode, " Body: ", resp_raw.left(200))

				if gcode == 200:
					var json = JSON.parse_string(resp_raw)
					if json and json.has("candidates") and json["candidates"].size() > 0:
						var cand = json["candidates"][0]
						if cand.has("content") and cand["content"].has("parts") and cand["content"]["parts"].size() > 0:
							new_trans = str(cand["content"]["parts"][0].get("text", "")).strip_edges()

				if new_trans != "":
					trans_lbl.text = "\"" + new_trans + "\""
					trans_lbl.add_theme_color_override("font_color", Color(0.20, 0.25, 0.32, 1.0))
					com_service.update_voicemail_transcription(vm_uuid, new_trans)
					btn_transcribe.text = "✅ Transcribed!"
					status_lbl.text = "Transcription updated successfully."
				else:
					if gcode == 429:
						status_lbl.text = "Gemini Error 429: Rate limit/Quota 0 for this key. Get key at aistudio.google.com"
					elif gcode == 400 or gcode == 403:
						status_lbl.text = "Gemini Error " + str(gcode) + ": Invalid API Key."
					else:
						status_lbl.text = "Gemini transcription failed (HTTP " + str(gcode) + ")."
					btn_transcribe.text = "✨ Re-Transcribe"
					btn_transcribe.disabled = false
			)
			gem_http.request(g_url, g_headers, HTTPClient.METHOD_POST, g_body)

		var _start_process = func(valid_key: String):
			if audio_bytes_cache.size() > 0:
				_exec_transcribe.call(valid_key, Marshalls.raw_to_base64(audio_bytes_cache))
			else:
				_fetch_twilio_audio.call(recording_url, func(code: int, body: PackedByteArray):
					if code == 200 and body.size() > 0:
						_exec_transcribe.call(valid_key, Marshalls.raw_to_base64(body))
					else:
						btn_transcribe.text = "✨ Re-Transcribe with Gemini"
						btn_transcribe.disabled = false
				)

		_start_process_ref[0] = _start_process

		if api_key == "":
			_prompt_gemini_api_key_dialog(func(new_key: String):
				_start_process.call(new_key)
			)
		else:
			_start_process.call(api_key)
	)

	var btn_close = Button.new()
	btn_close.text = "Close"
	btn_close.custom_minimum_size = Vector2(80, 32)
	btn_close.pressed.connect(func():
		timer.stop()
		timer.queue_free()
		audio_player.stop()
		audio_player.queue_free()
		backdrop.queue_free()
		_refresh_all_feeds()
	)

	btn_hbox.add_child(btn_transcribe)
	btn_hbox.add_child(btn_close)
	vbox.add_child(btn_hbox)

func _prompt_gemini_api_key_dialog(on_saved_callback: Callable) -> void:
	var backdrop = ColorRect.new()
	backdrop.color = Color(0.08, 0.12, 0.18, 0.7)
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)

	var center = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.add_child(center)

	var card = PanelContainer.new()
	var card_st = StyleBoxFlat.new()
	card_st.bg_color = Color(1.0, 1.0, 1.0, 1.0)
	card_st.corner_radius_top_left = 12; card_st.corner_radius_top_right = 12; card_st.corner_radius_bottom_left = 12; card_st.corner_radius_bottom_right = 12
	card_st.content_margin_left = 22; card_st.content_margin_top = 20; card_st.content_margin_right = 22; card_st.content_margin_bottom = 20
	card.add_theme_stylebox_override("panel", card_st)
	center.add_child(card)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	vbox.custom_minimum_size = Vector2(400, 160)
	card.add_child(vbox)

	var title = Label.new()
	title.text = "🔑 Gemini API Key Required"
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", _get_active_theme_color())
	vbox.add_child(title)

	var desc = Label.new()
	desc.text = "Enter your Google Gemini API Key to enable instant AI audio transcription:"
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.add_theme_font_size_override("font_size", 12)
	desc.add_theme_color_override("font_color", Color(0.35, 0.40, 0.50, 1.0))
	vbox.add_child(desc)

	var key_edit = LineEdit.new()
	key_edit.placeholder_text = "AIzaSy..."
	key_edit.secret = true
	key_edit.add_theme_font_size_override("font_size", 13)
	vbox.add_child(key_edit)

	var btn_hbox = HBoxContainer.new()
	btn_hbox.alignment = BoxContainer.ALIGNMENT_END
	btn_hbox.add_theme_constant_override("separation", 10)

	var btn_cancel = Button.new(); btn_cancel.text = "Cancel"
	var btn_save = Button.new(); btn_save.text = "💾 Save & Transcribe"
	var save_st = StyleBoxFlat.new()
	save_st.bg_color = Color(0.12, 0.53, 0.90, 1.0)
	save_st.corner_radius_top_left = 6; save_st.corner_radius_top_right = 6; save_st.corner_radius_bottom_left = 6; save_st.corner_radius_bottom_right = 6
	btn_save.add_theme_stylebox_override("normal", save_st)
	btn_save.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 1.0))

	btn_cancel.pressed.connect(func(): backdrop.queue_free())
	btn_save.pressed.connect(func():
		var k = key_edit.text.strip_edges()
		if k != "":
			if db:
				db.execute("INSERT OR REPLACE INTO app_settings (setting_key, setting_value) VALUES ('GEMINI_API_KEY', ?);", [k])
			backdrop.queue_free()
			on_saved_callback.call(k)
	)

	btn_hbox.add_child(btn_cancel)
	btn_hbox.add_child(btn_save)
	vbox.add_child(btn_hbox)


