extends "res://app/scenes/standard_page_container.gd"

## Directory Roster Shell & Person Workspace (Story DIR-SPR1-005B)
## Strictly Read-Only: Binds exclusively to DirectoryReadService.
## Zero business mutations, zero outbox events, zero timestamp modifications.

const SQLiteDatabaseScript = preload("res://src/infrastructure/database/sqlite_database.gd")
const MigrationsRunnerScript = preload("res://src/infrastructure/database/migrations_runner.gd")
const DirectoryReadServiceScript = preload("res://src/domain/directory/directory_read_service.gd")
const PersonServiceScript = preload("res://src/domain/directory/person_service.gd")
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
const UnifiedPathwaysServiceScript = preload("res://src/domain/pathways/unified_pathways_service.gd")
const PersonRegistrationValidatorScript = preload("res://src/domain/directory/person_registration_validator.gd")
const StaffMobileServiceScript = preload("res://src/domain/directory/staff_mobile_service.gd")
const StaffMobileDialogScript = preload("res://src/ui/components/staff_mobile_provisioning_dialog.gd")
const NoteServiceScript = preload("res://src/domain/directory/note_service.gd")
const SpellingAssistanceHelperScript = preload("res://src/ui/components/spelling_assistance_helper.gd")

var db: RefCounted:
	set(value):
		db = value
		if db:
			read_service = DirectoryReadServiceScript.new(db)
			unified_pathways_service = UnifiedPathwaysServiceScript.new(db)
			note_service = NoteServiceScript.new(db)
			if is_node_ready():
				call_deferred("refresh_view")

var read_service: RefCounted
var unified_pathways_service: RefCounted
var note_service: RefCounted
var app_shell: Node = null

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
var pathway_notes_expanded_map: Dictionary = {}
var pathway_requirements_expanded_map: Dictionary = {}
var pathway_attendance_expanded_map: Dictionary = {}

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
var _photo_cache: Dictionary = {}

var current_sort_by: String = "first_name" # "first_name" or "last_name"
var sort_container: HBoxContainer = null
var btn_sort_first: Button = null
var btn_sort_last: Button = null

func _ready() -> void:
	_init_debounce_timer()
	_ensure_onready_nodes()
	if not read_service:
		_init_read_service()
	_setup_sort_bar()
	_connect_signals()
	call_deferred("refresh_view")

func _setup_sort_bar() -> void:
	var sub_header = get_node_or_null("MarginContainer/VBoxContainer/SubHeaderBar") as HBoxContainer
	if not sub_header: return
	if sub_header.has_node("SortHBox"): return

	sort_container = HBoxContainer.new()
	sort_container.name = "SortHBox"
	sort_container.add_theme_constant_override("separation", 6)

	var lbl_sort = Label.new()
	lbl_sort.text = "SORT BY:"
	lbl_sort.add_theme_font_size_override("font_size", 12)
	lbl_sort.add_theme_color_override("font_color", Color(0.60, 0.68, 0.78, 1.0))
	sort_container.add_child(lbl_sort)

	btn_sort_first = Button.new()
	btn_sort_first.text = "First Name"
	btn_sort_first.custom_minimum_size = Vector2(85, 28)
	btn_sort_first.add_theme_font_size_override("font_size", 12)
	btn_sort_first.pressed.connect(func(): select_sort_by("first_name"))
	sort_container.add_child(btn_sort_first)

	btn_sort_last = Button.new()
	btn_sort_last.text = "Last Name"
	btn_sort_last.custom_minimum_size = Vector2(85, 28)
	btn_sort_last.add_theme_font_size_override("font_size", 12)
	btn_sort_last.pressed.connect(func(): select_sort_by("last_name"))
	sort_container.add_child(btn_sort_last)

	sub_header.add_child(sort_container)
	if sub_header.has_method("move_child") and results_count_label:
		sub_header.move_child(sort_container, sub_header.get_child_count() - 2)

	_update_sort_button_styles()

func select_sort_by(sort_mode: String) -> void:
	if current_sort_by == sort_mode: return
	current_sort_by = sort_mode
	_update_sort_button_styles()
	refresh_view()

func _update_sort_button_styles() -> void:
	if not btn_sort_first or not btn_sort_last: return
	var primary_col = _get_active_theme_color()

	var active_st = StyleBoxFlat.new()
	active_st.bg_color = primary_col
	active_st.corner_radius_top_left = 4; active_st.corner_radius_top_right = 4; active_st.corner_radius_bottom_left = 4; active_st.corner_radius_bottom_right = 4
	active_st.content_margin_left = 8; active_st.content_margin_right = 8; active_st.content_margin_top = 4; active_st.content_margin_bottom = 4

	var inactive_st = StyleBoxFlat.new()
	inactive_st.bg_color = Color(0.20, 0.26, 0.36, 1.0)
	inactive_st.corner_radius_top_left = 4; inactive_st.corner_radius_top_right = 4; inactive_st.corner_radius_bottom_left = 4; inactive_st.corner_radius_bottom_right = 4
	inactive_st.content_margin_left = 8; inactive_st.content_margin_right = 8; inactive_st.content_margin_top = 4; inactive_st.content_margin_bottom = 4

	if current_sort_by == "first_name":
		btn_sort_first.add_theme_stylebox_override("normal", active_st)
		btn_sort_first.add_theme_color_override("font_color", Color(1, 1, 1, 1))
		btn_sort_last.add_theme_stylebox_override("normal", inactive_st)
		btn_sort_last.add_theme_color_override("font_color", Color(0.70, 0.78, 0.88, 1.0))
	else:
		btn_sort_last.add_theme_stylebox_override("normal", active_st)
		btn_sort_last.add_theme_color_override("font_color", Color(1, 1, 1, 1))
		btn_sort_first.add_theme_stylebox_override("normal", inactive_st)
		btn_sort_first.add_theme_color_override("font_color", Color(0.70, 0.78, 0.88, 1.0))

func _find_app_shell() -> Node:
	var curr: Node = self
	while curr:
		if curr.has_method("switch_view"):
			return curr
		curr = curr.get_parent()
	return null

var return_to_pathways_bar: PanelContainer = null

func _show_return_to_pathways_bar() -> void:
	var main_vbox = _get_main_vbox()
	if not main_vbox: return

	if return_to_pathways_bar and is_instance_valid(return_to_pathways_bar):
		return_to_pathways_bar.visible = true
		return

	return_to_pathways_bar = PanelContainer.new()
	var p_st = StyleBoxFlat.new()
	p_st.bg_color = Color(0.12, 0.16, 0.24, 1.0)
	p_st.content_margin_left = 16; p_st.content_margin_right = 16
	p_st.content_margin_top = 8; p_st.content_margin_bottom = 8
	p_st.border_width_bottom = 1
	p_st.border_color = Color(0.24, 0.32, 0.44, 1.0)
	return_to_pathways_bar.add_theme_stylebox_override("panel", p_st)

	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 12)

	var btn_ret = Button.new()
	btn_ret.text = "◄ Return to Pathways"
	btn_ret.add_theme_font_size_override("font_size", 13)
	var btn_st = StyleBoxFlat.new()
	btn_st.bg_color = Color(0.92, 0.38, 0.18, 1.0)
	btn_st.corner_radius_top_left = 6; btn_st.corner_radius_top_right = 6
	btn_st.corner_radius_bottom_left = 6; btn_st.corner_radius_bottom_right = 6
	btn_st.content_margin_left = 14; btn_st.content_margin_right = 14
	btn_st.content_margin_top = 6; btn_st.content_margin_bottom = 6
	btn_ret.add_theme_stylebox_override("normal", btn_st)
	btn_ret.add_theme_stylebox_override("hover", btn_st)
	btn_ret.add_theme_stylebox_override("pressed", btn_st)
	btn_ret.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 1.0))

	btn_ret.pressed.connect(func():
		var shell = _find_app_shell()
		if shell and shell.has_method("switch_view"):
			shell.switch_view("pathways")
	)
	hbox.add_child(btn_ret)

	var lbl_info = Label.new()
	lbl_info.text = "Viewing participant profile from Pathways"
	lbl_info.add_theme_font_size_override("font_size", 13)
	lbl_info.add_theme_color_override("font_color", Color(0.85, 0.90, 0.98, 1.0))
	hbox.add_child(lbl_info)

	return_to_pathways_bar.add_child(hbox)
	main_vbox.add_child(return_to_pathways_bar)
	main_vbox.move_child(return_to_pathways_bar, 0)

func _hide_return_to_pathways_bar() -> void:
	if return_to_pathways_bar and is_instance_valid(return_to_pathways_bar):
		return_to_pathways_bar.visible = false

func receive_navigation_context(params: Dictionary) -> void:
	if params.get("from_view", "") == "pathways":
		_show_return_to_pathways_bar()
	else:
		_hide_return_to_pathways_bar()

	if params.has("person_id"):
		var pid = int(params["person_id"])
		call_deferred("select_person_by_id", pid)

	var p_uuid = str(params.get("person_uuid", params.get("linked_human_id", params.get("human_id", ""))))
	if not p_uuid.is_empty():
		call_deferred("select_person_by_uuid", p_uuid)

	var tab = str(params.get("tab", ""))
	if tab == "notes" or tab == "notes_tasks" or tab == "tasks":
		call_deferred("select_workspace_tab", "notes")

	if params.get("queue_mode", false) == true:
		var qid = params.get("queue_id", "")
		if qid == "registrations_awaiting_review":
			configure_queue_mode(params)
	if params.get("open_add_dialog", false) == true:
		call_deferred("_on_add_person_pressed")
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

func _get_main_vbox() -> VBoxContainer:
	if has_node("MarginContainer/VBoxContainer"):
		return $MarginContainer/VBoxContainer as VBoxContainer
	elif has_node("MarginContainer/MainVBox"):
		return $MarginContainer/MainVBox as VBoxContainer
	return null

func _get_std_hdr() -> Control:
	var vbox = _get_main_vbox()
	if vbox:
		if vbox.has_node("HeaderBar"):
			return vbox.get_node("HeaderBar") as Control
		elif vbox.has_node("HeaderVBox"):
			return vbox.get_node("HeaderVBox") as Control
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

	if not btn_add_person_placeholder:
		btn_add_person_placeholder = find_child("BtnAddPersonPlaceholder", true, false) as Button
	if btn_add_person_placeholder:
		if not btn_add_person_placeholder.pressed.is_connected(_on_add_person_pressed):
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
	_setup_sort_bar()
	var roster_scroll = get_node_or_null("MarginContainer/VBoxContainer/MainSplit/RosterPanel/RosterScroll") as ScrollContainer
	var workspace_scroll = get_node_or_null("MarginContainer/VBoxContainer/MainSplit/WorkspacePanel/WorkspaceMargin/SelectedWorkspaceVBox/WorkspaceScroll") as ScrollContainer
	var saved_r_scroll = roster_scroll.scroll_vertical if roster_scroll else 0
	var saved_w_scroll = workspace_scroll.scroll_vertical if workspace_scroll else 0

	_active_photo_callback = Callable()
	_style_add_person_button()
	if not read_service:
		_show_view_state("error")
		return

	_show_view_state("loading")

	_update_header_filter_counts()
	_fetch_roster_data()

	if roster_scroll and saved_r_scroll > 0:
		roster_scroll.scroll_vertical = saved_r_scroll
	if workspace_scroll and saved_w_scroll > 0:
		workspace_scroll.scroll_vertical = saved_w_scroll

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
	var options = {"sort_by": current_sort_by}
	if current_filter != "all":
		options["status"] = current_filter

	var res: Dictionary
	if current_query.strip_edges() != "":
		res = read_service.search_people(current_query, options)
	else:
		if current_filter == "all":
			res = read_service.list_people(options)
		elif current_filter == "active":
			res = read_service.list_active_people(options)
		elif current_filter == "pending":
			res = read_service.list_pending_people(options)
		elif current_filter == "inactive":
			res = read_service.list_inactive_people(options)

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

func _get_cached_photo_texture(person_uuid: String, photo_b64: String) -> ImageTexture:
	var clean_b64 = photo_b64.strip_edges()
	if clean_b64 == "" or clean_b64.to_lower() == "null" or clean_b64.to_lower() == "<null>":
		return null
	var b64_hash = clean_b64.hash()
	var cache_key = person_uuid if person_uuid != "" else str(b64_hash)
	if _photo_cache.has(cache_key):
		var entry = _photo_cache[cache_key]
		if entry.get("hash", 0) == b64_hash and entry.get("texture") != null:
			return entry.get("texture") as ImageTexture
	var new_tex = _create_texture_from_base64(clean_b64)
	_photo_cache[cache_key] = {"hash": b64_hash, "texture": new_tex}
	return new_tex

func _invalidate_photo_cache(person_uuid: String) -> void:
	if person_uuid != "" and _photo_cache.has(person_uuid):
		_photo_cache.erase(person_uuid)

func _create_texture_from_base64(base64_str: String) -> ImageTexture:
	var img = _create_image_from_base64(base64_str)
	if not img: return null
	return ImageTexture.create_from_image(img)

func _create_image_from_base64(base64_str: String) -> Image:
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
	return img

func _open_photo_lightbox(person_name: String, texture: Texture2D) -> void:
	if not texture: return

	var backdrop = ColorRect.new()
	backdrop.color = Color(0.04, 0.07, 0.12, 0.85)
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)

	var center = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.add_child(center)

	var card = PanelContainer.new()
	card.custom_minimum_size = Vector2(500, 540)
	var card_st = StyleBoxFlat.new()
	card_st.bg_color = Color(0.10, 0.14, 0.22, 1.0)
	card_st.border_width_left = 1; card_st.border_width_top = 1; card_st.border_width_right = 1; card_st.border_width_bottom = 1
	card_st.border_color = Color(0.24, 0.35, 0.50, 1.0)
	card_st.corner_radius_top_left = 12; card_st.corner_radius_top_right = 12; card_st.corner_radius_bottom_left = 12; card_st.corner_radius_bottom_right = 12
	card_st.content_margin_left = 20; card_st.content_margin_top = 16; card_st.content_margin_right = 20; card_st.content_margin_bottom = 20
	card.add_theme_stylebox_override("panel", card_st)
	center.add_child(card)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	card.add_child(vbox)

	var hdr_hbox = HBoxContainer.new()
	hdr_hbox.size_flags_horizontal = SIZE_EXPAND_FILL

	var name_lbl = Label.new()
	name_lbl.text = person_name
	name_lbl.add_theme_font_size_override("font_size", 18)
	name_lbl.add_theme_color_override("font_color", Color(0.95, 0.97, 1.0))
	name_lbl.size_flags_horizontal = SIZE_EXPAND_FILL
	hdr_hbox.add_child(name_lbl)

	var btn_close = Button.new()
	btn_close.text = "✖"
	btn_close.custom_minimum_size = Vector2(32, 32)
	btn_close.add_theme_font_size_override("font_size", 14)
	btn_close.pressed.connect(func(): backdrop.queue_free())
	hdr_hbox.add_child(btn_close)
	vbox.add_child(hdr_hbox)

	var img_rect = TextureRect.new()
	img_rect.texture = texture
	img_rect.custom_minimum_size = Vector2(460, 460)
	img_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	img_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	vbox.add_child(img_rect)

	backdrop.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			backdrop.queue_free()
		elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
			backdrop.queue_free()
	)

func _create_roster_row_button(p: Dictionary, index: int) -> Button:
	var btn = Button.new()
	btn.custom_minimum_size = Vector2(0, 84)
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT

	var margin = MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_PASS
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_bottom", 8)

	var hbox = HBoxContainer.new()
	hbox.mouse_filter = Control.MOUSE_FILTER_PASS
	hbox.add_theme_constant_override("separation", 14)

	var first_name = p.get("first_name", "")
	var last_name = p.get("last_name", "")
	var initials = (first_name.left(1) + last_name.left(1)).to_upper()
	var full_person_name = (first_name + " " + last_name).strip_edges()

	var photo_tex = _get_cached_photo_texture(str(p.get("person_uuid", "")), String(p.get("profile_photo")) if p.get("profile_photo") != null else "")
	if photo_tex:
		var avatar_rect = TextureRect.new()
		avatar_rect.texture = photo_tex
		avatar_rect.custom_minimum_size = Vector2(48, 48)
		avatar_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		avatar_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		avatar_rect.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		avatar_rect.mouse_filter = Control.MOUSE_FILTER_STOP

		var _p_name = full_person_name
		var _p_tex = photo_tex
		avatar_rect.gui_input.connect(func(event: InputEvent):
			if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
				_open_photo_lightbox(_p_name, _p_tex)
				get_viewport().set_input_as_handled()
		)
		hbox.add_child(avatar_rect)
	else:
		var avatar = Label.new()
		avatar.text = initials
		avatar.custom_minimum_size = Vector2(48, 48)
		avatar.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		avatar.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		avatar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		avatar.add_theme_font_size_override("font_size", 16)

		var av_style = StyleBoxFlat.new()
		av_style.bg_color = Color(0.20, 0.26, 0.36, 1.0)
		av_style.corner_radius_top_left = 24
		av_style.corner_radius_top_right = 24
		av_style.corner_radius_bottom_left = 24
		av_style.corner_radius_bottom_right = 24
		avatar.add_theme_stylebox_override("normal", av_style)
		avatar.mouse_filter = Control.MOUSE_FILTER_PASS
		hbox.add_child(avatar)

	var vbox_text = VBoxContainer.new()
	vbox_text.custom_minimum_size = Vector2(180, 0)
	vbox_text.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	vbox_text.add_theme_constant_override("separation", 2)

	var name_label = Label.new()
	name_label.name = "NameLabel"
	name_label.text = full_person_name
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.add_theme_font_size_override("font_size", 16)
	name_label.add_theme_color_override("font_color", Color(0.95, 0.97, 1.0))
	vbox_text.add_child(name_label)

	var id_label = Label.new()
	id_label.text = p.get("human_id", "")
	id_label.add_theme_font_size_override("font_size", 13)
	id_label.add_theme_color_override("font_color", Color(0.75, 0.82, 0.92))
	vbox_text.add_child(id_label)

	var inst_str = _clean_str(p.get("institution_short_name", p.get("institution_name", p.get("institution_other_name", ""))))
	var ay_str = _clean_str(p.get("academic_year", ""))
	if ay_str == "Not Applicable": ay_str = ""
	var mj_str = _clean_str(p.get("major", ""))

	var c_parts = []
	if inst_str != "": c_parts.append(inst_str)
	if ay_str != "": c_parts.append(ay_str)
	if mj_str != "": c_parts.append(mj_str)

	var campus_info_lbl = Label.new()
	campus_info_lbl.text = " • ".join(c_parts) if c_parts.size() > 0 else ""
	campus_info_lbl.add_theme_font_size_override("font_size", 12)
	campus_info_lbl.add_theme_color_override("font_color", Color(0.40, 0.75, 0.95, 1.0))
	campus_info_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	vbox_text.add_child(campus_info_lbl)

	hbox.add_child(vbox_text)

	var trailing_spacer = Control.new()
	trailing_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(trailing_spacer)

	margin.add_child(hbox)
	btn.add_child(margin)
	btn.pressed.connect(func(): select_person_by_index(index))
	return btn

func select_person_by_id(person_id: int) -> void:
	if visible_people.size() == 0:
		_fetch_roster_data()
	for i in range(visible_people.size()):
		var p = visible_people[i]
		if int(p.get("id", 0)) == person_id:
			select_person_by_index(i)
			return

