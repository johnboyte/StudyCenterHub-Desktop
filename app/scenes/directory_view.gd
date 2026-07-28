extends "res://app/scenes/standard_page_container.gd"

## Directory Roster Shell & Person Workspace (Story DIR-SPR1-005B)
## Strictly Read-Only: Binds exclusively to DirectoryReadService.
## Zero business mutations, zero outbox events, zero timestamp modifications.

const SQLiteDatabaseScript = preload("res://src/infrastructure/database/sqlite_database.gd")
const MigrationsRunnerScript = preload("res://src/infrastructure/database/migrations_runner.gd")
const DirectoryReadServiceScript = preload("res://src/domain/directory/directory_read_service.gd")
const QrGeneratorScript = preload("res://src/domain/sync/qr_code_generator.gd")
const MembershipCardEngineScript = preload("res://src/domain/sync/membership_card_engine.gd")
const CardPrintQueueDialogScript = preload("res://app/scenes/card_print_queue_dialog.gd")
const PublicQrSignDialogScript = preload("res://app/scenes/public_qr_sign_dialog.gd")
const QRCredentialServiceScript = preload("res://src/domain/security/qr_credential_service.gd")
const CommunicationsServiceScript = preload("res://src/domain/communications/communications_service.gd")
const AppleWalletServiceScript = preload("res://src/domain/security/apple_wallet_service.gd")
const GoogleWalletServiceScript = preload("res://src/domain/security/google_wallet_service.gd")
const WorkQueueHeaderBarScene = preload("res://app/scenes/components/work_queue_header_bar.tscn")
const QueueControllerScript = preload("res://src/domain/work_queue/queue_controller.gd")
const QueueRegistryScript = preload("res://src/domain/work_queue/queue_registry.gd")

var db: RefCounted
var read_service: RefCounted

var current_filter: String = "all" # "all", "active", "pending", "inactive"
var current_query: String = ""
var selected_person_uuid: String = ""
var current_workspace_section: String = "overview" # "profile", "communications", "participation", "overview", "history"

var visible_people: Array = []
var selected_person_index: int = -1

var debounce_timer: Timer
var _active_photo_callback: Callable = Callable()

# Queue Mode Members
var is_queue_mode: bool = false
var active_queue_id: String = ""
var queue_controller: RefCounted = null
var header_bar_instance: Control = null
var queue_card_container: PanelContainer = null

@onready var btn_filter_all: Button = $MarginContainer/VBoxContainer/HeaderBar/FilterContainer/BtnFilterAll
@onready var btn_filter_active: Button = $MarginContainer/VBoxContainer/HeaderBar/FilterContainer/BtnFilterActive
@onready var btn_filter_pending: Button = $MarginContainer/VBoxContainer/HeaderBar/FilterContainer/BtnFilterPending
@onready var btn_filter_inactive: Button = $MarginContainer/VBoxContainer/HeaderBar/FilterContainer/BtnFilterInactive
@onready var btn_add_person_placeholder: Button = $MarginContainer/VBoxContainer/HeaderBar/BtnAddPersonPlaceholder

@onready var search_input: LineEdit = $MarginContainer/VBoxContainer/SubHeaderBar/SearchInput
@onready var results_count_label: Label = $MarginContainer/VBoxContainer/SubHeaderBar/ResultsCountLabel

var is_roster_collapsed: bool = false

@onready var roster_panel: PanelContainer = $MarginContainer/VBoxContainer/MainSplit/RosterPanel
@onready var roster_container: VBoxContainer = $MarginContainer/VBoxContainer/MainSplit/RosterPanel/RosterScroll/RosterContainer
@onready var loading_state: Label = $MarginContainer/VBoxContainer/MainSplit/RosterPanel/LoadingState
@onready var empty_state: Label = $MarginContainer/VBoxContainer/MainSplit/RosterPanel/EmptyState
@onready var no_results_state: Label = $MarginContainer/VBoxContainer/MainSplit/RosterPanel/NoResultsState
@onready var error_state: Label = $MarginContainer/VBoxContainer/MainSplit/RosterPanel/ErrorState

@onready var workspace_panel: PanelContainer = $MarginContainer/VBoxContainer/MainSplit/WorkspacePanel
@onready var no_selection_workspace: Label = $MarginContainer/VBoxContainer/MainSplit/WorkspacePanel/WorkspaceMargin/NoSelectionWorkspace
@onready var selected_workspace_vbox: VBoxContainer = $MarginContainer/VBoxContainer/MainSplit/WorkspacePanel/WorkspaceMargin/SelectedWorkspaceVBox

@onready var btn_toggle_roster: Button = $MarginContainer/VBoxContainer/MainSplit/WorkspacePanel/WorkspaceMargin/SelectedWorkspaceVBox/WorkspaceHeader/HeaderMargin/HeaderVBox/TitleHBox/BtnToggleRoster
@onready var workspace_initials: Label = $MarginContainer/VBoxContainer/MainSplit/WorkspacePanel/WorkspaceMargin/SelectedWorkspaceVBox/WorkspaceHeader/HeaderMargin/HeaderVBox/TitleHBox/AvatarInitials
@onready var workspace_name: Label = $MarginContainer/VBoxContainer/MainSplit/WorkspacePanel/WorkspaceMargin/SelectedWorkspaceVBox/WorkspaceHeader/HeaderMargin/HeaderVBox/TitleHBox/NameLabel
@onready var workspace_human_id: Label = $MarginContainer/VBoxContainer/MainSplit/WorkspacePanel/WorkspaceMargin/SelectedWorkspaceVBox/WorkspaceHeader/HeaderMargin/HeaderVBox/MetaHBox/HumanIdLabel
@onready var workspace_status_badge: Label = $MarginContainer/VBoxContainer/MainSplit/WorkspacePanel/WorkspaceMargin/SelectedWorkspaceVBox/WorkspaceHeader/HeaderMargin/HeaderVBox/MetaHBox/StatusBadge
@onready var workspace_grade_badge: Label = $MarginContainer/VBoxContainer/MainSplit/WorkspacePanel/WorkspaceMargin/SelectedWorkspaceVBox/WorkspaceHeader/HeaderMargin/HeaderVBox/MetaHBox/GradeBadge

@onready var tab_profile: Button = $MarginContainer/VBoxContainer/MainSplit/WorkspacePanel/WorkspaceMargin/SelectedWorkspaceVBox/SectionTabBar/TabProfile
@onready var tab_notes: Button = $MarginContainer/VBoxContainer/MainSplit/WorkspacePanel/WorkspaceMargin/SelectedWorkspaceVBox/SectionTabBar/TabNotes
@onready var tab_communications: Button = $MarginContainer/VBoxContainer/MainSplit/WorkspacePanel/WorkspaceMargin/SelectedWorkspaceVBox/SectionTabBar/TabCommunications
@onready var tab_participation: Button = $MarginContainer/VBoxContainer/MainSplit/WorkspacePanel/WorkspaceMargin/SelectedWorkspaceVBox/SectionTabBar/TabParticipation
@onready var tab_overview: Button = $MarginContainer/VBoxContainer/MainSplit/WorkspacePanel/WorkspaceMargin/SelectedWorkspaceVBox/SectionTabBar/TabOverview
@onready var tab_history: Button = $MarginContainer/VBoxContainer/MainSplit/WorkspacePanel/WorkspaceMargin/SelectedWorkspaceVBox/SectionTabBar/TabHistory

@onready var profile_section: VBoxContainer = $MarginContainer/VBoxContainer/MainSplit/WorkspacePanel/WorkspaceMargin/SelectedWorkspaceVBox/WorkspaceScroll/SectionStack/ProfileSection
@onready var notes_section: VBoxContainer = $MarginContainer/VBoxContainer/MainSplit/WorkspacePanel/WorkspaceMargin/SelectedWorkspaceVBox/WorkspaceScroll/SectionStack/NotesSection
@onready var participation_section: VBoxContainer = $MarginContainer/VBoxContainer/MainSplit/WorkspacePanel/WorkspaceMargin/SelectedWorkspaceVBox/WorkspaceScroll/SectionStack/ParticipationSection
@onready var communications_section: VBoxContainer = $MarginContainer/VBoxContainer/MainSplit/WorkspacePanel/WorkspaceMargin/SelectedWorkspaceVBox/WorkspaceScroll/SectionStack/CommunicationsSection
@onready var overview_section: VBoxContainer = $MarginContainer/VBoxContainer/MainSplit/WorkspacePanel/WorkspaceMargin/SelectedWorkspaceVBox/WorkspaceScroll/SectionStack/OverviewSection
@onready var history_section: VBoxContainer = $MarginContainer/VBoxContainer/MainSplit/WorkspacePanel/WorkspaceMargin/SelectedWorkspaceVBox/WorkspaceScroll/SectionStack/HistorySection

func _ready() -> void:
	_init_debounce_timer()
	if not read_service:
		_init_read_service()
	_connect_signals()

func receive_navigation_context(params: Dictionary) -> void:
	if params.get("queue_mode", false) == true:
		var qid = params.get("queue_id", "")
		if qid == "registrations_awaiting_review":
			configure_queue_mode(params)
		else:
			_clear_queue_mode()
	else:
		_clear_queue_mode()

func configure_queue_mode(params: Dictionary = {}) -> void:
	is_queue_mode = true
	active_queue_id = params.get("queue_id", "registrations_awaiting_review")

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

func _attach_header_bar() -> void:
	if header_bar_instance: return

	var parent_container = $MarginContainer/VBoxContainer if has_node("MarginContainer/VBoxContainer") else (get_child(0) if get_child_count() > 0 else self)
	if parent_container:
		header_bar_instance = WorkQueueHeaderBarScene.instantiate()
		parent_container.add_child(header_bar_instance)
		if parent_container.has_method("move_child"):
			parent_container.move_child(header_bar_instance, 0)

		var cur_idx = queue_controller.current_index if queue_controller else 0
		var rem_count = queue_controller.get_remaining_count() if queue_controller else 0
		var def = QueueRegistryScript.get_definition(active_queue_id)
		var q_title = def.get("title", "Registrations Awaiting Review")
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
		var parent_container = $MarginContainer/VBoxContainer if has_node("MarginContainer/VBoxContainer") else (get_child(0) if get_child_count() > 0 else self)
		if parent_container:
			parent_container.add_child(queue_card_container)
			if parent_container.has_method("move_child") and header_bar_instance:
				parent_container.move_child(queue_card_container, 1)

	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.98, 0.99, 1.0, 1.0)
	style.border_width_left = 2; style.border_width_top = 2; style.border_width_right = 2; style.border_width_bottom = 2
	style.border_color = Color(0.12, 0.53, 0.90, 1.0)
	style.corner_radius_top_left = 12; style.corner_radius_top_right = 12; style.corner_radius_bottom_left = 12; style.corner_radius_bottom_right = 12
	style.content_margin_left = 20; style.content_margin_top = 18; style.content_margin_right = 20; style.content_margin_bottom = 18
	queue_card_container.add_theme_stylebox_override("panel", style)

	for child in queue_card_container.get_children():
		queue_card_container.remove_child(child)
		child.queue_free()

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	queue_card_container.add_child(vbox)

	if rem_count == 0 or not queue_controller:
		var empty_lbl = Label.new()
		empty_lbl.text = "✨ Queue Complete! All items in " + q_title + " have been resolved."
		empty_lbl.add_theme_font_size_override("font_size", 16)
		empty_lbl.add_theme_color_override("font_color", Color(0.18, 0.55, 0.35, 1.0))
		vbox.add_child(empty_lbl)

		var exit_btn = Button.new()
		exit_btn.text = "Return to Standard Directory"
		exit_btn.custom_minimum_size = Vector2(240, 36)
		exit_btn.pressed.connect(_on_queue_exit)
		vbox.add_child(exit_btn)
		return

	var current_item = queue_controller.get_current_item()
	if current_item.is_empty():
		return

	var item_id = current_item.get("id", 0)
	var first_name = str(current_item.get("first_name", ""))
	var last_name = str(current_item.get("last_name", ""))
	var name = (first_name + " " + last_name).strip_edges()
	var human_id = str(current_item.get("human_id", ""))
	var phone = str(current_item.get("phone", ""))
	var role = str(current_item.get("primary_role", "Participant"))

	var hdr_lbl = Label.new()
	hdr_lbl.text = "REGISTRATION AWAITING REVIEW — " + name + " (" + human_id + ")"
	hdr_lbl.add_theme_font_size_override("font_size", 16)
	hdr_lbl.add_theme_color_override("font_color", Color(0.08, 0.12, 0.18, 1.0))
	vbox.add_child(hdr_lbl)

	var details_lbl = Label.new()
	details_lbl.text = "Role: " + role + " | Phone: " + (phone if phone != "" else "Not on file")
	details_lbl.add_theme_font_size_override("font_size", 14)
	details_lbl.add_theme_color_override("font_color", Color(0.20, 0.25, 0.32, 1.0))
	vbox.add_child(details_lbl)

	var btn_hbox = HBoxContainer.new()
	btn_hbox.add_theme_constant_override("separation", 12)
	vbox.add_child(btn_hbox)

	var comp_btn = Button.new()
	comp_btn.text = "✅ Approve & Mark Reviewed"
	comp_btn.custom_minimum_size = Vector2(220, 38)
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
	_style_add_person_button()

	var header_bar = get_node_or_null("MarginContainer/VBoxContainer/HeaderBar")
	if header_bar:
		var btn_card_queue = Button.new()
		btn_card_queue.text = "🎴 Card Print Queue"
		btn_card_queue.custom_minimum_size = Vector2(170, 36)
		btn_card_queue.pressed.connect(func(): _open_card_print_queue_dialog())
		header_bar.add_child(btn_card_queue)

	var win = get_window()
	if win:
		win.files_dropped.connect(_on_window_files_dropped)
	refresh_view()

func _get_active_theme_color() -> Color:
	if not db:
		db = SQLiteDatabaseScript.new()
		var mig = MigrationsRunnerScript.new(db)
		mig.run_migrations()

	var idx = 1
	if db:
		var res = db.execute("SELECT setting_value FROM app_settings WHERE setting_key = 'ORG_ACCENT_INDEX' LIMIT 1;")
		if res["success"] and res["data"].size() > 0:
			idx = int(res["data"][0].get("setting_value", "1"))

	if idx == 0:
		return Color(0.596, 0.192, 0.255, 1.0) # AU Crimson Red #983141
	elif idx == 1:
		return Color(0.88, 0.35, 0.21, 1.0) # Warm Terracotta Orange #E05A36
	elif idx == 2:
		return Color(0.10, 0.15, 0.21, 1.0) # Deep Navy #1A2536
	elif idx == 3:
		return Color(0.18, 0.49, 0.20, 1.0) # Forest Green #2E7D32
	elif idx == 4:
		return Color(0.42, 0.11, 0.60, 1.0) # Royal Purple #6A1B9A
	return Color(0.88, 0.35, 0.21, 1.0)

func _style_add_person_button() -> void:
	if not btn_add_person_placeholder: return

	var theme_col = _get_active_theme_color()

	var btn_st = StyleBoxFlat.new()
	btn_st.bg_color = theme_col
	btn_st.corner_radius_top_left = 6
	btn_st.corner_radius_top_right = 6
	btn_st.corner_radius_bottom_left = 6
	btn_st.corner_radius_bottom_right = 6
	btn_st.content_margin_left = 16
	btn_st.content_margin_top = 8
	btn_st.content_margin_right = 16
	btn_st.content_margin_bottom = 8

	var hover_st = StyleBoxFlat.new()
	hover_st.bg_color = theme_col.lightened(0.08)
	hover_st.corner_radius_top_left = 6
	hover_st.corner_radius_top_right = 6
	hover_st.corner_radius_bottom_left = 6
	hover_st.corner_radius_bottom_right = 6
	hover_st.content_margin_left = 16
	hover_st.content_margin_top = 8
	hover_st.content_margin_right = 16
	hover_st.content_margin_bottom = 8

	btn_add_person_placeholder.disabled = false
	btn_add_person_placeholder.add_theme_stylebox_override("normal", btn_st)
	btn_add_person_placeholder.add_theme_stylebox_override("hover", hover_st)
	btn_add_person_placeholder.add_theme_stylebox_override("pressed", btn_st)
	btn_add_person_placeholder.add_theme_stylebox_override("focus", btn_st)
	btn_add_person_placeholder.add_theme_stylebox_override("disabled", btn_st)

	btn_add_person_placeholder.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 1.0))
	btn_add_person_placeholder.add_theme_color_override("font_hover_color", Color(1.0, 1.0, 1.0, 1.0))
	btn_add_person_placeholder.add_theme_color_override("font_pressed_color", Color(1.0, 1.0, 1.0, 1.0))
	btn_add_person_placeholder.add_theme_color_override("font_focus_color", Color(1.0, 1.0, 1.0, 1.0))
	btn_add_person_placeholder.add_theme_color_override("font_disabled_color", Color(1.0, 1.0, 1.0, 1.0))
	btn_add_person_placeholder.add_theme_font_size_override("font_size", 15)
	btn_add_person_placeholder.text = "➕ Add Member"

func set_read_service(service: RefCounted) -> void:
	read_service = service
	if debounce_timer:
		debounce_timer.stop()
	if is_inside_tree():
		refresh_view()

func _init_read_service() -> void:
	if not db:
		db = SQLiteDatabaseScript.new()
		var migrations_runner = MigrationsRunnerScript.new(db)
		migrations_runner.run_migrations()
	read_service = DirectoryReadServiceScript.new(db)

func _init_debounce_timer() -> void:
	debounce_timer = Timer.new()
	debounce_timer.one_shot = true
	debounce_timer.wait_time = 0.20
	debounce_timer.timeout.connect(_on_debounce_timeout)
	add_child(debounce_timer)

func _connect_signals() -> void:
	if btn_filter_all:
		btn_filter_all.pressed.connect(func(): select_filter("all"))
	if btn_filter_active:
		btn_filter_active.pressed.connect(func(): select_filter("active"))
	if btn_filter_pending:
		btn_filter_pending.pressed.connect(func(): select_filter("pending"))
	if btn_filter_inactive:
		btn_filter_inactive.pressed.connect(func(): select_filter("inactive"))
	if search_input:
		search_input.text_changed.connect(_on_search_text_changed)

	if btn_add_person_placeholder:
		btn_add_person_placeholder.pressed.connect(_on_add_person_pressed)

	if btn_toggle_roster:
		btn_toggle_roster.pressed.connect(_toggle_roster_drawer)

	if tab_profile:
		tab_profile.pressed.connect(func(): select_workspace_tab("profile"))
	if tab_notes:
		tab_notes.pressed.connect(func(): select_workspace_tab("notes"))
	if tab_communications:
		tab_communications.pressed.connect(func(): select_workspace_tab("communications"))
	if tab_participation:
		tab_participation.pressed.connect(func(): select_workspace_tab("participation"))
	if tab_overview:
		tab_overview.pressed.connect(func(): select_workspace_tab("overview"))
	if tab_history:
		tab_history.pressed.connect(func(): select_workspace_tab("history"))

func _toggle_roster_drawer() -> void:
	is_roster_collapsed = not is_roster_collapsed
	if roster_panel:
		roster_panel.visible = not is_roster_collapsed
	if btn_toggle_roster:
		btn_toggle_roster.text = "▶ Show Roster" if is_roster_collapsed else "◀ Hide Roster"

func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.is_pressed():
		return

	var key_event = event as InputEventKey
	if key_event.keycode == KEY_SLASH and search_input and not search_input.has_focus():
		search_input.grab_focus()
		get_viewport().set_input_as_handled()
		return
	elif key_event.keycode == KEY_K and (key_event.ctrl_pressed or key_event.meta_pressed) and search_input:
		search_input.grab_focus()
		get_viewport().set_input_as_handled()
		return

	if search_input and search_input.has_focus():
		if key_event.keycode == KEY_ESCAPE:
			if search_input.text != "":
				set_search_query("")
			else:
				search_input.release_focus()
			get_viewport().set_input_as_handled()
			return

	if visible_people.size() > 0:
		if key_event.keycode == KEY_DOWN:
			var new_idx = clampi(selected_person_index + 1, 0, visible_people.size() - 1)
			select_person_by_index(new_idx)
			var vp = get_viewport()
			if vp: vp.set_input_as_handled()
		elif key_event.keycode == KEY_UP:
			var new_idx = clampi(selected_person_index - 1, 0, visible_people.size() - 1)
			select_person_by_index(new_idx)
			var vp = get_viewport()
			if vp: vp.set_input_as_handled()

func refresh_view() -> void:
	_ensure_onready_nodes()
	_active_photo_callback = Callable()
	_style_add_person_button()
	if not read_service:
		_show_view_state("error")
		return

	_show_view_state("loading")

	_update_header_filter_counts()
	_fetch_roster_data()

func select_filter(filter_name: String) -> void:
	if not filter_name in ["all", "active", "pending", "inactive"]:
		return
	current_filter = filter_name
	_update_filter_button_styles()
	refresh_view()

func set_search_query(query: String) -> void:
	current_query = query
	if search_input and search_input.text != query:
		search_input.text = query
	refresh_view()

func select_workspace_tab(tab_name: String) -> void:
	current_workspace_section = tab_name
	var tabs = {
		"profile": tab_profile,
		"notes": tab_notes,
		"communications": tab_communications,
		"participation": tab_participation,
		"overview": tab_overview,
		"history": tab_history
	}
	for k in tabs.keys():
		var btn = tabs[k] as Button
		if btn:
			var is_active = (k == tab_name)
			btn.flat = not is_active
			if is_active:
				var style_tab = StyleBoxFlat.new()
				style_tab.bg_color = Color(0.20, 0.32, 0.48, 1.0)
				style_tab.content_margin_left = 8
				style_tab.content_margin_right = 8
				style_tab.content_margin_top = 6
				style_tab.content_margin_bottom = 6
				style_tab.corner_radius_top_left = 4
				style_tab.corner_radius_top_right = 4
				btn.add_theme_stylebox_override("normal", style_tab)
				btn.add_theme_stylebox_override("hover", style_tab)
				btn.add_theme_stylebox_override("pressed", style_tab)
			else:
				btn.remove_theme_stylebox_override("normal")
				btn.remove_theme_stylebox_override("hover")
				btn.remove_theme_stylebox_override("pressed")

	if profile_section: profile_section.visible = (tab_name == "profile")
	if notes_section: notes_section.visible = (tab_name == "notes")
	if communications_section: communications_section.visible = (tab_name == "communications")
	if participation_section: participation_section.visible = (tab_name == "participation")
	if overview_section: overview_section.visible = (tab_name == "overview")
	if history_section: history_section.visible = (tab_name == "history")

func _on_search_text_changed(new_text: String) -> void:
	current_query = new_text
	if debounce_timer:
		debounce_timer.start()

func _on_debounce_timeout() -> void:
	refresh_view()

func _update_header_filter_counts() -> void:
	if not read_service:
		return

	var total_cnt = read_service.count_people()
	var active_cnt = read_service.count_active()
	var pending_cnt = read_service.count_pending()
	var inactive_cnt = read_service.count_inactive()

	if btn_filter_all: btn_filter_all.text = "All (" + str(total_cnt) + ")"
	if btn_filter_active: btn_filter_active.text = "Active (" + str(active_cnt) + ")"
	if btn_filter_pending: btn_filter_pending.text = "Pending (" + str(pending_cnt) + ")"
	if btn_filter_inactive: btn_filter_inactive.text = "Inactive (" + str(inactive_cnt) + ")"

	_update_filter_button_styles()

func get_count_all_text() -> String:
	return str(read_service.count_people()) if read_service else "0"

func get_count_active_text() -> String:
	return str(read_service.count_active()) if read_service else "0"

func get_count_pending_text() -> String:
	return str(read_service.count_pending()) if read_service else "0"

func get_count_inactive_text() -> String:
	return str(read_service.count_inactive()) if read_service else "0"

func _update_filter_button_styles() -> void:
	var buttons = {
		"all": btn_filter_all,
		"active": btn_filter_active,
		"pending": btn_filter_pending,
		"inactive": btn_filter_inactive
	}
	for k in buttons.keys():
		var btn = buttons[k] as Button
		if btn:
			btn.flat = (k != current_filter)

