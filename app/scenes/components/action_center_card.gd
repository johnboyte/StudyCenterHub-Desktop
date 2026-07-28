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
	var btn_label = data.get("primary_button", "Start Queue")

	if title_label:
		title_label.text = title

	if count_badge:
		count_badge.text = str(count) + " Item" + ("s" if count != 1 else "") + " Need Action"

	if detail_label:
		detail_label.text = detail
		detail_label.visible = not detail.is_empty()

	var is_supported = data.get("queue_mode_supported", true)

	if primary_button:
		if is_supported:
			primary_button.text = btn_label
			primary_button.disabled = (count == 0)
		else:
			primary_button.text = btn_label + " (Unavailable)"
			primary_button.disabled = true

	_apply_urgency_style(urgency)

func _apply_urgency_style(urgency: String) -> void:
	var color = URGENCY_COLORS.get(urgency, URGENCY_COLORS["normal"])
	if urgency_label:
		urgency_label.text = urgency.to_upper()
	
	if urgency_pill:
		var pill_style = StyleBoxFlat.new()
		pill_style.bg_color = color
		pill_style.corner_radius_top_left = 4
		pill_style.corner_radius_bottom_left = 4
		pill_style.corner_radius_top_right = 4
		pill_style.corner_radius_bottom_right = 4
		pill_style.content_margin_left = 8
		pill_style.content_margin_right = 8
		pill_style.content_margin_top = 2
		pill_style.content_margin_bottom = 2
		urgency_pill.add_theme_stylebox_override("panel", pill_style)

func _apply_button_styles() -> void:
	if not primary_button: return
	
	# Explicit font colors to prevent hover invisible white-on-white text bug
	primary_button.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	primary_button.add_theme_color_override("font_hover_color", Color(1, 1, 1, 1))
	primary_button.add_theme_color_override("font_pressed_color", Color(0.9, 0.9, 0.9, 1))
	primary_button.add_theme_color_override("font_focus_color", Color(1, 1, 1, 1))

	var btn_style = StyleBoxFlat.new()
	btn_style.bg_color = Color(0.15, 0.39, 0.92, 1.0)
	btn_style.corner_radius_top_left = 6
	btn_style.corner_radius_bottom_left = 6
	btn_style.corner_radius_top_right = 6
	btn_style.corner_radius_bottom_right = 6
	btn_style.content_margin_left = 14
	btn_style.content_margin_right = 14
	btn_style.content_margin_top = 8
	btn_style.content_margin_bottom = 8

	var hover_style = btn_style.duplicate() as StyleBoxFlat
	hover_style.bg_color = Color(0.11, 0.31, 0.78, 1.0)

	primary_button.add_theme_stylebox_override("normal", btn_style)
	primary_button.add_theme_stylebox_override("hover", hover_style)
	primary_button.add_theme_stylebox_override("pressed", hover_style)

func _on_button_pressed() -> void:
	if not queue_id.is_empty():
		action_requested.emit(queue_id)