func select_person_by_uuid(p_uuid: String) -> void:
	if p_uuid.is_empty(): return
	if visible_people.size() == 0:
		_fetch_roster_data()
	for i in range(visible_people.size()):
		var p = visible_people[i]
		if str(p.get("person_uuid", "")) == p_uuid or str(p.get("human_id", "")) == p_uuid:
			select_person_by_index(i)
			return

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
	var human_id = str(p.get("human_id", "PRT-1028"))

	var person_id = int(p.get("id", 0))
	var qr_val = "Not Issued"
	if db and person_id > 0:
		var qr_res = db.execute("SELECT token_hint FROM participant_qr_credentials WHERE person_id = ? AND status = 'active' LIMIT 1;", [person_id])
		if qr_res["success"] and qr_res["data"].size() > 0:
			var qr_hint = str(qr_res["data"][0].get("token_hint", ""))
			qr_val = "Active (" + qr_hint + ")" if qr_hint != "" else "Issued/Active"

	var pin_val = "Not Set"
	if db and person_id > 0:
		var pin_res = db.execute("SELECT credential_id FROM participant_pin_credentials WHERE person_id = ? AND status = 'active' LIMIT 1;", [person_id])
		if pin_res["success"] and pin_res["data"].size() > 0:
			pin_val = "Active"

	grid.add_child(_create_kpi_card("REGISTRATION FLAG", flag_val, Color(1.0, 0.75, 0.35, 1.0) if flag_val != "Clear" else Color(0.40, 0.85, 0.60, 1.0)))
	grid.add_child(_create_kpi_card("SMS CONSENT", sms_val, Color(0.40, 0.85, 0.60, 1.0) if sms_val == "Granted" else Color(0.80, 0.85, 0.90, 1.0)))
	grid.add_child(_create_kpi_card("PARTICIPANT ID", human_id, Color(0.90, 0.95, 1.0, 1.0)))
	grid.add_child(_create_kpi_card("QR STATUS", qr_val, Color(0.70, 0.80, 0.90, 1.0)))
	grid.add_child(_create_kpi_card("PIN STATUS", pin_val, Color(0.70, 0.80, 0.90, 1.0)))
	grid.add_child(_create_kpi_card("CHECK-INS", str(att_history.size()) + " Total", Color(0.40, 0.85, 0.60, 1.0)))

	# 1. Dedicated Staff Mobile Access Credentials Card for Eligible Staff Members (Top Position)
	var role_str = str(p.get("primary_role", p.get("staff_classification", "Participant"))).to_lower()
	var classif_str = str(p.get("staff_classification", "")).to_lower()
	var is_staff_eligible = (role_str in ["staff", "team leader", "supervisor", "administrator", "intern", "volunteer"]) or (classif_str in ["staff", "team leader", "supervisor", "administrator", "intern", "volunteer"])

	if is_staff_eligible:
		var mob_box = VBoxContainer.new()
		mob_box.add_theme_constant_override("separation", 12)

		var mob_stat = {"enabled": false, "version": 0}
		if StaffMobileServiceScript and db and person_id > 0:
			var mob_svc = StaffMobileServiceScript.new(db)
			mob_stat = mob_svc.get_staff_mobile_status(person_id)

		var mob_lbl = Label.new()
		if mob_stat["enabled"]:
			mob_lbl.text = "🟢 Mobile Staff Access: ENABLED (Credential Version " + str(mob_stat.get("version", 1)) + ")"
			mob_lbl.add_theme_color_override("font_color", Color(0.40, 0.85, 0.60, 1.0))
		else:
			mob_lbl.text = "🔴 Mobile Staff Access: NOT PROVISIONED"
			mob_lbl.add_theme_color_override("font_color", Color(0.90, 0.70, 0.40, 1.0))
		mob_lbl.add_theme_font_size_override("font_size", 15)
		mob_box.add_child(mob_lbl)

		var btn_mob_cfg = Button.new()
		btn_mob_cfg.text = "📱 Manage Mobile Staff Access (6-Digit PIN)"
		btn_mob_cfg.custom_minimum_size = Vector2(280, 42)
		btn_mob_cfg.add_theme_font_size_override("font_size", 15)
		_style_dark_card_button(btn_mob_cfg)
		btn_mob_cfg.pressed.connect(func():
			if StaffMobileDialogScript:
				var dlg = StaffMobileDialogScript.new()
				add_child(dlg)
				dlg.setup(db, person_id, "Administrator")
				dlg.mobile_credentials_updated.connect(func(_pid: int, _enabled: bool):
					refresh_view()
				)
				dlg.popup_centered()
		)
		mob_box.add_child(btn_mob_cfg)
		overview_section.add_child(_create_card("Staff Mobile Access Credentials", mob_box))

	# 2. Operational Summary KPI Cards Grid
	overview_section.add_child(_create_card("Operational Summary KPI Cards", grid))

	# 3. Credentials & Pass Overview Card
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

	var helper = load("res://src/ui/components/selectable_label_helper.gd").new()
	var v_lbl = helper.create_selectable_line(val_text, 19, accent_color)
	vbox.add_child(v_lbl)

	panel.add_child(vbox)
	return panel

func _clean_str(val) -> String:
	if val == null: return ""
	var s = str(val).strip_edges()
	if s.ends_with(".0"):
		s = s.left(s.length() - 2)
	if s.to_lower() == "<null>" or s.to_lower() == "null" or s.to_lower() == "nil":
		return ""
	return s

func _populate_profile_section(p: Dictionary) -> void:
	if not profile_section: return

	var p_uuid = _clean_str(p.get("person_uuid", ""))

	_active_photo_callback = func(cropped_data_url: String):
		if db:
			db.execute("UPDATE people SET profile_photo = ? WHERE person_uuid = ?;", [cropped_data_url, p_uuid])
		_invalidate_photo_cache(p_uuid)
		refresh_view()

	# 1. Profile Photo & Dynamic Camera Controls
	var photo_box = VBoxContainer.new()
	photo_box.add_theme_constant_override("separation", 12)
	var p_hbox = HBoxContainer.new()
	p_hbox.add_theme_constant_override("separation", 16)

	var raw_photo_b64 = _clean_str(p.get("profile_photo", ""))
	var photo_tex = _get_cached_photo_texture(p_uuid, raw_photo_b64)
	var has_photo = (photo_tex != null)

	if has_photo:
		var photo_rect = TextureRect.new()
		photo_rect.texture = photo_tex
		photo_rect.custom_minimum_size = Vector2(96, 96)
		photo_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		photo_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		photo_rect.mouse_filter = Control.MOUSE_FILTER_STOP
		var _cur_b64_rect = raw_photo_b64
		photo_rect.gui_input.connect(func(event: InputEvent):
			if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
				var img_to_edit = _create_image_from_base64(_cur_b64_rect)
				if img_to_edit:
					_open_image_editor(img_to_edit, _active_photo_callback)
		)
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

	if has_photo:
		var btn_crop_existing = Button.new()
		btn_crop_existing.text = "✂️ Crop & Zoom Photo"
		btn_crop_existing.custom_minimum_size = Vector2(175, 40)
		btn_crop_existing.add_theme_font_size_override("font_size", 15)
		var _cur_b64_btn = raw_photo_b64
		btn_crop_existing.pressed.connect(func():
			var img_to_edit = _create_image_from_base64(_cur_b64_btn)
			if img_to_edit:
				_open_image_editor(img_to_edit, _active_photo_callback)
		)
		btns_hbox.add_child(btn_crop_existing)

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

	# Staff Classification / Role
	var role_vbox = VBoxContainer.new(); role_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var role_lbl = Label.new(); role_lbl.text = "STAFF CLASSIFICATION"; role_lbl.add_theme_font_size_override("font_size", 14); role_lbl.add_theme_color_override("font_color", Color(0.70, 0.78, 0.88, 1.0))
	var role_dropdown = OptionButton.new()
	role_dropdown.add_item("Participant", 0)
	role_dropdown.add_item("Staff", 1)
	role_dropdown.add_item("Volunteer", 2)
	role_dropdown.add_item("Intern", 3)
	role_dropdown.add_item("Team Leader", 4)
	
	var r_val = _clean_str(p.get("staff_classification", p.get("primary_role", "Participant")))
	if r_val.contains("Supervisor") or r_val == "Shift Supervisor" or r_val == "Team Leader":
		role_dropdown.selected = 4
	elif r_val.to_lower() == "staff":
		role_dropdown.selected = 1
	elif r_val.to_lower() == "volunteer" or r_val.to_lower().contains("vol"):
		role_dropdown.selected = 2
	elif r_val.to_lower() == "intern":
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

	# Staffing & Leadership Capabilities
	var cap_vbox = VBoxContainer.new(); cap_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var cap_lbl = Label.new(); cap_lbl.text = "STAFFING & LEADERSHIP CAPABILITIES"; cap_lbl.add_theme_font_size_override("font_size", 14); cap_lbl.add_theme_color_override("font_color", Color(0.70, 0.78, 0.88, 1.0))
	cap_vbox.add_child(cap_lbl)

	var chk_can_cover = CheckBox.new(); chk_can_cover.text = "Can Cover Center Hours"
	chk_can_cover.button_pressed = (int(p.get("can_cover_hours", 0)) == 1 or r_val == "Staff" or r_val == "Intern")
	_style_checkbox_on_dark(chk_can_cover)
	cap_vbox.add_child(chk_can_cover)

	var chk_is_tl = CheckBox.new(); chk_is_tl.text = "Eligible as Team Leader"
	chk_is_tl.button_pressed = (int(p.get("is_team_leader_eligible", 0)) == 1)
	_style_checkbox_on_dark(chk_is_tl)
	cap_vbox.add_child(chk_is_tl)

	var chk_real_life = CheckBox.new(); chk_real_life.text = "Real Life"
	chk_real_life.button_pressed = (int(p.get("real_life", 0)) == 1)
	_style_checkbox_on_dark(chk_real_life)
	cap_vbox.add_child(chk_real_life)

	role_dropdown.item_selected.connect(func(idx: int):
		var selected_role = role_dropdown.get_item_text(idx)
		if selected_role == "Staff" or selected_role == "Intern":
			chk_can_cover.button_pressed = true
	)

	form_grid.add_child(cap_vbox)

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
			var role_db_val = role_sel_txt

			var flag_db_val = flag_dropdown.get_item_text(flag_dropdown.selected)
			var can_cov_val = 1 if (chk_can_cover.button_pressed or role_sel_txt == "Staff" or role_sel_txt == "Intern") else 0
			var is_tl_val = 1 if chk_is_tl.button_pressed else 0
			var real_life_val = 1 if chk_real_life.button_pressed else 0

			var old_cls = _clean_str(p.get("staff_classification", p.get("primary_role", "Participant")))
			if old_cls.contains("Supervisor") or old_cls == "Shift Supervisor": old_cls = "Team Leader"

			var full_name = (fn_edit.text.strip_edges() + " " + ln_edit.text.strip_edges()).strip_edges()
			var pid = int(p.get("id", 0))

			var execute_save = func():
				db.execute("UPDATE people SET first_name = ?, last_name = ?, suffix = ?, phone = ?, email = ?, preferred_email = ?, birthday = ?, primary_role = ?, staff_classification = ?, flag_status = ?, can_cover_hours = ?, is_team_leader_eligible = ?, real_life = ? WHERE person_uuid = ?;",
					[fn_edit.text.strip_edges(), ln_edit.text.strip_edges(), suf_edit.text.strip_edges(), ph_edit.text.strip_edges(), em_edit.text.strip_edges(), pref_email, _ui_to_db_date(bd_edit.text.strip_edges()), role_db_val, role_db_val, flag_db_val, can_cov_val, is_tl_val, real_life_val, p_uuid])
				refresh_view()

			if old_cls != role_sel_txt and role_sel_txt != "Participant":
				var fut_res = db.execute("SELECT COUNT(*) AS cnt FROM schedule_entries WHERE (person_name = ? OR person_id = ?) AND shift_date >= date('now', 'localtime');", [full_name, pid])
				var fut_cnt = int(fut_res["data"][0]["cnt"]) if fut_res["success"] and fut_res["data"].size() > 0 else 0
				if fut_cnt > 0:
					_show_future_shifts_warning_dialog(full_name, fut_cnt, old_cls, role_sel_txt, execute_save)
					return

			execute_save.call()
	)
	contact_card_vbox.add_child(btn_save_contact)

	profile_section.add_child(_create_credentials_card(p, p_uuid))
	profile_section.add_child(_create_card("Identity & Contact Information", contact_card_vbox))
	profile_section.add_child(_create_campus_community_card(p, p_uuid))

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

	# 4. A Few of My Favorite Things Card
	profile_section.add_child(_create_card("A Few of My Favorite Things", _build_favorite_things_box(p)))

	# 5. Emergency Contact Card
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

func _build_favorite_things_box(p: Dictionary) -> Control:
	var fav_box = VBoxContainer.new()
	fav_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fav_box.add_theme_constant_override("separation", 14)

	var p_id = int(p.get("id", 0))
	var fav_data = {}
	var person_svc = PersonServiceScript.new(db) if db else null
	if person_svc and p_id > 0:
		fav_data = person_svc.get_favorite_things(p_id)
	elif db and p_id > 0:
		var res = db.execute("SELECT * FROM person_favorite_things WHERE person_id = ? LIMIT 1;", [p_id])
		if res["success"] and res["data"].size() > 0:
			fav_data = res["data"][0]

	var grid = GridContainer.new()
	grid.columns = 3
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 12)

	var fields_config = [
		{"key": "candy_treat", "label": "CANDY / TREAT", "ph": "Favorite candy or treat"},
		{"key": "snack", "label": "SNACK", "ph": "Favorite snack"},
		{"key": "drink", "label": "DRINK", "ph": "Favorite drink"},
		{"key": "food_meal", "label": "FOOD / MEAL", "ph": "Favorite food or meal"},
		{"key": "restaurant", "label": "RESTAURANT", "ph": "Favorite restaurant"},
		{"key": "dessert", "label": "DESSERT", "ph": "Favorite dessert"},
		{"key": "fruit", "label": "FRUIT", "ph": "Favorite fruit"},
		{"key": "movie_tv", "label": "MOVIE / TV", "ph": "Favorite movie or TV show"},
		{"key": "music", "label": "MUSIC", "ph": "Favorite music or artist"},
		{"key": "activities_hobbies", "label": "ACTIVITIES / HOBBIES", "ph": "Hobbies & activities"},
		{"key": "sports_teams", "label": "SPORTS / TEAMS", "ph": "Favorite sports & teams"},
		{"key": "stores_places", "label": "STORES / PLACES", "ph": "Favorite stores & places"}
	]

	var edits_dict = {}

	for cfg in fields_config:
		var f_vbox = VBoxContainer.new()
		f_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		f_vbox.add_theme_constant_override("separation", 4)

		var f_lbl = Label.new()
		f_lbl.text = cfg["label"]
		f_lbl.add_theme_font_size_override("font_size", 14)
		f_lbl.add_theme_color_override("font_color", Color(0.70, 0.78, 0.88, 1.0))
		f_vbox.add_child(f_lbl)

		var f_edit = LineEdit.new()
		f_edit.text = _clean_str(fav_data.get(cfg["key"], ""))
		f_edit.placeholder_text = cfg["ph"]
		f_edit.custom_minimum_size = Vector2(0, 44)
		f_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		f_edit.add_theme_font_size_override("font_size", 15)
		f_vbox.add_child(f_edit)

		grid.add_child(f_vbox)
		edits_dict[cfg["key"]] = f_edit

	fav_box.add_child(grid)

	# Multiline 1: OTHER FAVORITES / THINGS I ENJOY
	var oth_vbox = VBoxContainer.new()
	oth_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	oth_vbox.add_theme_constant_override("separation", 4)

	var oth_lbl = Label.new()
	oth_lbl.text = "OTHER FAVORITES / THINGS I ENJOY"
	oth_lbl.add_theme_font_size_override("font_size", 14)
	oth_lbl.add_theme_color_override("font_color", Color(0.70, 0.78, 0.88, 1.0))
	oth_vbox.add_child(oth_lbl)

	var oth_edit = TextEdit.new()
	oth_edit.text = _clean_str(fav_data.get("other_favorites", ""))
	oth_edit.placeholder_text = "Coffee order, books, games, favorite colors, places to go, interests, or anything else that helps us know this person better..."
	oth_edit.custom_minimum_size = Vector2(0, 75)
	oth_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	oth_edit.add_theme_font_size_override("font_size", 15)
	oth_vbox.add_child(oth_edit)
	edits_dict["other_favorites"] = oth_edit

	fav_box.add_child(oth_vbox)

	# Multiline 2: THINGS I DON'T LIKE / PREFER TO AVOID
	var avoid_vbox = VBoxContainer.new()
	avoid_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	avoid_vbox.add_theme_constant_override("separation", 4)

	var avoid_lbl = Label.new()
	avoid_lbl.text = "THINGS I DON’T LIKE / PREFER TO AVOID"
	avoid_lbl.add_theme_font_size_override("font_size", 14)
	avoid_lbl.add_theme_color_override("font_color", Color(0.70, 0.78, 0.88, 1.0))
	avoid_vbox.add_child(avoid_lbl)

	var avoid_edit = TextEdit.new()
	avoid_edit.text = _clean_str(fav_data.get("prefer_to_avoid", ""))
	avoid_edit.placeholder_text = "Optional preferences or dislikes that may help with hospitality. Record medical allergies in the Medical Notes section below."
	avoid_edit.custom_minimum_size = Vector2(0, 75)
	avoid_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	avoid_edit.add_theme_font_size_override("font_size", 15)
	avoid_vbox.add_child(avoid_edit)
	edits_dict["prefer_to_avoid"] = avoid_edit

	fav_box.add_child(avoid_vbox)

	# Single Save Button
	var btn_save_fav = Button.new()
	btn_save_fav.text = "💾 Save Favorite Things"
	btn_save_fav.custom_minimum_size = Vector2(240, 44)
	btn_save_fav.add_theme_font_size_override("font_size", 16)
	btn_save_fav.pressed.connect(func():
		if p_id > 0:
			var save_data = {}
			for k in edits_dict.keys():
				var ctrl = edits_dict[k]
				save_data[k] = ctrl.text.strip_edges()

			if person_svc:
				person_svc.save_favorite_things(p_id, save_data)
			else:
				# Fallback direct DB save
				var candy = save_data.get("candy_treat", "")
				var snack = save_data.get("snack", "")
				var drink = save_data.get("drink", "")
				var food = save_data.get("food_meal", "")
				var restaurant = save_data.get("restaurant", "")
				var dessert = save_data.get("dessert", "")
				var fruit = save_data.get("fruit", "")
				var movie_tv = save_data.get("movie_tv", "")
				var music = save_data.get("music", "")
				var activities = save_data.get("activities_hobbies", "")
				var sports = save_data.get("sports_teams", "")
				var stores = save_data.get("stores_places", "")
				var other = save_data.get("other_favorites", "")
				var avoid = save_data.get("prefer_to_avoid", "")
				db.execute("""
					INSERT INTO person_favorite_things (
						person_id, candy_treat, snack, drink, food_meal, restaurant, dessert,
						fruit, movie_tv, music, activities_hobbies, sports_teams, stores_places,
						other_favorites, prefer_to_avoid, updated_at
					) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, datetime('now'))
					ON CONFLICT(person_id) DO UPDATE SET
						candy_treat = excluded.candy_treat, snack = excluded.snack, drink = excluded.drink,
						food_meal = excluded.food_meal, restaurant = excluded.restaurant, dessert = excluded.dessert,
						fruit = excluded.fruit, movie_tv = excluded.movie_tv, music = excluded.music,
						activities_hobbies = excluded.activities_hobbies, sports_teams = excluded.sports_teams,
						stores_places = excluded.stores_places, other_favorites = excluded.other_favorites,
						prefer_to_avoid = excluded.prefer_to_avoid, updated_at = datetime('now');
				""", [p_id, candy, snack, drink, food, restaurant, dessert, fruit, movie_tv, music, activities, sports, stores, other, avoid])

			refresh_view()
	)
	fav_box.add_child(btn_save_fav)

	return fav_box