func _fetch_roster_data() -> void:
	var options = {}
	if current_filter != "all":
		options["status"] = current_filter

	var res: Dictionary
	if current_query.strip_edges() != "":
		res = read_service.search_people(current_query, options)
	else:
		if current_filter == "all":
			res = read_service.list_people()
		elif current_filter == "active":
			res = read_service.list_active_people()
		elif current_filter == "pending":
			res = read_service.list_pending_people()
		elif current_filter == "inactive":
			res = read_service.list_inactive_people()

	if not res.get("success", false):
		_show_view_state("error")
		visible_people = []
		_clear_workspace()
		return

	visible_people = res.get("people", [])
	var count = visible_people.size()

	if results_count_label:
		results_count_label.text = str(count) + " constituent(s) visible"

	if count == 0:
		if current_query.strip_edges() != "":
			_show_view_state("no_results")
		else:
			_show_view_state("empty")
		_clear_workspace()
		return

	_show_view_state("populated")
	_render_roster_list()

	var retain_idx = -1
	if selected_person_uuid != "":
		for i in range(visible_people.size()):
			if visible_people[i].get("person_uuid", "") == selected_person_uuid:
				retain_idx = i
				break

	if retain_idx != -1:
		select_person_by_index(retain_idx)
	else:
		_clear_workspace()

func _render_roster_list() -> void:
	var r_box = roster_container if roster_container else get_node_or_null("MarginContainer/VBoxContainer/MainSplit/RosterPanel/RosterScroll/RosterContainer") as VBoxContainer
	if not r_box:
		return

	for child in r_box.get_children():
		child.free()

	for i in range(visible_people.size()):
		var p = visible_people[i]
		var btn = _create_roster_row_button(p, i)
		r_box.add_child(btn)

func _create_texture_from_base64(base64_str: String) -> ImageTexture:
	var b64_data = base64_str.strip_edges()
	if b64_data == "" or b64_data.to_lower() == "null" or b64_data.to_lower() == "<null>":
		return null
	if "," in b64_data:
		b64_data = b64_data.split(",")[1]
	var buffer = Marshalls.base64_to_raw(b64_data)
	if buffer.size() == 0:
		return null
	var img = Image.new()
	var err = img.load_jpg_from_buffer(buffer)
	if err != OK:
		err = img.load_png_from_buffer(buffer)
	if err != OK:
		return null
	return ImageTexture.create_from_image(img)

func _create_roster_row_button(p: Dictionary, index: int) -> Button:
	var btn = Button.new()
	btn.custom_minimum_size = Vector2(0, 68)
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT

	var margin = MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_PASS
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_bottom", 10)

	var hbox = HBoxContainer.new()
	hbox.mouse_filter = Control.MOUSE_FILTER_PASS
	hbox.add_theme_constant_override("separation", 16)

	var first_name = p.get("first_name", "")
	var last_name = p.get("last_name", "")
	var initials = (first_name.left(1) + last_name.left(1)).to_upper()

	var photo_tex = _create_texture_from_base64(String(p.get("profile_photo")) if p.get("profile_photo") != null else "")
	if photo_tex:
		var avatar_rect = TextureRect.new()
		avatar_rect.texture = photo_tex
		avatar_rect.custom_minimum_size = Vector2(42, 42)
		avatar_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		avatar_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		hbox.add_child(avatar_rect)
	else:
		var avatar = Label.new()
		avatar.text = initials
		avatar.custom_minimum_size = Vector2(42, 42)
		avatar.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		avatar.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		avatar.add_theme_font_size_override("font_size", 15)

		var av_style = StyleBoxFlat.new()
		av_style.bg_color = Color(0.20, 0.26, 0.36, 1.0)
		av_style.corner_radius_top_left = 21
		av_style.corner_radius_top_right = 21
		av_style.corner_radius_bottom_left = 21
		av_style.corner_radius_bottom_right = 21
		avatar.add_theme_stylebox_override("normal", av_style)
		hbox.add_child(avatar)

	var vbox_text = VBoxContainer.new()
	vbox_text.custom_minimum_size = Vector2(180, 0)
	vbox_text.add_theme_constant_override("separation", 2)

	var name_label = Label.new()
	name_label.name = "NameLabel"
	name_label.text = first_name + " " + last_name
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.add_theme_font_size_override("font_size", 18)
	name_label.add_theme_color_override("font_color", Color(0.95, 0.97, 1.0))
	vbox_text.add_child(name_label)

	var id_label = Label.new()
	id_label.text = p.get("human_id", "")
	id_label.add_theme_font_size_override("font_size", 14)
	id_label.add_theme_color_override("font_color", Color(0.75, 0.82, 0.92))
	vbox_text.add_child(id_label)

	hbox.add_child(vbox_text)

	var trailing_spacer = Control.new()
	trailing_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(trailing_spacer)

	margin.add_child(hbox)
	btn.add_child(margin)
	btn.pressed.connect(func(): select_person_by_index(index))
	return btn

func select_person_by_index(index: int) -> void:
	if index < 0 or index >= visible_people.size():
		_clear_workspace()
		return

	selected_person_index = index
	var p = visible_people[index]
	selected_person_uuid = p.get("person_uuid", "")

	var r_box = roster_container if roster_container else get_node_or_null("MarginContainer/VBoxContainer/MainSplit/RosterPanel/RosterScroll/RosterContainer") as VBoxContainer
	if r_box:
		var children = r_box.get_children()
		for i in range(children.size()):
			var btn = children[i] as Button
			if btn:
				var is_sel = (i == index)
				btn.flat = not is_sel
				if is_sel:
					var style_sel = StyleBoxFlat.new()
					style_sel.bg_color = Color(0.18, 0.26, 0.38, 1.0)
					style_sel.border_width_left = 4
					style_sel.border_color = Color(0.35, 0.60, 0.90, 1.0)
					style_sel.content_margin_left = 14
					style_sel.content_margin_right = 14
					style_sel.content_margin_top = 8
					style_sel.content_margin_bottom = 8
					style_sel.corner_radius_top_left = 6
					style_sel.corner_radius_bottom_left = 6
					style_sel.corner_radius_top_right = 6
					style_sel.corner_radius_bottom_right = 6
					btn.add_theme_stylebox_override("normal", style_sel)
					btn.add_theme_stylebox_override("hover", style_sel)
					btn.add_theme_stylebox_override("pressed", style_sel)
				else:
					btn.remove_theme_stylebox_override("normal")
					btn.remove_theme_stylebox_override("hover")
					btn.remove_theme_stylebox_override("pressed")

	var att_res = read_service.get_person_attendance_history(selected_person_uuid)
	var att_history = att_res.get("history", []) if att_res.get("success", false) else []

	_render_person_workspace(p, att_history)

func _render_person_workspace(p: Dictionary, att_history: Array) -> void:
	_ensure_onready_nodes()
	if no_selection_workspace: no_selection_workspace.visible = false
	if selected_workspace_vbox: selected_workspace_vbox.visible = true

	var first_name = p.get("first_name", "")
	var last_name = p.get("last_name", "")
	var initials = (first_name.left(1) + last_name.left(1)).to_upper()

	if workspace_initials: workspace_initials.text = initials
	if workspace_name: workspace_name.text = first_name + " " + last_name
	if workspace_human_id: workspace_human_id.text = "Human ID: " + p.get("human_id", "")

	var st = p.get("status", "active")
	if workspace_status_badge:
		if st == "active":
			workspace_status_badge.text = "Status: Active"
		elif st == "pending" or st == "To Be Confirmed":
			workspace_status_badge.text = "Status: Pending (To Be Confirmed)"
		else:
			workspace_status_badge.text = "Status: Inactive"

	var grade_val = _clean_str(p.get("grade", ""))
	if workspace_grade_badge:
		if grade_val != "":
			workspace_grade_badge.text = _get_vocab_grade_label() + ": " + grade_val
			workspace_grade_badge.visible = true
		else:
			workspace_grade_badge.visible = false

	_clear_container(overview_section)
	_clear_container(profile_section)
	_clear_container(notes_section)
	_clear_container(participation_section)
	_clear_container(communications_section)
	_clear_container(history_section)

	_populate_overview_section(p, att_history)
	_populate_profile_section(p)
	_populate_notes_section(p)
	_populate_participation_section(p, att_history)
	_populate_communications_section(p)
	_populate_history_section(p, att_history)

	select_workspace_tab(current_workspace_section)

func _populate_overview_section(p: Dictionary, att_history: Array) -> void:
	if not overview_section: return

	# 1. Operational Summary KPI Cards Grid
	var grid = GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)

	var flag_val = str(p.get("flag_status", "To Be Confirmed"))
	var sms_val = "Granted" if (int(p.get("sms_consent", 1)) == 1 or bool(p.get("sms_consent_given", true))) else "Not Granted"
	var qr_val = str(p.get("qr_status", "Not Issued"))
	var pin_val = str(p.get("pin_status", "Not Set"))
	var human_id = str(p.get("human_id", "PRT-1028"))

	grid.add_child(_create_kpi_card("REGISTRATION FLAG", flag_val, Color(1.0, 0.75, 0.35, 1.0) if flag_val != "Clear" else Color(0.40, 0.85, 0.60, 1.0)))
	grid.add_child(_create_kpi_card("SMS CONSENT", sms_val, Color(0.40, 0.85, 0.60, 1.0) if sms_val == "Granted" else Color(0.80, 0.85, 0.90, 1.0)))
	grid.add_child(_create_kpi_card("PARTICIPANT ID", human_id, Color(0.90, 0.95, 1.0, 1.0)))
	grid.add_child(_create_kpi_card("QR STATUS", qr_val, Color(0.70, 0.80, 0.90, 1.0)))
	grid.add_child(_create_kpi_card("PIN STATUS", pin_val, Color(0.70, 0.80, 0.90, 1.0)))
	grid.add_child(_create_kpi_card("CHECK-INS", str(att_history.size()) + " Total", Color(0.40, 0.85, 0.60, 1.0)))

	overview_section.add_child(_create_card("Operational Summary KPI Cards", grid))
	overview_section.add_child(_create_credentials_card(p, str(p.get("person_uuid", ""))))

func _on_take_camera_photo_pressed(_person_uuid: String) -> void:
	if OS.get_name() == "macOS":
		OS.execute("open", ["-a", "Photo Booth"])
	elif OS.get_name() == "Windows":
		OS.execute("cmd.exe", ["/c", "start ms-windows-camera:"])

func _load_image_from_file(path: String) -> Image:
	var file = FileAccess.open(path, FileAccess.READ)
	if not file:
		return null
	var bytes = file.get_buffer(file.get_length())
	file.close()
	if bytes.size() == 0:
		return null
	var img = Image.new()
	var err = img.load_jpg_from_buffer(bytes)
	if err != OK:
		err = img.load_png_from_buffer(bytes)
	if err == OK:
		return img
	return null

func _on_window_files_dropped(files: PackedStringArray) -> void:
	if files.size() == 0 or not _active_photo_callback.is_valid():
		return
	var path = files[0]
	var ext = path.get_extension().to_lower()
	if ext in ["png", "jpg", "jpeg"]:
		var img = _load_image_from_file(path)
		if img:
			_open_image_editor(img, _active_photo_callback)

func _on_update_photo_pressed(person_uuid: String) -> void:
	var fd = FileDialog.new()
	fd.access = FileDialog.ACCESS_FILESYSTEM
	fd.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	fd.filters = PackedStringArray(["*.png, *.jpg, *.jpeg ; Image Files"])
	fd.title = "Select Profile Photo / Face Shot Image"
	fd.size = Vector2i(700, 500)
	fd.file_selected.connect(func(path: String):
		var img = _load_image_from_file(path)
		if img and _active_photo_callback.is_valid():
			_open_image_editor(img, _active_photo_callback)
	)
	add_child(fd)
	fd.popup_centered()

func _create_kpi_card(title: String, val_text: String, accent_color: Color) -> PanelContainer:
	var panel = PanelContainer.new()
	var st = StyleBoxFlat.new()
	st.bg_color = Color(0.12, 0.18, 0.26, 1.0)
	st.border_width_left = 1; st.border_width_top = 1; st.border_width_right = 1; st.border_width_bottom = 1
	st.border_color = Color(0.25, 0.32, 0.44, 1.0)
	st.corner_radius_top_left = 8; st.corner_radius_top_right = 8; st.corner_radius_bottom_left = 8; st.corner_radius_bottom_right = 8
	st.content_margin_left = 14; st.content_margin_top = 12; st.content_margin_right = 14; st.content_margin_bottom = 12
	panel.add_theme_stylebox_override("panel", st)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)

	var t_lbl = Label.new()
	t_lbl.text = title
	t_lbl.add_theme_font_size_override("font_size", 13)
	t_lbl.add_theme_color_override("font_color", Color(0.68, 0.78, 0.90, 1.0))
	vbox.add_child(t_lbl)

	var v_lbl = Label.new()
	v_lbl.text = val_text
	v_lbl.add_theme_font_size_override("font_size", 19)
	v_lbl.add_theme_color_override("font_color", accent_color)
	vbox.add_child(v_lbl)

	panel.add_child(vbox)
	return panel

func _clean_str(val) -> String:
	if val == null: return ""
	var s = str(val).strip_edges()
	if s.to_lower() == "<null>" or s.to_lower() == "null" or s.to_lower() == "nil":
		return ""
	return s

