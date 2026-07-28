extends Control

@onready var title_label: Label = $CenterContainer/PanelContainer/MarginContainer/VBoxContainer/TitleLabel
@onready var greeting_label: Label = $CenterContainer/PanelContainer/MarginContainer/VBoxContainer/GreetingLabel
@onready var message_label: Label = $CenterContainer/PanelContainer/MarginContainer/VBoxContainer/MessageLabel
@onready var status_label: Label = $CenterContainer/PanelContainer/MarginContainer/VBoxContainer/StatusLabel
@onready var test_button: Button = $CenterContainer/PanelContainer/MarginContainer/VBoxContainer/TestButton

func _ready() -> void:
	# Connect the button pressed signal
	test_button.pressed.connect(_on_test_button_pressed)
	# Ensure status label starts empty
	status_label.text = ""

func _on_test_button_pressed() -> void:
	message_label.text = "Communication test successful!"
	status_label.text = "Project Manager → Senior Developer → Godot"
	test_button.disabled = true
	test_button.text = "Test Complete"
	print("Success: Communication test completed successfully without errors.")