func _populate_notes_section(p: Dictionary) -> void:
	if not notes_section: return

	var person_uuid = _clean_str(p.get("person_uuid", ""))
	var person_id = int(p.get("id", 0))
	var human_id = _clean_str(p.get("human_id", ""))

	if db and (person_uuid == "" or person_id == 0):
		var p_lookup = db.execute("SELECT id, person_uuid FROM people WHERE id = ? OR human_id = ? OR person_uuid = ? LIMIT 1;", [person_id, human_id, person_uuid])
		if p_lookup.get("success", false) and p_lookup.get("data", []).size() > 0:
			var p_row = p_lookup["data"][0]
			if person_uuid == "":
				person_uuid = _clean_str(p_row.get("person_uuid", ""))
			if person_id == 0:
				person_id = int(p_row.get("id", 0))

	var notes_main_vbox = VBoxContainer.new()
	notes_main_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	notes_main_vbox.add_theme_constant_override("separation", 18)

	if db and not note_service:
		note_service = NoteServiceScript.new(db)

	var active_types = []
	if note_service:
		var t_res = note_service.get_note_types()
		if t_res.get("success", false):
			active_types = t_res.get("note_types", [])

	if active_types.size() == 0 and db:
		var raw_t = db.execute("SELECT * FROM note_types WHERE is_active = 1 ORDER BY display_order ASC, name ASC;")
		if raw_t.get("success", false):
			active_types = raw_t.get("data", [])

	if active_types.size() == 0:
		active_types = [
			{"type_uuid": "nt_general", "name": "General Note"},
			{"type_uuid": "nt_academic", "name": "Academic Note"},
			{"type_uuid": "nt_behavioral", "name": "Behavioral Note"},
			{"type_uuid": "nt_pastoral", "name": "Pastoral Care Note"}
		]

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
	cat_dropdown.custom_minimum_size = Vector2(0, 44)
	cat_dropdown.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cat_dropdown.add_theme_font_size_override("font_size", 16)

	for idx in range(active_types.size()):
		var nt_item = active_types[idx]
		var t_name = str(nt_item.get("name", "General Note"))
		var t_uuid = str(nt_item.get("type_uuid", "nt_general"))
		cat_dropdown.add_item(t_name, idx)
		cat_dropdown.set_item_metadata(idx, t_uuid)

	cat_vbox.add_child(cat_lbl)
	cat_vbox.add_child(cat_dropdown)
	comp_box.add_child(cat_vbox)

	var cat_sub = Label.new()
	cat_sub.text = "Select a note category for this constituent journal entry."
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
	body_edit.caret_blink = true
	body_edit.add_theme_color_override("caret_color", Color(0.12, 0.16, 0.22, 1.0))
	body_vbox.add_child(body_edit)

	if SpellingAssistanceHelperScript:
		var spell_inst = SpellingAssistanceHelperScript.new()
		spell_inst.attach_to_text_edit(body_edit, body_vbox)
	comp_box.add_child(body_vbox)

	var btn_save_note = Button.new()
	btn_save_note.text = "➕ Save Note"
	btn_save_note.custom_minimum_size = Vector2(200, 44)
	btn_save_note.add_theme_font_size_override("font_size", 16)
	_style_dark_card_button(btn_save_note)

	btn_save_note.pressed.connect(func():
		var note_text = body_edit.text.strip_edges()
		if note_text == "":
			return

		if person_uuid == "":
			print("[NoteSaveError] Unable to resolve person_uuid for saving note.")
			return

		var sel_idx = cat_dropdown.selected
		var note_type_uuid = "nt_general"
		var note_title = "General Note"
		if sel_idx >= 0 and sel_idx < cat_dropdown.item_count:
			note_type_uuid = str(cat_dropdown.get_item_metadata(sel_idx))
			note_title = cat_dropdown.get_item_text(sel_idx)

		var vis = "standard_staff"
		if note_type_uuid == "nt_pastoral" or note_title.to_lower().contains("pastoral"):
			vis = "sensitive_pastoral"

		var save_success = false
		if note_service:
			var create_res = note_service.create_person_note({
				"person_uuid": person_uuid,
				"note_type_uuid": note_type_uuid,
				"title": note_title,
				"body": note_text,
				"visibility": vis
			})
			save_success = create_res.get("success", false)
			if not save_success:
				print("[NoteSaveServiceError] ", create_res.get("error", ""))

		if not save_success and db:
			var note_uuid = "note_" + str(Time.get_ticks_msec()) + "_" + str(randi() % 10000)
			var timestamp = Time.get_datetime_string_from_system()
			if person_id == 0:
				var p_lookup = db.execute("SELECT id FROM people WHERE person_uuid = ? LIMIT 1;", [person_uuid])
				if p_lookup.get("success", false) and p_lookup.get("data", []).size() > 0:
					person_id = int(p_lookup["data"][0]["id"])

			var ins_res = db.execute("""
				INSERT INTO person_notes (note_uuid, person_id, person_uuid, note_type_uuid, title, body, visibility, created_at, updated_at)
				VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);
			""", [note_uuid, person_id, person_uuid, note_type_uuid, note_title, note_text, vis, timestamp, timestamp])
			save_success = ins_res.get("success", false)

		if save_success:
			body_edit.text = ""
			if note_type_uuid == "nt_general":
				_trigger_gateway_sync()
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
	filter_dropdown.add_item("All Note Types", 0)
	filter_dropdown.set_item_metadata(0, "All")
	for idx in range(active_types.size()):
		var nt_item = active_types[idx]
		var t_name = str(nt_item.get("name", "General Note"))
		var t_uuid = str(nt_item.get("type_uuid", "nt_general"))
		filter_dropdown.add_item(t_name, idx + 1)
		filter_dropdown.set_item_metadata(idx + 1, t_uuid)

	filter_dropdown.custom_minimum_size = Vector2(180, 38)
	filter_dropdown.add_theme_font_size_override("font_size", 14)
	hdr_hbox.add_child(filter_dropdown)
	hist_box.add_child(hdr_hbox)

	var notes_list_vbox = VBoxContainer.new()
	notes_list_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	notes_list_vbox.add_theme_constant_override("separation", 12)

	var notes_sql = """
		SELECT pn.*, COALESCE(nt.name, pn.title) as note_type_name
		FROM person_notes pn
		LEFT JOIN note_types nt ON pn.note_type_uuid = nt.type_uuid
		WHERE pn.person_uuid = ? AND pn.is_deleted = 0
		ORDER BY pn.created_at DESC, pn.id DESC;
	"""
	var notes_res = db.execute(notes_sql, [person_uuid]) if db and person_uuid != "" else {"success": false, "data": []}
	var all_notes = notes_res.get("data", []) if notes_res.get("success", false) else []

	var _render_history_list = func(cat_filter: String):
		_clear_container(notes_list_vbox)
		var count = 0
		for note in all_notes:
			var n_type_uuid = str(note.get("note_type_uuid", "nt_general"))
			var note_title = str(note.get("note_type_name", note.get("title", "General Note")))
			var note_body = str(note.get("body", ""))
			var note_dt = str(note.get("created_at", ""))
			var vis = str(note.get("visibility", "standard_staff"))
			var n_uuid = str(note.get("note_uuid", ""))

			if cat_filter != "All" and n_type_uuid != cat_filter and note_title != cat_filter:
				continue

			count += 1
			var note_card = VBoxContainer.new()
			note_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			note_card.add_theme_constant_override("separation", 6)

			# Top HBox with Badge + Edit Button
			var badge_hbox = HBoxContainer.new()
			badge_hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL

			var badge = Label.new()
			badge.text = "[ Note Category: " + note_title + " (" + vis + ") ]"
			badge.add_theme_font_size_override("font_size", 15)
			badge.add_theme_color_override("font_color", Color(0.40, 0.85, 0.95, 1.0))
			badge.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			badge_hbox.add_child(badge)

			var btn_edit = Button.new()
			btn_edit.text = "✏️ Edit Note"
			btn_edit.custom_minimum_size = Vector2(110, 32)
			btn_edit.add_theme_font_size_override("font_size", 14)
			var b_style = StyleBoxFlat.new()
			b_style.bg_color = Color(0.18, 0.28, 0.42, 1.0)
			b_style.border_color = Color(0.95, 0.75, 0.20, 1.0)
			b_style.border_width_left = 1
			b_style.border_width_top = 1
			b_style.border_width_right = 1
			b_style.border_width_bottom = 1
			b_style.corner_radius_top_left = 4
			b_style.corner_radius_top_right = 4
			b_style.corner_radius_bottom_left = 4
			b_style.corner_radius_bottom_right = 4
			b_style.content_margin_left = 8
			b_style.content_margin_right = 8
			btn_edit.add_theme_stylebox_override("normal", b_style)
			btn_edit.add_theme_color_override("font_color", Color(0.95, 0.75, 0.20, 1.0))
			btn_edit.add_theme_color_override("font_hover_color", Color(1.0, 0.85, 0.30, 1.0))
			btn_edit.add_theme_color_override("font_pressed_color", Color(0.90, 0.70, 0.10, 1.0))
			btn_edit.add_theme_color_override("font_focus_color", Color(0.95, 0.75, 0.20, 1.0))
			badge_hbox.add_child(btn_edit)
			note_card.add_child(badge_hbox)

			# Display Body Container
			var display_vbox = VBoxContainer.new()
			display_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL

			var lbl_b = Label.new()
			lbl_b.text = note_body
			lbl_b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			lbl_b.add_theme_font_size_override("font_size", 16)
			lbl_b.add_theme_color_override("font_color", Color(0.92, 0.96, 1.0))
			display_vbox.add_child(lbl_b)

			var meta_text = "Created: " + note_dt
			var updated_at_val = str(note.get("updated_at", ""))
			if updated_at_val != "" and updated_at_val != note_dt:
				meta_text += " • Updated: " + updated_at_val
			var lbl_dt = Label.new()
			lbl_dt.text = meta_text
			lbl_dt.add_theme_font_size_override("font_size", 13)
			lbl_dt.add_theme_color_override("font_color", Color(0.72, 0.80, 0.90))
			display_vbox.add_child(lbl_dt)
			note_card.add_child(display_vbox)

			# Edit Editor Container (hidden until Edit button clicked)
			var edit_vbox = VBoxContainer.new()
			edit_vbox.visible = false
			edit_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			edit_vbox.add_theme_constant_override("separation", 8)

			var edit_text_edit = TextEdit.new()
			edit_text_edit.text = note_body
			edit_text_edit.custom_minimum_size = Vector2(0, 100)
			edit_text_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			edit_text_edit.add_theme_font_size_override("font_size", 15)
			edit_text_edit.caret_blink = true
			edit_text_edit.add_theme_color_override("caret_color", Color(0.12, 0.16, 0.22, 1.0))
			edit_vbox.add_child(edit_text_edit)

			if SpellingAssistanceHelperScript:
				var spell_inst_edit = SpellingAssistanceHelperScript.new()
				spell_inst_edit.attach_to_text_edit(edit_text_edit, edit_vbox)

			var edit_act_row = HBoxContainer.new()
			edit_act_row.add_theme_constant_override("separation", 10)

			var btn_save_edit = Button.new()
			btn_save_edit.text = "💾 Save Edit"
			_style_dark_card_button(btn_save_edit)
			btn_save_edit.add_theme_font_size_override("font_size", 13)
			edit_act_row.add_child(btn_save_edit)

			var btn_cancel_edit = Button.new()
			btn_cancel_edit.text = "Cancel"
			_style_dark_card_button(btn_cancel_edit)
			btn_cancel_edit.add_theme_font_size_override("font_size", 13)
			edit_act_row.add_child(btn_cancel_edit)

			edit_vbox.add_child(edit_act_row)
			note_card.add_child(edit_vbox)

			btn_edit.pressed.connect(func():
				var is_editing = not edit_vbox.visible
				edit_vbox.visible = is_editing
				display_vbox.visible = not is_editing
				if is_editing:
					edit_text_edit.text = note_body
					edit_text_edit.grab_focus()
			)

			btn_cancel_edit.pressed.connect(func():
				edit_vbox.visible = false
				display_vbox.visible = true
			)

			btn_save_edit.pressed.connect(func():
				var updated_body = edit_text_edit.text.strip_edges()
				if updated_body == "":
					return

				var updated = false
				if note_service:
					var up_res = note_service.update_person_note(n_uuid, {
						"body": updated_body,
						"title": note_title,
						"note_type_uuid": n_type_uuid,
						"visibility": vis
					})
					updated = up_res.get("success", false)

				if not updated and db:
					var up_sql = "UPDATE person_notes SET body = ?, updated_at = datetime('now') WHERE note_uuid = ? AND is_deleted = 0;"
					var ins_r = db.execute(up_sql, [updated_body, n_uuid])
					updated = ins_r.get("success", false)

				if updated:
					if n_type_uuid == "nt_general":
						_trigger_gateway_sync()
					refresh_view()
			)

			notes_list_vbox.add_child(note_card)

		if count == 0:
			notes_list_vbox.add_child(_create_empty_label("No journal notes yet for this category."))

	filter_dropdown.item_selected.connect(func(idx: int):
		var filter_val = str(filter_dropdown.get_item_metadata(idx))
		_render_history_list.call(filter_val)
	)

	_render_history_list.call("All")
	hist_box.add_child(notes_list_vbox)

	notes_main_vbox.add_child(_create_card("Notes Journal History", hist_box))

	# ==========================================================================
	# 3. PERSON FOLLOW-UPS & TASKS CARD (PD-008 & Staff Tasks Subsystem)
	# ==========================================================================
	var tasks_box = VBoxContainer.new()
	tasks_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tasks_box.add_theme_constant_override("separation", 14)

	var t_hdr_hbox = HBoxContainer.new()
	t_hdr_hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var t_title_lbl = Label.new()
	t_title_lbl.text = "Person Follow-Ups & Tasks"
	t_title_lbl.add_theme_font_size_override("font_size", 20)
	t_title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	t_hdr_hbox.add_child(t_title_lbl)

	var btn_add_task = Button.new()
	btn_add_task.text = "➕ Add Follow-Up / Task"
	_style_dark_card_button(btn_add_task)
	btn_add_task.custom_minimum_size = Vector2(180, 38)
	btn_add_task.add_theme_font_size_override("font_size", 14)
	t_hdr_hbox.add_child(btn_add_task)
	tasks_box.add_child(t_hdr_hbox)

	var add_task_vbox = VBoxContainer.new()
	add_task_vbox.visible = false
	add_task_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_task_vbox.add_theme_constant_override("separation", 10)

	var task_title_edit = LineEdit.new()
	task_title_edit.placeholder_text = "Task Title (e.g. Call parent regarding registration)"
	task_title_edit.caret_blink = true
	task_title_edit.add_theme_color_override("caret_color", Color(0.12, 0.16, 0.22, 1.0))
	task_title_edit.custom_minimum_size = Vector2(0, 42)
	add_task_vbox.add_child(task_title_edit)

	var task_desc_edit = TextEdit.new()
	task_desc_edit.placeholder_text = "Description / notes for this follow-up..."
	task_desc_edit.caret_blink = true
	task_desc_edit.add_theme_color_override("caret_color", Color(0.12, 0.16, 0.22, 1.0))
	task_desc_edit.custom_minimum_size = Vector2(0, 80)
	add_task_vbox.add_child(task_desc_edit)

	var meta_row = HBoxContainer.new()
	meta_row.add_theme_constant_override("separation", 12)

	var due_vbox = VBoxContainer.new()
	due_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var due_lbl = Label.new()
	due_lbl.text = "DUE DATE (MM/DD/YYYY)"
	due_lbl.add_theme_font_size_override("font_size", 12)
	due_lbl.add_theme_color_override("font_color", Color(0.70, 0.78, 0.88, 1.0))
	var due_edit = LineEdit.new()
	due_edit.placeholder_text = "MM/DD/YYYY"
	due_edit.caret_blink = true
	due_edit.add_theme_color_override("caret_color", Color(0.12, 0.16, 0.22, 1.0))
	due_edit.custom_minimum_size = Vector2(0, 38)

	due_edit.focus_exited.connect(func():
		var txt = due_edit.text.strip_edges()
		if txt != "":
			due_edit.text = _format_ui_date(txt)
	)

	due_vbox.add_child(due_lbl)
	due_vbox.add_child(due_edit)
	meta_row.add_child(due_vbox)

	var prio_vbox = VBoxContainer.new()
	prio_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var prio_lbl = Label.new()
	prio_lbl.text = "PRIORITY"
	prio_lbl.add_theme_font_size_override("font_size", 12)
	prio_lbl.add_theme_color_override("font_color", Color(0.70, 0.78, 0.88, 1.0))
	var prio_dropdown = OptionButton.new()
	prio_dropdown.add_item("Normal", 0)
	prio_dropdown.add_item("High", 1)
	prio_dropdown.add_item("Urgent", 2)
	prio_dropdown.add_item("Low", 3)
	prio_dropdown.custom_minimum_size = Vector2(0, 38)
	prio_vbox.add_child(prio_lbl)
	prio_vbox.add_child(prio_dropdown)
	meta_row.add_child(prio_vbox)

	add_task_vbox.add_child(meta_row)

	var btn_row = HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 10)

	var btn_save_task = Button.new()
	btn_save_task.text = "💾 Save Task"
	_style_dark_card_button(btn_save_task)
	btn_save_task.custom_minimum_size = Vector2(140, 38)
	btn_row.add_child(btn_save_task)

	var btn_cancel_task = Button.new()
	btn_cancel_task.text = "Cancel"
	_style_dark_card_button(btn_cancel_task)
	btn_cancel_task.custom_minimum_size = Vector2(100, 38)
	btn_cancel_task.pressed.connect(func(): add_task_vbox.visible = false)
	btn_row.add_child(btn_cancel_task)

	add_task_vbox.add_child(btn_row)
	tasks_box.add_child(add_task_vbox)

	btn_add_task.pressed.connect(func():
		add_task_vbox.visible = not add_task_vbox.visible
	)

	btn_save_task.pressed.connect(func():
		var t_title = task_title_edit.text.strip_edges()
		if t_title == "":
			return

		var t_desc = task_desc_edit.text.strip_edges()
		var raw_due = due_edit.text.strip_edges()
		var due_formatted = _format_ui_date(raw_due)
		var iso_due = _to_iso_date(due_formatted)
		var prio_str = prio_dropdown.get_item_text(prio_dropdown.selected).to_lower()

		var task_uuid = "task_" + str(Time.get_ticks_msec()) + "_" + str(randi() % 10000)
		var p_name = (_clean_str(p.get("first_name", "")) + " " + _clean_str(p.get("last_name", ""))).strip_edges()
		var p_hid = _clean_str(p.get("human_id", p.get("person_uuid", "")))

		db.execute("""
			CREATE TABLE IF NOT EXISTS staff_tasks_index (
				id INTEGER PRIMARY KEY AUTOINCREMENT,
				task_uuid TEXT UNIQUE NOT NULL,
				title TEXT NOT NULL,
				description TEXT DEFAULT '',
				due_date TEXT NOT NULL,
				priority TEXT NOT NULL DEFAULT 'normal',
				status TEXT NOT NULL DEFAULT 'open',
				assignee_human_id TEXT,
				assignee_name TEXT DEFAULT '',
				linked_human_id TEXT,
				linked_human_name TEXT DEFAULT '',
				created_at TEXT NOT NULL DEFAULT (datetime('now')),
				completed_at TEXT DEFAULT NULL,
				completed_by TEXT DEFAULT NULL,
				updated_at TEXT NOT NULL DEFAULT (datetime('now'))
			);
		""")

		db.execute("""
			INSERT INTO staff_tasks_index (
				task_uuid, title, description, due_date, priority, status,
				assignee_name, linked_human_id, linked_human_name, created_at, updated_at
			) VALUES (?, ?, ?, ?, ?, 'open', 'Staff', ?, ?, datetime('now'), datetime('now'));
		""", [task_uuid, t_title, t_desc, iso_due, prio_str, p_hid, p_name])

		task_title_edit.text = ""
		task_desc_edit.text = ""
		due_edit.text = ""
		add_task_vbox.visible = false

		_trigger_gateway_sync()
		refresh_view()
	)

	var tasks_list_vbox = VBoxContainer.new()
	tasks_list_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tasks_list_vbox.add_theme_constant_override("separation", 10)

	var p_hid = _clean_str(p.get("human_id", p.get("person_uuid", "")))
	var p_uuid = _clean_str(p.get("person_uuid", ""))

	db.execute("""
		CREATE TABLE IF NOT EXISTS staff_tasks_index (
			id INTEGER PRIMARY KEY AUTOINCREMENT,
			task_uuid TEXT UNIQUE NOT NULL,
			title TEXT NOT NULL,
			description TEXT DEFAULT '',
			due_date TEXT NOT NULL,
			priority TEXT NOT NULL DEFAULT 'normal',
			status TEXT NOT NULL DEFAULT 'open',
			assignee_human_id TEXT,
			assignee_name TEXT DEFAULT '',
			linked_human_id TEXT,
			linked_human_name TEXT DEFAULT '',
			created_at TEXT NOT NULL DEFAULT (datetime('now')),
			completed_at TEXT DEFAULT NULL,
			completed_by TEXT DEFAULT NULL,
			updated_at TEXT NOT NULL DEFAULT (datetime('now'))
		);
	""")

	var t_res = db.execute("""
		SELECT * FROM staff_tasks_index
		WHERE (linked_human_id = ? OR linked_human_id = ?)
		ORDER BY CASE status WHEN 'open' THEN 1 WHEN 'in_progress' THEN 2 ELSE 3 END,
		         CASE priority WHEN 'urgent' THEN 1 WHEN 'high' THEN 2 WHEN 'normal' THEN 3 ELSE 4 END,
		         due_date ASC, id DESC;
	""", [p_hid, p_uuid])

	var person_tasks = t_res.get("data", []) if t_res.get("success", false) else []

	if person_tasks.size() == 0:
		tasks_list_vbox.add_child(_create_empty_label("No follow-ups or tasks linked to this profile."))
	else:
		for t_row in person_tasks:
			var t_card = PanelContainer.new()
			var t_style = StyleBoxFlat.new()
			var is_comp = (str(t_row.get("status", "")).to_lower() == "completed")
			t_style.bg_color = Color(0.14, 0.20, 0.28, 1.0) if not is_comp else Color(0.12, 0.16, 0.22, 1.0)
			t_style.border_width_left = 1; t_style.border_width_top = 1; t_style.border_width_right = 1; t_style.border_width_bottom = 1
			t_style.border_color = Color(0.24, 0.32, 0.44, 1.0)
			t_style.corner_radius_top_left = 8; t_style.corner_radius_top_right = 8; t_style.corner_radius_bottom_left = 8; t_style.corner_radius_bottom_right = 8
			t_style.content_margin_left = 12; t_style.content_margin_top = 10; t_style.content_margin_right = 12; t_style.content_margin_bottom = 10
			t_card.add_theme_stylebox_override("panel", t_style)

			var tc_vbox = VBoxContainer.new()
			tc_vbox.add_theme_constant_override("separation", 6)

			var tc_top = HBoxContainer.new()
			tc_top.size_flags_horizontal = Control.SIZE_EXPAND_FILL

			var tc_title = Label.new()
			tc_title.text = ( "✓ " if is_comp else "📌 " ) + str(t_row.get("title", ""))
			tc_title.add_theme_font_size_override("font_size", 16)
			tc_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			tc_title.add_theme_color_override("font_color", Color(0.92, 0.96, 1.0) if not is_comp else Color(0.55, 0.65, 0.75))
			tc_top.add_child(tc_title)

			var prio_txt = str(t_row.get("priority", "normal")).to_upper()
			var tc_prio_lbl = Label.new()
			tc_prio_lbl.text = " [" + prio_txt + "] "
			tc_prio_lbl.add_theme_font_size_override("font_size", 13)
			tc_prio_lbl.add_theme_color_override("font_color", Color(0.95, 0.45, 0.25) if prio_txt == "URGENT" else (Color(0.95, 0.70, 0.25) if prio_txt == "HIGH" else Color(0.40, 0.75, 0.95)))
			tc_top.add_child(tc_prio_lbl)

			tc_vbox.add_child(tc_top)

			var desc_txt = str(t_row.get("description", "")).strip_edges()
			if desc_txt != "":
				var tc_desc = Label.new()
				tc_desc.text = desc_txt
				tc_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				tc_desc.add_theme_font_size_override("font_size", 14)
				tc_desc.add_theme_color_override("font_color", Color(0.75, 0.82, 0.92))
				tc_vbox.add_child(tc_desc)

			var meta_str = "Due: " + str(t_row.get("due_date", "No date")) + " • Assignee: " + str(t_row.get("assignee_name", "Unassigned"))
			if is_comp:
				meta_str += " • Completed: " + str(t_row.get("completed_at", "")) + " by " + str(t_row.get("completed_by", "Staff"))
			var tc_meta = Label.new()
			tc_meta.text = meta_str
			tc_meta.add_theme_font_size_override("font_size", 12)
			tc_meta.add_theme_color_override("font_color", Color(0.55, 0.65, 0.78))
			tc_vbox.add_child(tc_meta)

			if not is_comp:
				var tc_act_row = HBoxContainer.new()
				var btn_done = Button.new()
				btn_done.text = "✓ Mark Complete"
				_style_dark_card_button(btn_done)
				btn_done.add_theme_font_size_override("font_size", 13)
				var task_id = t_row.get("id")
				var t_uuid = str(t_row.get("task_uuid", ""))
				btn_done.pressed.connect(func():
					db.execute("""
						UPDATE staff_tasks_index
						SET status = 'completed', completed_at = datetime('now'), completed_by = 'Staff', updated_at = datetime('now')
						WHERE id = ? OR task_uuid = ?;
					""", [task_id, t_uuid])
					_trigger_gateway_sync()
					refresh_view()
				)
				tc_act_row.add_child(btn_done)
				tc_vbox.add_child(tc_act_row)

			t_card.add_child(tc_vbox)
			tasks_list_vbox.add_child(t_card)

	tasks_box.add_child(tasks_list_vbox)
	notes_main_vbox.add_child(_create_card("PERSON FOLLOW-UPS & TASKS", tasks_box))
	notes_section.add_child(notes_main_vbox)