func _populate_profile_section(p: Dictionary) -> void:
	if not profile_section: return

	var p_uuid = _clean_str(p.get("person_uuid", ""))

	_active_photo_callback = func(cropped_data_url: String):
		if db:
			db.execute("UPDATE people SET profile_photo = ? WHERE person_uuid = ?;", [cropped_data_url, p_uuid])
		refresh_view()

	# 1. Profile Photo & Dynamic Camera Controls
	var photo_box = VBoxContainer.new()
	photo_box.add_theme_constant_override("separation", 12)
	var p_hbox = HBoxContainer.new()
	p_hbox.add_theme_constant_override("separation", 16)

	var raw_photo_b64 = _clean_str(p.get("profile_photo", ""))
	var photo_tex = _create_texture_from_base64(raw_photo_b64)
	var has_photo = (photo_tex != null)

	if has_photo:
		var photo_rect = TextureRect.new()
		photo_rect.texture = photo_tex
		photo_rect.custom_minimum_size = Vector2(96, 96)
		photo_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		photo_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		p_hbox.add_child(photo_rect)
	else:
		var fn = _clean_str(p.get("first_name", ""))
		var ln = _clean_str(p.get("last_name", ""))
		var initials = (fn.left(1) + ln.left(1)).to_upper()

		var no_photo_lbl = Label.new()
		no_photo_lbl.text = initials if initials != "" else "No Photo"
		no_photo_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		no_photo_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		no_photo_lbl.custom_minimum_size = Vector2(96, 96)
		no_photo_lbl.add_theme_font_size_override("font_size", 24)
		no_photo_lbl.add_theme_color_override("font_color", Color(0.70, 0.80, 0.95, 1.0))
		no_photo_lbl.mouse_filter = Control.MOUSE_FILTER_STOP
		no_photo_lbl.gui_input.connect(func(event: InputEvent):
			if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
				_open_native_camera_dialog(func(captured_img: Image):
					_open_image_editor(captured_img, _active_photo_callback)
				)
		)
		p_hbox.add_child(no_photo_lbl)

	var photo_btns_vbox = VBoxContainer.new()
	photo_btns_vbox.add_theme_constant_override("separation", 8)
	photo_btns_vbox.size_flags_horizontal = SIZE_EXPAND_FILL

	var photo_status_lbl = Label.new()
	photo_status_lbl.text = "✓ Active Face Shot Photo On File" if has_photo else "⚠️ No Profile Photo Uploaded"
	photo_status_lbl.add_theme_font_size_override("font_size", 14)
	photo_status_lbl.add_theme_color_override("font_color", Color(0.35, 0.85, 0.55, 1.0) if has_photo else Color(1.0, 0.75, 0.35, 1.0))
	photo_btns_vbox.add_child(photo_status_lbl)

	var btns_hbox = HBoxContainer.new()
	btns_hbox.add_theme_constant_override("separation", 10)

	var btn_camera_photo = Button.new()
	btn_camera_photo.text = "📸 Retake Photo" if has_photo else "📷 Take Photo"
	btn_camera_photo.custom_minimum_size = Vector2(175, 40)
	btn_camera_photo.add_theme_font_size_override("font_size", 15)
	btn_camera_photo.pressed.connect(func():
		_open_native_camera_dialog(func(captured_img: Image):
			_open_image_editor(captured_img, _active_photo_callback)
		)
	)
	btns_hbox.add_child(btn_camera_photo)

	var btn_upload_photo = Button.new()
	btn_upload_photo.text = "📁 Upload Image File"
	btn_upload_photo.custom_minimum_size = Vector2(175, 40)
	btn_upload_photo.add_theme_font_size_override("font_size", 15)
	btn_upload_photo.pressed.connect(func(): _on_update_photo_pressed(p_uuid))
	btns_hbox.add_child(btn_upload_photo)

	photo_btns_vbox.add_child(btns_hbox)
	p_hbox.add_child(photo_btns_vbox)
	photo_box.add_child(p_hbox)
	profile_section.add_child(_create_card("Profile Photo", photo_box))

	# 2. Contact & Identity Form Card
	var form_grid = GridContainer.new()
	form_grid.columns = 3
	form_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	form_grid.add_theme_constant_override("h_separation", 18)
	form_grid.add_theme_constant_override("v_separation", 16)

	# First Name
	var fn_vbox = VBoxContainer.new(); fn_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var fn_lbl = Label.new(); fn_lbl.text = "FIRST NAME"; fn_lbl.add_theme_font_size_override("font_size", 14); fn_lbl.add_theme_color_override("font_color", Color(0.70, 0.78, 0.88, 1.0))
	var fn_edit = LineEdit.new(); fn_edit.text = _clean_str(p.get("first_name", "")); fn_edit.custom_minimum_size = Vector2(0, 44); fn_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL; fn_edit.add_theme_font_size_override("font_size", 16)
	fn_vbox.add_child(fn_lbl); fn_vbox.add_child(fn_edit); form_grid.add_child(fn_vbox)

	# Last Name
	var ln_vbox = VBoxContainer.new(); ln_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var ln_lbl = Label.new(); ln_lbl.text = "LAST NAME"; ln_lbl.add_theme_font_size_override("font_size", 14); ln_lbl.add_theme_color_override("font_color", Color(0.70, 0.78, 0.88, 1.0))
	var ln_edit = LineEdit.new(); ln_edit.text = _clean_str(p.get("last_name", "")); ln_edit.custom_minimum_size = Vector2(0, 44); ln_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL; ln_edit.add_theme_font_size_override("font_size", 16)
	ln_vbox.add_child(ln_lbl); ln_vbox.add_child(ln_edit); form_grid.add_child(ln_vbox)

	# Suffix
	var suf_vbox = VBoxContainer.new(); suf_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var suf_lbl = Label.new(); suf_lbl.text = "SUFFIX (Jr, Sr, III)"; suf_lbl.add_theme_font_size_override("font_size", 14); suf_lbl.add_theme_color_override("font_color", Color(0.70, 0.78, 0.88, 1.0))
	var suf_edit = LineEdit.new(); suf_edit.text = _clean_str(p.get("suffix", "")); suf_edit.placeholder_text = "Jr, Sr, III"; suf_edit.custom_minimum_size = Vector2(0, 44); suf_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL; suf_edit.add_theme_font_size_override("font_size", 16)
	suf_vbox.add_child(suf_lbl); suf_vbox.add_child(suf_edit); form_grid.add_child(suf_vbox)

	# Phone
	var ph_vbox = VBoxContainer.new(); ph_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var ph_lbl = Label.new(); ph_lbl.text = "PHONE"; ph_lbl.add_theme_font_size_override("font_size", 14); ph_lbl.add_theme_color_override("font_color", Color(0.70, 0.78, 0.88, 1.0))
	var ph_edit = LineEdit.new(); ph_edit.text = _format_phone_string(_clean_str(p.get("phone", ""))); ph_edit.placeholder_text = "(555) 000-0000"; ph_edit.custom_minimum_size = Vector2(0, 44); ph_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL; ph_edit.add_theme_font_size_override("font_size", 16)
	ph_edit.text_changed.connect(func(new_text): _on_phone_text_changed(new_text, ph_edit))
	ph_vbox.add_child(ph_lbl); ph_vbox.add_child(ph_edit); form_grid.add_child(ph_vbox)

	# Primary Email
	var em_vbox = VBoxContainer.new(); em_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var em_lbl = Label.new(); em_lbl.text = "PRIMARY EMAIL"; em_lbl.add_theme_font_size_override("font_size", 14); em_lbl.add_theme_color_override("font_color", Color(0.70, 0.78, 0.88, 1.0))
	var em_edit = LineEdit.new(); em_edit.text = _clean_str(p.get("email", "")); em_edit.placeholder_text = "name@example.com"; em_edit.custom_minimum_size = Vector2(0, 44); em_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL; em_edit.add_theme_font_size_override("font_size", 16)
	em_vbox.add_child(em_lbl); em_vbox.add_child(em_edit); form_grid.add_child(em_vbox)

	# School Email
	var se_vbox = VBoxContainer.new(); se_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var se_lbl = Label.new(); se_lbl.text = "SCHOOL EMAIL"; se_lbl.add_theme_font_size_override("font_size", 14); se_lbl.add_theme_color_override("font_color", Color(0.70, 0.78, 0.88, 1.0))
	var se_edit = LineEdit.new(); se_edit.text = _clean_str(p.get("school_email", "")); se_edit.placeholder_text = "student@school.edu"; se_edit.custom_minimum_size = Vector2(0, 44); se_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL; se_edit.add_theme_font_size_override("font_size", 16)
	se_vbox.add_child(se_lbl); se_vbox.add_child(se_edit); form_grid.add_child(se_vbox)

	# Preferred Email Option
	var pe_vbox = VBoxContainer.new(); pe_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var pe_lbl = Label.new(); pe_lbl.text = "PREFERRED EMAIL"; pe_lbl.add_theme_font_size_override("font_size", 14); pe_lbl.add_theme_color_override("font_color", Color(0.70, 0.78, 0.88, 1.0))
	var pe_dropdown = OptionButton.new()
	pe_dropdown.add_item("Main", 0); pe_dropdown.add_item("School", 1)
	if _clean_str(p.get("preferred_email", "Main")) == "School": pe_dropdown.selected = 1
	pe_dropdown.custom_minimum_size = Vector2(0, 44); pe_dropdown.size_flags_horizontal = Control.SIZE_EXPAND_FILL; pe_dropdown.add_theme_font_size_override("font_size", 16)
	pe_vbox.add_child(pe_lbl); pe_vbox.add_child(pe_dropdown); form_grid.add_child(pe_vbox)

	# Birthday Date
	var bd_vbox = VBoxContainer.new(); bd_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var bd_lbl = Label.new(); bd_lbl.text = "BIRTHDAY (MM/DD/YYYY)"; bd_lbl.add_theme_font_size_override("font_size", 14); bd_lbl.add_theme_color_override("font_color", Color(0.70, 0.78, 0.88, 1.0))
	var bd_hbox = HBoxContainer.new(); bd_hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var bd_edit = LineEdit.new(); bd_edit.text = _db_to_ui_date(_clean_str(p.get("birthday", ""))); bd_edit.placeholder_text = "MM/DD/YYYY"; bd_edit.custom_minimum_size = Vector2(0, 44); bd_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL; bd_edit.add_theme_font_size_override("font_size", 16)
	var bd_cal_btn = Button.new(); bd_cal_btn.text = "📅"; bd_cal_btn.custom_minimum_size = Vector2(44, 44)
	bd_cal_btn.pressed.connect(func(): _open_calendar_picker(bd_edit))
	bd_hbox.add_child(bd_edit); bd_hbox.add_child(bd_cal_btn)
	bd_vbox.add_child(bd_lbl); bd_vbox.add_child(bd_hbox); form_grid.add_child(bd_vbox)

	# Primary Role
	var role_vbox = VBoxContainer.new(); role_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var role_lbl = Label.new(); role_lbl.text = "PRIMARY ROLE"; role_lbl.add_theme_font_size_override("font_size", 14); role_lbl.add_theme_color_override("font_color", Color(0.70, 0.78, 0.88, 1.0))
	var role_dropdown = OptionButton.new()
	role_dropdown.add_item("Participant", 0)
	role_dropdown.add_item("Staff", 1)
	role_dropdown.add_item("Volunteer", 2)
	role_dropdown.add_item("Intern", 3)
	
	var r_val = _clean_str(p.get("primary_role", "Participant")).to_lower()
	if r_val == "staff":
		role_dropdown.selected = 1
	elif r_val == "volunteer":
		role_dropdown.selected = 2
	elif r_val == "intern":
		role_dropdown.selected = 3
	else:
		role_dropdown.selected = 0
		
	role_dropdown.custom_minimum_size = Vector2(0, 44); role_dropdown.size_flags_horizontal = Control.SIZE_EXPAND_FILL; role_dropdown.add_theme_font_size_override("font_size", 16)
	role_vbox.add_child(role_lbl); role_vbox.add_child(role_dropdown); form_grid.add_child(role_vbox)

	# Registration Status
	var flag_vbox = VBoxContainer.new(); flag_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var flag_lbl = Label.new(); flag_lbl.text = "REGISTRATION STATUS"; flag_lbl.add_theme_font_size_override("font_size", 14); flag_lbl.add_theme_color_override("font_color", Color(0.70, 0.78, 0.88, 1.0))
	var flag_dropdown = OptionButton.new()
	flag_dropdown.add_item("Clear", 0)
	flag_dropdown.add_item("To Be Confirmed", 1)
	flag_dropdown.add_item("Suspended", 2)
	
	var f_val = _clean_str(p.get("flag_status", "Clear"))
	if f_val == "To Be Confirmed":
		flag_dropdown.selected = 1
	elif f_val == "Suspended":
		flag_dropdown.selected = 2
	else:
		flag_dropdown.selected = 0
		
	flag_dropdown.custom_minimum_size = Vector2(0, 44); flag_dropdown.size_flags_horizontal = Control.SIZE_EXPAND_FILL; flag_dropdown.add_theme_font_size_override("font_size", 16)
	flag_vbox.add_child(flag_lbl); flag_vbox.add_child(flag_dropdown); form_grid.add_child(flag_vbox)

	# Grade/Year Level
	var gr_vocab_lbl = _get_vocab_grade_label().to_upper()
	var gr_vbox = VBoxContainer.new(); gr_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var gr_lbl = Label.new(); gr_lbl.text = gr_vocab_lbl; gr_lbl.add_theme_font_size_override("font_size", 14); gr_lbl.add_theme_color_override("font_color", Color(0.70, 0.78, 0.88, 1.0))
	var gr_dropdown = OptionButton.new()
	gr_dropdown.add_item("None", 0)
	gr_dropdown.add_item("Freshman", 1)
	gr_dropdown.add_item("Sophomore", 2)
	gr_dropdown.add_item("Junior", 3)
	gr_dropdown.add_item("Senior", 4)
	gr_dropdown.add_item("Grad Student", 5)
	gr_dropdown.add_item("Other", 6)
	
	var g_val = _clean_str(p.get("grade", ""))
	if g_val == "Freshman":
		gr_dropdown.selected = 1
	elif g_val == "Sophomore":
		gr_dropdown.selected = 2
	elif g_val == "Junior":
		gr_dropdown.selected = 3
	elif g_val == "Senior":
		gr_dropdown.selected = 4
	elif g_val == "Grad Student":
		gr_dropdown.selected = 5
	elif g_val == "Other":
		gr_dropdown.selected = 6
	else:
		gr_dropdown.selected = 0
		
	gr_dropdown.custom_minimum_size = Vector2(0, 44); gr_dropdown.size_flags_horizontal = Control.SIZE_EXPAND_FILL; gr_dropdown.add_theme_font_size_override("font_size", 16)
	gr_vbox.add_child(gr_lbl); gr_vbox.add_child(gr_dropdown); form_grid.add_child(gr_vbox)

	var contact_card_vbox = VBoxContainer.new(); contact_card_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	contact_card_vbox.add_theme_constant_override("separation", 16)
	contact_card_vbox.add_child(form_grid)

	var btn_save_contact = Button.new()
	btn_save_contact.text = "💾 Save Contact & Identity Details"
	btn_save_contact.custom_minimum_size = Vector2(260, 44)
	btn_save_contact.add_theme_font_size_override("font_size", 16)
	btn_save_contact.pressed.connect(func():
		if db and p_uuid != "":
			var pref_email = "School" if pe_dropdown.selected == 1 else "Main"
			var role_sel_txt = role_dropdown.get_item_text(role_dropdown.selected)
			var role_db_val = "Participant"
			if role_sel_txt == "Staff":
				role_db_val = "staff"
			elif role_sel_txt == "Volunteer":
				role_db_val = "volunteer"
			elif role_sel_txt == "Intern":
				role_db_val = "intern"
				
			var flag_db_val = flag_dropdown.get_item_text(flag_dropdown.selected)
			var grade_sel_txt = gr_dropdown.get_item_text(gr_dropdown.selected)
			if grade_sel_txt == "None":
				grade_sel_txt = ""
			
			db.execute("UPDATE people SET first_name = ?, last_name = ?, suffix = ?, phone = ?, email = ?, school_email = ?, preferred_email = ?, birthday = ?, primary_role = ?, flag_status = ?, grade = ? WHERE person_uuid = ?;",
				[fn_edit.text.strip_edges(), ln_edit.text.strip_edges(), suf_edit.text.strip_edges(), ph_edit.text.strip_edges(), em_edit.text.strip_edges(), se_edit.text.strip_edges(), pref_email, _ui_to_db_date(bd_edit.text.strip_edges()), role_db_val, flag_db_val, grade_sel_txt, p_uuid])
			refresh_view()
	)
	contact_card_vbox.add_child(btn_save_contact)

	profile_section.add_child(_create_credentials_card(p, p_uuid))
	profile_section.add_child(_create_card("Identity & Contact Information", contact_card_vbox))

	# 3. Home & School Addresses Card
	var addr_box = VBoxContainer.new()
	addr_box.add_theme_constant_override("separation", 18)

	var home_hdr = Label.new(); home_hdr.text = "🏠 HOME ADDRESS"; home_hdr.add_theme_font_size_override("font_size", 15); home_hdr.add_theme_color_override("font_color", Color(0.40, 0.85, 0.60, 1.0))
	addr_box.add_child(home_hdr)

	var home_grid = GridContainer.new(); home_grid.columns = 3; home_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL; home_grid.add_theme_constant_override("h_separation", 18); home_grid.add_theme_constant_override("v_separation", 12)

	var h_st_edit = LineEdit.new(); h_st_edit.text = _clean_str(p.get("home_address_street", "")); h_st_edit.placeholder_text = "Street Address (e.g. 123 Main St)"; h_st_edit.custom_minimum_size = Vector2(0, 44); h_st_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL; h_st_edit.add_theme_font_size_override("font_size", 15)
	var h_l2_edit = LineEdit.new(); h_l2_edit.text = _clean_str(p.get("home_address_line2", "")); h_l2_edit.placeholder_text = "Apt, Suite, Unit (Optional)"; h_l2_edit.custom_minimum_size = Vector2(0, 44); h_l2_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL; h_l2_edit.add_theme_font_size_override("font_size", 15)
	var h_ct_edit = LineEdit.new(); h_ct_edit.text = _clean_str(p.get("home_address_city", "")); h_ct_edit.placeholder_text = "City"; h_ct_edit.custom_minimum_size = Vector2(0, 44); h_ct_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL; h_ct_edit.add_theme_font_size_override("font_size", 15)

	var h_st_zip_hbox = HBoxContainer.new(); h_st_zip_hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL; h_st_zip_hbox.add_theme_constant_override("separation", 10)
	var h_state_edit = LineEdit.new(); h_state_edit.text = _clean_str(p.get("home_address_state", "")); h_state_edit.placeholder_text = "State (e.g. TN)"; h_state_edit.custom_minimum_size = Vector2(115, 44); h_state_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL; h_state_edit.add_theme_font_size_override("font_size", 15)
	var h_zip_edit = LineEdit.new(); h_zip_edit.text = _clean_str(p.get("home_address_zip", "")); h_zip_edit.placeholder_text = "ZIP Code"; h_zip_edit.custom_minimum_size = Vector2(125, 44); h_zip_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL; h_zip_edit.add_theme_font_size_override("font_size", 15)
	h_st_zip_hbox.add_child(h_state_edit); h_st_zip_hbox.add_child(h_zip_edit)

	home_grid.add_child(h_st_edit); home_grid.add_child(h_l2_edit)
	home_grid.add_child(h_ct_edit); home_grid.add_child(h_st_zip_hbox)
	addr_box.add_child(home_grid)

	var sch_hdr = Label.new(); sch_hdr.text = "🏫 SCHOOL / CAMPUS ADDRESS"; sch_hdr.add_theme_font_size_override("font_size", 15); sch_hdr.add_theme_color_override("font_color", Color(0.40, 0.75, 0.95, 1.0))
	addr_box.add_child(sch_hdr)

	var sch_grid = GridContainer.new(); sch_grid.columns = 3; sch_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL; sch_grid.add_theme_constant_override("h_separation", 18); sch_grid.add_theme_constant_override("v_separation", 12)

	var s_st_edit = LineEdit.new(); s_st_edit.text = _clean_str(p.get("school_address_street", "")); s_st_edit.placeholder_text = "Campus Address / Residence Hall"; s_st_edit.custom_minimum_size = Vector2(0, 44); s_st_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL; s_st_edit.add_theme_font_size_override("font_size", 15)
	var s_l2_edit = LineEdit.new(); s_l2_edit.text = _clean_str(p.get("school_address_line2", "")); s_l2_edit.placeholder_text = "Dorm / Room # (Optional)"; s_l2_edit.custom_minimum_size = Vector2(0, 44); s_l2_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL; s_l2_edit.add_theme_font_size_override("font_size", 15)
	var s_ct_edit = LineEdit.new(); s_ct_edit.text = _clean_str(p.get("school_address_city", "")); s_ct_edit.placeholder_text = "City"; s_ct_edit.custom_minimum_size = Vector2(0, 44); s_ct_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL; s_ct_edit.add_theme_font_size_override("font_size", 15)

	var s_st_zip_hbox = HBoxContainer.new(); s_st_zip_hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL; s_st_zip_hbox.add_theme_constant_override("separation", 10)
	var s_state_edit = LineEdit.new(); s_state_edit.text = _clean_str(p.get("school_address_state", "")); s_state_edit.placeholder_text = "State"; s_state_edit.custom_minimum_size = Vector2(115, 44); s_state_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL; s_state_edit.add_theme_font_size_override("font_size", 15)
	var s_zip_edit = LineEdit.new(); s_zip_edit.text = _clean_str(p.get("school_address_zip", "")); s_zip_edit.placeholder_text = "ZIP Code"; s_zip_edit.custom_minimum_size = Vector2(125, 44); s_zip_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL; s_zip_edit.add_theme_font_size_override("font_size", 15)
	s_st_zip_hbox.add_child(s_state_edit); s_st_zip_hbox.add_child(s_zip_edit)

	sch_grid.add_child(s_st_edit); sch_grid.add_child(s_l2_edit)
	sch_grid.add_child(s_ct_edit); sch_grid.add_child(s_st_zip_hbox)
	addr_box.add_child(sch_grid)

	var btn_save_addr = Button.new()
	btn_save_addr.text = "💾 Save Home & School Addresses"
	btn_save_addr.custom_minimum_size = Vector2(260, 44)
	btn_save_addr.add_theme_font_size_override("font_size", 16)
	btn_save_addr.pressed.connect(func():
		if db and p_uuid != "":
			db.execute("UPDATE people SET home_address_street = ?, home_address_line2 = ?, home_address_city = ?, home_address_state = ?, home_address_zip = ?, school_address_street = ?, school_address_line2 = ?, school_address_city = ?, school_address_state = ?, school_address_zip = ? WHERE person_uuid = ?;",
				[h_st_edit.text.strip_edges(), h_l2_edit.text.strip_edges(), h_ct_edit.text.strip_edges(), h_state_edit.text.strip_edges(), h_zip_edit.text.strip_edges(),
				 s_st_edit.text.strip_edges(), s_l2_edit.text.strip_edges(), s_ct_edit.text.strip_edges(), s_state_edit.text.strip_edges(), s_zip_edit.text.strip_edges(), p_uuid])
			refresh_view()
	)
	addr_box.add_child(btn_save_addr)
	profile_section.add_child(_create_card("Home & School Addresses", addr_box))

	# 4. Emergency Contact Card
	var em_box = VBoxContainer.new(); em_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	em_box.add_theme_constant_override("separation", 14)

	var em_grid = GridContainer.new(); em_grid.columns = 3; em_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL; em_grid.add_theme_constant_override("h_separation", 16); em_grid.add_theme_constant_override("v_separation", 12)

	var em_n_vbox = VBoxContainer.new(); em_n_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL; var em_n_lbl = Label.new(); em_n_lbl.text = "CONTACT NAME"; em_n_lbl.add_theme_font_size_override("font_size", 14); em_n_lbl.add_theme_color_override("font_color", Color(0.70, 0.78, 0.88, 1.0))
	var em_n_edit = LineEdit.new(); em_n_edit.text = _clean_str(p.get("emergency_contact_name", "")); em_n_edit.placeholder_text = "Full Name"; em_n_edit.custom_minimum_size = Vector2(0, 44); em_n_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL; em_n_edit.add_theme_font_size_override("font_size", 15)
	em_n_vbox.add_child(em_n_lbl); em_n_vbox.add_child(em_n_edit); em_grid.add_child(em_n_vbox)

	var em_p_vbox = VBoxContainer.new(); em_p_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL; var em_p_lbl = Label.new(); em_p_lbl.text = "PHONE NUMBER"; em_p_lbl.add_theme_font_size_override("font_size", 14); em_p_lbl.add_theme_color_override("font_color", Color(0.70, 0.78, 0.88, 1.0))
	var em_p_edit = LineEdit.new(); em_p_edit.text = _format_phone_string(_clean_str(p.get("emergency_contact_phone", ""))); em_p_edit.placeholder_text = "(555) 000-0000"; em_p_edit.custom_minimum_size = Vector2(0, 44); em_p_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL; em_p_edit.add_theme_font_size_override("font_size", 15)
	em_p_edit.text_changed.connect(func(new_text): _on_phone_text_changed(new_text, em_p_edit))
	em_p_vbox.add_child(em_p_lbl); em_p_vbox.add_child(em_p_edit); em_grid.add_child(em_p_vbox)

	var em_r_vbox = VBoxContainer.new(); em_r_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL; var em_r_lbl = Label.new(); em_r_lbl.text = "RELATIONSHIP"; em_r_lbl.add_theme_font_size_override("font_size", 14); em_r_lbl.add_theme_color_override("font_color", Color(0.70, 0.78, 0.88, 1.0))
	var em_r_edit = LineEdit.new(); em_r_edit.text = _clean_str(p.get("emergency_contact_relationship", "")); em_r_edit.placeholder_text = "Parent, Spouse, Guardian"; em_r_edit.custom_minimum_size = Vector2(0, 44); em_r_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL; em_r_edit.add_theme_font_size_override("font_size", 15)
	em_r_vbox.add_child(em_r_lbl); em_r_vbox.add_child(em_r_edit); em_grid.add_child(em_r_vbox)

	em_box.add_child(em_grid)

	var btn_save_em = Button.new()
	btn_save_em.text = "💾 Save Emergency Contact"
	btn_save_em.custom_minimum_size = Vector2(240, 44)
	btn_save_em.add_theme_font_size_override("font_size", 16)
	btn_save_em.pressed.connect(func():
		if db and p_uuid != "":
			db.execute("UPDATE people SET emergency_contact_name = ?, emergency_contact_phone = ?, emergency_contact_relationship = ? WHERE person_uuid = ?;",
				[em_n_edit.text.strip_edges(), em_p_edit.text.strip_edges(), em_r_edit.text.strip_edges(), p_uuid])
			refresh_view()
	)
	em_box.add_child(btn_save_em)
	profile_section.add_child(_create_card("Emergency Contact Information", em_box))

	# 5. Medical Notes, Health & Allergies Card
	var med_box = VBoxContainer.new(); med_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	med_box.add_theme_constant_override("separation", 12)

	var med_lbl = Label.new(); med_lbl.text = "MEDICAL NOTES, HEALTH CONDITIONS & ALLERGIES"; med_lbl.add_theme_font_size_override("font_size", 14); med_lbl.add_theme_color_override("font_color", Color(0.70, 0.78, 0.88, 1.0))
	var med_edit = TextEdit.new(); med_edit.text = _clean_str(p.get("medical_notes", "")); med_edit.placeholder_text = "Record medical conditions, dietary restrictions, severe allergies, and emergency protocols..."
	med_edit.custom_minimum_size = Vector2(0, 100); med_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL; med_edit.add_theme_font_size_override("font_size", 16)
	med_box.add_child(med_lbl); med_box.add_child(med_edit)

	var btn_save_med = Button.new()
	btn_save_med.text = "💾 Save Medical Notes & Allergies"
	btn_save_med.custom_minimum_size = Vector2(260, 44)
	btn_save_med.add_theme_font_size_override("font_size", 16)
	btn_save_med.pressed.connect(func():
		if db and p_uuid != "":
			db.execute("UPDATE people SET medical_notes = ? WHERE person_uuid = ?;", [med_edit.text.strip_edges(), p_uuid])
			refresh_view()
	)
	med_box.add_child(btn_save_med)
	profile_section.add_child(_create_card("Medical Notes, Health & Allergies", med_box))

func _populate_notes_section(p: Dictionary) -> void:
	if not notes_section: return

	var person_uuid = _clean_str(p.get("person_uuid", ""))

	var notes_main_vbox = VBoxContainer.new()
	notes_main_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	notes_main_vbox.add_theme_constant_override("separation", 18)

	# 1. Add Journal Note Card (Composer)
	var comp_box = VBoxContainer.new()
	comp_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	comp_box.add_theme_constant_override("separation", 14)

	# Note Category Dropdown
	var cat_vbox = VBoxContainer.new()
	cat_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var cat_lbl = Label.new()
	cat_lbl.text = "NOTE CATEGORY"
	cat_lbl.add_theme_font_size_override("font_size", 14)
	cat_lbl.add_theme_color_override("font_color", Color(0.70, 0.78, 0.88, 1.0))

	var cat_dropdown = OptionButton.new()
	cat_dropdown.add_item("Administrative", 0)
	cat_dropdown.add_item("Pastoral / Care", 1)
	cat_dropdown.add_item("Pathway", 2)
	cat_dropdown.add_item("Staff Only", 3)
	cat_dropdown.add_item("Mentor", 4)
	cat_dropdown.add_item("General", 5)
	cat_dropdown.custom_minimum_size = Vector2(0, 44)
	cat_dropdown.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cat_dropdown.add_theme_font_size_override("font_size", 16)
	cat_vbox.add_child(cat_lbl)
	cat_vbox.add_child(cat_dropdown)
	comp_box.add_child(cat_vbox)

	var cat_sub = Label.new()
	cat_sub.text = "Administrative is the default category."
	cat_sub.add_theme_font_size_override("font_size", 14)
	cat_sub.add_theme_color_override("font_color", Color(0.70, 0.78, 0.88, 1.0))
	comp_box.add_child(cat_sub)

	# Add Journal Note TextEdit
	var body_vbox = VBoxContainer.new()
	body_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var body_edit = TextEdit.new()
	body_edit.placeholder_text = "Write a member note..."
	body_edit.custom_minimum_size = Vector2(0, 120)
	body_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body_edit.add_theme_font_size_override("font_size", 16)
	body_vbox.add_child(body_edit)
	comp_box.add_child(body_vbox)

	var btn_save_note = Button.new()
	btn_save_note.text = "➕ Save Note"
	btn_save_note.custom_minimum_size = Vector2(200, 44)
	btn_save_note.add_theme_font_size_override("font_size", 16)
	btn_save_note.pressed.connect(func():
		var note_text = body_edit.text.strip_edges()
		if note_text != "" and db and person_uuid != "":
			var cat_name = cat_dropdown.get_item_text(cat_dropdown.selected)
			var note_uuid = "note_" + str(Time.get_ticks_msec())
			var timestamp = Time.get_datetime_string_from_system()
			db.execute("INSERT INTO person_notes (note_uuid, person_uuid, title, body, visibility, created_at, updated_at) VALUES (?, ?, ?, ?, 'standard_staff', ?, ?);",
				[note_uuid, person_uuid, cat_name, note_text, timestamp, timestamp])
			body_edit.text = ""
			refresh_view()
	)
	comp_box.add_child(btn_save_note)

	var priv_sub = Label.new()
	priv_sub.text = "Visible note categories are limited by your signed-in staff privilege."
	priv_sub.add_theme_font_size_override("font_size", 14)
	priv_sub.add_theme_color_override("font_color", Color(0.70, 0.78, 0.88, 1.0))
	comp_box.add_child(priv_sub)

	notes_main_vbox.add_child(_create_card("NOTES JOURNAL", comp_box))

	# 2. Notes Journal History Card
	var hist_box = VBoxContainer.new()
	hist_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hist_box.add_theme_constant_override("separation", 14)

	# Category Filter Header HBox
	var hdr_hbox = HBoxContainer.new()
	hdr_hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var hist_title = Label.new()
	hist_title.text = "Notes Journal History"
	hist_title.add_theme_font_size_override("font_size", 20)
	hist_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hdr_hbox.add_child(hist_title)

	var filter_dropdown = OptionButton.new()
	filter_dropdown.add_item("All", 0)
	filter_dropdown.add_item("Administrative", 1)
	filter_dropdown.add_item("Pastoral / Care", 2)
	filter_dropdown.add_item("Pathway", 3)
	filter_dropdown.add_item("Staff Only", 4)
	filter_dropdown.add_item("Mentor", 5)
	filter_dropdown.add_item("General", 6)
	filter_dropdown.custom_minimum_size = Vector2(180, 38)
	filter_dropdown.add_theme_font_size_override("font_size", 14)
	hdr_hbox.add_child(filter_dropdown)
	hist_box.add_child(hdr_hbox)

	var notes_list_vbox = VBoxContainer.new()
	notes_list_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	notes_list_vbox.add_theme_constant_override("separation", 12)

	var notes_res = db.execute("SELECT * FROM person_notes WHERE person_uuid = ? AND is_deleted = 0 ORDER BY created_at DESC, id DESC;", [person_uuid]) if db and person_uuid != "" else {"success": false, "data": []}
	var all_notes = notes_res.get("data", []) if notes_res.get("success", false) else []

	var _render_history_list = func(cat_filter: String):
		_clear_container(notes_list_vbox)
		var count = 0
		for note in all_notes:
			var note_title = str(note.get("title", "General"))
			var note_body = str(note.get("body", ""))
			var note_dt = str(note.get("created_at", ""))

			if cat_filter != "All" and note_title != cat_filter:
				continue

			count += 1
			var note_card = VBoxContainer.new()
			note_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			note_card.add_theme_constant_override("separation", 4)

			var badge = Label.new()
			badge.text = "[ Note Category: " + note_title + " ]"
			badge.add_theme_font_size_override("font_size", 15)
			badge.add_theme_color_override("font_color", Color(0.40, 0.85, 0.95, 1.0))
			note_card.add_child(badge)

			var lbl_b = Label.new()
			lbl_b.text = note_body
			lbl_b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			lbl_b.add_theme_font_size_override("font_size", 16)
			lbl_b.add_theme_color_override("font_color", Color(0.92, 0.96, 1.0))
			note_card.add_child(lbl_b)

			if note_dt != "":
				var lbl_dt = Label.new()
				lbl_dt.text = "Date: " + note_dt
				lbl_dt.add_theme_font_size_override("font_size", 14)
				lbl_dt.add_theme_color_override("font_color", Color(0.72, 0.80, 0.90))
				note_card.add_child(lbl_dt)

			notes_list_vbox.add_child(note_card)

		if count == 0:
			notes_list_vbox.add_child(_create_empty_label("No journal notes yet."))

	filter_dropdown.item_selected.connect(func(idx: int):
		var cat_name = filter_dropdown.get_item_text(idx)
		_render_history_list.call(cat_name)
	)

	_render_history_list.call("All")
	hist_box.add_child(notes_list_vbox)

	notes_main_vbox.add_child(_create_card("Notes Journal History", hist_box))
	notes_section.add_child(notes_main_vbox)

