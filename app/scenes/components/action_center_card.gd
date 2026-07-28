class_name ActionCenterCard
extends PanelContainer

## Reusable Action Center Card Component (PD-008 Compliant)
## Displays queue badge counts, urgency accents, supporting detail, and action buttons.

signal action_requested(queue_id: String)

var queue_id: String = ""

@onready var margin_container: MarginContainer = $MarginContainer
@onready var main_vbox: VBoxContainer = $MarginContainer/MainVBox
@onready var title_label: Label = $MarginContainer/MainVBox/TopHBox/TitleLabel
@onready var count_badge: Label = $MarginContainer/MainVBox/MiddleHBox/CountBadge
@onready var detail_label: Label = $MarginContainer/MainVBox/MiddleHBox/DetailLabel
@onready var primary_button: Button = $MarginContainer/MainVBox/BottomHBox/PrimaryButton
@onready var urgency_pill: PanelContainer = $MarginContainer/MainVBox/TopHBox/UrgencyPill
@onready var urgency_label: Label = $MarginContainer/MainVBox/TopHBox/UrgencyPill/Margin/UrgencyLabel

const URGENCY_COLORS: Dictionary = {
	"critical": Color(0.86, 0.15, 0.15, 1.0), # #DC2626 Red
	"urgent": Color(0.85, 0.47, 0.02, 1.0),   # #D97706 Amber
	"normal": Color(0.15, 0.39, 0.92, 1.0),   # #2563EB Blue
	"resource": Color(0.49, 0.23, 0.93, 1.0)  # #7C3AED Purple
}

func _ready() -> void:
	if primary_button:
		primary_button.pressed.connect(_on_button_pressed)
		_apply_button_styles()

func configure_card(data: Dictionary) -> void:
	queue_id = data.get("queue_id", "")
	var title = data.get("title", "Work Queue")
	var count = int(data.get("count", 0))
	var detail = data.get("supporting_detail", "")
	var urgency = data.get("urgency", "normal").to_lower()
	var btn_label = data.get("primary_button", "Begin Actions")
	var is_supported = data.get("queue_mode_supported", true)

	if title_label:
		title_label.text = title
		title_label.add_theme_font_size_override("font_size", 16)
		title_label.add_theme_color_override("font_color", Color(0.08, 0.12, 0.18, 1.0))

	if count_badge:
		count_badge.text = str(count) + " Item" + ("s" if count != 1 else "") + " Need Action"
		if count > 0:
			count_badge.add_theme_font_size_override("font_size", 17)
			count_badge.add_theme_color_override("font_color", Color(0.08, 0.12, 0.18, 1.0))
		else:
			count_badge.add_theme_font_size_override("font_size", 14)
			count_badge.add_theme_color_override("font_color", Color(0.48, 0.54, 0.62, 1.0))

	if detail_label:
		detail_label.text = detail
		detail_label.visible = not detail.is_empty()
		detail_label.add_theme_font_size_override("font_size", 13)
		detail_label.add_theme_color_override("font_color", Color(0.40, 0.46, 0.54, 1.0))

	if primary_button:
		if is_supported:
			primary_button.text = btn_label
			primary_button.disabled = (count == 0)
		else:
			primary_button.text = btn_label + " (Unavailable)"
			primary_button.disabled = true

	_apply_card_background_style(count > 0)
	_apply_urgency_style(urgency)
	_apply_button_styles(count > 0, is_supported)

func _apply_card_background_style(is_active: bool) -> void:
	var style = StyleBoxFlat.new()
	if is_active:
		style.bg_color = Color(1.0, 1.0, 1.0, 1.0)
		style.border_width_left = 1; style.border_width_top = 1; style.border_width_right = 1; style.border_width_bottom = 1
		style.border_color = Color(0.86, 0.89, 0.94, 1.0)
		style.shadow_color = Color(0.0, 0.0, 0.0, 0.03)
		style.shadow_size = 4
	else:
		# Inactive/empty queue: lighter, visually quiet appearance
		style.bg_color = Color(0.975, 0.98, 0.99, 1.0)
		style.border_width_left = 1; style.border_width_top = 1; style.border_width_right = 1; style.border_width_bottom = 1
		style.border_color = Color(0.91, 0.93, 0.96, 1.0)

	style.corner_radius_top_left = 12; style.corner_radius_top_right = 12; style.corner_radius_bottom_left = 12; style.corner_radius_bottom_right = 12
	style.content_margin_left = 16; style.content_margin_top = 14; style.content_margin_right = 16; style.content_margin_bottom = 14
	add_theme_stylebox_override("panel", style)