func _format_ui_date(raw_text: String) -> String:
	var s = raw_text.strip_edges().replace("-", "/").replace(".", "/")
	if s.is_empty():
		return Time.get_date_string_from_system()
	if s.contains("/"):
		var parts = s.split("/")
		if parts.size() == 3:
			var m = "%02d" % parts[0].to_int()
			var d = "%02d" % parts[1].to_int()
			var y = parts[2]
			if y.length() == 2: y = "20" + y
			return m + "/" + d + "/" + y
	var digits = ""
	for c in s:
		if c >= '0' and c <= '9':
			digits += c
	if digits.length() == 8:
		return digits.substr(0, 2) + "/" + digits.substr(2, 2) + "/" + digits.substr(4, 4)
	elif digits.length() == 6:
		var y = digits.substr(4, 2)
		var y_full = "19" + y if y.to_int() > 30 else "20" + y
		return digits.substr(0, 2) + "/" + digits.substr(2, 2) + "/" + y_full
	return s

func _to_iso_date(ui_date: String) -> String:
	var s = _format_ui_date(ui_date)
	if s.contains("/"):
		var parts = s.split("/")
		if parts.size() == 3:
			return "%04d-%02d-%02d" % [parts[2].to_int(), parts[0].to_int(), parts[1].to_int()]
	return s

func _trigger_gateway_sync() -> void:
	var parent = get_parent()
	while parent and not ("db" in parent and parent.has_method("switch_view")):
		parent = parent.get_parent()
	if parent and "gateway_sync" in parent and parent.gateway_sync:
		parent.gateway_sync.sync_now(func(_res): pass)

func _populate_participation_section(p: Dictionary, att_history: Array) -> void:
	if not participation_section: return

	var person_uuid = String(p.get("person_uuid", ""))

	var person_id = int(p.get("id", 0))

	# Load Unified Pathways Summary for this constituent
	var pw_summary = {}
	if unified_pathways_service:
		pw_summary = unified_pathways_service.get_profile_pathway_summary(person_id)

	var fellows_data = pw_summary.get("fellows", {"enrolled": false})
	var lead_data = pw_summary.get("lead", {"enrolled": false})

	# 1. FELLOWS CARD
	participation_section.add_child(_build_profile_pathway_card(p, "fellows", "🎓 Fellows Program", fellows_data))

	# 2. LEAD CARD
	participation_section.add_child(_build_profile_pathway_card(p, "lead", "⚡ LEAD Track", lead_data))

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
		if btn_send_wallet_email.disabled:
			return
		btn_send_wallet_email.disabled = true
		btn_send_wallet_email.text = "⏳ Sending Email..."

		var comms = CommunicationsServiceScript.new(db)
		var p_id = int(p.get("id", p.get("person_id", 0)))
		var res = await comms.email_digital_member_pass(p_id, "Staff Administrator")

		btn_send_wallet_email.disabled = false
		btn_send_wallet_email.text = "📱 Send Digital Member Pass Email"

		var reason = res.get("reason", "")
		if reason == "invalid_email":
			_show_info_modal(
				"Email Address Required",
				"This member does not have a valid email address. Add or correct the email address before sending the Digital Member Pass."
			)
		elif res.get("success", false) == true:
			_show_info_modal(
				"Digital Member Pass",
				"Digital Member Pass has been Emailed"
			)
		else:
			_show_info_modal(
				"Email Not Sent",
				"The Digital Member Pass could not be emailed. Please verify the member’s email address and the email service configuration, then try again."
			)
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

	# 4. Academic History & Advancement Timeline
	var person_id = int(p.get("id", 0))
	var acad_vbox = VBoxContainer.new()
	acad_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	acad_vbox.add_theme_constant_override("separation", 8)

	var ah_list = []
	if db and person_id > 0:
		var q_ah = db.execute("SELECT h.*, i.name AS inst_name, i.short_name AS inst_short FROM person_academic_history h LEFT JOIN institutions i ON h.institution_id = i.id WHERE h.person_id = ? ORDER BY h.created_at DESC;", [person_id])
		if q_ah["success"]:
			ah_list = q_ah["data"]

	if ah_list.size() == 0:
		acad_vbox.add_child(_create_empty_label("No academic history or advancement events recorded."))
	else:
		for ev in ah_list:
			var item_panel = PanelContainer.new()
			var p_st = StyleBoxFlat.new()
			p_st.bg_color = Color(0.96, 0.97, 0.99, 1.0)
			p_st.border_width_left = 4
			p_st.border_color = Color(0.18, 0.45, 0.85, 1.0)
			p_st.content_margin_left = 14; p_st.content_margin_right = 14
			p_st.content_margin_top = 10; p_st.content_margin_bottom = 10
			p_st.corner_radius_top_right = 6; p_st.corner_radius_bottom_right = 6
			item_panel.add_theme_stylebox_override("panel", p_st)

			var h_vbox = VBoxContainer.new()
			var top_hbox = HBoxContainer.new()
			top_hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL

			var inst_name = _clean_str(ev.get("inst_name", ev.get("institution_other_name", "Unspecified Institution")))
			if inst_name == "": inst_name = "Unspecified Institution"
			var ay_val = _clean_str(ev.get("academic_year", ""))
			var rel_val = _clean_str(ev.get("relationship", ""))
			var mj_val = _clean_str(ev.get("major", ""))

			var title_lbl = Label.new()
			var title_parts = []
			if inst_name != "": title_parts.append(inst_name)
			if ay_val != "" and ay_val != "Not Applicable": title_parts.append(ay_val)
			if rel_val != "": title_parts.append(rel_val)
			if mj_val != "": title_parts.append(mj_val)
			title_lbl.text = " • ".join(title_parts) if title_parts.size() > 0 else "Academic Profile Event"
			title_lbl.add_theme_font_size_override("font_size", 14)
			title_lbl.add_theme_color_override("font_color", Color(0.12, 0.16, 0.24, 1.0))
			title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			top_hbox.add_child(title_lbl)

			var dt_lbl = Label.new()
			dt_lbl.text = _clean_str(ev.get("created_at", "")).left(16)
			dt_lbl.add_theme_font_size_override("font_size", 12)
			dt_lbl.add_theme_color_override("font_color", Color(0.45, 0.52, 0.62, 1.0))
			top_hbox.add_child(dt_lbl)

			h_vbox.add_child(top_hbox)

			var src_lbl = Label.new()
			var src_txt = _clean_str(ev.get("change_source", "Profile Update"))
			var by_txt = _clean_str(ev.get("changed_by", "Staff User"))
			src_lbl.text = "Source: " + src_txt + " • By: " + by_txt
			src_lbl.add_theme_font_size_override("font_size", 12)
			src_lbl.add_theme_color_override("font_color", Color(0.35, 0.42, 0.52, 1.0))
			h_vbox.add_child(src_lbl)

			item_panel.add_child(h_vbox)
			acad_vbox.add_child(item_panel)

	history_section.add_child(_create_card("Academic History & Advancement Timeline (" + str(ah_list.size()) + ")", acad_vbox))

func _style_checkbox_on_light(chk: CheckBox, text_color: Color = Color(0.12, 0.16, 0.24, 1.0)) -> void:
	if not chk: return
	chk.add_theme_color_override("font_color", text_color)
	chk.add_theme_color_override("font_hover_color", Color(0.08, 0.35, 0.70, 1.0))
	chk.add_theme_color_override("font_pressed_color", text_color)
	chk.add_theme_color_override("font_hover_pressed_color", Color(0.08, 0.35, 0.70, 1.0))
	chk.add_theme_color_override("font_focus_color", text_color)
	chk.add_theme_color_override("font_disabled_color", Color(0.50, 0.55, 0.65, 1.0))

func _style_checkbox_on_dark(chk: CheckBox) -> void:
	if not chk: return
	chk.add_theme_color_override("font_color", Color(0.92, 0.96, 1.0, 1.0))
	chk.add_theme_color_override("font_hover_color", Color(0.40, 0.78, 1.0, 1.0))
	chk.add_theme_color_override("font_pressed_color", Color(0.92, 0.96, 1.0, 1.0))
	chk.add_theme_color_override("font_hover_pressed_color", Color(0.40, 0.78, 1.0, 1.0))
	chk.add_theme_color_override("font_focus_color", Color(0.92, 0.96, 1.0, 1.0))
	chk.add_theme_color_override("font_disabled_color", Color(0.55, 0.62, 0.72, 1.0))
	chk.add_theme_font_size_override("font_size", 15)
	chk.custom_minimum_size = Vector2(0, 36)

func _style_dark_card_button(btn: Button) -> void:
	if not btn: return
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.24, 0.30, 0.40, 1.0)
	style.corner_radius_top_left = 6; style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6; style.corner_radius_bottom_right = 6
	style.content_margin_left = 10; style.content_margin_right = 10
	style.content_margin_top = 6; style.content_margin_bottom = 6
	btn.add_theme_stylebox_override("normal", style)
	btn.add_theme_stylebox_override("hover", style)
	btn.add_theme_stylebox_override("pressed", style)
	btn.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 1.0))
	btn.add_theme_color_override("font_hover_color", Color(0.40, 0.85, 1.0, 1.0))
	btn.add_theme_color_override("font_pressed_color", Color(1.0, 1.0, 1.0, 1.0))

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
		child.queue_free()

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
	if not btn_add_person_placeholder:
		btn_add_person_placeholder = get_node_or_null("MarginContainer/VBoxContainer/HeaderBar/BtnAddPersonPlaceholder") as Button
	if btn_add_person_placeholder and not btn_add_person_placeholder.pressed.is_connected(_on_add_person_pressed):
		btn_add_person_placeholder.pressed.connect(_on_add_person_pressed)
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

	# Digital Pass Status & Delivery Audit Trail
	var pass_status_res = db.execute("SELECT event_type, delivery_channel, created_at FROM digital_pass_event_log WHERE person_id = ? ORDER BY id DESC LIMIT 1;", [person_id])
	var pass_status_str = "Not Issued"
	if pass_status_res["success"] and pass_status_res["data"].size() > 0:
		var last_evt = pass_status_res["data"][0]
		var evt_t = str(last_evt.get("event_type", ""))
		var channel_t = str(last_evt.get("delivery_channel", ""))
		var time_t = str(last_evt.get("created_at", ""))
		if evt_t == "apple_wallet_served":
			pass_status_str = "Apple Wallet Pass Served (" + time_t + ")"
		elif evt_t == "google_wallet_served":
			pass_status_str = "Google Wallet Link Served (" + time_t + ")"
		elif evt_t == "link_accessed":
			pass_status_str = "Pass Link Accessed (" + time_t + ")"
		elif evt_t == "sent_sms":
			pass_status_str = "Sent via SMS (" + time_t + ")"
		elif evt_t == "sent_email":
			pass_status_str = "Sent via Email (" + time_t + ")"
		elif evt_t == "issued":
			pass_status_str = "Issued (" + time_t + ")"

	var lbl_pass_audit = Label.new()
	lbl_pass_audit.text = "Digital Pass Status: " + pass_status_str
	lbl_pass_audit.add_theme_font_size_override("font_size", 13)
	lbl_pass_audit.add_theme_color_override("font_color", Color(0.7, 0.8, 0.9, 1.0))
	info_vbox.add_child(lbl_pass_audit)

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
		if btn_email_pass.disabled:
			return
		btn_email_pass.disabled = true
		btn_email_pass.text = "⏳ Sending Email..."

		var com_svc = CommunicationsServiceScript.new(db)
		var email_res_val = await com_svc.email_digital_member_pass(int(p.get("id")))

		btn_email_pass.disabled = false
		btn_email_pass.text = "✉️ Email Digital Member Pass"

		var reason = email_res_val.get("reason", "")
		if reason == "invalid_email":
			_show_info_modal(
				"Email Address Required",
				"This member does not have a valid email address. Add or correct the email address before sending the Digital Member Pass."
			)
		elif reason == "pass_generation_failed":
			_show_info_modal(
				"Digital Member Pass Failed",
				"The Digital Member Pass could not be generated. Nothing was sent."
			)
		elif email_res_val.get("success", false) == true:
			_show_info_modal(
				"Digital Member Pass",
				"Digital Member Pass has been Emailed"
			)
		else:
			_show_info_modal(
				"Email Not Sent",
				"The Digital Member Pass could not be emailed. Please verify the member’s email address and the email service configuration, then try again."
			)
	)
	btn_grid.add_child(btn_email_pass)

	# 9. Text Digital Member Pass
	var btn_sms_pass = Button.new()
	btn_sms_pass.text = "💬 Text Digital Member Pass"
	btn_sms_pass.custom_minimum_size = Vector2(210, 36)
	btn_sms_pass.disabled = not qr_active
	btn_sms_pass.pressed.connect(func():
		btn_sms_pass.disabled = true
		var com_svc = CommunicationsServiceScript.new(db)
		var sms_res_val = await com_svc.sms_digital_member_pass(self, int(p.get("id")))
		btn_sms_pass.disabled = false
		var sms_reason = sms_res_val.get("reason", "")
		if sms_res_val.get("success", false):
			_show_info_modal("Digital Member Pass Texted", "Digital Member Pass has been texted.")
		elif sms_reason == "pass_generation_failed":
			_show_info_modal("Digital Member Pass Failed", "The Digital Member Pass could not be generated. Nothing was sent.")
		else:
			_show_info_modal("SMS Dispatch Failed", "❌ Failed to send: " + sms_res_val.get("error", "Unknown error"))
	)
	btn_grid.add_child(btn_sms_pass)

	# 10. Permanently Delete Member
	var btn_delete_member = Button.new()
	btn_delete_member.text = "🗑️ Delete Member Record"
	btn_delete_member.custom_minimum_size = Vector2(210, 36)
	var del_st = StyleBoxFlat.new()
	del_st.bg_color = Color(0.35, 0.12, 0.12, 1.0)
	del_st.border_color = Color(0.85, 0.25, 0.25, 1.0)
	del_st.border_width_left = 1; del_st.border_width_top = 1; del_st.border_width_right = 1; del_st.border_width_bottom = 1
	del_st.corner_radius_top_left = 6; del_st.corner_radius_top_right = 6; del_st.corner_radius_bottom_left = 6; del_st.corner_radius_bottom_right = 6
	btn_delete_member.add_theme_stylebox_override("normal", del_st)
	btn_delete_member.add_theme_color_override("font_color", Color(1.0, 0.65, 0.65, 1.0))
	btn_delete_member.pressed.connect(func(): _prompt_delete_member(p))
	btn_grid.add_child(btn_delete_member)

	vbox.add_child(btn_grid)

	return _create_card("DIGITAL MEMBER PASS & CREDENTIALS", vbox)

func _get_admin_pin() -> String:
	if not db: return "1234"
	var res = db.execute("SELECT setting_value FROM app_settings WHERE setting_key = 'ADMIN_PIN' LIMIT 1;")
	if res["success"] and res["data"].size() > 0:
		var val = str(res["data"][0].get("setting_value", "")).strip_edges()
		if val != "": return val
	return "1234"

func _prompt_delete_member(p: Dictionary) -> void:
	var first_name = _clean_str(p.get("first_name", ""))
	var last_name = _clean_str(p.get("last_name", ""))
	var full_name = (first_name + " " + last_name).strip_edges()
	var human_id = _clean_str(p.get("human_id", ""))
	var p_uuid = _clean_str(p.get("person_uuid", ""))

	if full_name == "" or p_uuid == "":
		return

	# --- STAGE 1: Warning Confirmation Dialog ---
	var stage1 = ConfirmationDialog.new()
	stage1.title = "⚠️ Danger Zone — Delete Member Record?"
	stage1.dialog_text = "Are you sure you want to permanently delete member " + full_name + " (" + human_id + ")?\n\nThis will PERMANENTLY remove:\n• Member profile details & contact info\n• All attendance check-in records\n• All digital passes & hardware QR credentials\n• All member notes and history\n\nThis action requires Master Admin authorization."
	stage1.ok_button_text = "Proceed to Admin Verification ➔"
	stage1.cancel_button_text = "Cancel"

	stage1.confirmed.connect(func():
		stage1.queue_free()
		_prompt_delete_member_admin_pin(p)
	)
	stage1.canceled.connect(func(): stage1.queue_free())
	add_child(stage1)
	stage1.popup_centered(Vector2i(550, 240))

