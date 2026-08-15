extends AcceptDialog

## Staff Mobile Access Provisioning Dialog
## Provides authorized administrators and team leaders with UI controls to enable,
## set/reset 6-digit PINs, and disable Staff Mobile Access for eligible staff members.

signal mobile_credentials_updated(person_id: int, enabled: bool)

var db: RefCounted
var person_id: int = 0
var staff_name: String = ""
var human_id: String = ""
var current_user_role: String = "Staff"
var is_admin_or_tl: bool = false

var mobile_service: RefCounted

# UI Controls
var status_label: Label
var pin_input: LineEdit
var confirm_input: LineEdit
var error_label: Label
var save_button: Button
var disable_button: Button

func setup(database: RefCounted, target_person_id: int, current_user_role_str: String = "Administrator") -> void:
	db = database
	person_id = target_person_id
	current_user_role = current_user_role_str
	
	var StaffMobileServiceScript = load("res://src/domain/directory/staff_mobile_service.gd")
	if StaffMobileServiceScript:
		mobile_service = StaffMobileServiceScript.new(db)

	title = "Manage Mobile Staff Access (6-Digit PIN)"
	size = Vector2i(480, 420)

	_build_ui()
	_load_person_details()

func _build_ui() -> void:
	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_bottom", 16)
	add_child(margin)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	margin.add_child(vbox)

	var banner = Label.new()
	banner.text = "📱 Staff Mobile PIN setup (Requires EXACTLY 6 numeric digits).\nDoes not affect 4-digit kiosk check-in PINs."
	banner.add_theme_color_override("font_color", Color(0.70, 0.85, 1.0, 1.0))
	banner.add_theme_font_size_override("font_size", 13)
	banner.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(banner)

	status_label = Label.new()
	status_label.text = "Status: Checking..."
	vbox.add_child(status_label)

	var sep = HSeparator.new()
	vbox.add_child(sep)

	var pin_lbl = Label.new()
	pin_lbl.text = "New 6-Digit Mobile Staff PIN:"
	vbox.add_child(pin_lbl)

	pin_input = LineEdit.new()
	pin_input.secret = true
	pin_input.max_length = 6
	pin_input.placeholder_text = "e.g. 849201 (6 numeric digits)"
	vbox.add_child(pin_input)

	var confirm_lbl = Label.new()
	confirm_lbl.text = "Confirm 6-Digit Mobile Staff PIN:"
	vbox.add_child(confirm_lbl)

	confirm_input = LineEdit.new()
	confirm_input.secret = true
	confirm_input.max_length = 6
	confirm_input.placeholder_text = "Re-enter 6 numeric digits"
	vbox.add_child(confirm_input)

	error_label = Label.new()
	error_label.add_theme_color_override("font_color", Color.RED)
	error_label.visible = false
	vbox.add_child(error_label)

	var btn_hbox = HBoxContainer.new()
	btn_hbox.add_theme_constant_override("separation", 10)
	vbox.add_child(btn_hbox)

	save_button = Button.new()
	save_button.text = "Save Mobile Credentials"
	save_button.pressed.connect(_on_save_pressed)
	btn_hbox.add_child(save_button)

	disable_button = Button.new()
	disable_button.text = "Disable Mobile Access"
	disable_button.pressed.connect(_on_disable_pressed)
	btn_hbox.add_child(disable_button)

func _load_person_details() -> void:
	if not db or person_id <= 0: return

	var res = db.execute("SELECT first_name, last_name, human_id, primary_role FROM people WHERE id = ?;", [person_id])
	if res["success"] and res["data"].size() > 0:
		var p = res["data"][0]
		staff_name = String(p.get("first_name", "")) + " " + String(p.get("last_name", ""))
		human_id = String(p.get("human_id", ""))
		title = "Mobile Staff Access — " + staff_name + " (" + human_id + ")"

	var stat = mobile_service.get_staff_mobile_status(person_id) if mobile_service else {"enabled": false}
	if stat["enabled"]:
		status_label.text = "Mobile Access: ENABLED (Version " + str(stat.get("version", 1)) + ")"
		status_label.add_theme_color_override("font_color", Color.GREEN)
		disable_button.disabled = false
	else:
		status_label.text = "Mobile Access: DISABLED"
		status_label.add_theme_color_override("font_color", Color.GRAY)
		disable_button.disabled = true

func _on_save_pressed() -> void:
	error_label.visible = false
	var pin1 = pin_input.text.strip_edges()
	var pin2 = confirm_input.text.strip_edges()

	if pin1.length() != 6 or not pin1.is_valid_int():
		error_label.text = "PIN must be exactly 6 numeric digits."
		error_label.visible = true
		return

	if pin1 != pin2:
		error_label.text = "PIN confirmation does not match."
		error_label.visible = true
		return

	if not mobile_service:
		error_label.text = "Mobile service unavailable."
		error_label.visible = true
		return

	var res = mobile_service.set_staff_mobile_pin(person_id, pin1)
	if res["success"]:
		pin_input.text = ""
		confirm_input.text = ""
		_load_person_details()

		# Trigger immediate gateway sync after credential change
		_trigger_immediate_sync()

		mobile_credentials_updated.emit(person_id, true)
		hide()
	else:
		error_label.text = res.get("error", "Failed to set PIN.")
		error_label.visible = true

func _on_disable_pressed() -> void:
	if not mobile_service: return
	var res = mobile_service.disable_staff_mobile_access(person_id)
	if res["success"]:
		_load_person_details()
		_trigger_immediate_sync()
		mobile_credentials_updated.emit(person_id, false)
		hide()

func _trigger_immediate_sync() -> void:
	var GatewaySyncScript = load("res://src/domain/sync/gateway_sync_service.gd")
	if GatewaySyncScript:
		var sync_svc = GatewaySyncScript.new(db, get_tree().root)
		sync_svc.publish_staff_credentials_index()