func _populate_participation_section(p: Dictionary, att_history: Array) -> void:
	if not participation_section: return

	var person_uuid = String(p.get("person_uuid", ""))

	# 1. Pathways Card
	var path_res = read_service.get_person_pathways(person_uuid) if read_service and read_service.has_method("get_person_pathways") else {"pathways": []}
	var pathways_list = path_res.get("pathways", [])
	if pathways_list.size() > 0:
		var p_box = VBoxContainer.new()
		p_box.add_theme_constant_override("separation", 12)
		for pw in pathways_list:
			var pw_vbox = VBoxContainer.new()
			pw_vbox.add_theme_constant_override("separation", 4)

			var header_hbox = HBoxContainer.new()
			var name_lbl = Label.new()
			name_lbl.text = str(pw.get("pathway_name", "Pathway"))
			name_lbl.add_theme_font_size_override("font_size", 18)
			name_lbl.size_flags_horizontal = SIZE_EXPAND_FILL
			header_hbox.add_child(name_lbl)

			var stage_lbl = Label.new()
			stage_lbl.text = "Stage: " + str(pw.get("current_stage", "In Progress")) + " (" + str(pw.get("progress_percent", 0)) + "%)"
			stage_lbl.add_theme_font_size_override("font_size", 15)
			stage_lbl.add_theme_color_override("font_color", Color(0.88, 0.35, 0.21, 1.0))
			header_hbox.add_child(stage_lbl)
			pw_vbox.add_child(header_hbox)

			var milestones = pw.get("milestones", [])
			if milestones.size() > 0:
				var m_vbox = VBoxContainer.new()
				m_vbox.add_theme_constant_override("separation", 4)
				for m in milestones:
					var m_lbl = Label.new()
					var chk = "☑ " if int(m.get("is_completed", 0)) == 1 else "☐ "
					m_lbl.text = "   " + chk + str(m.get("milestone_name", ""))
					m_lbl.add_theme_font_size_override("font_size", 16)
					m_lbl.add_theme_color_override("font_color", Color(0.78, 0.85, 0.95, 1.0))
					m_vbox.add_child(m_lbl)
				pw_vbox.add_child(m_vbox)
			p_box.add_child(pw_vbox)
		participation_section.add_child(_create_card("Pathways (" + str(pathways_list.size()) + ")", p_box))
	else:
		participation_section.add_child(_create_card("Pathways", _create_empty_label("No active pathways assigned.")))

	# 2. Sessions Card
	var sess_res = read_service.get_person_sessions(person_uuid) if read_service and read_service.has_method("get_person_sessions") else {"sessions": []}
	var sessions_list = sess_res.get("sessions", [])
	if sessions_list.size() > 0:
		var s_box = VBoxContainer.new()
		s_box.add_theme_constant_override("separation", 8)
		for s in sessions_list:
			var s_lbl = Label.new()
			s_lbl.text = str(s.get("title", "")) + " • " + str(s.get("date_text", "")) + " (" + str(s.get("start_time", "")) + ") | " + str(s.get("room_location", ""))
			s_lbl.add_theme_font_size_override("font_size", 16)
			s_box.add_child(s_lbl)
		participation_section.add_child(_create_card("Sessions (" + str(sessions_list.size()) + ")", s_box))
	else:
		participation_section.add_child(_create_card("Sessions", _create_empty_label("No scheduled sessions recorded.")))

	# 3. Attendance
	var att_box = VBoxContainer.new()
	att_box.add_theme_constant_override("separation", 6)

	if att_history.size() > 0:
		for item in att_history:
			var date_s = str(item.get("check_in_date", ""))
			var time_s = str(item.get("check_in_time", ""))
			var meth_s = str(item.get("method", "Manual"))
			var row = Label.new()
			row.text = date_s + " at " + time_s + " | Method: " + meth_s
			row.add_theme_font_size_override("font_size", 16)
			att_box.add_child(row)
	else:
		att_box.add_child(_create_empty_label("No attendance check-ins recorded."))

	participation_section.add_child(_create_card("Attendance History (" + str(att_history.size()) + ")", att_box))

func _populate_communications_section(p: Dictionary) -> void:
	if not communications_section: return

	var p_uuid = _clean_str(p.get("person_uuid", ""))
	var phone = _clean_str(p.get("phone", ""))
	var email = _clean_str(p.get("email", ""))

	# 0. Digital Member Pass & Smartphone e-Wallet (Top Card)
	var wallet_box = VBoxContainer.new()
	wallet_box.add_theme_constant_override("separation", 12)

	var wallet_sub = Label.new()
	wallet_sub.text = "Send official Real Life House Digital Member Pass directly to this constituent's smartphone e-Wallet (Apple Wallet & Google Wallet) or email."
	wallet_sub.add_theme_font_size_override("font_size", 15)
	wallet_sub.add_theme_color_override("font_color", Color(0.78, 0.85, 0.95, 1.0))
	wallet_sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	wallet_box.add_child(wallet_sub)

	var wallet_hbox = HBoxContainer.new()
	wallet_hbox.add_theme_constant_override("separation", 12)

	var btn_send_wallet_email = Button.new()
	btn_send_wallet_email.text = "📱 Send Digital Member Pass Email"
	btn_send_wallet_email.custom_minimum_size = Vector2(260, 44)
	btn_send_wallet_email.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_send_wallet_email.add_theme_font_size_override("font_size", 16)
	btn_send_wallet_email.pressed.connect(func():
		var comms = CommunicationsServiceScript.new(db)
		var p_id = int(p.get("id", p.get("person_id", 0)))
		var res = comms.email_digital_member_pass(p_id, "Staff Administrator")
		var target_email = str(p.get("email", p.get("email_address", "")))
		if res.get("success", false):
			btn_send_wallet_email.text = "✓ Member Pass Emailed to " + target_email
		else:
			btn_send_wallet_email.text = "⚠️ Email Failed: " + str(res.get("error", "Check settings"))
	)
	wallet_hbox.add_child(btn_send_wallet_email)

	wallet_box.add_child(wallet_hbox)
	communications_section.add_child(_create_card("📱 Digital Member Pass & Smartphone e-Wallet", wallet_box))

	# 1. Quick Actions & Direct Contact (Middle Card)
	var qa_box = VBoxContainer.new()
	qa_box.add_theme_constant_override("separation", 14)

	# Outbound Dispatcher Controls Grid
	var disp_grid = GridContainer.new()
	disp_grid.columns = 2
	disp_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	disp_grid.add_theme_constant_override("h_separation", 18)
	disp_grid.add_theme_constant_override("v_separation", 10)

	# SMS/Voice Sender Line Dropdown & Override
	var sms_disp_vbox = VBoxContainer.new(); sms_disp_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var sms_disp_lbl = Label.new()
	sms_disp_lbl.text = "OUTBOUND SMS / VOICE SENDER LINE"
	sms_disp_lbl.add_theme_font_size_override("font_size", 13)
	sms_disp_lbl.add_theme_color_override("font_color", Color(0.70, 0.78, 0.88, 1.0))

	var sms_disp_hbox = HBoxContainer.new(); sms_disp_hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sms_disp_hbox.add_theme_constant_override("separation", 8)

	var sms_disp_dropdown = OptionButton.new()
	sms_disp_dropdown.add_item("Twilio Main Line: (864) 712-4446", 0)
	sms_disp_dropdown.add_item("✏️ Custom Number Override...", 1)
	sms_disp_dropdown.custom_minimum_size = Vector2(0, 38)
	sms_disp_dropdown.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sms_disp_dropdown.add_theme_font_size_override("font_size", 14)

	var sms_override_edit = LineEdit.new()
	sms_override_edit.placeholder_text = "Override Phone #"
	sms_override_edit.custom_minimum_size = Vector2(0, 38)
	sms_override_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sms_override_edit.add_theme_font_size_override("font_size", 14)
	sms_override_edit.visible = false

	sms_disp_dropdown.item_selected.connect(func(idx: int):
		sms_override_edit.visible = (idx == 1)
	)

	sms_disp_hbox.add_child(sms_disp_dropdown)
	sms_disp_hbox.add_child(sms_override_edit)
	sms_disp_vbox.add_child(sms_disp_lbl)
	sms_disp_vbox.add_child(sms_disp_hbox)
	disp_grid.add_child(sms_disp_vbox)

	# Email Sender Address Dropdown & Override
	var email_disp_vbox = VBoxContainer.new(); email_disp_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var email_disp_lbl = Label.new()
	email_disp_lbl.text = "OUTBOUND EMAIL SENDER ADDRESS"
	email_disp_lbl.add_theme_font_size_override("font_size", 13)
	email_disp_lbl.add_theme_color_override("font_color", Color(0.70, 0.78, 0.88, 1.0))

	var email_disp_hbox = HBoxContainer.new(); email_disp_hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	email_disp_hbox.add_theme_constant_override("separation", 8)

	var email_disp_dropdown = OptionButton.new()
	email_disp_dropdown.add_item("connect@studycenter.org", 0)
	email_disp_dropdown.add_item("✏️ Custom Email Override...", 1)
	email_disp_dropdown.custom_minimum_size = Vector2(0, 38)
	email_disp_dropdown.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	email_disp_dropdown.add_theme_font_size_override("font_size", 14)

	var email_override_edit = LineEdit.new()
	email_override_edit.placeholder_text = "sender@example.com"
	email_override_edit.custom_minimum_size = Vector2(0, 38)
	email_override_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	email_override_edit.add_theme_font_size_override("font_size", 14)
	email_override_edit.visible = false

	email_disp_dropdown.item_selected.connect(func(idx: int):
		email_override_edit.visible = (idx == 1)
	)

	email_disp_hbox.add_child(email_disp_dropdown)
	email_disp_hbox.add_child(email_override_edit)
	email_disp_vbox.add_child(email_disp_lbl)
	email_disp_vbox.add_child(email_disp_hbox)
	disp_grid.add_child(email_disp_vbox)

	qa_box.add_child(disp_grid)

	# Quick Action Buttons
	var qa_hbox = HBoxContainer.new(); qa_hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	qa_hbox.add_theme_constant_override("separation", 10)

	var phone_display = phone if phone != "" else "Member"
	var email_display = email if email != "" else "Member"

	var btn_call = Button.new()
	btn_call.text = "📞 Call " + phone_display
	btn_call.custom_minimum_size = Vector2(0, 42); btn_call.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_call.add_theme_font_size_override("font_size", 15)
	btn_call.pressed.connect(func():
		var sender_num = "(864) 712-4446"
		if sms_disp_dropdown.selected == 1 and sms_override_edit.text.strip_edges() != "":
			sender_num = sms_override_edit.text.strip_edges()
		OS.shell_open("tel:" + (phone if phone != "" else sender_num))
	)
	qa_hbox.add_child(btn_call)

	var btn_text = Button.new()
	btn_text.text = "💬 Text " + phone_display
	btn_text.custom_minimum_size = Vector2(0, 42); btn_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_text.add_theme_font_size_override("font_size", 15)
	btn_text.pressed.connect(func():
		var sender_num = "(864) 712-4446"
		if sms_disp_dropdown.selected == 1 and sms_override_edit.text.strip_edges() != "":
			sender_num = sms_override_edit.text.strip_edges()
		OS.shell_open("sms:" + phone)
	)
	qa_hbox.add_child(btn_text)

	var btn_email = Button.new()
	btn_email.text = "✉️ Email " + email_display
	btn_email.custom_minimum_size = Vector2(0, 42); btn_email.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_email.add_theme_font_size_override("font_size", 15)
	btn_email.pressed.connect(func():
		var sender_em = "connect@studycenter.org"
		if email_disp_dropdown.selected == 1 and email_override_edit.text.strip_edges() != "":
			sender_em = email_override_edit.text.strip_edges()
		OS.shell_open("mailto:" + email)
	)
	qa_hbox.add_child(btn_email)

	var btn_com = Button.new()
	btn_com.text = "💬 Open Communications Hub"
	btn_com.custom_minimum_size = Vector2(0, 42); btn_com.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_com.add_theme_font_size_override("font_size", 15)
	btn_com.pressed.connect(func(): select_workspace_tab("communications"))
	qa_hbox.add_child(btn_com)

	qa_box.add_child(qa_hbox)

	var qa_sub = Label.new()
	qa_sub.text = "Outbound SMS/Calls default to Twilio Main Line (864) 712-4446 and Outbound Email defaults to connect@studycenter.org. Use dropdowns above to specify custom sender overrides."
	qa_sub.add_theme_font_size_override("font_size", 15)
	qa_sub.add_theme_color_override("font_color", Color(0.78, 0.85, 0.95, 1.0))
	qa_sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	qa_box.add_child(qa_sub)

	communications_section.add_child(_create_card("Quick Actions & Direct Contact", qa_box))

	# 2. Check-In Messages & Next-Visit Alerts (Middle Card)
	var chk_box = VBoxContainer.new()
	chk_box.add_theme_constant_override("separation", 12)

	var chk_sub = Label.new()
	chk_sub.text = "Queue a message or alert to display automatically when this member checks in next at the kiosk."
	chk_sub.add_theme_font_size_override("font_size", 15)
	chk_sub.add_theme_color_override("font_color", Color(0.78, 0.85, 0.95, 1.0))
	chk_sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	chk_box.add_child(chk_sub)

	var ch_lbl = Label.new(); ch_lbl.text = "CHANNEL"; ch_lbl.add_theme_font_size_override("font_size", 14); ch_lbl.add_theme_color_override("font_color", Color(0.70, 0.78, 0.88, 1.0))
	var ch_dropdown = OptionButton.new()
	ch_dropdown.add_item("Email", 0); ch_dropdown.add_item("SMS Text", 1); ch_dropdown.add_item("On-Screen Check-In Popup Alert", 2)
	ch_dropdown.custom_minimum_size = Vector2(0, 44)
	ch_dropdown.add_theme_font_size_override("font_size", 16)
	chk_box.add_child(ch_lbl); chk_box.add_child(ch_dropdown)

	var msg_lbl = Label.new(); msg_lbl.text = "MESSAGE"; msg_lbl.add_theme_font_size_override("font_size", 14); msg_lbl.add_theme_color_override("font_color", Color(0.70, 0.78, 0.88, 1.0))
	var msg_edit = TextEdit.new()
	msg_edit.placeholder_text = "Type message or staff reminder for next check-in..."
	msg_edit.custom_minimum_size = Vector2(0, 100)
	msg_edit.add_theme_font_size_override("font_size", 16)
	chk_box.add_child(msg_lbl); chk_box.add_child(msg_edit)

	var btn_queue_msg = Button.new()
	btn_queue_msg.text = "➕ Queue Message For Next Check-In"
	btn_queue_msg.custom_minimum_size = Vector2(260, 44)
	btn_queue_msg.add_theme_font_size_override("font_size", 16)
	btn_queue_msg.pressed.connect(func():
		var body = msg_edit.text.strip_edges()
		if body != "" and db:
			db.execute("INSERT INTO event_outbox (event_uuid, event_type, aggregate_type, aggregate_id, payload) VALUES (?, 'CHECKIN_MESSAGE_QUEUED', 'person', ?, ?);",
				["evt_" + str(Time.get_ticks_msec()), p_uuid, body])
			msg_edit.text = ""
			refresh_view()
	)
	chk_box.add_child(btn_queue_msg)

	communications_section.add_child(_create_card("Check-In Messages & Next-Visit Alerts", chk_box))

	# 3. SMS Consent & Preferences (Bottom Card)
	var sms_box = VBoxContainer.new()
	sms_box.add_theme_constant_override("separation", 6)

	var is_sms_granted = (int(p.get("sms_consent", 1)) == 1 or bool(p.get("sms_consent_given", true)))
	var sms_lbl = Label.new()
	sms_lbl.text = "SMS Broadcast Consent: " + ("✓ Granted" if is_sms_granted else "Not Granted")
	sms_lbl.add_theme_font_size_override("font_size", 15)
	sms_lbl.add_theme_color_override("font_color", Color(0.35, 0.85, 0.55, 1.0) if is_sms_granted else Color(0.80, 0.85, 0.90, 1.0))
	sms_box.add_child(sms_lbl)

	var sms_sub = Label.new()
	sms_sub.text = "Granted via public registration or staff entry. Allows automated appointment, birthday, and ministry updates."
	sms_sub.add_theme_font_size_override("font_size", 15)
	sms_sub.add_theme_color_override("font_color", Color(0.78, 0.85, 0.95, 1.0))
	sms_sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sms_box.add_child(sms_sub)

	communications_section.add_child(_create_card("SMS Consent & Preferences", sms_box))

func _populate_history_section(p: Dictionary, att_history: Array) -> void:
	if not history_section: return

	# 1. Communication Events
	history_section.add_child(_create_card("Communication Events", _create_empty_label("No communication events recorded.")))

	# 2. Credential Events
	history_section.add_child(_create_card("Credential Events", _create_empty_label("No credential events recorded.")))

	# 3. Profile Changes
	history_section.add_child(_create_card("Profile Changes", _create_empty_label("No profile changes recorded.")))

func _create_card(title: String, body_control: Control) -> PanelContainer:
	var panel = PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.14, 0.17, 0.23, 1.0)
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.border_color = Color(0.24, 0.28, 0.36, 1.0)
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	style.content_margin_left = 22
	style.content_margin_top = 20
	style.content_margin_right = 22
	style.content_margin_bottom = 20

	panel.add_theme_stylebox_override("panel", style)

	var vbox = VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 14)

	var title_lbl = Label.new()
	title_lbl.text = title
	title_lbl.add_theme_font_size_override("font_size", 22)
	title_lbl.add_theme_color_override("font_color", Color(0.95, 0.97, 1.0))
	vbox.add_child(title_lbl)

	body_control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(body_control)
	panel.add_child(vbox)
	return panel

func _create_empty_label(text: String) -> Label:
	var lbl = Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 16)
	lbl.add_theme_color_override("font_color", Color(0.82, 0.88, 0.96))
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return lbl

func _clear_container(c: Container) -> void:
	if not c: return
	for child in c.get_children():
		child.free()

func _clear_workspace() -> void:
	_ensure_onready_nodes()
	selected_person_uuid = ""
	selected_person_index = -1
	if selected_workspace_vbox: selected_workspace_vbox.visible = false
	if no_selection_workspace: no_selection_workspace.visible = true

func _ensure_onready_nodes() -> void:
	if not workspace_initials:
		workspace_initials = get_node_or_null("MarginContainer/VBoxContainer/MainSplit/WorkspacePanel/WorkspaceMargin/SelectedWorkspaceVBox/WorkspaceHeader/HeaderMargin/HeaderVBox/TitleHBox/AvatarInitials") as Label
	if not workspace_name:
		workspace_name = get_node_or_null("MarginContainer/VBoxContainer/MainSplit/WorkspacePanel/WorkspaceMargin/SelectedWorkspaceVBox/WorkspaceHeader/HeaderMargin/HeaderVBox/TitleHBox/NameLabel") as Label
	if not workspace_human_id:
		workspace_human_id = get_node_or_null("MarginContainer/VBoxContainer/MainSplit/WorkspacePanel/WorkspaceMargin/SelectedWorkspaceVBox/WorkspaceHeader/HeaderMargin/HeaderVBox/MetaHBox/HumanIdLabel") as Label
	if not workspace_status_badge:
		workspace_status_badge = get_node_or_null("MarginContainer/VBoxContainer/MainSplit/WorkspacePanel/WorkspaceMargin/SelectedWorkspaceVBox/WorkspaceHeader/HeaderMargin/HeaderVBox/MetaHBox/StatusBadge") as Label
	if not workspace_grade_badge:
		workspace_grade_badge = get_node_or_null("MarginContainer/VBoxContainer/MainSplit/WorkspacePanel/WorkspaceMargin/SelectedWorkspaceVBox/WorkspaceHeader/HeaderMargin/HeaderVBox/MetaHBox/GradeBadge") as Label
	if not overview_section:
		overview_section = get_node_or_null("MarginContainer/VBoxContainer/MainSplit/WorkspacePanel/WorkspaceMargin/SelectedWorkspaceVBox/WorkspaceScroll/SectionStack/OverviewSection") as VBoxContainer
	if not profile_section:
		profile_section = get_node_or_null("MarginContainer/VBoxContainer/MainSplit/WorkspacePanel/WorkspaceMargin/SelectedWorkspaceVBox/WorkspaceScroll/SectionStack/ProfileSection") as VBoxContainer
	if not notes_section:
		notes_section = get_node_or_null("MarginContainer/VBoxContainer/MainSplit/WorkspacePanel/WorkspaceMargin/SelectedWorkspaceVBox/WorkspaceScroll/SectionStack/NotesSection") as VBoxContainer
	if not participation_section:
		participation_section = get_node_or_null("MarginContainer/VBoxContainer/MainSplit/WorkspacePanel/WorkspaceMargin/SelectedWorkspaceVBox/WorkspaceScroll/SectionStack/ParticipationSection") as VBoxContainer
	if not communications_section:
		communications_section = get_node_or_null("MarginContainer/VBoxContainer/MainSplit/WorkspacePanel/WorkspaceMargin/SelectedWorkspaceVBox/WorkspaceScroll/SectionStack/CommunicationsSection") as VBoxContainer
	if not history_section:
		history_section = get_node_or_null("MarginContainer/VBoxContainer/MainSplit/WorkspacePanel/WorkspaceMargin/SelectedWorkspaceVBox/WorkspaceScroll/SectionStack/HistorySection") as VBoxContainer
	if not selected_workspace_vbox:
		selected_workspace_vbox = get_node_or_null("MarginContainer/VBoxContainer/MainSplit/WorkspacePanel/WorkspaceMargin/SelectedWorkspaceVBox") as VBoxContainer
	if not no_selection_workspace:
		no_selection_workspace = get_node_or_null("MarginContainer/VBoxContainer/MainSplit/WorkspacePanel/WorkspaceMargin/NoSelectionWorkspace") as Label

func _show_view_state(state_name: String) -> void:
	var l_state = loading_state if loading_state else get_node_or_null("MarginContainer/VBoxContainer/MainSplit/RosterPanel/LoadingState") as Label
	var e_state = empty_state if empty_state else get_node_or_null("MarginContainer/VBoxContainer/MainSplit/RosterPanel/EmptyState") as Label
	var nr_state = no_results_state if no_results_state else get_node_or_null("MarginContainer/VBoxContainer/MainSplit/RosterPanel/NoResultsState") as Label
	var err_state = error_state if error_state else get_node_or_null("MarginContainer/VBoxContainer/MainSplit/RosterPanel/ErrorState") as Label
	var r_scroll = get_node_or_null("MarginContainer/VBoxContainer/MainSplit/RosterPanel/RosterScroll") as ScrollContainer
	var r_box = roster_container if roster_container else get_node_or_null("MarginContainer/VBoxContainer/MainSplit/RosterPanel/RosterScroll/RosterContainer") as VBoxContainer

	if l_state: l_state.visible = (state_name == "loading")
	if e_state: e_state.visible = (state_name == "empty")
	if nr_state: nr_state.visible = (state_name == "no_results")
	if err_state: err_state.visible = (state_name == "error")
	if r_scroll: r_scroll.visible = (state_name == "populated")
	if r_box: r_box.visible = (state_name == "populated")

func is_no_results_visible() -> bool:
	var nr_state = no_results_state if no_results_state else get_node_or_null("MarginContainer/VBoxContainer/MainSplit/RosterPanel/NoResultsState") as Label
	return nr_state.visible if nr_state else false

func is_empty_state_visible() -> bool:
	var e_state = empty_state if empty_state else get_node_or_null("MarginContainer/VBoxContainer/MainSplit/RosterPanel/EmptyState") as Label
	return e_state.visible if e_state else false

func is_error_state_visible() -> bool:
	var err_state = error_state if error_state else get_node_or_null("MarginContainer/VBoxContainer/MainSplit/RosterPanel/ErrorState") as Label
	return err_state.visible if err_state else false

func is_preview_grade_badge_visible() -> bool:
	var lbl_grade = workspace_grade_badge if workspace_grade_badge else get_node_or_null("MarginContainer/VBoxContainer/MainSplit/WorkspacePanel/WorkspaceMargin/SelectedWorkspaceVBox/WorkspaceHeader/HeaderMargin/HeaderVBox/MetaHBox/GradeBadge") as Label
	return lbl_grade.visible if lbl_grade else false