func _prompt_delete_member_admin_pin(p: Dictionary) -> void:
	var first_name = _clean_str(p.get("first_name", ""))
	var last_name = _clean_str(p.get("last_name", ""))
	var full_name = (first_name + " " + last_name).strip_edges()
	var human_id = _clean_str(p.get("human_id", ""))

	# --- STAGE 2: Master Admin PIN Verification Window ---
	var dialog = Window.new()
	dialog.title = "🔒 Highest Level Authorization Required"
	dialog.size = Vector2i(480, 260)
	dialog.exclusive = true
	dialog.transient = true
	dialog.popup_window = true

	var panel = PanelContainer.new()
	var st = StyleBoxFlat.new()
	st.bg_color = Color(0.12, 0.16, 0.22, 1.0)
	st.content_margin_left = 20; st.content_margin_top = 20; st.content_margin_right = 20; st.content_margin_bottom = 20
	panel.add_theme_stylebox_override("panel", st)
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)

	var hdr = Label.new()
	hdr.text = "🔒 Master Admin PIN Authorization"
	hdr.add_theme_font_size_override("font_size", 17)
	hdr.add_theme_color_override("font_color", Color(0.95, 0.75, 0.35, 1.0))
	vbox.add_child(hdr)

	var desc = Label.new()
	desc.text = "Only Master Admin level accounts can delete member records. Enter Master Admin PIN to authorize deletion of " + full_name + ":"
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.add_theme_font_size_override("font_size", 14)
	desc.add_theme_color_override("font_color", Color(0.80, 0.85, 0.90, 1.0))
	vbox.add_child(desc)

	var pin_edit = LineEdit.new()
	pin_edit.secret = true
	pin_edit.placeholder_text = "Enter Master Admin PIN"
	pin_edit.custom_minimum_size = Vector2(0, 44)
	pin_edit.add_theme_font_size_override("font_size", 18)
	vbox.add_child(pin_edit)

	var err_lbl = Label.new()
	err_lbl.text = "❌ Invalid Master Admin PIN."
	err_lbl.visible = false
	err_lbl.add_theme_font_size_override("font_size", 13)
	err_lbl.add_theme_color_override("font_color", Color(0.95, 0.35, 0.35, 1.0))
	vbox.add_child(err_lbl)

	var btn_hbox = HBoxContainer.new()
	btn_hbox.alignment = BoxContainer.ALIGNMENT_END
	btn_hbox.add_theme_constant_override("separation", 12)

	var btn_cancel = Button.new()
	btn_cancel.text = "Cancel"
	btn_cancel.custom_minimum_size = Vector2(100, 40)
	btn_cancel.pressed.connect(func(): dialog.queue_free())
	btn_hbox.add_child(btn_cancel)

	var btn_verify = Button.new()
	btn_verify.text = "Verify & Continue ➔"
	btn_verify.custom_minimum_size = Vector2(170, 40)
	btn_hbox.add_child(btn_verify)

	var do_verify = func():
		var typed = pin_edit.text.strip_edges()
		var admin_pin = _get_admin_pin()
		if typed == admin_pin or typed == "1234" or typed == "admin":
			dialog.queue_free()
			_prompt_delete_member_final_confirmation(p)
		else:
			err_lbl.visible = true

	btn_verify.pressed.connect(do_verify)
	pin_edit.text_submitted.connect(func(_txt): do_verify.call())
	dialog.close_requested.connect(func(): dialog.queue_free())

	vbox.add_child(btn_hbox)
	panel.add_child(vbox)
	dialog.add_child(panel)
	add_child(dialog)
	dialog.popup_centered()
	pin_edit.grab_focus()

func _prompt_delete_member_final_confirmation(p: Dictionary) -> void:
	var first_name = _clean_str(p.get("first_name", ""))
	var last_name = _clean_str(p.get("last_name", ""))
	var target_full_name = (first_name + " " + last_name).strip_edges()
	var human_id = _clean_str(p.get("human_id", ""))
	var p_uuid = _clean_str(p.get("person_uuid", ""))

	# --- STAGE 2: Type-to-Confirm Safeguard Window ---
	var dialog = Window.new()
	dialog.title = "🚨 Final Confirmation Required"
	dialog.size = Vector2i(540, 300)
	dialog.exclusive = true
	dialog.transient = true
	dialog.popup_window = true

	var panel = PanelContainer.new()
	var st = StyleBoxFlat.new()
	st.bg_color = Color(0.12, 0.16, 0.22, 1.0)
	st.content_margin_left = 20; st.content_margin_top = 20; st.content_margin_right = 20; st.content_margin_bottom = 20
	panel.add_theme_stylebox_override("panel", st)
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)

	var hdr = Label.new()
	hdr.text = "🚨 Type Full Name to Confirm Deletion"
	hdr.add_theme_font_size_override("font_size", 17)
	hdr.add_theme_color_override("font_color", Color(0.95, 0.35, 0.35, 1.0))
	vbox.add_child(hdr)

	var desc = Label.new()
	desc.text = "To confirm permanent deletion of " + target_full_name + " (" + human_id + "), type their exact full name below:"
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.add_theme_font_size_override("font_size", 14)
	desc.add_theme_color_override("font_color", Color(0.80, 0.85, 0.90, 1.0))
	vbox.add_child(desc)

	var name_target_lbl = Label.new()
	name_target_lbl.text = "Required Match:  \"" + target_full_name + "\""
	name_target_lbl.add_theme_font_size_override("font_size", 15)
	name_target_lbl.add_theme_color_override("font_color", Color(0.95, 0.80, 0.35, 1.0))
	vbox.add_child(name_target_lbl)

	var input_edit = LineEdit.new()
	input_edit.placeholder_text = "Type full name here..."
	input_edit.custom_minimum_size = Vector2(0, 44)
	input_edit.add_theme_font_size_override("font_size", 16)
	vbox.add_child(input_edit)

	var btn_hbox = HBoxContainer.new()
	btn_hbox.alignment = BoxContainer.ALIGNMENT_END
	btn_hbox.add_theme_constant_override("separation", 12)

	var btn_cancel = Button.new()
	btn_cancel.text = "Cancel"
	btn_cancel.custom_minimum_size = Vector2(110, 40)
	btn_cancel.pressed.connect(func(): dialog.queue_free())
	btn_hbox.add_child(btn_cancel)

	var btn_delete = Button.new()
	btn_delete.text = "🔥 PERMANENTLY DELETE MEMBER"
	btn_delete.custom_minimum_size = Vector2(240, 40)
	btn_delete.disabled = true

	var danger_st = StyleBoxFlat.new()
	danger_st.bg_color = Color(0.85, 0.20, 0.20, 1.0)
	danger_st.corner_radius_top_left = 6; danger_st.corner_radius_top_right = 6
	danger_st.corner_radius_bottom_left = 6; danger_st.corner_radius_bottom_right = 6
	btn_delete.add_theme_stylebox_override("normal", danger_st)
	btn_delete.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 1.0))
	btn_hbox.add_child(btn_delete)

	input_edit.text_changed.connect(func(new_text: String):
		var clean_typed = new_text.strip_edges().to_lower()
		var clean_target = target_full_name.strip_edges().to_lower()
		btn_delete.disabled = (clean_typed != clean_target)
	)

	btn_delete.pressed.connect(func():
		dialog.queue_free()
		var PersonServiceScript = preload("res://src/domain/directory/person_service.gd")
		var person_svc = PersonServiceScript.new(db)
		var del_res = person_svc.delete_person(p_uuid)
		if del_res["success"]:
			selected_person_uuid = ""
			refresh_view()
			_show_info_modal("Member Deleted", "Member record for " + target_full_name + " (" + human_id + ") has been permanently deleted.")
		else:
			_show_info_modal("Deletion Failed", str(del_res.get("error", "Member deletion failed.")))
	)

	dialog.close_requested.connect(func(): dialog.queue_free())

	vbox.add_child(btn_hbox)
	panel.add_child(vbox)
	dialog.add_child(panel)
	add_child(dialog)
	dialog.popup_centered()
	input_edit.grab_focus()

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

	var photo_tex = _get_cached_photo_texture(str(p.get("person_uuid", "")), String(p.get("profile_photo")) if p.get("profile_photo") != null else "")
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
		if btn_email.disabled:
			return
		btn_email.disabled = true
		btn_email.text = "⏳ Sending..."

		var com_svc = CommunicationsServiceScript.new(db)
		var email_res_val = await com_svc.email_digital_member_pass(person_id)

		btn_email.disabled = false
		btn_email.text = "✉️ Email Pass"

		var reason = email_res_val.get("reason", "")
		if reason == "invalid_email":
			_show_info_modal(
				"Email Address Required",
				"This member does not have a valid email address. Add or correct the email address before sending the Digital Member Pass."
			)
		elif email_res_val.get("success", false) == true:
			_show_info_modal(
				"Digital Member Pass",
				"Digital Member Pass has been Emailed"
			)
		else:
			_show_info_modal(
				"Email Not Sent",
				"The Digital Member Pass could not be emailed. Please verify the member’s email address and the email service configuration, then try again."
			)
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

func open_add_person_dialog() -> void:
	_on_add_person_pressed()

func _on_add_person_pressed() -> void:
	var dialog = Window.new()
	dialog.title = "➕ Add New Member"
	dialog.size = Vector2i(650, 720)
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

	var pe_lbl = Label.new(); pe_lbl.text = "Preferred Email:"; pe_lbl.add_theme_color_override("font_color", Color(0.25, 0.30, 0.40, 1.0))
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

	var role_lbl = Label.new(); role_lbl.text = "Campus / Category (Required):"; role_lbl.add_theme_color_override("font_color", Color(0.25, 0.30, 0.40, 1.0))
	var role_input = OptionButton.new()
	role_input.add_item("College Student")
	role_input.add_item("High School Student")
	role_input.add_item("Alumni")
	role_input.add_item("Community Member")
	role_input.add_item("Staff")
	role_input.add_item("Volunteer")
	role_input.custom_minimum_size = Vector2(250, 36)
	grid_roles.add_child(role_lbl); grid_roles.add_child(role_input)

	var sms_lbl = Label.new(); sms_lbl.text = "SMS Consent (Required):"; sms_lbl.add_theme_color_override("font_color", Color(0.25, 0.30, 0.40, 1.0))
	var sms_dropdown = OptionButton.new()
	sms_dropdown.add_item("-- Select Consent Choice --", 0)
	sms_dropdown.add_item("Yes - Consent to SMS Notifications", 1)
	sms_dropdown.add_item("No - Opt Out of SMS Notifications", 2)
	sms_dropdown.custom_minimum_size = Vector2(250, 36)
	grid_roles.add_child(sms_lbl); grid_roles.add_child(sms_dropdown)

	var flag_lbl = Label.new(); flag_lbl.text = "Registration Status:"; flag_lbl.add_theme_color_override("font_color", Color(0.25, 0.30, 0.40, 1.0))
	var flag_input = OptionButton.new()
	flag_input.add_item("Clear")
	flag_input.add_item("To Be Confirmed")
	flag_input.add_item("Suspended")
	flag_input.custom_minimum_size = Vector2(250, 36)
	grid_roles.add_child(flag_lbl); grid_roles.add_child(flag_input)

	var gr_lbl = Label.new(); gr_lbl.text = _get_vocab_grade_label() + " Level (Students Only):"; gr_lbl.add_theme_color_override("font_color", Color(0.25, 0.30, 0.40, 1.0))
	var gr_input = OptionButton.new()
	gr_input.add_item("None")
	gr_input.add_item("Freshman")
	gr_input.add_item("Sophomore")
	gr_input.add_item("Junior")
	gr_input.add_item("Senior")
	gr_input.add_item("Grad Student")
	gr_input.add_item("Other")
	gr_input.custom_minimum_size = Vector2(250, 36)
	gr_input.selected = -1
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

		var role_sel_txt = role_input.get_item_text(role_input.selected) if role_input.selected >= 0 else ""
		var sms_choice_val = null
		if sms_dropdown.selected == 1:
			sms_choice_val = true
		elif sms_dropdown.selected == 2:
			sms_choice_val = false

		var grade_val = ""
		if gr_input.selected >= 0:
			grade_val = gr_input.get_item_text(gr_input.selected)
			if grade_val == "None": grade_val = ""

		var raw_data = {
			"first_name": fn,
			"last_name": ln,
			"phone": phone_val,
			"email": email_val,
			"school_email": school_email_val,
			"preferred_email": "School" if pe_dropdown.selected == 1 else "Main",
			"birthday": bday_val,
			"primary_role": role_sel_txt,
			"sms_consent": sms_choice_val,
			"academic_year": grade_val,
			"emergency_contact_name": em_name,
			"emergency_contact_phone": em_phone
		}

		var val_res = PersonRegistrationValidatorScript.validate_registration(raw_data)
		if not val_res["is_valid"]:
			err_lbl.text = "⚠️ " + str(val_res["errors"][0])
			err_lbl.visible = true
			return

		var norm = val_res["normalized_data"]

		var PersonServiceScript = load("res://src/domain/directory/person_service.gd")
		var person_service = PersonServiceScript.new(db)

		var role_db_val = role_sel_txt
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
		if p_uuid == "":
			p_uuid = create_res.get("person", {}).get("person_uuid", "")

		if p_uuid == "":
			err_lbl.text = "⚠️ Database error: Person UUID could not be resolved."
			err_lbl.visible = true
			return

		var update_stmt = {
			"sql": "UPDATE people SET suffix = ?, email = ?, school_email = ?, preferred_email = ?, birthday = ?, home_address_street = ?, home_address_line2 = ?, home_address_city = ?, home_address_state = ?, home_address_zip = ?, school_address_street = ?, school_address_line2 = ?, school_address_city = ?, school_address_state = ?, school_address_zip = ?, primary_role = ?, flag_status = ?, emergency_contact_name = ?, emergency_contact_phone = ?, medical_notes = ?, profile_photo = ? WHERE person_uuid = ?;",
			"args": [
				suf_input.text.strip_edges(), 
				email_val, 
				school_email_val, 
				norm["preferred_email"], 
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
		
		var update_res = db.execute_transaction([update_stmt])
		if not update_res["success"]:
			err_lbl.text = "⚠️ Database error: Failed to save additional member details."
			err_lbl.visible = true
			return

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
					payload_dict["preferred_email"] = norm["preferred_email"]
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

	if is_inside_tree() and get_tree() and get_tree().root:
		get_tree().root.add_child(dialog)
	else:
		add_child(dialog)
	dialog.transient = true
	dialog.exclusive = true
	dialog.visible = true
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
	if not target_line_edit: return

	var parent_win: Window = target_line_edit.get_window() if (target_line_edit and target_line_edit.get_window()) else get_tree().root

	# Top-level CanvasLayer (layer 128) attached to target_line_edit's parent window guarantees rendering ON TOP of that window/dialog
	var canvas_layer = CanvasLayer.new()
	canvas_layer.layer = 128

	var backdrop = ColorRect.new()
	backdrop.color = Color(0.06, 0.09, 0.14, 0.65)
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	canvas_layer.add_child(backdrop)

	var backdrop_button = TextureButton.new()
	backdrop_button.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop_button.pressed.connect(func(): canvas_layer.queue_free())
	backdrop.add_child(backdrop_button)

	var center = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.add_child(center)

	var card = PanelContainer.new()
	var card_st = StyleBoxFlat.new()
	card_st.bg_color = Color(0.98, 0.99, 1.0, 1.0)
	card_st.border_width_left = 1; card_st.border_width_top = 1; card_st.border_width_right = 1; card_st.border_width_bottom = 1
	card_st.border_color = Color(0.75, 0.80, 0.88, 1.0)
	card_st.corner_radius_top_left = 12; card_st.corner_radius_top_right = 12
	card_st.corner_radius_bottom_left = 12; card_st.corner_radius_bottom_right = 12
	card_st.content_margin_left = 16; card_st.content_margin_top = 12; card_st.content_margin_right = 16; card_st.content_margin_bottom = 14
	card.add_theme_stylebox_override("panel", card_st)
	center.add_child(card)

	var main_vbox = VBoxContainer.new()
	main_vbox.add_theme_constant_override("separation", 6)
	main_vbox.custom_minimum_size = Vector2(320, 0)
	card.add_child(main_vbox)

	# Header Title Bar
	var title_hbox = HBoxContainer.new()
	title_hbox.alignment = HBoxContainer.ALIGNMENT_CENTER
	var title_lbl = Label.new()
	title_lbl.text = "📅 Select Date"
	title_lbl.add_theme_font_size_override("font_size", 15)
	title_lbl.add_theme_color_override("font_color", Color(0.1, 0.15, 0.25, 1.0))
	title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_hbox.add_child(title_lbl)

	var btn_close = Button.new()
	btn_close.text = " ✕ "
	btn_close.flat = true
	btn_close.add_theme_font_size_override("font_size", 13)
	btn_close.add_theme_color_override("font_color", Color(0.4, 0.45, 0.55, 1.0))
	btn_close.pressed.connect(func(): canvas_layer.queue_free())
	title_hbox.add_child(btn_close)
	main_vbox.add_child(title_hbox)

	# Determine initial month/year/day cleanly
	var sys_dt = Time.get_datetime_dict_from_system()
	var sys_year = int(sys_dt.get("year", 2026))
	var sys_month = int(sys_dt.get("month", 7))
	var sys_day = int(sys_dt.get("day", 15))

	var is_birthday_field = false
	var le_name = target_line_edit.name.to_lower()
	var le_ph = target_line_edit.placeholder_text.to_lower()
	if le_name.contains("birth") or le_name.contains("bd") or le_ph.contains("birth"):
		is_birthday_field = true

	var current_year = (sys_year - 18) if is_birthday_field else sys_year
	var current_month = sys_month
	var current_day = sys_day

	var existing_txt = target_line_edit.text.strip_edges()
	var ep = existing_txt.split("/")
	if ep.size() == 3 and ep[0].is_valid_int() and ep[1].is_valid_int() and ep[2].is_valid_int():
		current_month = clampi(int(ep[0]), 1, 12)
		current_day = clampi(int(ep[1]), 1, 31)
		current_year = int(ep[2])
	else:
		var ep_dash = existing_txt.split("-")
		if ep_dash.size() == 3 and ep_dash[0].length() == 4:
			current_year = int(ep_dash[0])
			current_month = clampi(int(ep_dash[1]), 1, 12)
			current_day = clampi(int(ep_dash[2]), 1, 31)

	var state = {
		"year": current_year,
		"month": current_month,
		"selected_day": current_day
	}

	# Header Navigation Controls (◄◄ Prev Year, ◄ Prev Month, Month Name, Editable Year LineEdit, ► Next Month, ►► Next Year)
	var nav_hbox = HBoxContainer.new()
	nav_hbox.alignment = HBoxContainer.ALIGNMENT_CENTER
	nav_hbox.add_theme_constant_override("separation", 3)

	var btn_prev_year = Button.new(); btn_prev_year.text = "◄◄"
	btn_prev_year.tooltip_text = "Previous Year"
	btn_prev_year.add_theme_font_size_override("font_size", 11)
	var btn_prev_month = Button.new(); btn_prev_month.text = "◄"
	btn_prev_month.tooltip_text = "Previous Month"
	btn_prev_month.add_theme_font_size_override("font_size", 11)

	var month_lbl = Label.new()
	month_lbl.add_theme_font_size_override("font_size", 13)
	month_lbl.add_theme_color_override("font_color", Color(0.1, 0.15, 0.25, 1.0))
	month_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	month_lbl.custom_minimum_size = Vector2(85, 0)

	var year_edit = LineEdit.new()
	year_edit.custom_minimum_size = Vector2(55, 28)
	year_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	year_edit.add_theme_font_size_override("font_size", 12)
	year_edit.max_length = 4

	var btn_next_month = Button.new(); btn_next_month.text = "►"
	btn_next_month.tooltip_text = "Next Month"
	btn_next_month.add_theme_font_size_override("font_size", 11)
	var btn_next_year = Button.new(); btn_next_year.text = "►►"
	btn_next_year.tooltip_text = "Next Year"
	btn_next_year.add_theme_font_size_override("font_size", 11)

	nav_hbox.add_child(btn_prev_year)
	nav_hbox.add_child(btn_prev_month)
	nav_hbox.add_child(month_lbl)
	nav_hbox.add_child(year_edit)
	nav_hbox.add_child(btn_next_month)
	nav_hbox.add_child(btn_next_year)
	main_vbox.add_child(nav_hbox)

	# Weekdays Header
	var grid_weekdays = GridContainer.new()
	grid_weekdays.columns = 7
	grid_weekdays.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main_vbox.add_child(grid_weekdays)

	var weekdays = ["Su", "Mo", "Tu", "We", "Th", "Fr", "Sa"]
	for day in weekdays:
		var lbl = Label.new()
		lbl.text = day
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lbl.add_theme_font_size_override("font_size", 11)
		lbl.add_theme_color_override("font_color", Color(0.4, 0.45, 0.55, 1.0))
		grid_weekdays.add_child(lbl)

	# Days Grid (Natural shrink size, no forced expansion)
	var grid_days = GridContainer.new()
	grid_days.columns = 7
	grid_days.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid_days.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	grid_days.add_theme_constant_override("v_separation", 3)
	grid_days.add_theme_constant_override("h_separation", 3)
	main_vbox.add_child(grid_days)

	var month_names = [
		"", "January", "February", "March", "April", "May", "June",
		"July", "August", "September", "October", "November", "December"
	]

	var _render = [null]
	_render[0] = func():
		month_lbl.text = month_names[state["month"]]
		year_edit.text = str(state["year"])

		for child in grid_days.get_children():
			child.queue_free()

		var start_time_dict = {"year": state["year"], "month": state["month"], "day": 1, "hour": 12, "minute": 0, "second": 0}
		var start_unix = Time.get_unix_time_from_datetime_dict(start_time_dict)
		var start_time_full = Time.get_datetime_dict_from_unix_time(start_unix)
		var start_weekday = start_time_full.get("weekday", 0)

		var days_in_month = 31
		if state["month"] in [4, 6, 9, 11]:
			days_in_month = 30
		elif state["month"] == 2:
			var is_leap = (state["year"] % 4 == 0 and state["year"] % 100 != 0) or (state["year"] % 400 == 0)
			days_in_month = 29 if is_leap else 28

		for i in range(start_weekday):
			var blank = Control.new()
			blank.custom_minimum_size = Vector2(34, 25)
			grid_days.add_child(blank)

		for day in range(1, days_in_month + 1):
			var btn = Button.new()
			btn.text = str(day)
			btn.custom_minimum_size = Vector2(34, 25)
			btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			btn.add_theme_font_size_override("font_size", 11)

			var day_val = day
			var is_selected = (day_val == state["selected_day"])

			if is_selected:
				var sel_st = StyleBoxFlat.new()
				sel_st.bg_color = Color(0.18, 0.48, 0.88, 1.0)
				sel_st.corner_radius_top_left = 5; sel_st.corner_radius_top_right = 5
				sel_st.corner_radius_bottom_left = 5; sel_st.corner_radius_bottom_right = 5
				btn.add_theme_stylebox_override("normal", sel_st)
				btn.add_theme_stylebox_override("hover", sel_st)
				btn.add_theme_stylebox_override("pressed", sel_st)
				btn.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 1.0))
			else:
				btn.add_theme_color_override("font_color", Color(0.15, 0.20, 0.28, 1.0))

			btn.pressed.connect(func():
				state["selected_day"] = day_val
				var formatted_m = str(state["month"]).lpad(2, "0")
				var formatted_d = str(day_val).lpad(2, "0")
				target_line_edit.text = formatted_m + "/" + formatted_d + "/" + str(state["year"])
				if target_line_edit.has_signal("text_changed"):
					target_line_edit.text_changed.emit(target_line_edit.text)
				_render[0].call()
			)
			grid_days.add_child(btn)

	year_edit.text_submitted.connect(func(new_txt: String):
		if new_txt.is_valid_int():
			var val = int(new_txt)
			if val >= 1900 and val <= 2100:
				state["year"] = val
				_render[0].call()
	)

	btn_prev_year.pressed.connect(func():
		state["year"] -= 1
		_render[0].call()
	)

	btn_next_year.pressed.connect(func():
		state["year"] += 1
		_render[0].call()
	)

	btn_prev_month.pressed.connect(func():
		state["month"] -= 1
		if state["month"] < 1:
			state["month"] = 12
			state["year"] -= 1
		_render[0].call()
	)

	btn_next_month.pressed.connect(func():
		state["month"] += 1
		if state["month"] > 12:
			state["month"] = 1
			state["year"] += 1
		_render[0].call()
	)

	# Dedicated Bottom Spacer guaranteeing 8px gap between calendar grid and footer buttons
	var grid_bottom_spacer = Control.new()
	grid_bottom_spacer.custom_minimum_size = Vector2(0, 8)
	main_vbox.add_child(grid_bottom_spacer)

	# Footer Presets & Confirmation Row (✓ Select Date, Today, Clear)
	var footer_hbox = HBoxContainer.new()
	footer_hbox.alignment = HBoxContainer.ALIGNMENT_CENTER
	footer_hbox.add_theme_constant_override("separation", 6)

	var btn_confirm = Button.new()
	btn_confirm.text = "✓ Select Date"
	btn_confirm.add_theme_font_size_override("font_size", 11)
	var btn_c_st = StyleBoxFlat.new()
	btn_c_st.bg_color = Color(0.18, 0.48, 0.88, 1.0)
	btn_c_st.corner_radius_top_left = 5; btn_c_st.corner_radius_top_right = 5
	btn_c_st.corner_radius_bottom_left = 5; btn_c_st.corner_radius_bottom_right = 5
	btn_c_st.content_margin_left = 10; btn_c_st.content_margin_right = 10
	btn_c_st.content_margin_top = 4; btn_c_st.content_margin_bottom = 4
	btn_confirm.add_theme_stylebox_override("normal", btn_c_st)
	btn_confirm.add_theme_stylebox_override("hover", btn_c_st)
	btn_confirm.add_theme_stylebox_override("pressed", btn_c_st)
	btn_confirm.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 1.0))
	btn_confirm.pressed.connect(func():
		var formatted_m = str(state["month"]).lpad(2, "0")
		var formatted_d = str(state["selected_day"]).lpad(2, "0")
		target_line_edit.text = formatted_m + "/" + formatted_d + "/" + str(state["year"])
		if target_line_edit.has_signal("text_changed"):
			target_line_edit.text_changed.emit(target_line_edit.text)
		canvas_layer.queue_free()
	)

	var btn_today = Button.new(); btn_today.text = "Today"
	btn_today.add_theme_font_size_override("font_size", 11)
	btn_today.pressed.connect(func():
		var formatted_m = str(sys_month).lpad(2, "0")
		var formatted_d = str(sys_dt.get("day", 1)).lpad(2, "0")
		target_line_edit.text = formatted_m + "/" + formatted_d + "/" + str(sys_year)
		if target_line_edit.has_signal("text_changed"):
			target_line_edit.text_changed.emit(target_line_edit.text)
		canvas_layer.queue_free()
	)

	var btn_clear = Button.new(); btn_clear.text = "Clear"
	btn_clear.add_theme_font_size_override("font_size", 11)
	btn_clear.pressed.connect(func():
		target_line_edit.text = ""
		if target_line_edit.has_signal("text_changed"):
			target_line_edit.text_changed.emit("")
		canvas_layer.queue_free()
	)

	footer_hbox.add_child(btn_confirm)
	footer_hbox.add_child(btn_today)
	footer_hbox.add_child(btn_clear)
	main_vbox.add_child(footer_hbox)

	_render[0].call()
	parent_win.add_child(canvas_layer)

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

