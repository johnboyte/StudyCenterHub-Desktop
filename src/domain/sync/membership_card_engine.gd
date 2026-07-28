extends RefCounted

## Permanent Membership Card & Public Sign Rendering Engine for StudyCenterHub
## Canonical composition path using exact 1013x638 template: res://assets/cards/real_life_house_member_card_template_1013x638.png

const QrGenerator = preload("res://src/domain/sync/qr_code_generator.gd")

const CARD_WIDTH_PX: int = 1013
const CARD_HEIGHT_PX: int = 638
const TEMPLATE_PATH: String = "res://assets/cards/real_life_house_member_card_template_1013x638.png"

# Color constants
const TEXT_DARK_COLOR = Color(0.12, 0.16, 0.24, 1.0)
const AVATAR_BG_COLOR = Color(0.86, 0.89, 0.93, 1.0)
const AVATAR_DARK_COLOR = Color(0.20, 0.28, 0.38, 1.0)

# 5x7 Bitmap Font definition for clean name rendering
const FONT_DATA = {
	"A": [0x0E, 0x11, 0x11, 0x1F, 0x11, 0x11, 0x11],
	"B": [0x1E, 0x11, 0x11, 0x1E, 0x11, 0x11, 0x1E],
	"C": [0x0E, 0x11, 0x10, 0x10, 0x10, 0x11, 0x0E],
	"D": [0x1C, 0x12, 0x11, 0x11, 0x11, 0x12, 0x1C],
	"E": [0x1F, 0x10, 0x10, 0x1E, 0x10, 0x10, 0x1F],
	"F": [0x1F, 0x10, 0x10, 0x1E, 0x10, 0x10, 0x10],
	"G": [0x0E, 0x11, 0x10, 0x13, 0x11, 0x11, 0x0F],
	"H": [0x11, 0x11, 0x11, 0x1F, 0x11, 0x11, 0x11],
	"I": [0x0E, 0x04, 0x04, 0x04, 0x04, 0x04, 0x0E],
	"J": [0x07, 0x02, 0x02, 0x02, 0x02, 0x12, 0x0C],
	"K": [0x11, 0x12, 0x14, 0x18, 0x14, 0x12, 0x11],
	"L": [0x10, 0x10, 0x10, 0x10, 0x10, 0x10, 0x1F],
	"M": [0x11, 0x1B, 0x15, 0x15, 0x11, 0x11, 0x11],
	"N": [0x11, 0x11, 0x19, 0x15, 0x13, 0x11, 0x11],
	"O": [0x0E, 0x11, 0x11, 0x11, 0x11, 0x11, 0x0E],
	"P": [0x1E, 0x11, 0x11, 0x1E, 0x10, 0x10, 0x10],
	"Q": [0x0E, 0x11, 0x11, 0x11, 0x15, 0x12, 0x0D],
	"R": [0x1E, 0x11, 0x11, 0x1E, 0x14, 0x12, 0x11],
	"S": [0x0E, 0x11, 0x10, 0x0E, 0x01, 0x11, 0x0E],
	"T": [0x1F, 0x04, 0x04, 0x04, 0x04, 0x04, 0x04],
	"U": [0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x0E],
	"V": [0x11, 0x11, 0x11, 0x11, 0x11, 0x0A, 0x04],
	"W": [0x11, 0x11, 0x11, 0x15, 0x15, 0x1B, 0x11],
	"X": [0x11, 0x11, 0x0A, 0x04, 0x0A, 0x11, 0x11],
	"Y": [0x11, 0x11, 0x0A, 0x04, 0x04, 0x04, 0x04],
	"Z": [0x1F, 0x01, 0x02, 0x04, 0x08, 0x10, 0x1F],
	"0": [0x0E, 0x11, 0x13, 0x15, 0x19, 0x11, 0x0E],
	"1": [0x04, 0x0C, 0x04, 0x04, 0x04, 0x04, 0x0E],
	"2": [0x0E, 0x11, 0x01, 0x06, 0x10, 0x10, 0x1F],
	"3": [0x0E, 0x11, 0x01, 0x06, 0x01, 0x11, 0x0E],
	"4": [0x02, 0x06, 0x0A, 0x12, 0x1F, 0x02, 0x02],
	"5": [0x1F, 0x10, 0x1E, 0x01, 0x01, 0x11, 0x0E],
	"6": [0x06, 0x08, 0x10, 0x1E, 0x11, 0x11, 0x0E],
	"7": [0x1F, 0x01, 0x02, 0x04, 0x08, 0x08, 0x08],
	"8": [0x0E, 0x11, 0x11, 0x0E, 0x11, 0x11, 0x0E],
	"9": [0x0E, 0x11, 0x11, 0x0F, 0x01, 0x02, 0x0C],
	"-": [0x00, 0x00, 0x00, 0x1F, 0x00, 0x00, 0x00],
	".": [0x00, 0x00, 0x00, 0x00, 0x00, 0x0C, 0x0C],
	"'": [0x0C, 0x0C, 0x04, 0x00, 0x00, 0x00, 0x00],
	" ": [0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]
}