func get_preview_name_text() -> String:
	var lbl_name = workspace_name if workspace_name else get_node_or_null("MarginContainer/VBoxContainer/MainSplit/WorkspacePanel/WorkspaceMargin/SelectedWorkspaceVBox/WorkspaceHeader/HeaderMargin/HeaderVBox/TitleHBox/NameLabel") as Label
	return lbl_name.text if lbl_name else ""

func _create_credentials_card(p: Dictionary, p_uuid: String) -> PanelContainer:
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 16)
	
	# Fetch active QR info
	var qr_active = false
	var qr_hint = ""
	var issued_at = ""
	var cred_svc = QRCredentialServiceScript.new(db)
	var person_id = int(p.get("id"))
	var active_token = ""

	if db:
		var qr_res = db.execute("SELECT credential_id, token_hint, issued_at FROM participant_qr_credentials WHERE person_id = ? AND status = 'active' LIMIT 1;", [person_id])
		if qr_res["success"] and qr_res["data"].size() > 0:
			qr_active = true
			qr_hint = str(qr_res["data"][0].get("token_hint", ""))
			issued_at = str(qr_res["data"][0].get("issued_at", ""))
			if issued_at == "" or issued_at == "null":
				issued_at = "Active Issue"
			active_token = cred_svc.get_active_raw_token(person_id)
		
	# Fetch active PIN info
	var pin_active = false
	if db:
		var pin_res = db.execute("SELECT credential_id FROM participant_pin_credentials WHERE person_id = ? AND status = 'active' LIMIT 1;", [person_id])
		if pin_res["success"] and pin_res["data"].size() > 0:
			pin_active = true

	# Member Details Overview Grid
	var details_hbox = HBoxContainer.new()
	details_hbox.add_theme_constant_override("separation", 16)

	# Left Column: Photo & Details
	var info_vbox = VBoxContainer.new()
	info_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info_vbox.add_theme_constant_override("separation", 8)

	var human_id = str(p.get("human_id", "PRT-0000"))
	var photo_path = str(p.get("photo_url", ""))
	var has_photo = photo_path != "" and FileAccess.file_exists(photo_path)

	var lbl_member_id = Label.new()
	lbl_member_id.text = "Member ID: " + human_id
	lbl_member_id.add_theme_font_size_override("font_size", 16)
	lbl_member_id.add_theme_color_override("font_color", Color(0.95, 0.6, 0.2, 1.0))
	info_vbox.add_child(lbl_member_id)

	var lbl_qr_status = Label.new()
	lbl_qr_status.text = "Credential Status: " + ("🟢 Active" if qr_active else "🔴 Not Issued")
	if qr_active and qr_hint != "":
		lbl_qr_status.text += " (" + qr_hint + ")"
	lbl_qr_status.add_theme_font_size_override("font_size", 15)
	info_vbox.add_child(lbl_qr_status)

	var lbl_issue_date = Label.new()
	lbl_issue_date.text = "Issued Date: " + (issued_at.left(10) if qr_active else "N/A")
	lbl_issue_date.add_theme_font_size_override("font_size", 14)
	lbl_issue_date.add_theme_color_override("font_color", Color(0.7, 0.75, 0.8, 1.0))
	info_vbox.add_child(lbl_issue_date)

	var lbl_pin = Label.new()
	lbl_pin.text = "PIN Status: " + ("🟢 PIN Set" if pin_active else "🔴 No PIN Set")
	lbl_pin.add_theme_font_size_override("font_size", 14)
	info_vbox.add_child(lbl_pin)

	var lbl_card_eligibility = Label.new()
	if qr_active and active_token == "":
		lbl_card_eligibility.text = "Card Status: 🟡 Issued on Another Device (Replace Credential to Print on this Computer)"
		lbl_card_eligibility.add_theme_color_override("font_color", Color(0.9, 0.7, 0.2, 1.0))
	elif qr_active and has_photo:
		lbl_card_eligibility.text = "Card Status: 🟢 Ready for Printing (Photo & QR Active)"
		lbl_card_eligibility.add_theme_color_override("font_color", Color(0.3, 0.8, 0.4, 1.0))
	elif qr_active:
		lbl_card_eligibility.text = "Card Status: 🟡 Eligible (Avatar Fallback Photo)"
		lbl_card_eligibility.add_theme_color_override("font_color", Color(0.9, 0.7, 0.2, 1.0))
	else:
		lbl_card_eligibility.text = "Card Status: 🔴 Credential Required"
		lbl_card_eligibility.add_theme_color_override("font_color", Color(0.85, 0.35, 0.35, 1.0))
	lbl_card_eligibility.add_theme_font_size_override("font_size", 14)
	info_vbox.add_child(lbl_card_eligibility)

	details_hbox.add_child(info_vbox)

	# Right Column: QR Image Texture
	if qr_active and active_token != "":
		var qr_vbox = VBoxContainer.new()
		qr_vbox.alignment = BoxContainer.ALIGNMENT_CENTER

		var qr_url = "https://checkin.reallife-studycenter.org/public-returning?credential=" + active_token
		var qr_tex = QrGeneratorScript.generate_qr_texture(qr_url, 140)

		var qr_rect = TextureRect.new()
		qr_rect.texture = qr_tex
		qr_rect.custom_minimum_size = Vector2(140, 140)
		qr_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		qr_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		qr_vbox.add_child(qr_rect)

		var qr_caption = Label.new()
		qr_caption.text = "Scannable Pass QR"
		qr_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		qr_caption.add_theme_font_size_override("font_size", 12)
		qr_caption.add_theme_color_override("font_color", Color(0.6, 0.65, 0.7, 1.0))
		qr_vbox.add_child(qr_caption)

		details_hbox.add_child(qr_vbox)

	vbox.add_child(details_hbox)

	# Empty State Alert if no credential
	if not qr_active:
		var empty_banner = PanelContainer.new()
		var eb_st = StyleBoxFlat.new()
		eb_st.bg_color = Color(0.25, 0.15, 0.15, 1.0)
		eb_st.border_color = Color(0.8, 0.3, 0.3, 1.0)
		eb_st.border_width_left = 3
		eb_st.content_margin_left = 12
		eb_st.content_margin_top = 8
		eb_st.content_margin_right = 12
		eb_st.content_margin_bottom = 8
		empty_banner.add_theme_stylebox_override("panel", eb_st)

		var eb_lbl = Label.new()
		eb_lbl.text = "⚠️ No member credential has been issued."
		eb_lbl.add_theme_font_size_override("font_size", 14)
		eb_lbl.add_theme_color_override("font_color", Color(0.95, 0.7, 0.7, 1.0))
		empty_banner.add_child(eb_lbl)
		vbox.add_child(empty_banner)

	# Action Buttons Grid
	var btn_grid = GridContainer.new()
	btn_grid.columns = 3
	btn_grid.add_theme_constant_override("h_separation", 10)
	btn_grid.add_theme_constant_override("v_separation", 10)

	# 1. Issue / Replace QR
	var btn_issue = Button.new()
	btn_issue.text = "🔄 Replace QR Credential" if qr_active else "➕ Issue Member QR"
	btn_issue.custom_minimum_size = Vector2(170, 36)
	btn_issue.pressed.connect(func():
		var name_str = (str(p.get("first_name", "")) + " " + str(p.get("last_name", ""))).strip_edges()
		if qr_active:
			_show_confirm_dialog(
				"⚠️ Replace QR Credential",
				"Warning: Replacing the QR credential for " + name_str + " will immediately revoke all existing physical cards, Apple Wallet, and Google Wallet passes. Do you want to generate a new QR credential?",
				"Replace Credential",
				func(): _open_qr_issue_dialog(p, p_uuid),
				true
			)
		else:
			_open_qr_issue_dialog(p, p_uuid)
	)
	btn_grid.add_child(btn_issue)

	# 2. Preview Membership Card
	var btn_preview = Button.new()
	btn_preview.text = "👁️ Preview Membership Card"
	btn_preview.custom_minimum_size = Vector2(190, 36)
	btn_preview.pressed.connect(func(): _open_card_preview_for_person(p))
	btn_grid.add_child(btn_preview)

	# 3. Preview Wallet Card
	var btn_preview_wallet = Button.new()
	btn_preview_wallet.text = "📱 Preview Wallet Card"
	btn_preview_wallet.custom_minimum_size = Vector2(170, 36)
	btn_preview_wallet.disabled = not qr_active
	btn_preview_wallet.pressed.connect(func(): _open_wallet_card_preview_for_person(p))
	btn_grid.add_child(btn_preview_wallet)

	# 4. Print / Reprint Card
	var btn_print = Button.new()
	btn_print.text = "🖨️ Print / Reprint Card"
	btn_print.custom_minimum_size = Vector2(170, 36)
	btn_print.pressed.connect(func(): _open_card_preview_for_person(p))
	btn_grid.add_child(btn_print)

	# 5. Add to Print Queue
	var btn_queue = Button.new()
	btn_queue.text = "📥 Add to Print Queue"
	btn_queue.custom_minimum_size = Vector2(170, 36)
	btn_queue.pressed.connect(func(): _add_person_to_print_queue(p))
	btn_grid.add_child(btn_queue)

	# 6. Revoke Credential
	var btn_revoke = Button.new()
	btn_revoke.text = "🚫 Revoke Credential"
	btn_revoke.custom_minimum_size = Vector2(170, 36)
	btn_revoke.disabled = not qr_active
	btn_revoke.pressed.connect(func():
		var name_str = (str(p.get("first_name", "")) + " " + str(p.get("last_name", ""))).strip_edges()
		_show_confirm_dialog(
			"🚫 Revoke Credential",
			"Danger: Revoking credentials will immediately disable check-in access across physical cards, Apple Wallet, and Google Wallet for " + name_str + ". Are you sure you want to revoke?",
			"Revoke Credential",
			func():
				var svc = QRCredentialServiceScript.new(db)
				svc.revoke_credential(int(p.get("id")))
				refresh_view(),
			true
		)
	)
	btn_grid.add_child(btn_revoke)

	# 7. Set/Reset PIN
	var btn_pin = Button.new()
	btn_pin.text = "🔑 Reset PIN" if pin_active else "🔑 Set PIN"
	btn_pin.custom_minimum_size = Vector2(150, 36)
	btn_pin.pressed.connect(func():
		var name_str = (str(p.get("first_name", "")) + " " + str(p.get("last_name", ""))).strip_edges()
		if pin_active:
			_show_confirm_dialog(
				"🔑 Reset PIN",
				"Warning: Resetting the check-in PIN for " + name_str + " will replace their existing PIN. Proceed?",
				"Reset PIN",
				func(): _open_pin_reset_dialog(p, p_uuid),
				false
			)
		else:
			_open_pin_reset_dialog(p, p_uuid)
	)
	btn_grid.add_child(btn_pin)

	# 8. Email Digital Member Pass
	var btn_email_pass = Button.new()
	btn_email_pass.text = "✉️ Email Digital Member Pass"
	btn_email_pass.custom_minimum_size = Vector2(210, 36)
	btn_email_pass.disabled = not qr_active
	btn_email_pass.pressed.connect(func():
		var com_svc = CommunicationsServiceScript.new(db)
		var email_res_val = com_svc.email_digital_member_pass(int(p.get("id")))
		if email_res_val.get("success", false):
			_show_info_modal("Digital Member Pass Dispatched", "✅ Digital Member Pass email dispatched successfully to " + str(p.get("first_name", "")) + "!")
		else:
			_show_info_modal("Email Dispatch Notice", "ℹ️ Digital Member Pass link generated for " + str(p.get("first_name", "")) + ".")
	)
	btn_grid.add_child(btn_email_pass)

	# 9. SMS Digital Member Pass
	var btn_sms_pass = Button.new()
	btn_sms_pass.text = "💬 SMS Digital Member Pass"
	btn_sms_pass.custom_minimum_size = Vector2(210, 36)
	btn_sms_pass.disabled = not qr_active
	btn_sms_pass.pressed.connect(func():
		var com_svc = CommunicationsServiceScript.new(db)
		var sms_res_val = com_svc.sms_digital_member_pass(int(p.get("id")))
		if sms_res_val.get("success", false):
			_show_info_modal("Digital Member Pass SMS Dispatched", "✅ Digital Member Pass text message dispatched successfully to " + str(p.get("first_name", "")) + "!")
		else:
			_show_info_modal("SMS Dispatch Notice", "ℹ️ Digital Member Pass text queued for " + str(p.get("first_name", "")) + ".")
	)
	btn_grid.add_child(btn_sms_pass)

	vbox.add_child(btn_grid)

	return _create_card("DIGITAL MEMBER PASS & CREDENTIALS", vbox)

func _open_card_preview_for_person(p: Dictionary) -> void:
	var cred_svc = QRCredentialServiceScript.new(db)
	var person_id = int(p.get("id"))
	var token = cred_svc.get_active_raw_token(person_id)
	if token == "":
		_show_device_restriction_modal(p)
		return
	
	var dlg = CardPrintQueueDialogScript.new(self)
	dlg._open_card_preview(p, token)

func _show_confirm_dialog(title_text: String, warning_text: String, confirm_button_text: String, on_confirm: Callable, is_danger: bool = true) -> void:
	var modal_layer = CanvasLayer.new()
	modal_layer.layer = 140

	var overlay = ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.75)
	overlay.anchors_preset = Control.PRESET_FULL_RECT
	modal_layer.add_child(overlay)

	var panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(520, 220)
	panel.anchors_preset = Control.PRESET_CENTER
	panel.anchor_left = 0.5
	panel.anchor_top = 0.5
	panel.anchor_right = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -260
	panel.offset_top = -110
	panel.offset_right = 260
	panel.offset_bottom = 110

	var st = StyleBoxFlat.new()
	st.bg_color = Color(0.16, 0.18, 0.25, 1.0)
	st.border_color = Color(0.95, 0.40, 0.35, 1.0) if is_danger else Color(0.95, 0.70, 0.25, 1.0)
	st.border_width_left = 3; st.border_width_top = 3
	st.border_width_right = 3; st.border_width_bottom = 3
	st.corner_radius_top_left = 12; st.corner_radius_top_right = 12
	st.corner_radius_bottom_left = 12; st.corner_radius_bottom_right = 12
	st.content_margin_left = 24; st.content_margin_top = 20
	st.content_margin_right = 24; st.content_margin_bottom = 20
	panel.add_theme_stylebox_override("panel", st)
	modal_layer.add_child(panel)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	panel.add_child(vbox)

	var title = Label.new()
	title.text = title_text
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color(0.98, 0.45, 0.40, 1.0) if is_danger else Color(0.98, 0.75, 0.30, 1.0))
	vbox.add_child(title)

	var body = Label.new()
	body.text = warning_text
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_theme_font_size_override("font_size", 14)
	body.add_theme_color_override("font_color", Color(0.90, 0.92, 0.96, 1.0))
	vbox.add_child(body)

	var btn_hbox = HBoxContainer.new()
	btn_hbox.alignment = BoxContainer.ALIGNMENT_END
	btn_hbox.add_theme_constant_override("separation", 12)

	var btn_cancel = Button.new()
	btn_cancel.text = "Cancel"
	btn_cancel.custom_minimum_size = Vector2(100, 36)
	btn_cancel.pressed.connect(func(): modal_layer.queue_free())
	btn_hbox.add_child(btn_cancel)

	var btn_confirm = Button.new()
	btn_confirm.text = confirm_button_text
	btn_confirm.custom_minimum_size = Vector2(160, 36)
	if is_danger:
		var btn_st = StyleBoxFlat.new()
		btn_st.bg_color = Color(0.80, 0.22, 0.20, 1.0)
		btn_st.corner_radius_top_left = 6; btn_st.corner_radius_top_right = 6
		btn_st.corner_radius_bottom_left = 6; btn_st.corner_radius_bottom_right = 6
		btn_confirm.add_theme_stylebox_override("normal", btn_st)
		btn_confirm.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	btn_confirm.pressed.connect(func():
		modal_layer.queue_free()
		if on_confirm.is_valid():
			on_confirm.call()
	)
	btn_hbox.add_child(btn_confirm)

	vbox.add_child(btn_hbox)
	add_child(modal_layer)

func _show_status_change_confirmation(member_name: String, current_status: String, new_status: String, on_confirm: Callable) -> void:
	if current_status.to_lower() == new_status.to_lower():
		if on_confirm.is_valid():
			on_confirm.call()
		return

	var modal_layer = CanvasLayer.new()
	modal_layer.layer = 150

	var overlay = ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.75)
	overlay.anchors_preset = Control.PRESET_FULL_RECT
	modal_layer.add_child(overlay)

	var panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(560, 360)
	panel.anchors_preset = Control.PRESET_CENTER
	panel.anchor_left = 0.5; panel.anchor_top = 0.5
	panel.anchor_right = 0.5; panel.anchor_bottom = 0.5
	panel.offset_left = -280; panel.offset_top = -180
	panel.offset_right = 280; panel.offset_bottom = 180

	var st = StyleBoxFlat.new()
	st.bg_color = Color(0.14, 0.16, 0.22, 1.0)
	st.border_color = Color(0.95, 0.55, 0.25, 1.0)
	st.border_width_left = 3; st.border_width_top = 3
	st.border_width_right = 3; st.border_width_bottom = 3
	st.corner_radius_top_left = 12; st.corner_radius_top_right = 12
	st.corner_radius_bottom_left = 12; st.corner_radius_bottom_right = 12
	st.content_margin_left = 24; st.content_margin_top = 20
	st.content_margin_right = 24; st.content_margin_bottom = 20
	panel.add_theme_stylebox_override("panel", st)
	modal_layer.add_child(panel)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	panel.add_child(vbox)

	var title = Label.new()
	title.text = "Confirm Member Status Change"
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color(0.98, 0.65, 0.25, 1.0))
	vbox.add_child(title)

	var body_txt = "You are about to change this member's status.\n\n"
	body_txt += "Member:\n" + member_name + "\n\n"
	body_txt += "Current Status:\n" + current_status + "\n\n"
	body_txt += "New Status:\n" + new_status + "\n\n"
	body_txt += "Changing a member's status may immediately affect:\n\n"
	body_txt += "• Building access\n"
	body_txt += "• QR credential validity\n"
	body_txt += "• Apple Wallet access\n"
	body_txt += "• Google Wallet access\n"
	body_txt += "• Physical card eligibility\n"
	body_txt += "• Communications permissions\n"
	body_txt += "• Automated workflows\n\n"
	body_txt += "ARE YOU SURE YOU WANT TO CHANGE THIS MEMBER'S STATUS?"

	var body = Label.new()
	body.text = body_txt
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_theme_font_size_override("font_size", 13)
	body.add_theme_color_override("font_color", Color(0.90, 0.92, 0.96, 1.0))
	vbox.add_child(body)

	var btn_hbox = HBoxContainer.new()
	btn_hbox.alignment = BoxContainer.ALIGNMENT_END
	btn_hbox.add_theme_constant_override("separation", 12)

	var btn_cancel = Button.new()
	btn_cancel.text = "Cancel"
	btn_cancel.custom_minimum_size = Vector2(100, 36)
	btn_cancel.pressed.connect(func(): modal_layer.queue_free())
	btn_hbox.add_child(btn_cancel)

	var btn_confirm = Button.new()
	btn_confirm.text = "Change Status"
	btn_confirm.custom_minimum_size = Vector2(140, 36)
	var btn_st = StyleBoxFlat.new()
	btn_st.bg_color = Color(0.85, 0.45, 0.15, 1.0)
	btn_st.corner_radius_top_left = 6; btn_st.corner_radius_top_right = 6
	btn_st.corner_radius_bottom_left = 6; btn_st.corner_radius_bottom_right = 6
	btn_confirm.add_theme_stylebox_override("normal", btn_st)
	btn_confirm.add_theme_color_override("font_color", Color(1, 1, 1, 1))

	btn_confirm.pressed.connect(func():
		modal_layer.queue_free()
		if on_confirm.is_valid():
			on_confirm.call()
	)
	btn_hbox.add_child(btn_confirm)

	vbox.add_child(btn_hbox)
	add_child(modal_layer)

func _open_wallet_card_preview_for_person(p: Dictionary) -> void:
	var cred_svc = QRCredentialServiceScript.new(db)
	var person_id = int(p.get("id"))
	var token = cred_svc.get_active_raw_token(person_id)
	if token == "":
		_show_device_restriction_modal(p)
		return

	var modal_layer = CanvasLayer.new()
	modal_layer.layer = 150

	var overlay = ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.80)
	overlay.anchors_preset = Control.PRESET_FULL_RECT
	modal_layer.add_child(overlay)

	var panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(380, 580)
	panel.anchors_preset = Control.PRESET_CENTER
	panel.anchor_left = 0.5; panel.anchor_top = 0.5
	panel.anchor_right = 0.5; panel.anchor_bottom = 0.5
	panel.offset_left = -190; panel.offset_top = -290
	panel.offset_right = 190; panel.offset_bottom = 290

	var st = StyleBoxFlat.new()
	st.bg_color = Color(0.02, 0.02, 0.03, 1.0)
	st.border_color = Color(0.25, 0.28, 0.35, 1.0)
	st.border_width_left = 2; st.border_width_top = 2
	st.border_width_right = 2; st.border_width_bottom = 2
	st.corner_radius_top_left = 16; st.corner_radius_top_right = 16
	st.corner_radius_bottom_left = 16; st.corner_radius_bottom_right = 16
	st.content_margin_left = 20; st.content_margin_top = 18
	st.content_margin_right = 20; st.content_margin_bottom = 18
	panel.add_theme_stylebox_override("panel", st)
	modal_layer.add_child(panel)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	panel.add_child(vbox)

	# 1. Header Branding
	var header_path = ProjectSettings.globalize_path("res://assets/cards/pass_logo@3x.png")
	var header_tex: ImageTexture = null
	if FileAccess.file_exists(header_path):
		var h_img = Image.load_from_file(header_path)
		if h_img and not h_img.is_empty():
			header_tex = ImageTexture.create_from_image(h_img)
	if header_tex:
		var header_rect = TextureRect.new()
		header_rect.texture = header_tex
		header_rect.custom_minimum_size = Vector2(340, 54)
		header_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		header_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		vbox.add_child(header_rect)
	else:
		var header_lbl = Label.new()
		header_lbl.text = "REAL LIFE HOUSE"
		header_lbl.add_theme_font_size_override("font_size", 18)
		header_lbl.add_theme_color_override("font_color", Color(1, 1, 1))
		vbox.add_child(header_lbl)

	var sep = HSeparator.new()
	sep.add_theme_stylebox_override("separator", StyleBoxFlat.new())
	vbox.add_child(sep)

	# 2. Member Info & Photo
	var first_name = str(p.get("first_name", "")).strip_edges()
	var last_name = str(p.get("last_name", "")).strip_edges()
	var display_name = (first_name + " " + last_name).strip_edges()
	if display_name == "": display_name = "Valued Member"

	var content_hbox = HBoxContainer.new()
	content_hbox.add_theme_constant_override("separation", 12)

	var details_vbox = VBoxContainer.new()
	details_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	details_vbox.add_theme_constant_override("separation", 4)

	var lbl_name_title = Label.new()
	lbl_name_title.text = "MEMBER NAME"
	lbl_name_title.add_theme_font_size_override("font_size", 11)
	lbl_name_title.add_theme_color_override("font_color", Color(0.90, 0.66, 0.09))
	details_vbox.add_child(lbl_name_title)

	var lbl_name_val = Label.new()
	lbl_name_val.text = display_name.to_upper()
	lbl_name_val.add_theme_font_size_override("font_size", 18)
	lbl_name_val.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0))
	lbl_name_val.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	details_vbox.add_child(lbl_name_val)

	var spacer_mid = Control.new()
	spacer_mid.custom_minimum_size = Vector2(0, 6)
	details_vbox.add_child(spacer_mid)

	var lbl_fac_title = Label.new()
	lbl_fac_title.text = "FACILITY"
	lbl_fac_title.add_theme_font_size_override("font_size", 10)
	lbl_fac_title.add_theme_color_override("font_color", Color(0.90, 0.66, 0.09))
	details_vbox.add_child(lbl_fac_title)

	var lbl_fac_val = Label.new()
	lbl_fac_val.text = "Real Life House"
	lbl_fac_val.add_theme_font_size_override("font_size", 13)
	lbl_fac_val.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0))
	details_vbox.add_child(lbl_fac_val)

	var lbl_ph_title = Label.new()
	lbl_ph_title.text = "PHONE"
	lbl_ph_title.add_theme_font_size_override("font_size", 10)
	lbl_ph_title.add_theme_color_override("font_color", Color(0.90, 0.66, 0.09))
	details_vbox.add_child(lbl_ph_title)

	var lbl_ph_val = Label.new()
	lbl_ph_val.text = "(864) 712-4446"
	lbl_ph_val.add_theme_font_size_override("font_size", 13)
	lbl_ph_val.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0))
	details_vbox.add_child(lbl_ph_val)

	content_hbox.add_child(details_vbox)

	var photo_tex = _create_texture_from_base64(String(p.get("profile_photo")) if p.get("profile_photo") != null else "")
	if photo_tex:
		var photo_rect = TextureRect.new()
		photo_rect.texture = photo_tex
		photo_rect.custom_minimum_size = Vector2(90, 110)
		photo_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		photo_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		content_hbox.add_child(photo_rect)
	else:
		var av_lbl = Label.new()
		av_lbl.text = (first_name.left(1) + last_name.left(1)).to_upper()
		av_lbl.custom_minimum_size = Vector2(90, 110)
		av_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		av_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		av_lbl.add_theme_font_size_override("font_size", 28)
		var av_st = StyleBoxFlat.new()
		av_st.bg_color = Color(0.18, 0.22, 0.30, 1.0)
		av_st.corner_radius_top_left = 8; av_st.corner_radius_top_right = 8
		av_st.corner_radius_bottom_left = 8; av_st.corner_radius_bottom_right = 8
		av_lbl.add_theme_stylebox_override("normal", av_st)
		content_hbox.add_child(av_lbl)

	vbox.add_child(content_hbox)

	# 3. QR Barcode Zone
	var qr_vbox = VBoxContainer.new()
	qr_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	qr_vbox.add_theme_constant_override("separation", 6)

	var qr_url = "https://checkin.reallife-studycenter.org/public-returning?credential=" + token
	var qr_img = QrGeneratorScript.generate_qr_image(qr_url, 180)
	if qr_img and not qr_img.is_empty():
		var qr_tex = ImageTexture.create_from_image(qr_img)
		var qr_rect = TextureRect.new()
		qr_rect.texture = qr_tex
		qr_rect.custom_minimum_size = Vector2(170, 170)
		qr_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		qr_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		qr_rect.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		qr_vbox.add_child(qr_rect)

	var qr_lbl = Label.new()
	qr_lbl.text = "Scannable Pass QR"
	qr_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	qr_lbl.add_theme_font_size_override("font_size", 12)
	qr_lbl.add_theme_color_override("font_color", Color(0.70, 0.75, 0.85))
	qr_vbox.add_child(qr_lbl)

	vbox.add_child(qr_vbox)

	# 4. Action Buttons
	var btn_hbox = HBoxContainer.new()
	btn_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_hbox.add_theme_constant_override("separation", 8)

	var btn_email = Button.new()
	btn_email.text = "✉️ Email Pass"
	btn_email.custom_minimum_size = Vector2(110, 34)
	btn_email.pressed.connect(func():
		var com_svc = CommunicationsServiceScript.new(db)
		com_svc.email_digital_member_pass(person_id)
		_show_info_modal("Dispatched", "✅ Digital Wallet pass emailed to " + display_name + "!")
	)
	btn_hbox.add_child(btn_email)

	var btn_sms = Button.new()
	btn_sms.text = "💬 SMS Pass"
	btn_sms.custom_minimum_size = Vector2(110, 34)
	btn_sms.pressed.connect(func():
		var com_svc = CommunicationsServiceScript.new(db)
		com_svc.sms_digital_member_pass(person_id)
		_show_info_modal("Dispatched", "✅ Digital Wallet pass text sent to " + display_name + "!")
	)
	btn_hbox.add_child(btn_sms)

	var btn_close = Button.new()
	btn_close.text = "Close"
	btn_close.custom_minimum_size = Vector2(80, 34)
	btn_close.pressed.connect(func(): modal_layer.queue_free())
	btn_hbox.add_child(btn_close)

	vbox.add_child(btn_hbox)
	add_child(modal_layer)