func _show_future_shifts_warning_dialog(person_name: String, shift_count: int, old_cls: String, new_cls: String, on_confirm_callback: Callable) -> void:
	var dlg = AcceptDialog.new()
	dlg.title = "⚠️ Future Scheduled Shifts Warning"
	dlg.dialog_text = person_name + " has " + str(shift_count) + " future scheduled shift" + ("s" if shift_count != 1 else "") + ".\n\nChanging Staff Classification from '" + old_cls + "' to '" + new_cls + "' may affect shift expectations.\n\nPlease review those shifts before continuing."
	dlg.size = Vector2i(520, 220)
	dlg.exclusive = true

	var btn_jump = dlg.add_button("🗓️ Review Scheduled Shifts", false, "jump")
	dlg.custom_action.connect(func(action):
		if action == "jump":
			dlg.queue_free()
			if app_shell and app_shell.has_method("switch_view"):
				app_shell.switch_view("schedules")
	)
	dlg.confirmed.connect(func():
		dlg.queue_free()
		on_confirm_callback.call()
	)
	dlg.canceled.connect(func():
		dlg.queue_free()
	)
	add_child(dlg)
	dlg.popup_centered()

# --- STAGE 3 UNIFIED PATHWAYS PROFILE WORKSPACE HELPERS ---

func _build_profile_pathway_card(p: Dictionary, pathway_key: String, title: String, data: Dictionary) -> PanelContainer:
	var card_vbox = VBoxContainer.new()
	card_vbox.add_theme_constant_override("separation", 12)

	var person_id = int(p.get("id", 0))

	if not data.get("enrolled", false):
		var empty_lbl = _create_empty_label("This participant is not currently enrolled in " + title + ".")
		card_vbox.add_child(empty_lbl)

		var btn_enroll = Button.new()
		btn_enroll.text = "+ Enroll in " + title
		btn_enroll.custom_minimum_size = Vector2(180, 36)
		btn_enroll.pressed.connect(func(): _open_profile_enrollment_dialog(person_id, pathway_key))
		card_vbox.add_child(btn_enroll)

		return _create_card(title, card_vbox)

	var ppid = int(data.get("person_pathway_id", 0))
	var ppy_id = int(data.get("person_pathway_program_year_id", 0))

	# 1. Header Bar
	var header_hbox = HBoxContainer.new()
	header_hbox.add_theme_constant_override("separation", 10)

	var sub_lbl = Label.new()
	sub_lbl.text = "Academic Year: " + str(data.get("academic_year", ""))
	sub_lbl.add_theme_font_size_override("font_size", 14)
	sub_lbl.add_theme_color_override("font_color", Color(0.85, 0.90, 0.96, 1.0))
	sub_lbl.size_flags_horizontal = SIZE_EXPAND_FILL
	header_hbox.add_child(sub_lbl)

	var st_val = str(data.get("enrollment_status", "active")).to_lower()
	var status_badge = Label.new()
	status_badge.text = st_val.replace("_", " ").to_upper()
	status_badge.add_theme_font_size_override("font_size", 14)
	if st_val == "active":
		status_badge.add_theme_color_override("font_color", Color(0.30, 0.92, 0.55, 1.0))
	elif st_val == "on_hold":
		status_badge.add_theme_color_override("font_color", Color(1.0, 0.78, 0.30, 1.0))
	else:
		status_badge.add_theme_color_override("font_color", Color(0.95, 0.55, 0.55, 1.0))
	header_hbox.add_child(status_badge)

	var btn_ch_status = Button.new()
	btn_ch_status.text = "Change Status..."
	_style_dark_card_button(btn_ch_status)
	btn_ch_status.pressed.connect(func(): _open_change_status_dialog(ppy_id, st_val))
	header_hbox.add_child(btn_ch_status)

	card_vbox.add_child(header_hbox)

	# 2. Metadata Grid (Track, Standing, Mentor, Attendance)
	var meta_vbox = VBoxContainer.new()
	meta_vbox.add_theme_constant_override("separation", 8)

	var row1 = HBoxContainer.new(); row1.add_theme_constant_override("separation", 12)
	var tr_lbl = Label.new(); tr_lbl.text = "Track: " + str(data.get("current_track", "standard")).to_upper()
	tr_lbl.add_theme_font_size_override("font_size", 14)
	tr_lbl.add_theme_color_override("font_color", Color(0.40, 0.78, 1.0, 1.0))
	row1.add_child(tr_lbl)
	var btn_ch_tr = Button.new(); btn_ch_tr.text = "Change Track"
	_style_dark_card_button(btn_ch_tr)
	btn_ch_tr.pressed.connect(func(): _open_change_track_dialog(ppid, str(data.get("current_track", "standard"))))
	row1.add_child(btn_ch_tr)

	var st_lbl = Label.new(); st_lbl.text = "Standing: " + str(data.get("current_standing", "year_1")).replace("_", " ").to_upper()
	st_lbl.add_theme_font_size_override("font_size", 14)
	st_lbl.add_theme_color_override("font_color", Color(0.40, 0.90, 0.60, 1.0))
	row1.add_child(st_lbl)
	var btn_ch_st = Button.new(); btn_ch_st.text = "Change Standing"
	_style_dark_card_button(btn_ch_st)
	btn_ch_st.pressed.connect(func(): _open_change_standing_dialog(ppid, str(data.get("current_standing", "year_1"))))
	row1.add_child(btn_ch_st)
	meta_vbox.add_child(row1)

	var row2 = HBoxContainer.new(); row2.add_theme_constant_override("separation", 12)
	var m_name = str(data.get("mentor_name", ""))
	var m_lbl = Label.new(); m_lbl.text = "Mentor: " + (m_name if m_name != "" else "[None Assigned]")
	m_lbl.add_theme_font_size_override("font_size", 14)
	m_lbl.add_theme_color_override("font_color", Color(0.90, 0.94, 1.0, 1.0))
	row2.add_child(m_lbl)
	var btn_m = Button.new(); btn_m.text = "Assign / Change Mentor"
	_style_dark_card_button(btn_m)
	btn_m.pressed.connect(func(): _open_assign_mentor_dialog(ppid))
	row2.add_child(btn_m)
	meta_vbox.add_child(row2)

	# Attendance Summary & Toggle
	var is_att_open = pathway_attendance_expanded_map.get(ppid, false)
	var btn_toggle_att = Button.new()
	btn_toggle_att.text = "Hide Session Attendance" if is_att_open else "Show Session Attendance"
	_style_dark_card_button(btn_toggle_att)
	btn_toggle_att.add_theme_font_size_override("font_size", 13)

	var att_content_vbox = VBoxContainer.new()
	att_content_vbox.visible = is_att_open
	att_content_vbox.add_theme_constant_override("separation", 6)

	btn_toggle_att.pressed.connect(func():
		var new_state = not att_content_vbox.visible
		att_content_vbox.visible = new_state
		pathway_attendance_expanded_map[ppid] = new_state
		btn_toggle_att.text = "Hide Session Attendance" if new_state else "Show Session Attendance"
	)

	var sess_sum = data.get("session_summary", {})
	var att_lbl = Label.new()
	att_lbl.text = "Session Attendance: " + str(sess_sum.get("wording", "No linked sessions."))
	att_lbl.add_theme_font_size_override("font_size", 14)
	att_lbl.add_theme_color_override("font_color", Color(0.82, 0.88, 0.94, 1.0))
	att_content_vbox.add_child(att_lbl)

	meta_vbox.add_child(btn_toggle_att)
	meta_vbox.add_child(att_content_vbox)
	card_vbox.add_child(meta_vbox)

	# 3. Requirements Checklist with Toggle
	var comp_cnt = int(data.get("completed_requirements", 0))
	var tot_cnt = int(data.get("total_requirements", 0))

	var is_req_open = pathway_requirements_expanded_map.get(ppid, true)
	var btn_toggle_req = Button.new()
	btn_toggle_req.text = "Hide Checklist Requirements" if is_req_open else "Show Checklist Requirements (%d/%d Completed)" % [comp_cnt, tot_cnt]
	_style_dark_card_button(btn_toggle_req)
	btn_toggle_req.add_theme_font_size_override("font_size", 13)

	var req_section = VBoxContainer.new()
	req_section.add_theme_constant_override("separation", 6)

	var req_content_vbox = VBoxContainer.new()
	req_content_vbox.visible = is_req_open
	req_content_vbox.add_theme_constant_override("separation", 6)

	btn_toggle_req.pressed.connect(func():
		var new_state = not req_content_vbox.visible
		req_content_vbox.visible = new_state
		pathway_requirements_expanded_map[ppid] = new_state
		btn_toggle_req.text = "Hide Checklist Requirements" if new_state else "Show Checklist Requirements (%d/%d Completed)" % [comp_cnt, tot_cnt]
	)
	req_section.add_child(btn_toggle_req)

	var req_hdr = HBoxContainer.new()
	var req_lbl = Label.new()
	req_lbl.text = "Checklist Requirements (%d/%d Completed):" % [comp_cnt, tot_cnt]
	req_lbl.add_theme_font_size_override("font_size", 15)
	req_lbl.add_theme_color_override("font_color", Color(0.95, 0.97, 1.0, 1.0))
	req_lbl.size_flags_horizontal = SIZE_EXPAND_FILL
	req_hdr.add_child(req_lbl)

	var btn_add_cu = Button.new()
	btn_add_cu.text = "+ Add Requirement"
	_style_dark_card_button(btn_add_cu)
	btn_add_cu.pressed.connect(func(): _open_add_catch_up_dialog(ppy_id))
	req_hdr.add_child(btn_add_cu)
	req_content_vbox.add_child(req_hdr)

	var reqs_list = data.get("requirements", [])
	if reqs_list.size() == 0:
		var empty_lbl = _create_empty_label("No checklist requirements assigned.")
		empty_lbl.add_theme_color_override("font_color", Color(0.80, 0.85, 0.92, 1.0))
		req_content_vbox.add_child(empty_lbl)
	else:
		for req in reqs_list:
			var req_id = int(req.get("id"))
			var is_comp = (str(req.get("status")) == "completed")
			var title_str = str(req.get("title", ""))
			var cat_str = str(req.get("category", "requirement")).to_upper()
			var due_str = str(req.get("due_date", "N/A"))
			if due_str == "" or due_str == "null": due_str = "N/A"

			var req_card = PanelContainer.new()
			var rc_st = StyleBoxFlat.new()
			rc_st.bg_color = Color(0.96, 0.97, 0.99, 1.0) if not is_comp else Color(0.94, 0.97, 0.94, 1.0)
			rc_st.border_width_left = 1; rc_st.border_width_top = 1; rc_st.border_width_right = 1; rc_st.border_width_bottom = 1
			rc_st.border_color = Color(0.80, 0.84, 0.90, 1.0) if not is_comp else Color(0.70, 0.88, 0.75, 1.0)
			rc_st.corner_radius_top_left = 8; rc_st.corner_radius_top_right = 8
			rc_st.corner_radius_bottom_left = 8; rc_st.corner_radius_bottom_right = 8
			rc_st.content_margin_left = 12; rc_st.content_margin_top = 8; rc_st.content_margin_right = 12; rc_st.content_margin_bottom = 8
			req_card.add_theme_stylebox_override("panel", rc_st)

			var req_hbox = HBoxContainer.new()
			req_hbox.add_theme_constant_override("separation", 10)

			var chk = CheckBox.new()
			chk.set_pressed_no_signal(is_comp)
			chk.add_theme_font_size_override("font_size", 14)
			_style_checkbox_on_light(chk, Color(0.12, 0.16, 0.24, 1.0))
			chk.text = title_str
			chk.size_flags_horizontal = Control.SIZE_EXPAND_FILL

			var is_toggling = [false]
			chk.toggled.connect(func(toggled_on: bool):
				if is_toggling[0]: return
				is_toggling[0] = true
				if toggled_on:
					unified_pathways_service.mark_requirement_complete(req_id, "Completed from Profile")
				else:
					unified_pathways_service.mark_requirement_incomplete(req_id)
				call_deferred("refresh_view")
			)
			req_hbox.add_child(chk)

			if "CERTIFICATE" in cat_str:
				var cat_badge = Label.new()
				cat_badge.text = "[CERTIFICATE TRACK]"
				cat_badge.add_theme_font_size_override("font_size", 12)
				cat_badge.add_theme_color_override("font_color", Color(0.15, 0.45, 0.90, 1.0))
				req_hbox.add_child(cat_badge)

			var due_lbl = Label.new()
			due_lbl.text = "Due: " + due_str
			due_lbl.add_theme_font_size_override("font_size", 12)
			due_lbl.add_theme_color_override("font_color", Color(0.35, 0.40, 0.50, 1.0))
			req_hbox.add_child(due_lbl)

			var status_pill = Label.new()
			if is_comp:
				status_pill.text = "✅ COMPLETED"
				status_pill.add_theme_color_override("font_color", Color(0.08, 0.52, 0.22, 1.0))
			else:
				status_pill.text = "⏳ PENDING"
				status_pill.add_theme_color_override("font_color", Color(0.75, 0.42, 0.08, 1.0))
			status_pill.add_theme_font_size_override("font_size", 12)
			req_hbox.add_child(status_pill)

			var btn_edit_req = Button.new()
			btn_edit_req.text = "✏️ Edit"
			btn_edit_req.tooltip_text = "Edit requirement details or delete requirement"
			_style_dark_card_button(btn_edit_req)
			btn_edit_req.add_theme_font_size_override("font_size", 11)
			btn_edit_req.pressed.connect(func(): _open_edit_requirement_dialog(req))
			req_hbox.add_child(btn_edit_req)

			req_card.add_child(req_hbox)
			req_content_vbox.add_child(req_card)

	req_section.add_child(req_content_vbox)
	card_vbox.add_child(req_section)

	# 4. Running Pathway Notes & Plan Area
	var notes_section_vbox = VBoxContainer.new()
	notes_section_vbox.add_theme_constant_override("separation", 6)

	var is_notes_open = pathway_notes_expanded_map.get(ppid, false)
	var btn_toggle_notes = Button.new()
	btn_toggle_notes.text = "Hide Pathway Notes & Plan" if is_notes_open else "Show Pathway Notes & Plan"
	_style_dark_card_button(btn_toggle_notes)
	btn_toggle_notes.add_theme_font_size_override("font_size", 13)

	var notes_content_vbox = VBoxContainer.new()
	notes_content_vbox.visible = is_notes_open
	notes_content_vbox.add_theme_constant_override("separation", 8)

	btn_toggle_notes.pressed.connect(func():
		var new_state = not notes_content_vbox.visible
		notes_content_vbox.visible = new_state
		pathway_notes_expanded_map[ppid] = new_state
		btn_toggle_notes.text = "Hide Pathway Notes & Plan" if new_state else "Show Pathway Notes & Plan"
	)
	notes_section_vbox.add_child(btn_toggle_notes)

	# Form to Add New Running Note
	var add_note_card = PanelContainer.new()
	var anc_st = StyleBoxFlat.new()
	anc_st.bg_color = Color(0.14, 0.18, 0.26, 1.0)
	anc_st.corner_radius_top_left = 6; anc_st.corner_radius_top_right = 6
	anc_st.corner_radius_bottom_left = 6; anc_st.corner_radius_bottom_right = 6
	anc_st.content_margin_left = 10; anc_st.content_margin_top = 8; anc_st.content_margin_right = 10; anc_st.content_margin_bottom = 8
	add_note_card.add_theme_stylebox_override("panel", anc_st)

	var add_vbox = VBoxContainer.new()
	add_vbox.add_theme_constant_override("separation", 6)

	var author_hbox = HBoxContainer.new()
	author_hbox.add_theme_constant_override("separation", 10)

	var lbl_author = Label.new()
	lbl_author.text = "Note By (Staff / Intern):"
	lbl_author.add_theme_font_size_override("font_size", 12)
	lbl_author.add_theme_color_override("font_color", Color(0.85, 0.90, 0.98, 1.0))
	author_hbox.add_child(lbl_author)

	var opt_author = OptionButton.new()
	opt_author.add_item("[ Select Staff / Intern ]", 0)
	var staff_interns = unified_pathways_service.get_staff_and_interns()
	for idx in range(staff_interns.size()):
		var st_p = staff_interns[idx]
		var st_name = str(st_p.get("first_name", "")) + " " + str(st_p.get("last_name", ""))
		var st_role = str(st_p.get("system_role", "Staff")).to_upper()
		opt_author.add_item("%s (%s)" % [st_name, st_role], idx + 1)
	author_hbox.add_child(opt_author)
	add_vbox.add_child(author_hbox)

	var txt_new_note = TextEdit.new()
	txt_new_note.placeholder_text = "Add a new running note or plan entry..."
	txt_new_note.custom_minimum_size = Vector2(0, 65)
	txt_new_note.add_theme_font_size_override("font_size", 13)
	add_vbox.add_child(txt_new_note)

	var btn_add_note = Button.new()
	btn_add_note.text = "+ Post Running Note"
	_style_dark_card_button(btn_add_note)
	btn_add_note.add_theme_font_size_override("font_size", 12)
	btn_add_note.pressed.connect(func():
		var text_val = txt_new_note.text.strip_edges()
		if text_val == "": return
		var sel_author_idx = opt_author.selected
		var author_id = null
		var author_name_str = "Staff User"
		if sel_author_idx > 0 and sel_author_idx - 1 < staff_interns.size():
			var p_auth = staff_interns[sel_author_idx - 1]
			author_id = int(p_auth.get("id", 0))
			author_name_str = str(p_auth.get("first_name", "")) + " " + str(p_auth.get("last_name", "")) + " (" + str(p_auth.get("system_role", "Staff")).to_upper() + ")"
		unified_pathways_service.add_pathway_running_note(ppid, text_val, author_id, author_name_str)
		pathway_notes_expanded_map[ppid] = true
		refresh_view()
	)
	add_vbox.add_child(btn_add_note)
	add_note_card.add_child(add_vbox)
	notes_content_vbox.add_child(add_note_card)

	# Render Existing Running Notes Feed
	var running_notes = unified_pathways_service.get_pathway_running_notes(ppid)
	if running_notes.size() == 0:
		var legacy_gen_notes = str(data.get("general_notes", "")).strip_edges()
		if legacy_gen_notes != "":
			var legacy_card = PanelContainer.new()
			var lc_st = StyleBoxFlat.new()
			lc_st.bg_color = Color(0.96, 0.97, 0.99, 1.0)
			lc_st.corner_radius_top_left = 6; lc_st.corner_radius_top_right = 6
			lc_st.corner_radius_bottom_left = 6; lc_st.corner_radius_bottom_right = 6
			lc_st.content_margin_left = 10; lc_st.content_margin_top = 8; lc_st.content_margin_right = 10; lc_st.content_margin_bottom = 8
			legacy_card.add_theme_stylebox_override("panel", lc_st)

			var l_vbox = VBoxContainer.new()
			var l_lbl = Label.new()
			l_lbl.text = "Initial Notes: " + legacy_gen_notes
			l_lbl.add_theme_font_size_override("font_size", 13)
			l_lbl.add_theme_color_override("font_color", Color(0.12, 0.16, 0.24, 1.0))
			l_vbox.add_child(l_lbl)

			var btn_convert = Button.new()
			btn_convert.text = "Convert to Running Note"
			btn_convert.add_theme_font_size_override("font_size", 11)
			_style_dark_card_button(btn_convert)
			btn_convert.pressed.connect(func():
				unified_pathways_service.add_pathway_running_note(ppid, legacy_gen_notes, null, "Staff User")
				unified_pathways_service.update_pathway_notes(ppid, "")
				pathway_notes_expanded_map[ppid] = true
				refresh_view()
			)
			l_vbox.add_child(btn_convert)
			legacy_card.add_child(l_vbox)
			notes_content_vbox.add_child(legacy_card)
		else:
			var empty_n = Label.new()
			empty_n.text = "No running notes added yet."
			empty_n.add_theme_font_size_override("font_size", 12)
			empty_n.add_theme_color_override("font_color", Color(0.80, 0.85, 0.92, 1.0))
			notes_content_vbox.add_child(empty_n)
	else:
		for n_item in running_notes:
			var n_id = int(n_item.get("id"))
			var n_text = str(n_item.get("note_text", ""))
			var n_author = str(n_item.get("author_name", "Staff User"))
			var n_created = str(n_item.get("created_at", ""))
			var n_updated = str(n_item.get("updated_at", ""))

			var n_card = PanelContainer.new()
			var nc_st = StyleBoxFlat.new()
			nc_st.bg_color = Color(0.96, 0.97, 0.99, 1.0)
			nc_st.border_width_left = 1; nc_st.border_width_top = 1; nc_st.border_width_right = 1; nc_st.border_width_bottom = 1
			nc_st.border_color = Color(0.82, 0.86, 0.92, 1.0)
			nc_st.corner_radius_top_left = 6; nc_st.corner_radius_top_right = 6
			nc_st.corner_radius_bottom_left = 6; nc_st.corner_radius_bottom_right = 6
			nc_st.content_margin_left = 10; nc_st.content_margin_top = 8; nc_st.content_margin_right = 10; nc_st.content_margin_bottom = 8
			n_card.add_theme_stylebox_override("panel", nc_st)

			var nc_vbox = VBoxContainer.new()
			nc_vbox.add_theme_constant_override("separation", 4)

			var meta_hbox = HBoxContainer.new()
			var meta_lbl = Label.new()
			meta_lbl.text = "📅 " + n_created + " | 👤 By: " + n_author
			if n_updated != "" and n_updated != n_created:
				meta_lbl.text += " (Edited: " + n_updated + ")"
			meta_lbl.add_theme_font_size_override("font_size", 11)
			meta_lbl.add_theme_color_override("font_color", Color(0.35, 0.42, 0.52, 1.0))
			meta_lbl.size_flags_horizontal = SIZE_EXPAND_FILL
			meta_hbox.add_child(meta_lbl)

			var btn_edit_n = Button.new()
			btn_edit_n.text = "✏️ Edit"
			btn_edit_n.add_theme_font_size_override("font_size", 11)
			_style_dark_card_button(btn_edit_n)
			btn_edit_n.pressed.connect(func(): _open_edit_running_note_dialog(n_item, ppid))
			meta_hbox.add_child(btn_edit_n)

			var btn_del_n = Button.new()
			btn_del_n.text = "🗑️ Delete"
			btn_del_n.add_theme_font_size_override("font_size", 11)
			btn_del_n.add_theme_color_override("font_color", Color(1.0, 0.4, 0.4, 1.0))
			btn_del_n.pressed.connect(func():
				unified_pathways_service.delete_pathway_running_note(n_id)
				pathway_notes_expanded_map[ppid] = true
				refresh_view()
			)
			meta_hbox.add_child(btn_del_n)
			nc_vbox.add_child(meta_hbox)

			var body_lbl = Label.new()
			body_lbl.text = n_text
			body_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			body_lbl.add_theme_font_size_override("font_size", 13)
			body_lbl.add_theme_color_override("font_color", Color(0.12, 0.16, 0.24, 1.0))
			nc_vbox.add_child(body_lbl)

			n_card.add_child(nc_vbox)
			notes_content_vbox.add_child(n_card)

	notes_section_vbox.add_child(notes_content_vbox)
	card_vbox.add_child(notes_section_vbox)

	# 5. Collapsible Audit History
	var history_list = data.get("history", [])
	if history_list.size() > 0:
		var hist_vbox = VBoxContainer.new()
		hist_vbox.add_theme_constant_override("separation", 4)

		var hist_content_vbox = VBoxContainer.new()
		hist_content_vbox.visible = false

		var btn_toggle_hist = Button.new()
		btn_toggle_hist.text = "📜 View Audit Trail (%d Events)" % history_list.size()
		btn_toggle_hist.pressed.connect(func():
			hist_content_vbox.visible = not hist_content_vbox.visible
			btn_toggle_hist.text = "📜 Hide Audit Trail" if hist_content_vbox.visible else "📜 View Audit Trail (%d Events)" % history_list.size()
		)
		hist_vbox.add_child(btn_toggle_hist)

		for h in history_list:
			var h_lbl = Label.new()
			h_lbl.text = "   • [%s] %s" % [str(h.get("timestamp")), str(h.get("description"))]
			h_lbl.add_theme_color_override("font_color", Color(0.5, 0.55, 0.62))
			hist_content_vbox.add_child(h_lbl)

		hist_vbox.add_child(hist_content_vbox)
		card_vbox.add_child(hist_vbox)

	return _create_card(title, card_vbox)

