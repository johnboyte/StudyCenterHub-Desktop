extends SceneTree

# Standard ISO/IEC 18004 QR Code Generator Test
const QrGenerator = preload("res://src/domain/sync/qr_code_generator.gd")

func _init() -> void:
	print("Testing QR Code generation...")
	var payload = "https://checkin.reallife-studycenter.org/public"
	var img = QrGenerator.generate_qr_image(payload, 256)
	if img and not img.is_empty():
		print("QR Image generated successfully: ", img.get_width(), "x", img.get_height())
		var err = img.save_png("user://test_qr_output.png")
		print("Saved test QR PNG to user://test_qr_output.png (Error code: ", err, ")")
	else:
		print("FAIL: Failed to generate QR image.")
	quit(0)
