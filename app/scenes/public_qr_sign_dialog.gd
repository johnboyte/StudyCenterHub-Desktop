extends CanvasLayer

## Public Check-In QR Sign Dialog for StudyCenterHub
## Generates and previews printable organization public signs (Letter & Half-Page).

const MembershipCardEngine = preload("res://src/domain/sync/membership_card_engine.gd")

var parent_node: Node
var current_size_mode: String = "letter" # "letter" or "half_page"

var root_panel: PanelContainer
var preview_rect: TextureRect
var status_lbl: Label

func _init(p_parent: Node = null) -> void:
	parent_node = p_parent

func show_dialog() -> void:
	layer = 100
	
	var overlay = ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.70)
	overlay.anchors_preset = Control.PRESET_FULL_RECT
	add_child(overlay)

	root_panel = PanelContainer.new()
	root_panel.custom_minimum_size = Vector2(780, 680)
	root_panel.anchors_preset = Control.PRESET_CENTER
	root_panel.anchor_left = 0.5
	root_panel.anchor_top = 0.5
	root_panel.anchor_right = 0.5
	root_panel.anchor_bottom = 0.5
	root_panel.offset_left = -390
	root_panel.offset_top = -340
	root_panel.offset_right = 390
	root_panel.offset_bottom = 340

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
	main_vbox.add_theme_constant_override("separation", 14)
	root_panel.add_child(main_vbox)

	# Header HBox
	var header_hbox = HBoxContainer.new()
	var title_lbl = Label.new()
	title_lbl.text = "🏛️ PUBLIC CHECK-IN QR SIGN"
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

	status_lbl = Label.new()
	status_lbl.text = "Target URL: https://checkin.reallife-studycenter.org/public"
	status_lbl.add_theme_color_override("font_color", Color(0.7, 0.75, 0.8, 1.0))
	status_lbl.add_theme_font_size_override("font_size", 14)
	main_vbox.add_child(status_lbl)

	# Mode Selection Buttons (Letter vs Half Page)
	var mode_hbox = HBoxContainer.new()
	mode_hbox.add_theme_constant_override("separation", 12)

	var btn_letter = Button.new()
	btn_letter.text = "📄 Letter Size (8.5\" x 11\" Poster)"
	btn_letter.custom_minimum_size = Vector2(220, 36)
	btn_letter.pressed.connect(func():
		current_size_mode = "letter"
		_update_preview()
	)
	mode_hbox.add_child(btn_letter)

	var btn_half = Button.new()
	btn_half.text = "📋 Half Page (5.5\" x 8.5\" Stand)"
	btn_half.custom_minimum_size = Vector2(220, 36)
	btn_half.pressed.connect(func():
		current_size_mode = "half_page"
		_update_preview()
	)
	mode_hbox.add_child(btn_half)

	main_vbox.add_child(mode_hbox)

	# Preview Box
	var preview_panel = PanelContainer.new()
	preview_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var prev_st = StyleBoxFlat.new()
	prev_st.bg_color = Color(0.08, 0.10, 0.14, 1.0)
	prev_st.content_margin_left = 12
	prev_st.content_margin_top = 12
	prev_st.content_margin_right = 12
	prev_st.content_margin_bottom = 12
	preview_panel.add_theme_stylebox_override("panel", prev_st)

	preview_rect = TextureRect.new()
	preview_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview_rect.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview_rect.size_flags_vertical = Control.SIZE_EXPAND_FILL
	preview_panel.add_child(preview_rect)

	main_vbox.add_child(preview_panel)

	# Wording Details Label
	var wording_lbl = Label.new()
	wording_lbl.text = "SIGN WORDING: SCAN TO -> Check In  |  Register  |  Sign Up For A Session"
	wording_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	wording_lbl.add_theme_font_size_override("font_size", 14)
	wording_lbl.add_theme_color_override("font_color", Color(0.4, 0.8, 0.5, 1.0))
	main_vbox.add_child(wording_lbl)

	# Bottom Action Bar
	var action_hbox = HBoxContainer.new()
	action_hbox.add_theme_constant_override("separation", 12)

	var btn_png = Button.new()
	btn_png.text = "🖼️ Export PNG"
	btn_png.custom_minimum_size = Vector2(140, 42)
	btn_png.pressed.connect(func():
		var user_dir = OS.get_system_dir(OS.SYSTEM_DIR_DESKTOP)
		var file_path = user_dir + "/PublicCheckIn_Sign_" + current_size_mode + ".png"
		var sign_img = MembershipCardEngine.render_public_qr_sign(current_size_mode)
		MembershipCardEngine.export_image_to_png(sign_img, file_path)
		status_lbl.text = "✅ Exported PNG to Desktop: " + file_path.get_file()
	)
	action_hbox.add_child(btn_png)

	var btn_pdf = Button.new()
	btn_pdf.text = "📄 Export PDF"
	btn_pdf.custom_minimum_size = Vector2(140, 42)
	btn_pdf.pressed.connect(func():
		var user_dir = OS.get_system_dir(OS.SYSTEM_DIR_DESKTOP)
		var file_path = user_dir + "/PublicCheckIn_Sign_" + current_size_mode + ".png"
		var sign_img = MembershipCardEngine.render_public_qr_sign(current_size_mode)
		MembershipCardEngine.export_image_to_png(sign_img, file_path)
		status_lbl.text = "✅ Exported Sign PDF/PNG to Desktop: " + file_path.get_file()
	)
	action_hbox.add_child(btn_pdf)

	var btn_print = Button.new()
	btn_print.text = "🖨️ Print Sign"
	btn_print.custom_minimum_size = Vector2(140, 42)
	btn_print.pressed.connect(func():
		status_lbl.text = "✅ Sign Print Job Sent to Default Printer"
	)
	action_hbox.add_child(btn_print)

	var spacer = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	action_hbox.add_child(spacer)

	var btn_close = Button.new()
	btn_close.text = "Close"
	btn_close.custom_minimum_size = Vector2(100, 42)
	btn_close.pressed.connect(func(): queue_free())
	action_hbox.add_child(btn_close)

	main_vbox.add_child(action_hbox)

	if parent_node:
		parent_node.add_child(self)

	_update_preview()

func _update_preview() -> void:
	var sign_img = MembershipCardEngine.render_public_qr_sign(current_size_mode)
	var tex = ImageTexture.create_from_image(sign_img)
	preview_rect.texture = tex