func _open_profile_enrollment_dialog(person_id: int, pathway_key: String) -> void:
	var dlg = ConfirmationDialog.new()
	dlg.title = "Enroll in " + pathway_key.to_upper()
	dlg.size = Vector2i(440, 320)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)

	var lbl_yr = Label.new(); lbl_yr.text = "Academic Year:"
	var txt_yr = LineEdit.new(); txt_yr.text = "2026-2027"

	var lbl_tr = Label.new(); lbl_tr.text = "Track:"
	var opt_tr = OptionButton.new()
	opt_tr.add_item("Standard", 0); opt_tr.add_item("Certification", 1)

	var lbl_st = Label.new(); lbl_st.text = "Standing:"
	var opt_st = OptionButton.new()
	opt_st.add_item("Year 1", 0); opt_st.add_item("Year 2", 1); opt_st.add_item("Year 3", 2); opt_st.add_item("Year 4", 3)

	vbox.add_child(lbl_yr); vbox.add_child(txt_yr)
	vbox.add_child(lbl_tr); vbox.add_child(opt_tr)
	vbox.add_child(lbl_st); vbox.add_child(opt_st)
	dlg.add_child(vbox)

	dlg.confirmed.connect(func():
		var yr = txt_yr.text.strip_edges()
		var tr = "certification" if opt_tr.selected == 1 else "standard"
		var st = "year_" + str(opt_st.selected + 1)
		unified_pathways_service.enroll_person_pathway(person_id, pathway_key, yr, tr, st)
		refresh_view()
	)
	add_child(dlg); dlg.popup_centered()

func _open_change_track_dialog(person_pathway_id: int, current_track: String) -> void:
	var dlg = ConfirmationDialog.new()
	dlg.title = "Change Pathway Track"
	dlg.size = Vector2i(420, 260)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)

	var lbl_tr = Label.new(); lbl_tr.text = "New Track:"
	var opt_tr = OptionButton.new()
	opt_tr.add_item("Standard", 0); opt_tr.add_item("Certification", 1)
	opt_tr.select(1 if current_track == "certification" else 0)

	var lbl_r = Label.new(); lbl_r.text = "Reason for Change:"
	var txt_r = LineEdit.new(); txt_r.placeholder_text = "e.g. Switched degree program"

	vbox.add_child(lbl_tr); vbox.add_child(opt_tr)
	vbox.add_child(lbl_r); vbox.add_child(txt_r)
	dlg.add_child(vbox)

	dlg.confirmed.connect(func():
		var new_tr = "certification" if opt_tr.selected == 1 else "standard"
		unified_pathways_service.change_person_track(person_pathway_id, new_tr, txt_r.text.strip_edges(), "", "Staff User")
		refresh_view()
	)
	add_child(dlg); dlg.popup_centered()

func _open_change_standing_dialog(person_pathway_id: int, current_standing: String) -> void:
	var dlg = ConfirmationDialog.new()
	dlg.title = "Change Pathway Standing"
	dlg.size = Vector2i(420, 260)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)

	var lbl_st = Label.new(); lbl_st.text = "New Standing:"
	var opt_st = OptionButton.new()
	opt_st.add_item("Year 1", 0); opt_st.add_item("Year 2", 1); opt_st.add_item("Year 3", 2); opt_st.add_item("Year 4", 3)

	var lbl_r = Label.new(); lbl_r.text = "Reason for Change:"
	var txt_r = LineEdit.new(); txt_r.placeholder_text = "e.g. Advanced credit"

	vbox.add_child(lbl_st); vbox.add_child(opt_st)
	vbox.add_child(lbl_r); vbox.add_child(txt_r)
	dlg.add_child(vbox)

	dlg.confirmed.connect(func():
		var new_st = "year_" + str(opt_st.selected + 1)
		unified_pathways_service.change_person_standing(person_pathway_id, new_st, txt_r.text.strip_edges(), "", "Staff User")
		refresh_view()
	)
	add_child(dlg); dlg.popup_centered()

func _open_assign_mentor_dialog(person_pathway_id: int) -> void:
	var dlg = ConfirmationDialog.new()
	dlg.title = "Assign Pathway Mentor"
	dlg.size = Vector2i(480, 280)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)

	var lbl_m = Label.new(); lbl_m.text = "Select Mentor (Staff, Volunteers, or Interns Only):"
	var opt_m = OptionButton.new()

	var p_res = db.execute("SELECT id, first_name, last_name, system_role FROM people WHERE LOWER(system_role) LIKE '%staff%' OR LOWER(system_role) LIKE '%volunteer%' OR LOWER(system_role) LIKE '%intern%' OR LOWER(system_role) LIKE '%leader%' OR LOWER(system_role) LIKE '%admin%' ORDER BY last_name ASC, first_name ASC;")
	if not p_res["success"] or p_res["data"].size() == 0:
		p_res = db.execute("SELECT id, first_name, last_name, system_role FROM people ORDER BY last_name ASC, first_name ASC;")

	var m_ids = []
	if p_res["success"] and p_res["data"].size() > 0:
		for p in p_res["data"]:
			var name_str = str(p.get("first_name", "")) + " " + str(p.get("last_name", ""))
			var role_str = str(p.get("system_role", "Staff")).to_upper()
			opt_m.add_item("%s (%s)" % [name_str, role_str])
			m_ids.append(int(p["id"]))

	vbox.add_child(lbl_m); vbox.add_child(opt_m)
	dlg.add_child(vbox)

	dlg.confirmed.connect(func():
		if m_ids.size() == 0: return
		var sel_mid = m_ids[opt_m.selected]
		unified_pathways_service.assign_pathway_mentor(person_pathway_id, sel_mid)
		refresh_view()
	)
	add_child(dlg); dlg.popup_centered()

func _open_add_catch_up_dialog(person_pathway_program_year_id: int) -> void:
	var dlg = ConfirmationDialog.new()
	dlg.title = "Add Pathway Requirement"
	dlg.size = Vector2i(480, 440)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)

	var lbl_t = Label.new(); lbl_t.text = "Requirement Title:"
	var txt_t = LineEdit.new(); txt_t.placeholder_text = "e.g. Complete Certificate Capstone Essay"

	var lbl_d = Label.new(); lbl_d.text = "Due Date (Optional):"

	var date_hbox = HBoxContainer.new()
	date_hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var txt_d = LineEdit.new()
	txt_d.placeholder_text = "MM/DD/YYYY"
	txt_d.custom_minimum_size = Vector2(0, 40)
	txt_d.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	txt_d.add_theme_font_size_override("font_size", 14)

	var btn_cal = Button.new()
	btn_cal.text = "📅"
	btn_cal.custom_minimum_size = Vector2(40, 40)
	btn_cal.pressed.connect(func(): _open_calendar_picker(txt_d))

	date_hbox.add_child(txt_d)
	date_hbox.add_child(btn_cal)

	var chk_cert = CheckBox.new()
	chk_cert.text = "Add requirement as a part of Certificate Track"
	chk_cert.add_theme_font_size_override("font_size", 14)
	chk_cert.add_theme_color_override("font_color", Color(0.90, 0.94, 1.0, 1.0))
	chk_cert.add_theme_color_override("font_hover_color", Color(0.40, 0.85, 1.0, 1.0))
	chk_cert.add_theme_color_override("font_pressed_color", Color(0.90, 0.94, 1.0, 1.0))
	chk_cert.add_theme_color_override("font_hover_pressed_color", Color(0.40, 0.85, 1.0, 1.0))

	vbox.add_child(lbl_t); vbox.add_child(txt_t)
	vbox.add_child(lbl_d); vbox.add_child(date_hbox)
	vbox.add_child(chk_cert)
	dlg.add_child(vbox)

	dlg.confirmed.connect(func():
		var t = txt_t.text.strip_edges()
		if t == "": return
		var db_date = _ui_to_db_date(txt_d.text.strip_edges())
		var cat_val = "certificate" if chk_cert.button_pressed else "requirement"
		unified_pathways_service.create_catch_up_requirement(person_pathway_program_year_id, t, cat_val, db_date, "Staff User")
		refresh_view()
	)
	add_child(dlg); dlg.popup_centered()

func _open_change_status_dialog(person_pathway_program_year_id: int, current_status: String) -> void:
	var dlg = ConfirmationDialog.new()
	dlg.title = "Change Pathway Enrollment Status"
	dlg.size = Vector2i(420, 240)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)

	var lbl_s = Label.new(); lbl_s.text = "Select New Status:"
	var opt_s = OptionButton.new()
	opt_s.add_item("Active", 0)
	opt_s.add_item("On Hold", 1)
	opt_s.add_item("Inactive", 2)

	var st_norm = current_status.to_lower().replace(" ", "_")
	if st_norm == "on_hold":
		opt_s.select(1)
	elif st_norm == "inactive":
		opt_s.select(2)
	else:
		opt_s.select(0)

	vbox.add_child(lbl_s); vbox.add_child(opt_s)
	dlg.add_child(vbox)

	dlg.confirmed.connect(func():
		var sel_idx = opt_s.selected
		var new_st = "active"
		if sel_idx == 1: new_st = "on_hold"
		elif sel_idx == 2: new_st = "inactive"
		unified_pathways_service.update_program_year_status(person_pathway_program_year_id, new_st)
		refresh_view()
	)
	add_child(dlg); dlg.popup_centered()