func _show_device_restriction_modal(p: Dictionary) -> void:
	var modal_layer = CanvasLayer.new()
	modal_layer.layer = 120

	var overlay = ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.70)
	overlay.anchors_preset = Control.PRESET_FULL_RECT
	modal_layer.add_child(overlay)

	var panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(560, 240)
	panel.anchors_preset = Control.PRESET_CENTER
	panel.anchor_left = 0.5
	panel.anchor_top = 0.5
	panel.anchor_right = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -280
	panel.offset_top = -120
	panel.offset_right = 280
	panel.offset_bottom = 120

	var st = StyleBoxFlat.new()
	st.bg_color = Color(0.16, 0.18, 0.24, 1.0)
	st.corner_radius_top_left = 10
	st.corner_radius_top_right = 10
	st.corner_radius_bottom_left = 10
	st.corner_radius_bottom_right = 10
	st.content_margin_left = 20
	st.content_margin_top = 20
	st.content_margin_right = 20
	st.content_margin_bottom = 20
	panel.add_theme_stylebox_override("panel", st)
	modal_layer.add_child(panel)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	panel.add_child(vbox)

	var title = Label.new()
	title.text = "🔒 Device Credential Restriction"
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color(0.95, 0.7, 0.2, 1.0))
	vbox.add_child(title)

	var body = Label.new()
	body.text = "This credential cannot be reprinted on this device because it was issued on another device or the OS Keychain entry is unavailable. Click 'Replace Credential' to issue a new card for this computer."
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_theme_font_size_override("font_size", 14)
	body.add_theme_color_override("font_color", Color(0.85, 0.88, 0.9, 1.0))
	vbox.add_child(body)

	var btn_hbox = HBoxContainer.new()
	btn_hbox.alignment = BoxContainer.ALIGNMENT_END
	btn_hbox.add_theme_constant_override("separation", 10)

	var btn_replace = Button.new()
	btn_replace.text = "🔄 Replace Credential"
	btn_replace.custom_minimum_size = Vector2(160, 36)
	btn_replace.pressed.connect(func():
		modal_layer.queue_free()
		_open_qr_issue_dialog(p, str(p.get("person_uuid", "")))
	)
	btn_hbox.add_child(btn_replace)

	var btn_close = Button.new()
	btn_close.text = "Close"
	btn_close.custom_minimum_size = Vector2(90, 36)
	btn_close.pressed.connect(func(): modal_layer.queue_free())
	btn_hbox.add_child(btn_close)

	vbox.add_child(btn_hbox)
	add_child(modal_layer)

func _add_person_to_print_queue(p: Dictionary) -> void:
	if not db:
		return
	var person_id = int(p.get("id"))
	var person_uuid = str(p.get("person_uuid", ""))
	var name_str = (str(p.get("first_name", "")) + " " + str(p.get("last_name", ""))).strip_edges()
	var queue_uuid = "CPQ-" + str(Time.get_ticks_msec())

	var check_res = db.execute("SELECT id FROM card_print_queue WHERE person_id = ? AND status = 'pending' LIMIT 1;", [person_id])
	if check_res["success"] and check_res["data"].size() > 0:
		_show_info_modal("Card Print Queue Notice", "ℹ️ " + name_str + " is already in the print queue as Pending.", "Open Print Queue", func(): _open_card_print_queue_dialog())
		return

	var sql = "INSERT INTO card_print_queue (queue_uuid, person_id, person_uuid, status, added_at) VALUES (?, ?, ?, 'pending', datetime('now'));"
	var res = db.execute(sql, [queue_uuid, person_id, person_uuid])
	if res["success"]:
		_show_info_modal("Added to Print Queue", "✅ Successfully added " + name_str + " to the Card Print Queue!", "Open Print Queue", func(): _open_card_print_queue_dialog())

func _show_info_modal(title_text: String, message_text: String, action_text: String = "", on_action: Callable = Callable()) -> void:
	var modal_layer = CanvasLayer.new()
	modal_layer.layer = 130

	var overlay = ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.70)
	overlay.anchors_preset = Control.PRESET_FULL_RECT
	modal_layer.add_child(overlay)

	var panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(500, 200)
	panel.anchors_preset = Control.PRESET_CENTER
	panel.anchor_left = 0.5
	panel.anchor_top = 0.5
	panel.anchor_right = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -250
	panel.offset_top = -100
	panel.offset_right = 250
	panel.offset_bottom = 100

	var st = StyleBoxFlat.new()
	st.bg_color = Color(0.16, 0.20, 0.28, 1.0)
	st.border_color = Color(0.35, 0.65, 0.90, 1.0)
	st.border_width_left = 3
	st.border_width_top = 3
	st.border_width_right = 3
	st.border_width_bottom = 3
	st.corner_radius_top_left = 10
	st.corner_radius_top_right = 10
	st.corner_radius_bottom_left = 10
	st.corner_radius_bottom_right = 10
	st.content_margin_left = 20
	st.content_margin_top = 20
	st.content_margin_right = 20
	st.content_margin_bottom = 20
	panel.add_theme_stylebox_override("panel", st)
	modal_layer.add_child(panel)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	panel.add_child(vbox)

	var title = Label.new()
	title.text = title_text
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color(0.40, 0.85, 0.60, 1.0))
	vbox.add_child(title)

	var body = Label.new()
	body.text = message_text
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_theme_font_size_override("font_size", 14)
	body.add_theme_color_override("font_color", Color(0.9, 0.9, 0.95, 1.0))
	vbox.add_child(body)

	var btn_hbox = HBoxContainer.new()
	btn_hbox.alignment = BoxContainer.ALIGNMENT_END
	btn_hbox.add_theme_constant_override("separation", 10)

	if action_text != "" and on_action.is_valid():
		var btn_act = Button.new()
		btn_act.text = action_text
		btn_act.custom_minimum_size = Vector2(140, 36)
		btn_act.pressed.connect(func():
			modal_layer.queue_free()
			on_action.call()
		)
		btn_hbox.add_child(btn_act)

	var btn_close = Button.new()
	btn_close.text = "OK"
	btn_close.custom_minimum_size = Vector2(80, 36)
	btn_close.pressed.connect(func(): modal_layer.queue_free())
	btn_hbox.add_child(btn_close)

	vbox.add_child(btn_hbox)
	add_child(modal_layer)

func _open_card_print_queue_dialog() -> void:
	var dlg = CardPrintQueueDialogScript.new(self)
	dlg.show_dialog()

func _open_public_qr_sign_dialog() -> void:
	var dlg = PublicQrSignDialogScript.new(self)
	dlg.show_dialog()

func _open_qr_issue_dialog(p: Dictionary, p_uuid: String) -> void:
	var cred_svc = QRCredentialServiceScript.new(db)
	var person_id = int(p.get("id"))
	var name_str = (str(p.get("first_name", "")) + " " + str(p.get("last_name", ""))).strip_edges()

	# Check if active credential exists
	var active_exists = false
	if db:
		var check_res = db.execute("SELECT credential_id FROM participant_qr_credentials WHERE person_id = ? AND status = 'active' LIMIT 1;", [person_id])
		if check_res["success"] and check_res["data"].size() > 0:
			active_exists = true

	if active_exists:
		_show_replacement_warning_modal(p, func():
			cred_svc.issue_credential(person_id, p_uuid)
			refresh_view()
		)
	else:
		cred_svc.issue_credential(person_id, p_uuid)
		refresh_view()

func _show_replacement_warning_modal(p: Dictionary, on_confirm: Callable) -> void:
	var modal_layer = CanvasLayer.new()
	modal_layer.layer = 125

	var overlay = ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.70)
	overlay.anchors_preset = Control.PRESET_FULL_RECT
	modal_layer.add_child(overlay)

	var panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(560, 240)
	panel.anchors_preset = Control.PRESET_CENTER
	panel.anchor_left = 0.5
	panel.anchor_top = 0.5
	panel.anchor_right = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -280
	panel.offset_top = -120
	panel.offset_right = 280
	panel.offset_bottom = 120

	var st = StyleBoxFlat.new()
	st.bg_color = Color(0.22, 0.16, 0.16, 1.0)
	st.border_color = Color(0.85, 0.35, 0.35, 1.0)
	st.border_width_left = 3
	st.border_width_top = 3
	st.border_width_right = 3
	st.border_width_bottom = 3
	st.corner_radius_top_left = 10
	st.corner_radius_top_right = 10
	st.corner_radius_bottom_left = 10
	st.corner_radius_bottom_right = 10
	st.content_margin_left = 20
	st.content_margin_top = 20
	st.content_margin_right = 20
	st.content_margin_bottom = 20
	panel.add_theme_stylebox_override("panel", st)
	modal_layer.add_child(panel)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	panel.add_child(vbox)

	var name_str = (str(p.get("first_name", "")) + " " + str(p.get("last_name", ""))).strip_edges()
	var title = Label.new()
	title.text = "⚠️ Confirm Credential Replacement"
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color(0.95, 0.45, 0.45, 1.0))
	vbox.add_child(title)

	var body = Label.new()
	body.text = "Replacing this credential will immediately REVOKE the existing card for " + name_str + ". Any physical card printed previously will stop working and fail scanning. Do you want to proceed?"
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_theme_font_size_override("font_size", 14)
	body.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9, 1.0))
	vbox.add_child(body)

	var btn_hbox = HBoxContainer.new()
	btn_hbox.alignment = BoxContainer.ALIGNMENT_END
	btn_hbox.add_theme_constant_override("separation", 10)

	var btn_confirm = Button.new()
	btn_confirm.text = "🔄 Confirm & Replace Credential"
	btn_confirm.custom_minimum_size = Vector2(210, 36)
	btn_confirm.pressed.connect(func():
		modal_layer.queue_free()
		on_confirm.call()
	)
	btn_hbox.add_child(btn_confirm)

	var btn_cancel = Button.new()
	btn_cancel.text = "Cancel"
	btn_cancel.custom_minimum_size = Vector2(90, 36)
	btn_cancel.pressed.connect(func(): modal_layer.queue_free())
	btn_hbox.add_child(btn_cancel)

	vbox.add_child(btn_hbox)
	add_child(modal_layer)

func _open_pin_reset_dialog(p: Dictionary, p_uuid: String) -> void:
	var name_str = str(p.get("first_name", "")) + " " + str(p.get("last_name", ""))
	_show_input_modal(
		"Set PIN Code for " + name_str.strip_edges(),
		"Enter 4-digit PIN (e.g., 1234)...",
		"Set PIN",
		func(pin):
			if db:
				db.execute("UPDATE participant_pin_credentials SET status = 'revoked' WHERE person_id = ? AND status = 'active';", [p.get("id")])
				var cred_id = "PIN-" + str(Time.get_ticks_msec())
				db.execute("INSERT INTO participant_pin_credentials (credential_id, person_id, pin_hash, status) VALUES (?, ?, ?, 'active');",
					[cred_id, p.get("id"), pin])
				refresh_view()
	)

func _show_input_modal(title: String, placeholder: String, button_text: String, callback: Callable) -> void:
	var overlay = ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.6)
	overlay.anchors_preset = Control.PRESET_FULL_RECT
	overlay.grow_horizontal = Control.GROW_DIRECTION_BOTH
	overlay.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(overlay)
	
	var card = PanelContainer.new()
	card.custom_minimum_size = Vector2(400, 200)
	card.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	card.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	
	var card_st = StyleBoxFlat.new()
	card_st.bg_color = Color(0.14, 0.17, 0.23, 1.0)
	card_st.border_width_left = 2; card_st.border_width_top = 2; card_st.border_width_right = 2; card_st.border_width_bottom = 2
	card_st.border_color = Color(0.32, 0.42, 0.58, 1.0)
	card_st.corner_radius_top_left = 12; card_st.corner_radius_top_right = 12; card_st.corner_radius_bottom_left = 12; card_st.corner_radius_bottom_right = 12
	card_st.content_margin_left = 24; card_st.content_margin_top = 24; card_st.content_margin_right = 24; card_st.content_margin_bottom = 24
	card.add_theme_stylebox_override("panel", card_st)
	
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 18)
	
	var lbl_title = Label.new()
	lbl_title.text = title
	lbl_title.add_theme_font_size_override("font_size", 18)
	lbl_title.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 1.0))
	vbox.add_child(lbl_title)
	
	var edit = LineEdit.new()
	edit.placeholder_text = placeholder
	edit.custom_minimum_size = Vector2(0, 44)
	edit.add_theme_font_size_override("font_size", 16)
	var edit_st = StyleBoxFlat.new()
	edit_st.bg_color = Color(0.06, 0.08, 0.12, 1.0)
	edit_st.border_width_left = 1; edit_st.border_width_top = 1; edit_st.border_width_right = 1; edit_st.border_width_bottom = 1
	edit_st.border_color = Color(0.32, 0.42, 0.58, 1.0)
	edit_st.corner_radius_top_left = 6; edit_st.corner_radius_top_right = 6; edit_st.corner_radius_bottom_left = 6; edit_st.corner_radius_bottom_right = 6
	edit_st.content_margin_left = 10; edit_st.content_margin_right = 10
	edit.add_theme_stylebox_override("normal", edit_st)
	vbox.add_child(edit)
	
	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 12)
	
	var btn_cancel = Button.new()
	btn_cancel.text = "Cancel"
	btn_cancel.custom_minimum_size = Vector2(100, 38)
	btn_cancel.add_theme_font_size_override("font_size", 15)
	btn_cancel.pressed.connect(func():
		overlay.queue_free()
	)
	
	var btn_submit = Button.new()
	btn_submit.text = button_text
	btn_submit.custom_minimum_size = Vector2(140, 38)
	btn_submit.add_theme_font_size_override("font_size", 15)
	
	var active_color = _get_active_theme_color()
	var submit_st = StyleBoxFlat.new()
	submit_st.bg_color = active_color
	submit_st.corner_radius_top_left = 6; submit_st.corner_radius_top_right = 6; submit_st.corner_radius_bottom_left = 6; submit_st.corner_radius_bottom_right = 6
	btn_submit.add_theme_stylebox_override("normal", submit_st)
	btn_submit.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	
	btn_submit.pressed.connect(func():
		var val = edit.text.strip_edges()
		if val != "":
			callback.call(val)
			overlay.queue_free()
	)
	
	edit.text_submitted.connect(func(new_txt):
		var val = new_txt.strip_edges()
		if val != "":
			callback.call(val)
			overlay.queue_free()
	)
	
	hbox.add_child(btn_cancel)
	hbox.add_child(btn_submit)
	vbox.add_child(hbox)
	
	card.add_child(vbox)
	
	var center = CenterContainer.new()
	center.anchors_preset = Control.PRESET_FULL_RECT
	center.add_child(card)
	overlay.add_child(center)
	
	edit.grab_focus()