func _apply_urgency_style(urgency: String) -> void:
	var color = URGENCY_COLORS.get(urgency, URGENCY_COLORS["normal"])
	if urgency_label:
		urgency_label.text = urgency.to_upper()
	
	if urgency_pill:
		var pill_style = StyleBoxFlat.new()
		pill_style.bg_color = color
		pill_style.corner_radius_top_left = 6
		pill_style.corner_radius_bottom_left = 6
		pill_style.corner_radius_top_right = 6
		pill_style.corner_radius_bottom_right = 6
		pill_style.content_margin_left = 8
		pill_style.content_margin_right = 8
		pill_style.content_margin_top = 2
		pill_style.content_margin_bottom = 2
		urgency_pill.add_theme_stylebox_override("panel", pill_style)

func _apply_button_styles(is_active: bool = true, is_supported: bool = true) -> void:
	if not primary_button: return
	
	if is_active and is_supported:
		primary_button.add_theme_color_override("font_color", Color(1, 1, 1, 1))
		primary_button.add_theme_color_override("font_hover_color", Color(1, 1, 1, 1))
		primary_button.add_theme_color_override("font_pressed_color", Color(0.9, 0.9, 0.9, 1))
		primary_button.add_theme_color_override("font_focus_color", Color(1, 1, 1, 1))

		var btn_style = StyleBoxFlat.new()
		btn_style.bg_color = Color(0.15, 0.39, 0.92, 1.0) # Canonical Blue
		btn_style.corner_radius_top_left = 6; btn_style.corner_radius_top_right = 6; btn_style.corner_radius_bottom_left = 6; btn_style.corner_radius_bottom_right = 6
		btn_style.content_margin_left = 14; btn_style.content_margin_right = 14; btn_style.content_margin_top = 8; btn_style.content_margin_bottom = 8

		var hover_style = btn_style.duplicate() as StyleBoxFlat
		hover_style.bg_color = Color(0.11, 0.31, 0.78, 1.0)

		primary_button.add_theme_stylebox_override("normal", btn_style)
		primary_button.add_theme_stylebox_override("hover", hover_style)
		primary_button.add_theme_stylebox_override("pressed", hover_style)
	else:
		# Disabled state for empty queues or unsupported mode
		primary_button.add_theme_color_override("font_color", Color(0.55, 0.60, 0.68, 1.0))
		primary_button.add_theme_color_override("font_disabled_color", Color(0.55, 0.60, 0.68, 1.0))

		var dis_style = StyleBoxFlat.new()
		dis_style.bg_color = Color(0.92, 0.94, 0.96, 1.0)
		dis_style.border_width_left = 1; dis_style.border_width_top = 1; dis_style.border_width_right = 1; dis_style.border_width_bottom = 1
		dis_style.border_color = Color(0.88, 0.90, 0.94, 1.0)
		dis_style.corner_radius_top_left = 6; dis_style.corner_radius_top_right = 6; dis_style.corner_radius_bottom_left = 6; dis_style.corner_radius_bottom_right = 6
		dis_style.content_margin_left = 14; dis_style.content_margin_right = 14; dis_style.content_margin_top = 8; dis_style.content_margin_bottom = 8

		primary_button.add_theme_stylebox_override("disabled", dis_style)
		primary_button.add_theme_stylebox_override("normal", dis_style)

func _on_button_pressed() -> void:
	if not queue_id.is_empty():
		action_requested.emit(queue_id)