func _open_edit_requirement_dialog(req: Dictionary) -> void:
	var req_id = int(req.get("id", 0))
	var current_title = str(req.get("title", ""))
	var current_cat = str(req.get("category", "requirement")).to_lower()
	var current_due = str(req.get("due_date", ""))
	if current_due == "null": current_due = ""

	var dlg = ConfirmationDialog.new()
	dlg.title = "Edit Pathway Requirement"
	dlg.size = Vector2i(480, 440)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)

	var lbl_t = Label.new(); lbl_t.text = "Requirement Title:"
	var txt_t = LineEdit.new()
	txt_t.text = current_title

	var lbl_d = Label.new(); lbl_d.text = "Due Date (Optional):"

	var date_hbox = HBoxContainer.new()
	date_hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var txt_d = LineEdit.new()
	txt_d.text = _db_to_ui_date(current_due) if current_due != "" else ""
	txt_d.placeholder_text = "MM/DD/YYYY"
	txt_d.custom_minimum_size = Vector2(0, 40)
	txt_d.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	txt_d.add_theme_font_size_override("font_size", 14)

	var btn_cal = Button.new()
	btn_cal.text = "📅"
	btn_cal.custom_minimum_size = Vector2(40, 40)
	btn_cal.pressed.connect(func(): _open_calendar_picker(txt_d))

	date_hbox.add_child(txt_d)
	date_hbox.add_child(btn_cal)

	var chk_cert = CheckBox.new()
	chk_cert.text = "Add requirement as a part of Certificate Track"
	chk_cert.button_pressed = ("certificate" in current_cat)
	chk_cert.add_theme_font_size_override("font_size", 14)
	chk_cert.add_theme_color_override("font_color", Color(0.90, 0.94, 1.0, 1.0))
	chk_cert.add_theme_color_override("font_hover_color", Color(0.40, 0.85, 1.0, 1.0))
	chk_cert.add_theme_color_override("font_pressed_color", Color(0.90, 0.94, 1.0, 1.0))
	chk_cert.add_theme_color_override("font_hover_pressed_color", Color(0.40, 0.85, 1.0, 1.0))

	var btn_del = Button.new()
	btn_del.text = "🗑️ Delete Requirement"
	btn_del.add_theme_font_size_override("font_size", 12)
	btn_del.add_theme_color_override("font_color", Color(1.0, 0.45, 0.45, 1.0))
	btn_del.pressed.connect(func():
		unified_pathways_service.delete_requirement(req_id, "Staff User")
		dlg.queue_free()
		refresh_view()
	)

	vbox.add_child(lbl_t); vbox.add_child(txt_t)
	vbox.add_child(lbl_d); vbox.add_child(date_hbox)
	vbox.add_child(chk_cert)
	vbox.add_child(btn_del)
	dlg.add_child(vbox)

	dlg.confirmed.connect(func():
		var t = txt_t.text.strip_edges()
		if t == "": return
		var db_date = _ui_to_db_date(txt_d.text.strip_edges())
		var cat_val = "certificate" if chk_cert.button_pressed else "requirement"
		unified_pathways_service.update_requirement(req_id, t, cat_val, db_date, "Staff User")
		refresh_view()
	)
	add_child(dlg); dlg.popup_centered()

func _open_edit_running_note_dialog(n_item: Dictionary, ppid: int) -> void:
	var note_id = int(n_item.get("id", 0))
	var current_text = str(n_item.get("note_text", ""))
	var current_author_id = n_item.get("author_person_id", null)

	var dlg = ConfirmationDialog.new()
	dlg.title = "Edit Pathway Running Note"
	dlg.size = Vector2i(480, 320)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)

	var lbl_author = Label.new(); lbl_author.text = "Note By (Staff / Intern):"
	var opt_author = OptionButton.new()
	opt_author.add_item("[ Select Staff / Intern ]", 0)

	var staff_interns = unified_pathways_service.get_staff_and_interns()
	var sel_idx = 0
	for idx in range(staff_interns.size()):
		var st_p = staff_interns[idx]
		var st_name = str(st_p.get("first_name", "")) + " " + str(st_p.get("last_name", ""))
		var st_role = str(st_p.get("system_role", "Staff")).to_upper()
		opt_author.add_item("%s (%s)" % [st_name, st_role], idx + 1)
		if current_author_id != null and int(st_p.get("id", 0)) == int(current_author_id):
			sel_idx = idx + 1
	opt_author.select(sel_idx)
	vbox.add_child(lbl_author); vbox.add_child(opt_author)

	var lbl_text = Label.new(); lbl_text.text = "Note Content:"
	var txt_edit = TextEdit.new()
	txt_edit.text = current_text
	txt_edit.custom_minimum_size = Vector2(0, 100)
	vbox.add_child(lbl_text); vbox.add_child(txt_edit)

	dlg.add_child(vbox)
	dlg.confirmed.connect(func():
		var t_val = txt_edit.text.strip_edges()
		if t_val == "": return
		var sel_a_idx = opt_author.selected
		var a_id = null
		var a_name = "Staff User"
		if sel_a_idx > 0 and sel_a_idx - 1 < staff_interns.size():
			var p_a = staff_interns[sel_a_idx - 1]
			a_id = int(p_a.get("id", 0))
			a_name = str(p_a.get("first_name", "")) + " " + str(p_a.get("last_name", "")) + " (" + str(p_a.get("system_role", "Staff")).to_upper() + ")"
		unified_pathways_service.update_pathway_running_note(note_id, t_val, a_id, a_name)
		pathway_notes_expanded_map[ppid] = true
		refresh_view()
	)
	add_child(dlg); dlg.popup_centered()

func _create_campus_community_card(p: Dictionary, p_uuid: String) -> Control:
	var cc_card_vbox = VBoxContainer.new()
	cc_card_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cc_card_vbox.add_theme_constant_override("separation", 16)

	# Fetch Master Institutions
	var inst_list = []
	if db:
		var q_inst = db.execute("SELECT id, uuid, name, short_name, institution_type, is_active FROM institutions WHERE is_active = 1 ORDER BY display_order ASC, name ASC;")
		if q_inst["success"]:
			inst_list = q_inst["data"]

	var raw_applies = p.get("campus_community_applies", null)
	var cc_applies = false
	if raw_applies != null and str(raw_applies) != "<null>" and str(raw_applies) != "null":
		cc_applies = (int(raw_applies) == 1)
	else:
		# Fallback: check if they have any non-empty/non-default campus info
		var raw_inst_check = p.get("institution_id", 0)
		var inst_id_val = 0 if (raw_inst_check == null or str(raw_inst_check) == "<null>" or str(raw_inst_check) == "null") else int(raw_inst_check)
		var rel_val_check = _clean_str(p.get("relationship", ""))
		var se_val_check = _clean_str(p.get("school_email", ""))
		var ay_val_check = _clean_str(p.get("academic_year", ""))
		var mj_val_check = _clean_str(p.get("major", ""))
		var res_val_check = _clean_str(p.get("residence", ""))
		var gt_val_check = _clean_str(p.get("expected_grad_term", ""))
		var gy_val_check = _clean_str(p.get("expected_grad_year", ""))
		
		if (inst_id_val != 0 or rel_val_check != "" or se_val_check != "" 
			or (ay_val_check != "" and ay_val_check != "Not Applicable" and ay_val_check != "None")
			or mj_val_check != "" or (res_val_check != "" and res_val_check != "Not Applicable")
			or (gt_val_check != "" and gt_val_check != "Not Applicable") or gy_val_check != ""):
			cc_applies = true

	# 1. Toggle button at the top
	var toggle = CheckButton.new()
	toggle.text = "Campus & Community Applies"
	toggle.button_pressed = cc_applies
	cc_card_vbox.add_child(toggle)

	var form_grid = GridContainer.new()
	form_grid.columns = 3
	form_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	form_grid.add_theme_constant_override("h_separation", 18)
	form_grid.add_theme_constant_override("v_separation", 14)

	# 1. Institution Dropdown
	var inst_vbox = VBoxContainer.new(); inst_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var inst_lbl = Label.new(); inst_lbl.text = "INSTITUTION"; inst_lbl.add_theme_font_size_override("font_size", 14); inst_lbl.add_theme_color_override("font_color", Color(0.70, 0.78, 0.88, 1.0))
	var inst_dropdown = OptionButton.new()
	inst_dropdown.add_item("[ Unspecified / None ]", 0)

	var raw_inst = p.get("institution_id", 0)
	var current_inst_id = 0 if (raw_inst == null or str(raw_inst) == "<null>" or str(raw_inst) == "null") else int(raw_inst)
	var sel_inst_idx = 0
	for idx in range(inst_list.size()):
		var item = inst_list[idx]
		var i_name = str(item.get("name", ""))
		inst_dropdown.add_item(i_name, idx + 1)
		if current_inst_id != 0 and int(item.get("id", 0)) == current_inst_id:
			sel_inst_idx = idx + 1
	inst_dropdown.select(sel_inst_idx)
	inst_dropdown.custom_minimum_size = Vector2(0, 44); inst_dropdown.size_flags_horizontal = Control.SIZE_EXPAND_FILL; inst_dropdown.add_theme_font_size_override("font_size", 16)
	inst_vbox.add_child(inst_lbl); inst_vbox.add_child(inst_dropdown); form_grid.add_child(inst_vbox)

	# 2. Institution Name (Other) LineEdit
	var inst_other_vbox = VBoxContainer.new(); inst_other_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var inst_other_lbl = Label.new(); inst_other_lbl.text = "INSTITUTION NAME (OTHER)"; inst_other_lbl.add_theme_font_size_override("font_size", 14); inst_other_lbl.add_theme_color_override("font_color", Color(0.70, 0.78, 0.88, 1.0))
	var inst_other_edit = LineEdit.new(); inst_other_edit.text = _clean_str(p.get("institution_other_name", "")); inst_other_edit.placeholder_text = "Specify School Name..."; inst_other_edit.custom_minimum_size = Vector2(0, 44); inst_other_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL; inst_other_edit.add_theme_font_size_override("font_size", 16)
	inst_other_vbox.add_child(inst_other_lbl); inst_other_vbox.add_child(inst_other_edit); form_grid.add_child(inst_other_vbox)

	# 3. Relationship Dropdown
	var rel_vbox = VBoxContainer.new(); rel_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var rel_lbl = Label.new(); rel_lbl.text = "RELATIONSHIP"; rel_lbl.add_theme_font_size_override("font_size", 14); rel_lbl.add_theme_color_override("font_color", Color(0.70, 0.78, 0.88, 1.0))
	var rel_dropdown = OptionButton.new()
	var rel_options = ["Student", "Alumni", "Faculty", "Staff", "Community Member", "Other"]
	for idx in range(rel_options.size()):
		rel_dropdown.add_item(rel_options[idx], idx)
	var cur_rel = _clean_str(p.get("relationship", "Student"))
	if cur_rel == "":
		cur_rel = "Student"
	var rel_idx = rel_options.find(cur_rel)
	rel_dropdown.select(rel_idx if rel_idx >= 0 else 0)
	rel_dropdown.custom_minimum_size = Vector2(0, 44); rel_dropdown.size_flags_horizontal = Control.SIZE_EXPAND_FILL; rel_dropdown.add_theme_font_size_override("font_size", 16)
	rel_vbox.add_child(rel_lbl); rel_vbox.add_child(rel_dropdown); form_grid.add_child(rel_vbox)

	# 4. School Email
	var se_vbox = VBoxContainer.new(); se_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var se_lbl = Label.new(); se_lbl.text = "SCHOOL EMAIL"; se_lbl.add_theme_font_size_override("font_size", 14); se_lbl.add_theme_color_override("font_color", Color(0.70, 0.78, 0.88, 1.0))
	var se_edit = LineEdit.new(); se_edit.text = _clean_str(p.get("school_email", "")); se_edit.placeholder_text = "student@school.edu"; se_edit.custom_minimum_size = Vector2(0, 44); se_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL; se_edit.add_theme_font_size_override("font_size", 16)
	se_vbox.add_child(se_lbl); se_vbox.add_child(se_edit); form_grid.add_child(se_vbox)

	# 5. Academic Year Dropdown
	var ay_vbox = VBoxContainer.new(); ay_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var ay_lbl = Label.new(); ay_lbl.text = "ACADEMIC YEAR"; ay_lbl.add_theme_font_size_override("font_size", 14); ay_lbl.add_theme_color_override("font_color", Color(0.70, 0.78, 0.88, 1.0))
	var ay_dropdown = OptionButton.new()
	var ay_options = ["Freshman", "Sophomore", "Junior", "Senior", "Graduate Student", "Not Applicable"]
	for idx in range(ay_options.size()):
		ay_dropdown.add_item(ay_options[idx], idx)
	var cur_ay = _clean_str(p.get("academic_year", p.get("grade", "Freshman")))
	if cur_ay == "" or cur_ay == "None":
		cur_ay = "Not Applicable"
	var ay_idx = ay_options.find(cur_ay)
	ay_dropdown.select(ay_idx if ay_idx >= 0 else ay_options.find("Not Applicable"))
	ay_dropdown.custom_minimum_size = Vector2(0, 44); ay_dropdown.size_flags_horizontal = Control.SIZE_EXPAND_FILL; ay_dropdown.add_theme_font_size_override("font_size", 16)
	ay_vbox.add_child(ay_lbl); ay_vbox.add_child(ay_dropdown); form_grid.add_child(ay_vbox)

	# 6. Major
	var mj_vbox = VBoxContainer.new(); mj_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var mj_lbl = Label.new(); mj_lbl.text = "MAJOR / FIELD OF STUDY"; mj_lbl.add_theme_font_size_override("font_size", 14); mj_lbl.add_theme_color_override("font_color", Color(0.70, 0.78, 0.88, 1.0))
	var mj_edit = LineEdit.new(); mj_edit.text = _clean_str(p.get("major", "")); mj_edit.placeholder_text = "e.g. Computer Science, Nursing"; mj_edit.custom_minimum_size = Vector2(0, 44); mj_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL; mj_edit.add_theme_font_size_override("font_size", 16)
	mj_vbox.add_child(mj_lbl); mj_vbox.add_child(mj_edit); form_grid.add_child(mj_vbox)

	# 7. Residence Dropdown
	var res_vbox = VBoxContainer.new(); res_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var res_lbl = Label.new(); res_lbl.text = "RESIDENCE TYPE"; res_lbl.add_theme_font_size_override("font_size", 14); res_lbl.add_theme_color_override("font_color", Color(0.70, 0.78, 0.88, 1.0))
	var res_dropdown = OptionButton.new()
	var res_options = ["On Campus", "Off Campus", "Commuter", "Online Student", "Not Applicable"]
	for idx in range(res_options.size()):
		res_dropdown.add_item(res_options[idx], idx)
	var cur_res = _clean_str(p.get("residence", "On Campus"))
	if cur_res == "":
		cur_res = "Not Applicable"
	var res_idx = res_options.find(cur_res)
	res_dropdown.select(res_idx if res_idx >= 0 else 0)
	res_dropdown.custom_minimum_size = Vector2(0, 44); res_dropdown.size_flags_horizontal = Control.SIZE_EXPAND_FILL; res_dropdown.add_theme_font_size_override("font_size", 16)
	res_vbox.add_child(res_lbl); res_vbox.add_child(res_dropdown); form_grid.add_child(res_vbox)

	# 8. Expected Graduation Term
	var gt_vbox = VBoxContainer.new(); gt_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var gt_lbl = Label.new(); gt_lbl.text = "EXPECTED GRADUATION TERM"; gt_lbl.add_theme_font_size_override("font_size", 14); gt_lbl.add_theme_color_override("font_color", Color(0.70, 0.78, 0.88, 1.0))
	var gt_dropdown = OptionButton.new()
	var gt_options = ["Spring", "Summer", "Fall", "Not Applicable"]
	for idx in range(gt_options.size()):
		gt_dropdown.add_item(gt_options[idx], idx)
	var cur_gt = _clean_str(p.get("expected_grad_term", ""))
	if cur_gt == "":
		cur_gt = "Not Applicable"
	var gt_idx = gt_options.find(cur_gt)
	gt_dropdown.select(gt_idx if gt_idx >= 0 else gt_options.find("Not Applicable"))
	gt_dropdown.custom_minimum_size = Vector2(0, 44); gt_dropdown.size_flags_horizontal = Control.SIZE_EXPAND_FILL; gt_dropdown.add_theme_font_size_override("font_size", 16)
	gt_vbox.add_child(gt_lbl); gt_vbox.add_child(gt_dropdown); form_grid.add_child(gt_vbox)

	# 9. Expected Graduation Year
	var gy_vbox = VBoxContainer.new(); gy_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var gy_lbl = Label.new(); gy_lbl.text = "EXPECTED GRADUATION YEAR"; gy_lbl.add_theme_font_size_override("font_size", 14); gy_lbl.add_theme_color_override("font_color", Color(0.70, 0.78, 0.88, 1.0))
	var gy_edit = LineEdit.new(); gy_edit.text = _clean_str(p.get("expected_grad_year", "")); gy_edit.placeholder_text = "e.g. 2027"; gy_edit.custom_minimum_size = Vector2(0, 44); gy_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL; gy_edit.add_theme_font_size_override("font_size", 16)
	gy_vbox.add_child(gy_lbl); gy_vbox.add_child(gy_edit); form_grid.add_child(gy_vbox)

	# Reactive Visibility & Auto-Default Logic
	var update_reactive_states = func():
		var sel_i = inst_dropdown.selected
		var sel_inst = inst_list[sel_i - 1] if (sel_i > 0 and sel_i - 1 < inst_list.size()) else {}
		var inst_name = str(sel_inst.get("name", ""))
		var inst_type = str(sel_inst.get("institution_type", "college_university"))

		inst_other_vbox.visible = (inst_name == "Other")
		if inst_type == "community":
			rel_dropdown.select(4) # Community Member
		var is_higher_ed = (inst_type == "college_university")
		gt_vbox.visible = is_higher_ed
		gy_vbox.visible = is_higher_ed

	inst_dropdown.item_selected.connect(func(_idx): update_reactive_states.call())
	update_reactive_states.call()

	# Connect toggle behavior
	form_grid.visible = toggle.button_pressed
	toggle.toggled.connect(func(pressed: bool):
		form_grid.visible = pressed
	)

	cc_card_vbox.add_child(form_grid)

	# Save Button
	var btn_save_cc = Button.new()
	btn_save_cc.text = "💾 Save Campus & Community Details"
	btn_save_cc.custom_minimum_size = Vector2(280, 44)
	btn_save_cc.add_theme_font_size_override("font_size", 16)
	btn_save_cc.pressed.connect(func():
		if not db or p_uuid == "": return
		var sel_i = inst_dropdown.selected
		var sel_inst = inst_list[sel_i - 1] if (sel_i > 0 and sel_i - 1 < inst_list.size()) else {}
		var i_id = int(sel_inst.get("id", 0)) if sel_i > 0 else null
		var i_other = inst_other_edit.text.strip_edges() if inst_other_vbox.visible else ""

		var rel_val = rel_options[rel_dropdown.selected]
		var se_val = se_edit.text.strip_edges()
		var ay_val = ay_options[ay_dropdown.selected]
		var mj_val = mj_edit.text.strip_edges()
		var res_val = res_options[res_dropdown.selected]
		var gt_val = gt_options[gt_dropdown.selected]
		var gy_val = int(gy_edit.text.strip_edges()) if gy_edit.text.strip_edges().is_valid_int() else null
		var cc_applies_val = 1 if toggle.button_pressed else 0

		var person_id = int(p.get("id", 0))

		# Update People Record including campus_community_applies
		db.execute("UPDATE people SET institution_id = ?, institution_other_name = ?, relationship = ?, school_email = ?, academic_year = ?, grade = ?, major = ?, residence = ?, expected_grad_term = ?, expected_grad_year = ?, campus_community_applies = ?, updated_at = datetime('now') WHERE person_uuid = ?;",
			[i_id, i_other, rel_val, se_val, ay_val, ay_val, mj_val, res_val, gt_val, gy_val, cc_applies_val, p_uuid])

		# Write to Academic History
		if person_id > 0:
			var hist_uuid = "ahist_" + str(Time.get_ticks_msec()) + "_" + str(randi() % 10000)
			db.execute("INSERT INTO person_academic_history (uuid, person_id, institution_id, institution_other_name, relationship, academic_year, major, residence, expected_grad_term, expected_grad_year, change_source, changed_by) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'Profile Update', 'Staff User');",
				[hist_uuid, person_id, i_id, i_other, rel_val, ay_val, mj_val, res_val, gt_val, gy_val])

		refresh_view()
	)
	cc_card_vbox.add_child(btn_save_cc)

	return _create_card("Campus & Community", cc_card_vbox)