func _on_add_person_pressed() -> void:
	var dialog = Window.new()
	dialog.title = "➕ Add New Member"
	dialog.size = Vector2i(650, 720)
	dialog.exclusive = true
	dialog.transient = true
	dialog.close_requested.connect(func(): dialog.queue_free())
	dialog.tree_exited.connect(func():
		_active_photo_callback = Callable()
	)
	
	var panel = Panel.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	dialog.add_child(panel)

	var p_st = StyleBoxFlat.new()
	p_st.bg_color = Color(0.97, 0.98, 0.99, 1.0)
	panel.add_theme_stylebox_override("panel", p_st)

	var margin = MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_bottom", 24)
	panel.add_child(margin)

	var scroll = ScrollContainer.new()
	margin.add_child(scroll)

	var vbox = VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 16)
	scroll.add_child(vbox)

	var title_lbl = Label.new()
	title_lbl.text = "Add New Directory Member"
	title_lbl.add_theme_font_size_override("font_size", 20)
	title_lbl.add_theme_color_override("font_color", Color(0.12, 0.16, 0.24, 1.0))
	vbox.add_child(title_lbl)

	# Dynamic Theme Accent Bar
	var accent_bar = Panel.new()
	accent_bar.custom_minimum_size = Vector2(0, 4)
	var bar_st = StyleBoxFlat.new()
	bar_st.bg_color = _get_active_theme_color()
	bar_st.corner_radius_top_left = 2; bar_st.corner_radius_top_right = 2; bar_st.corner_radius_bottom_left = 2; bar_st.corner_radius_bottom_right = 2
	accent_bar.add_theme_stylebox_override("panel", bar_st)
	vbox.add_child(accent_bar)

	# --- 1. PROFILE PHOTO SECTION ---
	var photo_data_url = ""
	var photo_preview = TextureRect.new()
	var photo_placeholder_lbl = Label.new()

	_active_photo_callback = func(cropped_data_url: String):
		photo_data_url = cropped_data_url
		var tex = _create_texture_from_base64(cropped_data_url)
		if tex:
			photo_preview.texture = tex
			photo_preview.visible = true
			photo_placeholder_lbl.visible = false

	var photo_section_lbl = Label.new(); photo_section_lbl.text = "Profile Photo"; photo_section_lbl.add_theme_font_size_override("font_size", 15); photo_section_lbl.add_theme_color_override("font_color", _get_active_theme_color())
	vbox.add_child(photo_section_lbl)
	
	var photo_hbox = HBoxContainer.new()
	photo_hbox.add_theme_constant_override("separation", 16)
	vbox.add_child(photo_hbox)

	photo_preview.custom_minimum_size = Vector2(96, 96)
	photo_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	photo_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	photo_preview.visible = false
	photo_hbox.add_child(photo_preview)

	photo_placeholder_lbl.text = "📷\nNo Photo"
	photo_placeholder_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	photo_placeholder_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	photo_placeholder_lbl.custom_minimum_size = Vector2(96, 96)
	photo_placeholder_lbl.add_theme_font_size_override("font_size", 14)
	photo_placeholder_lbl.add_theme_color_override("font_color", Color(0.60, 0.65, 0.75, 1.0))
	photo_placeholder_lbl.mouse_filter = Control.MOUSE_FILTER_STOP
	photo_placeholder_lbl.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_open_native_camera_dialog(func(captured_img: Image):
				_open_image_editor(captured_img, _active_photo_callback)
			)
	)
	
	var ph_st = StyleBoxFlat.new()
	ph_st.bg_color = Color(0.88, 0.90, 0.94, 1.0)
	ph_st.border_width_left = 2; ph_st.border_width_top = 2; ph_st.border_width_right = 2; ph_st.border_width_bottom = 2
	ph_st.border_color = _get_active_theme_color()
	ph_st.corner_radius_top_left = 6; ph_st.corner_radius_top_right = 6; ph_st.corner_radius_bottom_left = 6; ph_st.corner_radius_bottom_right = 6
	photo_placeholder_lbl.add_theme_stylebox_override("normal", ph_st)
	photo_hbox.add_child(photo_placeholder_lbl)

	var photo_btns_vbox = VBoxContainer.new()
	photo_btns_vbox.add_theme_constant_override("separation", 8)
	photo_btns_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	photo_hbox.add_child(photo_btns_vbox)

	var photo_desc = Label.new(); photo_desc.text = "Add a profile picture or snapshot"; photo_desc.add_theme_font_size_override("font_size", 13); photo_desc.add_theme_color_override("font_color", Color(0.50, 0.55, 0.65, 1.0))
	photo_btns_vbox.add_child(photo_desc)

	var photo_btns_hbox = HBoxContainer.new()
	photo_btns_hbox.add_theme_constant_override("separation", 10)
	photo_btns_vbox.add_child(photo_btns_hbox)

	var btn_camera = Button.new()
	btn_camera.text = "📷 Take Photo"
	btn_camera.custom_minimum_size = Vector2(130, 36)
	btn_camera.add_theme_font_size_override("font_size", 13)
	btn_camera.pressed.connect(func():
		_open_native_camera_dialog(func(captured_img: Image):
			_open_image_editor(captured_img, _active_photo_callback)
		)
	)
	photo_btns_hbox.add_child(btn_camera)

	var btn_upload = Button.new()
	btn_upload.text = "📁 Upload File"
	btn_upload.custom_minimum_size = Vector2(130, 36)
	btn_upload.add_theme_font_size_override("font_size", 13)
	photo_btns_hbox.add_child(btn_upload)
	
	btn_upload.pressed.connect(func():
		var fd = FileDialog.new()
		fd.access = FileDialog.ACCESS_FILESYSTEM
		fd.file_mode = FileDialog.FILE_MODE_OPEN_FILE
		fd.filters = PackedStringArray(["*.png, *.jpg, *.jpeg ; Image Files"])
		fd.title = "Select Profile Photo / Face Shot Image"
		fd.size = Vector2i(700, 500)
		fd.file_selected.connect(func(path: String):
			var img = _load_image_from_file(path)
			if img and _active_photo_callback.is_valid():
				_open_image_editor(img, _active_photo_callback)
		)
		dialog.add_child(fd)
		fd.popup_centered()
	)

	var sep1 = HSeparator.new(); vbox.add_child(sep1)

	# --- 2. IDENTITY & CONTACT DETAILS SECTION ---
	var ident_lbl = Label.new(); ident_lbl.text = "Identity & Contact Details"; ident_lbl.add_theme_font_size_override("font_size", 16); ident_lbl.add_theme_color_override("font_color", _get_active_theme_color())
	vbox.add_child(ident_lbl)

	var grid_identity = GridContainer.new()
	grid_identity.columns = 2
	grid_identity.add_theme_constant_override("h_separation", 16)
	grid_identity.add_theme_constant_override("v_separation", 12)
	vbox.add_child(grid_identity)

	var fn_lbl = Label.new(); fn_lbl.text = "First Name (Required):"; fn_lbl.add_theme_color_override("font_color", Color(0.25, 0.30, 0.40, 1.0))
	var fn_input = LineEdit.new(); fn_input.custom_minimum_size = Vector2(250, 36)
	grid_identity.add_child(fn_lbl); grid_identity.add_child(fn_input)

	var ln_lbl = Label.new(); ln_lbl.text = "Last Name (Required):"; ln_lbl.add_theme_color_override("font_color", Color(0.25, 0.30, 0.40, 1.0))
	var ln_input = LineEdit.new(); ln_input.custom_minimum_size = Vector2(250, 36)
	grid_identity.add_child(ln_lbl); grid_identity.add_child(ln_input)

	var suf_lbl = Label.new(); suf_lbl.text = "Suffix (Jr, Sr, III):"; suf_lbl.add_theme_color_override("font_color", Color(0.25, 0.30, 0.40, 1.0))
	var suf_input = LineEdit.new(); suf_input.custom_minimum_size = Vector2(250, 36)
	grid_identity.add_child(suf_lbl); grid_identity.add_child(suf_input)

	var ph_lbl = Label.new(); ph_lbl.text = "Phone Number (Required):"; ph_lbl.add_theme_color_override("font_color", Color(0.25, 0.30, 0.40, 1.0))
	var ph_input = LineEdit.new(); ph_input.custom_minimum_size = Vector2(250, 36); ph_input.placeholder_text = "(555) 000-0000"
	ph_input.text_changed.connect(func(new_text): _on_phone_text_changed(new_text, ph_input))
	grid_identity.add_child(ph_lbl); grid_identity.add_child(ph_input)

	var email_desc = Label.new(); email_desc.text = "At least one email address is required:"; email_desc.add_theme_font_size_override("font_size", 13); email_desc.add_theme_color_override("font_color", Color(0.50, 0.55, 0.65, 1.0))
	grid_identity.add_child(Label.new()); grid_identity.add_child(email_desc)

	var em_lbl = Label.new(); em_lbl.text = "Primary Email:"; em_lbl.add_theme_color_override("font_color", Color(0.25, 0.30, 0.40, 1.0))
	var em_input = LineEdit.new(); em_input.custom_minimum_size = Vector2(250, 36); em_input.placeholder_text = "name@example.com"
	grid_identity.add_child(em_lbl); grid_identity.add_child(em_input)

	var se_lbl = Label.new(); se_lbl.text = "School Email:"; se_lbl.add_theme_color_override("font_color", Color(0.25, 0.30, 0.40, 1.0))
	var se_input = LineEdit.new(); se_input.custom_minimum_size = Vector2(250, 36); se_input.placeholder_text = "student@school.edu"
	grid_identity.add_child(se_lbl); grid_identity.add_child(se_input)

	var pe_lbl = Label.new(); pe_lbl.text = "Preferred Email (Required):"; pe_lbl.add_theme_color_override("font_color", Color(0.25, 0.30, 0.40, 1.0))
	var pe_dropdown = OptionButton.new()
	pe_dropdown.add_item("Main", 0); pe_dropdown.add_item("School", 1)
	pe_dropdown.custom_minimum_size = Vector2(250, 36)
	grid_identity.add_child(pe_lbl); grid_identity.add_child(pe_dropdown)

	var bd_lbl = Label.new(); bd_lbl.text = "Birthday (MM/DD/YYYY) (Required):"; bd_lbl.add_theme_color_override("font_color", Color(0.25, 0.30, 0.40, 1.0))
	var bd_hbox = HBoxContainer.new(); bd_hbox.custom_minimum_size = Vector2(250, 36)
	var bd_input = LineEdit.new(); bd_input.custom_minimum_size = Vector2(200, 36); bd_input.placeholder_text = "MM/DD/YYYY"; bd_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var bd_cal_btn = Button.new(); bd_cal_btn.text = "📅"; bd_cal_btn.custom_minimum_size = Vector2(36, 36)
	bd_cal_btn.pressed.connect(func(): _open_calendar_picker(bd_input))
	bd_hbox.add_child(bd_input); bd_hbox.add_child(bd_cal_btn)
	grid_identity.add_child(bd_lbl); grid_identity.add_child(bd_hbox)

	var sep2 = HSeparator.new(); vbox.add_child(sep2)

	# --- 3. ROLE, STATUS, & YEAR LEVEL ---
	var role_section_lbl = Label.new(); role_section_lbl.text = "Classification & Status"; role_section_lbl.add_theme_font_size_override("font_size", 16); role_section_lbl.add_theme_color_override("font_color", _get_active_theme_color())
	vbox.add_child(role_section_lbl)

	var grid_roles = GridContainer.new()
	grid_roles.columns = 2
	grid_roles.add_theme_constant_override("h_separation", 16)
	grid_roles.add_theme_constant_override("v_separation", 12)
	vbox.add_child(grid_roles)

	var role_lbl = Label.new(); role_lbl.text = "Primary Role (Required):"; role_lbl.add_theme_color_override("font_color", Color(0.25, 0.30, 0.40, 1.0))
	var role_input = OptionButton.new()
	role_input.add_item("Participant")
	role_input.add_item("Staff")
	role_input.add_item("Volunteer")
	role_input.add_item("Intern")
	role_input.custom_minimum_size = Vector2(250, 36)
	grid_roles.add_child(role_lbl); grid_roles.add_child(role_input)

	var flag_lbl = Label.new(); flag_lbl.text = "Registration Status (Required):"; flag_lbl.add_theme_color_override("font_color", Color(0.25, 0.30, 0.40, 1.0))
	var flag_input = OptionButton.new()
	flag_input.add_item("Clear")
	flag_input.add_item("To Be Confirmed")
	flag_input.add_item("Suspended")
	flag_input.custom_minimum_size = Vector2(250, 36)
	grid_roles.add_child(flag_lbl); grid_roles.add_child(flag_input)

	var gr_lbl = Label.new(); gr_lbl.text = _get_vocab_grade_label() + " Level (Required):"; gr_lbl.add_theme_color_override("font_color", Color(0.25, 0.30, 0.40, 1.0))
	var gr_input = OptionButton.new()
	gr_input.add_item("None")
	gr_input.add_item("Freshman")
	gr_input.add_item("Sophomore")
	gr_input.add_item("Junior")
	gr_input.add_item("Senior")
	gr_input.add_item("Grad Student")
	gr_input.add_item("Other")
	gr_input.custom_minimum_size = Vector2(250, 36)
	grid_roles.add_child(gr_lbl); grid_roles.add_child(gr_input)

	var sep3 = HSeparator.new(); vbox.add_child(sep3)

	# --- 4. HOME & SCHOOL ADDRESSES SECTION ---
	var addr_lbl = Label.new(); addr_lbl.text = "Home Address"; addr_lbl.add_theme_font_size_override("font_size", 16); addr_lbl.add_theme_color_override("font_color", _get_active_theme_color())
	vbox.add_child(addr_lbl)

	var grid_home = GridContainer.new()
	grid_home.columns = 2
	grid_home.add_theme_constant_override("h_separation", 16)
	grid_home.add_theme_constant_override("v_separation", 12)
	vbox.add_child(grid_home)

	var h_st_lbl = Label.new(); h_st_lbl.text = "Street Address:"; h_st_lbl.add_theme_color_override("font_color", Color(0.25, 0.30, 0.40, 1.0))
	var h_st_input = LineEdit.new(); h_st_input.custom_minimum_size = Vector2(250, 36)
	grid_home.add_child(h_st_lbl); grid_home.add_child(h_st_input)

	var h_l2_lbl = Label.new(); h_l2_lbl.text = "Apt / Suite / Unit:"; h_l2_lbl.add_theme_color_override("font_color", Color(0.25, 0.30, 0.40, 1.0))
	var h_l2_input = LineEdit.new(); h_l2_input.custom_minimum_size = Vector2(250, 36)
	grid_home.add_child(h_l2_lbl); grid_home.add_child(h_l2_input)

	var h_ct_lbl = Label.new(); h_ct_lbl.text = "City:"; h_ct_lbl.add_theme_color_override("font_color", Color(0.25, 0.30, 0.40, 1.0))
	var h_ct_input = LineEdit.new(); h_ct_input.custom_minimum_size = Vector2(250, 36)
	grid_home.add_child(h_ct_lbl); grid_home.add_child(h_ct_input)

	var h_state_lbl = Label.new(); h_state_lbl.text = "State (e.g. TN):"; h_state_lbl.add_theme_color_override("font_color", Color(0.25, 0.30, 0.40, 1.0))
	var h_state_input = LineEdit.new(); h_state_input.custom_minimum_size = Vector2(250, 36)
	grid_home.add_child(h_state_lbl); grid_home.add_child(h_state_input)

	var h_zip_lbl = Label.new(); h_zip_lbl.text = "ZIP Code:"; h_zip_lbl.add_theme_color_override("font_color", Color(0.25, 0.30, 0.40, 1.0))
	var h_zip_input = LineEdit.new(); h_zip_input.custom_minimum_size = Vector2(250, 36)
	grid_home.add_child(h_zip_lbl); grid_home.add_child(h_zip_input)

	var sep4 = HSeparator.new(); vbox.add_child(sep4)

	var s_addr_lbl = Label.new(); s_addr_lbl.text = "School / Campus Address"; s_addr_lbl.add_theme_font_size_override("font_size", 16); s_addr_lbl.add_theme_color_override("font_color", _get_active_theme_color())
	vbox.add_child(s_addr_lbl)

	var grid_school = GridContainer.new()
	grid_school.columns = 2
	grid_school.add_theme_constant_override("h_separation", 16)
	grid_school.add_theme_constant_override("v_separation", 12)
	vbox.add_child(grid_school)

	var s_st_lbl = Label.new(); s_st_lbl.text = "Campus Street Address:"; s_st_lbl.add_theme_color_override("font_color", Color(0.25, 0.30, 0.40, 1.0))
	var s_st_input = LineEdit.new(); s_st_input.custom_minimum_size = Vector2(250, 36)
	grid_school.add_child(s_st_lbl); grid_school.add_child(s_st_input)

	var s_l2_lbl = Label.new(); s_l2_lbl.text = "Dorm / Room / Box #:"; s_l2_lbl.add_theme_color_override("font_color", Color(0.25, 0.30, 0.40, 1.0))
	var s_l2_input = LineEdit.new(); s_l2_input.custom_minimum_size = Vector2(250, 36)
	grid_school.add_child(s_l2_lbl); grid_school.add_child(s_l2_input)

	var s_ct_lbl = Label.new(); s_ct_lbl.text = "City:"; s_ct_lbl.add_theme_color_override("font_color", Color(0.25, 0.30, 0.40, 1.0))
	var s_ct_input = LineEdit.new(); s_ct_input.custom_minimum_size = Vector2(250, 36)
	grid_school.add_child(s_ct_lbl); grid_school.add_child(s_ct_input)

	var s_state_lbl = Label.new(); s_state_lbl.text = "State:"; s_state_lbl.add_theme_color_override("font_color", Color(0.25, 0.30, 0.40, 1.0))
	var s_state_input = LineEdit.new(); s_state_input.custom_minimum_size = Vector2(250, 36)
	grid_school.add_child(s_state_lbl); grid_school.add_child(s_state_input)

	var s_zip_lbl = Label.new(); s_zip_lbl.text = "ZIP Code:"; s_zip_lbl.add_theme_color_override("font_color", Color(0.25, 0.30, 0.40, 1.0))
	var s_zip_input = LineEdit.new(); s_zip_input.custom_minimum_size = Vector2(250, 36)
	grid_school.add_child(s_zip_lbl); grid_school.add_child(s_zip_input)

	var sep5 = HSeparator.new(); vbox.add_child(sep5)

	# --- 5. EMERGENCY CONTACT & MEDICAL ---
	var em_title_lbl = Label.new(); em_title_lbl.text = "Emergency Contact & Medical Details"; em_title_lbl.add_theme_font_size_override("font_size", 16); em_title_lbl.add_theme_color_override("font_color", _get_active_theme_color())
	vbox.add_child(em_title_lbl)

	var grid_em = GridContainer.new()
	grid_em.columns = 2
	grid_em.add_theme_constant_override("h_separation", 16)
	grid_em.add_theme_constant_override("v_separation", 12)
	vbox.add_child(grid_em)

	var em_name_lbl = Label.new(); em_name_lbl.text = "Contact Name (Required):"; em_name_lbl.add_theme_color_override("font_color", Color(0.25, 0.30, 0.40, 1.0))
	var em_name_input = LineEdit.new(); em_name_input.custom_minimum_size = Vector2(250, 36)
	grid_em.add_child(em_name_lbl); grid_em.add_child(em_name_input)

	var em_phone_lbl = Label.new(); em_phone_lbl.text = "Contact Phone (Required):"; em_phone_lbl.add_theme_color_override("font_color", Color(0.25, 0.30, 0.40, 1.0))
	var em_phone_input = LineEdit.new(); em_phone_input.custom_minimum_size = Vector2(250, 36); em_phone_input.placeholder_text = "(555) 000-0000"
	em_phone_input.text_changed.connect(func(new_text): _on_phone_text_changed(new_text, em_phone_input))
	grid_em.add_child(em_phone_lbl); grid_em.add_child(em_phone_input)

	var med_lbl = Label.new(); med_lbl.text = "Medical Notes:"; med_lbl.add_theme_color_override("font_color", Color(0.25, 0.30, 0.40, 1.0))
	var med_input = TextEdit.new(); med_input.custom_minimum_size = Vector2(250, 70)
	grid_em.add_child(med_lbl); grid_em.add_child(med_input)

	var note_lbl = Label.new(); note_lbl.text = "Initial Notes:"; note_lbl.add_theme_color_override("font_color", Color(0.25, 0.30, 0.40, 1.0))
	var note_input = TextEdit.new(); note_input.custom_minimum_size = Vector2(250, 70)
	grid_em.add_child(note_lbl); grid_em.add_child(note_input)

	var err_lbl = Label.new()
	err_lbl.add_theme_color_override("font_color", Color(0.9, 0.2, 0.2, 1.0))
	err_lbl.visible = false
	vbox.add_child(err_lbl)

	# Action Buttons
	var hbox_btns = HBoxContainer.new()
	hbox_btns.add_theme_constant_override("separation", 16)
	hbox_btns.alignment = HBoxContainer.ALIGNMENT_END
	vbox.add_child(hbox_btns)

	var cancel_btn = Button.new()
	cancel_btn.text = "Cancel"
	hbox_btns.add_child(cancel_btn)

	var submit_btn = Button.new()
	submit_btn.text = "Create Member"
	hbox_btns.add_child(submit_btn)

	var cancel_st = StyleBoxFlat.new()
	cancel_st.bg_color = Color(0.85, 0.88, 0.92, 1.0)
	cancel_st.corner_radius_top_left = 6; cancel_st.corner_radius_top_right = 6; cancel_st.corner_radius_bottom_left = 6; cancel_st.corner_radius_bottom_right = 6
	cancel_st.content_margin_left = 16; cancel_st.content_margin_top = 8; cancel_st.content_margin_right = 16; cancel_st.content_margin_bottom = 8
	cancel_btn.add_theme_stylebox_override("normal", cancel_st)
	cancel_btn.add_theme_color_override("font_color", Color(0.12, 0.16, 0.24, 1.0))
	cancel_btn.add_theme_color_override("font_hover_color", Color(0.12, 0.16, 0.24, 1.0))
	cancel_btn.add_theme_color_override("font_pressed_color", Color(0.12, 0.16, 0.24, 1.0))

	var submit_st = StyleBoxFlat.new()
	submit_st.bg_color = _get_active_theme_color()
	submit_st.corner_radius_top_left = 6; submit_st.corner_radius_top_right = 6; submit_st.corner_radius_bottom_left = 6; submit_st.corner_radius_bottom_right = 6
	submit_st.content_margin_left = 16; submit_st.content_margin_top = 8; submit_st.content_margin_right = 16; submit_st.content_margin_bottom = 8
	submit_btn.add_theme_stylebox_override("normal", submit_st)
	submit_btn.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 1.0))

	cancel_btn.pressed.connect(func():
		dialog.queue_free()
	)

	submit_btn.pressed.connect(func():
		var fn = fn_input.text.strip_edges()
		var ln = ln_input.text.strip_edges()
		var phone_val = ph_input.text.strip_edges()
		var email_val = em_input.text.strip_edges()
		var school_email_val = se_input.text.strip_edges()
		
		var home_st = h_st_input.text.strip_edges()
		var home_ct = h_ct_input.text.strip_edges()
		var home_state = h_state_input.text.strip_edges()
		var home_zip = h_zip_input.text.strip_edges()

		var school_st = s_st_input.text.strip_edges()
		var school_ct = s_ct_input.text.strip_edges()
		var school_state = s_state_input.text.strip_edges()
		var school_zip = s_zip_input.text.strip_edges()

		var em_name = em_name_input.text.strip_edges()
		var em_phone = em_phone_input.text.strip_edges()
		var bday_val = bd_input.text.strip_edges()

		if fn == "" or ln == "":
			err_lbl.text = "⚠️ First Name and Last Name are required."
			err_lbl.visible = true
			return

		if phone_val == "":
			err_lbl.text = "⚠️ Phone Number is required."
			err_lbl.visible = true
			return

		if bday_val == "":
			err_lbl.text = "⚠️ Birthday is required."
			err_lbl.visible = true
			return

		var parts = bday_val.split("/")
		if parts.size() != 3 or parts[0].length() != 2 or parts[1].length() != 2 or parts[2].length() != 4 or not parts[0].is_valid_int() or not parts[1].is_valid_int() or not parts[2].is_valid_int():
			err_lbl.text = "⚠️ Birthday must be in MM/DD/YYYY format (e.g., 05/15/2002)."
			err_lbl.visible = true
			return

		if email_val == "" and school_email_val == "":
			err_lbl.text = "⚠️ At least one Email Address (Primary or School) is required."
			err_lbl.visible = true
			return



		if em_name == "" or em_phone == "":
			err_lbl.text = "⚠️ Emergency Contact Name and Phone are required."
			err_lbl.visible = true
			return

		var PersonServiceScript = load("res://src/domain/directory/person_service.gd")
		var person_service = PersonServiceScript.new(db)

		var grade_val = gr_input.get_item_text(gr_input.selected)
		if grade_val == "None":
			grade_val = ""

		var role_sel_txt = role_input.get_item_text(role_input.selected)
		var role_db_val = "Participant"
		if role_sel_txt == "Staff":
			role_db_val = "staff"
		elif role_sel_txt == "Volunteer":
			role_db_val = "volunteer"
		elif role_sel_txt == "Intern":
			role_db_val = "intern"
			
		var flag_val = flag_input.get_item_text(flag_input.selected)

		var payload = {
			"first_name": fn,
			"last_name": ln,
			"phone": phone_val,
			"grade": grade_val,
			"notes": note_input.text.strip_edges(),
			"status": "active"
		}

		var create_res = person_service.create_person(payload)
		if not create_res["success"]:
			err_lbl.text = "Error: " + str(create_res.get("error", "Database insert failed."))
			err_lbl.visible = true
			return

		var p_uuid = create_res.get("person_uuid", "")
		var pref_email = "School" if pe_dropdown.selected == 1 else "Main"

		var update_stmt = {
			"sql": "UPDATE people SET suffix = ?, email = ?, school_email = ?, preferred_email = ?, birthday = ?, home_address_street = ?, home_address_line2 = ?, home_address_city = ?, home_address_state = ?, home_address_zip = ?, school_address_street = ?, school_address_line2 = ?, school_address_city = ?, school_address_state = ?, school_address_zip = ?, primary_role = ?, flag_status = ?, emergency_contact_name = ?, emergency_contact_phone = ?, medical_notes = ?, profile_photo = ? WHERE person_uuid = ?;",
			"args": [
				suf_input.text.strip_edges(), 
				email_val, 
				school_email_val, 
				pref_email, 
				_ui_to_db_date(bd_input.text.strip_edges()),
				home_st, 
				h_l2_input.text.strip_edges(), 
				home_ct, 
				home_state, 
				home_zip,
				school_st, 
				s_l2_input.text.strip_edges(), 
				school_ct, 
				school_state, 
				school_zip,
				role_db_val, 
				flag_val, 
				em_name, 
				em_phone, 
				med_input.text.strip_edges(), 
				photo_data_url, 
				p_uuid
			]
		}
		db.execute_transaction([update_stmt])

		var ev_uuid = create_res.get("event_uuid", "")
		if ev_uuid != "":
			var outbox_res = db.execute("SELECT payload_json FROM event_outbox WHERE event_uuid = ? LIMIT 1;", [ev_uuid])
			if outbox_res["success"] and outbox_res["data"].size() > 0:
				var payload_json = outbox_res["data"][0].get("payload_json", "")
				var payload_dict = JSON.parse_string(payload_json)
				if typeof(payload_dict) == TYPE_DICTIONARY:
					payload_dict["suffix"] = suf_input.text.strip_edges()
					payload_dict["email"] = email_val
					payload_dict["school_email"] = school_email_val
					payload_dict["preferred_email"] = pref_email
					payload_dict["birthday"] = _ui_to_db_date(bd_input.text.strip_edges())
					payload_dict["home_address_street"] = home_st
					payload_dict["home_address_line2"] = h_l2_input.text.strip_edges()
					payload_dict["home_address_city"] = home_ct
					payload_dict["home_address_state"] = home_state
					payload_dict["home_address_zip"] = home_zip
					payload_dict["school_address_street"] = school_st
					payload_dict["school_address_line2"] = s_l2_input.text.strip_edges()
					payload_dict["school_address_city"] = school_ct
					payload_dict["school_address_state"] = school_state
					payload_dict["school_address_zip"] = school_zip
					payload_dict["primary_role"] = role_db_val
					payload_dict["flag_status"] = flag_val
					payload_dict["emergency_contact_name"] = em_name
					payload_dict["emergency_contact_phone"] = em_phone
					payload_dict["medical_notes"] = med_input.text.strip_edges()
					payload_dict["profile_photo"] = photo_data_url
					
					db.execute("UPDATE event_outbox SET payload_json = ? WHERE event_uuid = ?;", [JSON.stringify(payload_dict), ev_uuid])

		dialog.queue_free()
		refresh_view()
	)

	add_child(dialog)
	dialog.popup_centered()

func _get_vocab_grade_label() -> String:
	var label = "Grade"
	if db:
		var res = db.execute("SELECT setting_value FROM app_settings WHERE setting_key = 'VOCAB_GRADE' LIMIT 1;")
		if res["success"] and res["data"].size() > 0:
			label = str(res["data"][0].get("setting_value", "Grade")).strip_edges()
	return label

func _db_to_ui_date(db_date: String) -> String:
	var s = db_date.strip_edges()
	if s == "": return ""
	var parts = s.split("-")
	if parts.size() == 3 and parts[0].length() == 4:
		return parts[1] + "/" + parts[2] + "/" + parts[0]
	return s