static func _get_text_width_px(text: String, scale: int) -> int:
	return text.length() * 6 * scale

static func _draw_bitmap_text(img: Image, start_x: int, start_y: int, text: String, scale: int, color: Color) -> int:
	var cur_x = start_x
	var upper_str = text.to_upper()
	for i in range(upper_str.length()):
		var char_str = upper_str[i]
		var glyph = FONT_DATA.get(char_str, FONT_DATA[" "])
		for row_idx in range(glyph.size()):
			var row_val = glyph[row_idx]
			for col_idx in range(5):
				if (row_val & (1 << (4 - col_idx))) != 0:
					for sy in range(scale):
						for sx in range(scale):
							var px = cur_x + (col_idx * scale) + sx
							var py = start_y + (row_idx * scale) + sy
							if px >= 0 and px < CARD_WIDTH_PX and py >= 0 and py < CARD_HEIGHT_PX:
								img.set_pixel(px, py, color)
		cur_x += 6 * scale
	return cur_x - start_x

## Canonical Composition Path for all Membership Card Workflows
static func render_membership_card(person_data: Dictionary, raw_credential_token: String = "") -> Image:
	# 1. Create exact 1013 x 638 Image
	var img = Image.create(CARD_WIDTH_PX, CARD_HEIGHT_PX, false, Image.FORMAT_RGBA8)

	# 2. Load permanent template background
	var template_img: Image
	if FileAccess.file_exists(TEMPLATE_PATH):
		template_img = Image.load_from_file(TEMPLATE_PATH)
	else:
		# Fallback if path is external or absolute
		template_img = Image.load_from_file("/Users/johnboyte/Development/StudyCenterHub-Desktop/study-center-hub---desktop/assets/cards/real_life_house_member_card_template_1013x638.png")

	if template_img and not template_img.is_empty():
		if template_img.get_width() != CARD_WIDTH_PX or template_img.get_height() != CARD_HEIGHT_PX:
			template_img.resize(CARD_WIDTH_PX, CARD_HEIGHT_PX)
		img.copy_from(template_img)
	else:
		img.fill(Color(1.0, 1.0, 1.0, 1.0))

	# 3. Add Participant Photo (x = 55, y = 210, width = 225, height = 285)
	var photo_x: int = 55
	var photo_y: int = 210
	var photo_w: int = 225
	var photo_h: int = 285

	var photo_loaded: bool = false
	var photo_path = str(person_data.get("photo_url", ""))
	if photo_path == "" or photo_path == "<null>":
		photo_path = str(person_data.get("profile_photo", ""))

	if photo_path != "" and photo_path != "<null>" and FileAccess.file_exists(photo_path):
		var custom_photo = Image.load_from_file(photo_path)
		if custom_photo and not custom_photo.is_empty():
			# Preserve proportions with center crop
			var src_w = custom_photo.get_width()
			var src_h = custom_photo.get_height()
			var target_ratio = float(photo_w) / float(photo_h)
			var src_ratio = float(src_w) / float(src_h)

			var crop_w = src_w
			var crop_h = src_h
			var start_x = 0
			var start_y = 0

			if src_ratio > target_ratio:
				crop_w = int(float(src_h) * target_ratio)
				start_x = (src_w - crop_w) / 2
			else:
				crop_h = int(float(src_w) / target_ratio)
				start_y = (src_h - crop_h) / 2

			var cropped = custom_photo.get_region(Rect2i(start_x, start_y, crop_w, crop_h))
			cropped.resize(photo_w, photo_h)

			for py in range(photo_h):
				for px in range(photo_w):
					img.set_pixel(photo_x + px, photo_y + py, cropped.get_pixel(px, py))
			photo_loaded = true

	if not photo_loaded:
		# Avatar silhouette fallback
		for py in range(photo_h):
			for px in range(photo_w):
				var cur_x = photo_x + px
				var cur_y = photo_y + py
				var rel_x = float(px) / float(photo_w)
				var rel_y = float(py) / float(photo_h)

				# Head & shoulders geometric calculation
				var dist_head = sqrt(pow(rel_x - 0.5, 2) + pow(rel_y - 0.38, 2))
				var dist_shoulders = sqrt(pow(rel_x - 0.5, 2) + pow((rel_y - 0.95) * 0.7, 2))

				if dist_head < 0.22 or dist_shoulders < 0.35:
					img.set_pixel(cur_x, cur_y, AVATAR_DARK_COLOR)
				else:
					img.set_pixel(cur_x, cur_y, AVATAR_BG_COLOR)

	# 4. Add Participant Name (x = 320, y = 330, max width = 300)
	var first_name = str(person_data.get("first_name", "Valued")).strip_edges()
	var last_name = str(person_data.get("last_name", "Member")).strip_edges()
	if first_name == "<null>" or first_name == "null": first_name = ""
	if last_name == "<null>" or last_name == "null": last_name = ""
	var display_name = (first_name + " " + last_name).strip_edges()
	if display_name == "":
		display_name = "Valued Member"

	# Calculate scale to fit within max width = 300 px
	var name_scale: int = 4
	var max_w: int = 300
	while name_scale > 1 and _get_text_width_px(display_name, name_scale) > max_w:
		name_scale -= 1

	var name_x: int = 320
	var name_y: int = 330
	_draw_bitmap_text(img, name_x, name_y, display_name, name_scale, TEXT_DARK_COLOR)

	# 5. Add Participant QR Code (x = 690, y = 210, width = 260, height = 260)
	var qr_x: int = 690
	var qr_y: int = 210
	var qr_size: int = 260

	var qr_url = "https://checkin.reallife-studycenter.org/public-returning"
	if raw_credential_token != "":
		qr_url += "?credential=" + raw_credential_token

	var qr_img = QrGenerator.generate_qr_image(qr_url, qr_size)
	if qr_img and not qr_img.is_empty():
		for py in range(qr_size):
			for px in range(qr_size):
				var target_x = qr_x + px
				var target_y = qr_y + py
				if target_x < CARD_WIDTH_PX and target_y < CARD_HEIGHT_PX:
					img.set_pixel(target_x, target_y, qr_img.get_pixel(px, py))

	return img

static func render_public_qr_sign(size_mode: String = "letter") -> Image:
	var width_px = 850
	var height_px = 1100
	if size_mode.to_lower() == "half_page":
		width_px = 850
		height_px = 550

	var img = Image.create(width_px, height_px, false, Image.FORMAT_RGBA8)
	img.fill(Color(1.0, 1.0, 1.0, 1.0))

	# Header Banner
	var banner_h = 140 if size_mode == "letter" else 80
	for y in range(banner_h):
		for x in range(width_px):
			img.set_pixel(x, y, Color(0.12, 0.16, 0.24, 1.0))

	return img

static func export_image_to_png(img: Image, file_path: String) -> Error:
	if not img or img.is_empty():
		return ERR_INVALID_DATA
	return img.save_png(file_path)

static func export_image_to_pdf(img: Image, file_path: String) -> Error:
	if not img or img.is_empty():
		return ERR_INVALID_DATA
	var png_path = file_path
	if not png_path.ends_with(".png"):
		png_path = file_path.rsplit(".", true, 1)[0] + ".png"
	return img.save_png(png_path)