func _ui_to_db_date(ui_date: String) -> String:
	var s = ui_date.strip_edges()
	if s == "": return ""
	var parts = s.split("/")
	if parts.size() == 3:
		var m = parts[0].lpad(2, "0")
		var d = parts[1].lpad(2, "0")
		var y = parts[2]
		if y.length() == 2:
			y = "20" + y
		return y + "-" + m + "-" + d
	return s

func _format_phone_string(raw_string: String) -> String:
	var digits = ""
	for c in raw_string:
		if c >= '0' and c <= '9':
			digits += c
	
	var formatted = ""
	if digits.length() > 0:
		formatted += "(" + digits.left(3)
	if digits.length() > 3:
		formatted += ") " + digits.substr(3, 3)
	if digits.length() > 6:
		formatted += "-" + digits.substr(6, 4)
	return formatted if formatted != "" else raw_string

func _on_phone_text_changed(new_text: String, line_edit: LineEdit) -> void:
	var formatted = _format_phone_string(new_text)
	if line_edit.text != formatted:
		line_edit.text = formatted
		line_edit.caret_column = formatted.length()

func _open_calendar_picker(target_line_edit: LineEdit) -> void:
	var cal_dialog = Window.new()
	cal_dialog.title = "📅 Select Date"
	cal_dialog.size = Vector2i(320, 360)
	cal_dialog.transient = true
	cal_dialog.exclusive = true
	cal_dialog.close_requested.connect(func(): cal_dialog.queue_free())

	var panel = Panel.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	cal_dialog.add_child(panel)
	
	var p_st = StyleBoxFlat.new()
	p_st.bg_color = Color(0.97, 0.98, 0.99, 1.0)
	panel.add_theme_stylebox_override("panel", p_st)

	var main_vbox = VBoxContainer.new()
	main_vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	main_vbox.add_theme_constant_override("separation", 10)

	var margin = MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	panel.add_child(margin)
	margin.add_child(main_vbox)

	var header_hbox = HBoxContainer.new()
	header_hbox.alignment = HBoxContainer.ALIGNMENT_CENTER
	main_vbox.add_child(header_hbox)

	var btn_prev = Button.new(); btn_prev.text = " < "; header_hbox.add_child(btn_prev)
	var month_lbl = Label.new(); month_lbl.add_theme_font_size_override("font_size", 16); month_lbl.add_theme_color_override("font_color", Color(0.1, 0.15, 0.25, 1.0)); header_hbox.add_child(month_lbl)
	var btn_next = Button.new(); btn_next.text = " > "; header_hbox.add_child(btn_next)

	var grid_weekdays = GridContainer.new()
	grid_weekdays.columns = 7
	grid_weekdays.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main_vbox.add_child(grid_weekdays)
	
	var weekdays = ["S", "M", "T", "W", "T", "F", "S"]
	for day in weekdays:
		var lbl = Label.new()
		lbl.text = day
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lbl.add_theme_font_size_override("font_size", 12)
		lbl.add_theme_color_override("font_color", Color(0.4, 0.45, 0.55, 1.0))
		grid_weekdays.add_child(lbl)

	var grid_days = GridContainer.new()
	grid_days.columns = 7
	grid_days.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid_days.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_vbox.add_child(grid_days)

	var current_year = 2002
	var current_month = 1
	
	var existing_txt = target_line_edit.text.strip_edges()
	var ep = existing_txt.split("/")
	if ep.size() == 3 and ep[0].is_valid_int() and ep[1].is_valid_int() and ep[2].is_valid_int():
		current_month = clampi(int(ep[0]), 1, 12)
		current_year = int(ep[2])
	else:
		var datetime = Time.get_datetime_dict_from_system()
		current_year = datetime.get("year", 2002) - 18
		current_month = datetime.get("month", 1)

	var month_names = [
		"", "January", "February", "March", "April", "May", "June", 
		"July", "August", "September", "October", "November", "December"
	]

	var render_calendar = Callable()
	render_calendar = func():
		for child in grid_days.get_children():
			child.queue_free()
		
		month_lbl.text = " " + month_names[current_month] + " " + str(current_year) + " "
		
		var start_time_dict = {"year": current_year, "month": current_month, "day": 1, "hour": 12, "minute": 0, "second": 0}
		var start_unix = Time.get_unix_time_from_datetime_dict(start_time_dict)
		var start_time_full = Time.get_datetime_dict_from_unix_time(start_unix)
		var start_weekday = start_time_full.get("weekday", 0)
		
		var days_in_month = 31
		if current_month in [4, 6, 9, 11]:
			days_in_month = 30
		elif current_month == 2:
			var is_leap = (current_year % 4 == 0 and current_year % 100 != 0) or (current_year % 400 == 0)
			days_in_month = 29 if is_leap else 28
			
		for i in range(start_weekday):
			var blank = Control.new()
			grid_days.add_child(blank)
			
		for day in range(1, days_in_month + 1):
			var btn = Button.new()
			btn.text = str(day)
			btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			btn.size_flags_vertical = Control.SIZE_EXPAND_FILL
			btn.add_theme_font_size_override("font_size", 12)
			
			var day_val = day
			var m_val = current_month
			var y_val = current_year
			
			btn.pressed.connect(func():
				var formatted_m = str(m_val).lpad(2, "0")
				var formatted_d = str(day_val).lpad(2, "0")
				target_line_edit.text = formatted_m + "/" + formatted_d + "/" + str(y_val)
				cal_dialog.queue_free()
			)
			grid_days.add_child(btn)

	btn_prev.pressed.connect(func():
		current_month -= 1
		if current_month < 1:
			current_month = 12
			current_year -= 1
		render_calendar.call()
	)

	btn_next.pressed.connect(func():
		current_month += 1
		if current_month > 12:
			current_month = 1
			current_year += 1
		render_calendar.call()
	)

	render_calendar.call()
	add_child(cal_dialog)
	cal_dialog.popup_centered()

func _open_image_editor(source_img: Image, on_save_callback: Callable) -> void:
	var edit_dialog = Window.new()
	edit_dialog.title = "🎨 Crop & Rotate Photo"
	edit_dialog.size = Vector2i(500, 560)
	edit_dialog.transient = true
	edit_dialog.exclusive = false
	edit_dialog.close_requested.connect(func(): edit_dialog.queue_free())

	var panel = Panel.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	edit_dialog.add_child(panel)
	
	var p_st = StyleBoxFlat.new()
	p_st.bg_color = Color(0.95, 0.96, 0.98, 1.0)
	panel.add_theme_stylebox_override("panel", p_st)

	var main_vbox = VBoxContainer.new()
	main_vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	main_vbox.add_theme_constant_override("separation", 14)
	
	var margin = MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_bottom", 16)
	panel.add_child(margin)
	margin.add_child(main_vbox)

	var preview_panel = PanelContainer.new()
	preview_panel.custom_minimum_size = Vector2(300, 300)
	preview_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	
	var prev_st = StyleBoxFlat.new()
	prev_st.bg_color = Color(0.08, 0.12, 0.18, 1.0)
	prev_st.border_width_left = 2; prev_st.border_width_top = 2; prev_st.border_width_right = 2; prev_st.border_width_bottom = 2
	prev_st.border_color = _get_active_theme_color()
	prev_st.corner_radius_top_left = 8; prev_st.corner_radius_top_right = 8; prev_st.corner_radius_bottom_left = 8; prev_st.corner_radius_bottom_right = 8
	preview_panel.add_theme_stylebox_override("panel", prev_st)
	preview_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	main_vbox.add_child(preview_panel)

	var control_node = Control.new()
	control_node.clip_contents = true
	control_node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	control_node.custom_minimum_size = Vector2(296, 296)
	preview_panel.add_child(control_node)

	var img_rect = TextureRect.new()
	img_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	img_rect.stretch_mode = TextureRect.STRETCH_SCALE
	img_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	control_node.add_child(img_rect)

	var crop_overlay = ReferenceRect.new()
	crop_overlay.border_color = Color(1.0, 0.84, 0.0, 0.9)
	crop_overlay.border_width = 3.0
	crop_overlay.custom_minimum_size = Vector2(200, 200)
	crop_overlay.editor_only = false
	crop_overlay.position = Vector2(48, 48)
	crop_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	control_node.add_child(crop_overlay)

	var crop_label = Label.new()
	crop_label.text = "Crop Target Area"
	crop_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	crop_label.position = Vector2(48, 20)
	crop_label.custom_minimum_size = Vector2(200, 20)
	crop_label.add_theme_font_size_override("font_size", 11)
	crop_label.add_theme_color_override("font_color", Color(1.0, 0.84, 0.0, 0.9))
	crop_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	control_node.add_child(crop_label)

	var input_overlay = Control.new()
	input_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	input_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	control_node.add_child(input_overlay)

	var current_image = Image.new()
	current_image.copy_from(source_img)

	var state = {
		"zoom": 1.0,
		"offset_x": 0.0,
		"offset_y": 0.0,
		"rotation_clicks": 0
	}

	var update_preview = Callable()
	update_preview = func():
		var temp_img = Image.new()
		temp_img.copy_from(current_image)
		
		for r in range(state["rotation_clicks"]):
			temp_img.rotate_90(0)
			
		var base_w = temp_img.get_width()
		var base_h = temp_img.get_height()
		
		var fit_scale = minf(296.0 / base_w, 296.0 / base_h)
		var display_scale = fit_scale * state["zoom"]
		
		var display_w = maxf(10, base_w * display_scale)
		var display_h = maxf(10, base_h * display_scale)
		
		img_rect.size = Vector2(display_w, display_h)
		var centered_pos = Vector2(148 - display_w/2, 148 - display_h/2)
		img_rect.position = centered_pos + Vector2(state["offset_x"], state["offset_y"])
		
		img_rect.texture = ImageTexture.create_from_image(temp_img)

	var zoom_hbox = HBoxContainer.new()
	zoom_hbox.alignment = HBoxContainer.ALIGNMENT_CENTER
	main_vbox.add_child(zoom_hbox)
	
	var zoom_lbl = Label.new(); zoom_lbl.text = "🔍 Zoom:"; zoom_lbl.add_theme_color_override("font_color", Color(0.2, 0.25, 0.35, 1.0)); zoom_hbox.add_child(zoom_lbl)
	var zoom_slider = HSlider.new()
	zoom_slider.min_value = 0.5
	zoom_slider.max_value = 3.0
	zoom_slider.step = 0.1
	zoom_slider.value = 1.0
	zoom_slider.custom_minimum_size = Vector2(250, 24)
	zoom_slider.value_changed.connect(func(val):
		state["zoom"] = val
		update_preview.call()
	)
	zoom_hbox.add_child(zoom_slider)

	var dragging = false
	var drag_start = Vector2.ZERO
	var offset_start = Vector2.ZERO

	input_overlay.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton:
			if event.button_index == MOUSE_BUTTON_LEFT:
				if event.pressed:
					dragging = true
					drag_start = event.position
					offset_start = Vector2(state["offset_x"], state["offset_y"])
				else:
					dragging = false
			elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
				if event.pressed:
					zoom_slider.value += 0.05
			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				if event.pressed:
					zoom_slider.value -= 0.05
		elif event is InputEventMouseMotion:
			if dragging:
				var delta = event.position - drag_start
				state["offset_x"] = offset_start.x + delta.x
				state["offset_y"] = offset_start.y + delta.y
				update_preview.call()
	)

	var drag_lbl = Label.new()
	drag_lbl.text = "💡 Scroll to zoom | Drag image to pan & align"
	drag_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	drag_lbl.add_theme_font_size_override("font_size", 11)
	drag_lbl.add_theme_color_override("font_color", Color(0.3, 0.35, 0.45, 1.0))
	main_vbox.add_child(drag_lbl)

	var pan_hbox = HBoxContainer.new()
	pan_hbox.alignment = HBoxContainer.ALIGNMENT_CENTER
	main_vbox.add_child(pan_hbox)

	var btn_l = Button.new(); btn_l.text = "◀ Left"; pan_hbox.add_child(btn_l)
	var btn_u = Button.new(); btn_u.text = "▲ Up"; pan_hbox.add_child(btn_u)
	var btn_d = Button.new(); btn_d.text = "▼ Down"; pan_hbox.add_child(btn_d)
	var btn_r = Button.new(); btn_r.text = "▶ Right"; pan_hbox.add_child(btn_r)
	
	btn_l.pressed.connect(func(): state["offset_x"] -= 10; update_preview.call())
	btn_u.pressed.connect(func(): state["offset_y"] -= 10; update_preview.call())
	btn_d.pressed.connect(func(): state["offset_y"] += 10; update_preview.call())
	btn_r.pressed.connect(func(): state["offset_x"] += 10; update_preview.call())

	var act_hbox = HBoxContainer.new()
	act_hbox.alignment = HBoxContainer.ALIGNMENT_CENTER
	act_hbox.add_theme_constant_override("separation", 16)
	main_vbox.add_child(act_hbox)

	var btn_rot = Button.new()
	btn_rot.text = "🔄 Rotate 90°"
	btn_rot.custom_minimum_size = Vector2(120, 36)
	act_hbox.add_child(btn_rot)
	btn_rot.pressed.connect(func():
		state["rotation_clicks"] = (state["rotation_clicks"] + 1) % 4
		update_preview.call()
	)

	var btn_reset = Button.new()
	btn_reset.text = "Reset View"
	btn_reset.custom_minimum_size = Vector2(100, 36)
	act_hbox.add_child(btn_reset)
	btn_reset.pressed.connect(func():
		state["zoom"] = 1.0
		zoom_slider.value = 1.0
		state["offset_x"] = 0.0
		state["offset_y"] = 0.0
		state["rotation_clicks"] = 0
		update_preview.call()
	)

	var separator = HSeparator.new(); main_vbox.add_child(separator)
	var action_hbox = HBoxContainer.new()
	action_hbox.alignment = HBoxContainer.ALIGNMENT_END
	action_hbox.add_theme_constant_override("separation", 16)
	main_vbox.add_child(action_hbox)

	var cancel_btn = Button.new(); cancel_btn.text = "Cancel"; action_hbox.add_child(cancel_btn)
	cancel_btn.add_theme_color_override("font_color", Color(0.12, 0.16, 0.24, 1.0))
	cancel_btn.add_theme_color_override("font_hover_color", Color(0.12, 0.16, 0.24, 1.0))
	cancel_btn.add_theme_color_override("font_pressed_color", Color(0.12, 0.16, 0.24, 1.0))
	var save_btn = Button.new(); save_btn.text = "💾 Crop & Use Photo"; action_hbox.add_child(save_btn)

	var cancel_st = StyleBoxFlat.new()
	cancel_st.bg_color = Color(0.85, 0.88, 0.92, 1.0)
	cancel_st.corner_radius_top_left = 6; cancel_st.corner_radius_top_right = 6; cancel_st.corner_radius_bottom_left = 6; cancel_st.corner_radius_bottom_right = 6
	cancel_st.content_margin_left = 16; cancel_st.content_margin_top = 8; cancel_st.content_margin_right = 16; cancel_st.content_margin_bottom = 8
	cancel_btn.add_theme_stylebox_override("normal", cancel_st)

	var save_st = StyleBoxFlat.new()
	save_st.bg_color = _get_active_theme_color()
	save_st.corner_radius_top_left = 6; save_st.corner_radius_top_right = 6; save_st.corner_radius_bottom_left = 6; save_st.corner_radius_bottom_right = 6
	save_st.content_margin_left = 16; save_st.content_margin_top = 8; save_st.content_margin_right = 16; save_st.content_margin_bottom = 8
	save_btn.add_theme_stylebox_override("normal", save_st)
	save_btn.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 1.0))

	cancel_btn.pressed.connect(func():
		edit_dialog.queue_free()
	)

	save_btn.pressed.connect(func():
		var cropped_img = Image.new()
		cropped_img.copy_from(current_image)
		for r in range(state["rotation_clicks"]):
			cropped_img.rotate_90(0)
		
		var base_w = cropped_img.get_width()
		var base_h = cropped_img.get_height()
		
		var fit_scale = minf(296.0 / base_w, 296.0 / base_h)
		var display_scale = fit_scale * state["zoom"]
		
		var display_w = maxf(10, base_w * display_scale)
		var display_h = maxf(10, base_h * display_scale)
		
		var img_left = (148 - display_w/2) + state["offset_x"]
		var img_top = (148 - display_h/2) + state["offset_y"]
		
		var crop_left_prev = 48.0
		var crop_top_prev = 48.0
		
		var img_crop_x = int((crop_left_prev - img_left) / display_scale)
		var img_crop_y = int((crop_top_prev - img_top) / display_scale)
		var img_crop_w = int(200.0 / display_scale)
		var img_crop_h = int(200.0 / display_scale)
		
		img_crop_x = clampi(img_crop_x, 0, base_w - 1)
		img_crop_y = clampi(img_crop_y, 0, base_h - 1)
		img_crop_w = clampi(img_crop_w, 10, base_w - img_crop_x)
		img_crop_h = clampi(img_crop_h, 10, base_h - img_crop_y)
		
		var final_cropped = cropped_img.get_region(Rect2i(img_crop_x, img_crop_y, img_crop_w, img_crop_h))
		final_cropped.resize(256, 256, Image.INTERPOLATE_LANCZOS)
		
		var png_bytes = final_cropped.save_png_to_buffer()
		var b64 = Marshalls.raw_to_base64(png_bytes)
		var data_url = "data:image/png;base64," + b64
		
		on_save_callback.call(data_url)
		edit_dialog.queue_free()
	)

	update_preview.call()
	add_child(edit_dialog)
	edit_dialog.popup_centered()

func _open_native_camera_dialog(on_capture_callback: Callable) -> void:
	CameraServer.set_monitoring_feeds(true)
	var feeds = CameraServer.feeds()
	if feeds.size() == 0:
		_on_take_camera_photo_pressed("")
		return

	var cam_dialog = Window.new()
	cam_dialog.title = "📸 Native Camera Capture"
	cam_dialog.size = Vector2i(450, 460)
	cam_dialog.transient = true
	cam_dialog.exclusive = false

	var active_feed = feeds[0]
	active_feed.set_active(true)
	print("--- CAMERA DEBUG ---")
	print("Feed Name: ", active_feed.get_name())
	print("Feed Datatype: ", active_feed.get_datatype())
	print("--------------------")

	var panel = Panel.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	cam_dialog.add_child(panel)
	
	var p_st = StyleBoxFlat.new()
	p_st.bg_color = Color(0.95, 0.96, 0.98, 1.0)
	panel.add_theme_stylebox_override("panel", p_st)

	var main_vbox = VBoxContainer.new()
	main_vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	main_vbox.add_theme_constant_override("separation", 14)
	
	var margin = MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_bottom", 16)
	panel.add_child(margin)
	margin.add_child(main_vbox)

	var feed_panel = PanelContainer.new()
	feed_panel.custom_minimum_size = Vector2(324, 244)
	feed_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	
	var feed_st = StyleBoxFlat.new()
	feed_st.bg_color = Color(0.08, 0.12, 0.18, 1.0)
	feed_st.border_width_left = 2; feed_st.border_width_top = 2; feed_st.border_width_right = 2; feed_st.border_width_bottom = 2
	feed_st.border_color = _get_active_theme_color()
	feed_st.corner_radius_top_left = 8; feed_st.corner_radius_top_right = 8; feed_st.corner_radius_bottom_left = 8; feed_st.corner_radius_bottom_right = 8
	feed_panel.add_theme_stylebox_override("panel", feed_st)
	main_vbox.add_child(feed_panel)

	# Container for viewport
	var viewport_container = SubViewportContainer.new()
	viewport_container.custom_minimum_size = Vector2(320, 240)
	feed_panel.add_child(viewport_container)

	var sub_viewport = SubViewport.new()
	sub_viewport.size = Vector2i(320, 240)
	sub_viewport.disable_3d = true
	sub_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport_container.add_child(sub_viewport)

	var texture_rect = TextureRect.new()
	texture_rect.size = Vector2(320, 240)
	texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	sub_viewport.add_child(texture_rect)

	var is_ycbcr = false
	var datatype = active_feed.get_datatype()
	if datatype == 2 or datatype == 3 or OS.get_name() == "macOS":
		is_ycbcr = true

	if is_ycbcr:
		var y_tex = CameraTexture.new()
		y_tex.camera_feed_id = active_feed.get_id()
		y_tex.which_feed = 0
		y_tex.camera_is_active = true

		var uv_tex = CameraTexture.new()
		uv_tex.camera_feed_id = active_feed.get_id()
		uv_tex.which_feed = 1
		uv_tex.camera_is_active = true

		var shader = Shader.new()
		shader.code = """shader_type canvas_item;
		uniform sampler2D y_tex;
		uniform sampler2D uv_tex;
		void fragment() {
			float y = texture(y_tex, UV).r;
			vec2 uv = texture(uv_tex, UV).rg - vec2(0.5, 0.5);
			float r = y + 1.402 * uv.y;
			float g = y - 0.344 * uv.x - 0.714 * uv.y;
			float b = y + 1.772 * uv.x;
			COLOR = vec4(clamp(vec3(r, g, b), 0.0, 1.0), 1.0);
		}"""

		var mat = ShaderMaterial.new()
		mat.shader = shader
		mat.set_shader_parameter("y_tex", y_tex)
		mat.set_shader_parameter("uv_tex", uv_tex)

		texture_rect.texture = y_tex
		texture_rect.material = mat
	else:
		var cam_tex = CameraTexture.new()
		cam_tex.camera_feed_id = active_feed.get_id()
		cam_tex.camera_is_active = true
		texture_rect.texture = cam_tex

	var instr_lbl = Label.new()
	instr_lbl.text = "Center yourself in the camera feed above."
	instr_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	instr_lbl.add_theme_font_size_override("font_size", 13)
	instr_lbl.add_theme_color_override("font_color", Color(0.3, 0.35, 0.45, 1.0))
	main_vbox.add_child(instr_lbl)

	var separator = HSeparator.new(); main_vbox.add_child(separator)
	var action_hbox = HBoxContainer.new()
	action_hbox.alignment = HBoxContainer.ALIGNMENT_CENTER
	action_hbox.add_theme_constant_override("separation", 16)
	main_vbox.add_child(action_hbox)

	var cancel_btn = Button.new(); cancel_btn.text = "Cancel"; action_hbox.add_child(cancel_btn)
	cancel_btn.add_theme_color_override("font_color", Color(0.12, 0.16, 0.24, 1.0))
	cancel_btn.add_theme_color_override("font_hover_color", Color(0.12, 0.16, 0.24, 1.0))
	cancel_btn.add_theme_color_override("font_pressed_color", Color(0.12, 0.16, 0.24, 1.0))
	var capture_btn = Button.new(); capture_btn.text = "📸 Capture Photo"; action_hbox.add_child(capture_btn)

	var cancel_st = StyleBoxFlat.new()
	cancel_st.bg_color = Color(0.85, 0.88, 0.92, 1.0)
	cancel_st.corner_radius_top_left = 6; cancel_st.corner_radius_top_right = 6; cancel_st.corner_radius_bottom_left = 6; cancel_st.corner_radius_bottom_right = 6
	cancel_st.content_margin_left = 16; cancel_st.content_margin_top = 8; cancel_st.content_margin_right = 16; cancel_st.content_margin_bottom = 8
	cancel_btn.add_theme_stylebox_override("normal", cancel_st)

	var capture_st = StyleBoxFlat.new()
	capture_st.bg_color = _get_active_theme_color()
	capture_st.corner_radius_top_left = 6; capture_st.corner_radius_top_right = 6; capture_st.corner_radius_bottom_left = 6; capture_st.corner_radius_bottom_right = 6
	capture_st.content_margin_left = 16; capture_st.content_margin_top = 8; capture_st.content_margin_right = 16; capture_st.content_margin_bottom = 8
	capture_btn.add_theme_stylebox_override("normal", capture_st)
	capture_btn.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 1.0))

	var cleanup_camera = func():
		active_feed.set_active(false)
		cam_dialog.queue_free()

	cam_dialog.close_requested.connect(cleanup_camera)
	cancel_btn.pressed.connect(cleanup_camera)

	capture_btn.pressed.connect(func():
		var img = sub_viewport.get_texture().get_image()
		if img and not img.is_empty():
			var snap_img = Image.new()
			snap_img.copy_from(img)
			cleanup_camera.call()
			on_capture_callback.call(snap_img)
		else:
			cleanup_camera.call()
			_on_take_camera_photo_pressed("")
	)

	add_child(cam_dialog)
	cam_dialog.popup_centered()

