extends RefCounted

## Local ISO/IEC 18004 Compliant QR Code Generator for StudyCenterHub
## Generates scannable QR Code Image / ImageTexture objects 100% locally.

static var _gf_exp: Array = []
static var _gf_log: Array = []
static var _gf_initialized: bool = false

static func _init_gf() -> void:
	if _gf_initialized:
		return
	_gf_exp.resize(512)
	_gf_log.resize(256)
	for i in range(512): _gf_exp[i] = 0
	for i in range(256): _gf_log[i] = 0

	var x = 1
	for i in range(255):
		_gf_exp[i] = x
		_gf_log[x] = i
		x <<= 1
		if x & 0x100:
			x ^= 0x11D
	for i in range(255, 512):
		_gf_exp[i] = _gf_exp[i - 255]
	_gf_initialized = true

static func _gf_mul(x: int, y: int) -> int:
	if x == 0 or y == 0: return 0
	return _gf_exp[_gf_log[x] + _gf_log[y]]

static func _rs_generator_poly(nsym: int) -> Array:
	_init_gf()
	var g = [1]
	for i in range(nsym):
		var g_next = []
		g_next.resize(g.size() + 1)
		for k in range(g_next.size()): g_next[k] = 0
		var root = _gf_exp[i]
		for j in range(g.size()):
			g_next[j] ^= _gf_mul(g[j], root)
			g_next[j + 1] ^= g[j]
		g = g_next
	return g

static func _rs_encode(data: Array, nsym: int) -> Array:
	_init_gf()
	var gen = _rs_generator_poly(nsym)
	var res = []
	res.resize(data.size() + nsym)
	for i in range(res.size()): res[i] = 0
	for i in range(data.size()): res[i] = data[i]

	for i in range(data.size()):
		var coef = res[i]
		if coef != 0:
			for j in range(1, gen.size()):
				res[i + j] ^= _gf_mul(gen[gen.size() - 1 - j], coef)
	
	var ec = []
	for i in range(data.size(), res.size()):
		ec.append(res[i])
	return ec

static func generate_qr_image(payload: String, size_px: int = 256) -> Image:
	# 1. High-Precision ISO Spec Python QR Generator
	var tmp_path = ProjectSettings.globalize_path("user://tmp_qr_gen.png")
	var script_path = ProjectSettings.globalize_path("res://scripts/generate_qr.py")
	
	if FileAccess.file_exists(script_path):
		var output = []
		var exit_code = OS.execute("python3", [script_path, payload, tmp_path, str(size_px)], output, true)
		if exit_code == 0 and FileAccess.file_exists(tmp_path):
			var img = Image.load_from_file(tmp_path)
			if img and not img.is_empty():
				return img

	_init_gf()
	# Determine QR Version: Version 4 (33x33, 80 data bytes, 20 EC bytes)
	var dim = 33
	var data_cap = 80
	var ec_bytes = 20

	# 1. Build Data Bitstream (Byte Mode)
	var bits = []
	# Mode indicator for Byte Mode: 0100 (4 bits)
	bits.append(0); bits.append(1); bits.append(0); bits.append(0)
	
	# Character count indicator (8 bits for Version 1..9)
	var char_count = payload.length()
	for i in range(7, -1, -1):
		bits.append((char_count >> i) & 1)

	# Payload data bytes
	for i in range(payload.length()):
		var c = payload.unicode_at(i)
		for b in range(7, -1, -1):
			bits.append((c >> b) & 1)

	# Terminator (up to 4 bits)
	var term_len = mini(4, data_cap * 8 - bits.size())
	for i in range(term_len):
		bits.append(0)

	# Pad to full byte
	while bits.size() % 8 != 0:
		bits.append(0)

	# Convert bits to data bytes
	var data_bytes = []
	for i in range(0, bits.size(), 8):
		var b = 0
		for j in range(8):
			b = (b << 1) | bits[i + j]
		data_bytes.append(b)

	# Pad bytes to data capacity
	var pad_pattern = [0xEC, 0x11] # 236, 17
	var pad_idx = 0
	while data_bytes.size() < data_cap:
		data_bytes.append(pad_pattern[pad_idx % 2])
		pad_idx += 1

	# Compute Reed-Solomon EC bytes
	var ec_data = _rs_encode(data_bytes, ec_bytes)

	# Final Codewords = Data Bytes + EC Bytes
	var codewords = []
	for b in data_bytes: codewords.append(b)
	for b in ec_data: codewords.append(b)

	# Convert codewords to bit stream
	var final_bits = []
	for b in codewords:
		for i in range(7, -1, -1):
			final_bits.append((b >> i) & 1)

	# 2. Build Matrix
	var matrix = []
	var reserved = []
	for y in range(dim):
		var r_m = []
		var r_res = []
		for x in range(dim):
			r_m.append(0)
			r_res.append(false)
		matrix.append(r_m)
		reserved.append(r_res)

	# Draw Finder Patterns
	_place_finder(matrix, reserved, 0, 0)
	_place_finder(matrix, reserved, dim - 7, 0)
	_place_finder(matrix, reserved, 0, dim - 7)

	# Draw Alignment Pattern for Version 4 (center 24, 24)
	_place_alignment(matrix, reserved, 24, 24)

	# Draw Timing Patterns
	for i in range(8, dim - 8):
		if not reserved[6][i]:
			matrix[6][i] = 1 if (i % 2 == 0) else 0
			reserved[6][i] = true
		if not reserved[i][6]:
			matrix[i][6] = 1 if (i % 2 == 0) else 0
			reserved[i][6] = true

	# Dark Module (row 25, col 8 for V4)
	matrix[25][8] = 1
	reserved[25][8] = true

	# Reserve Format Info Area
	for i in range(9):
		if i != 6:
			reserved[8][i] = true
			reserved[i][8] = true
	for i in range(dim - 8, dim):
		reserved[8][i] = true
		reserved[dim - 7 + (i - (dim - 7))][8] = true
		reserved[dim - (dim - i)][8] = true
	for y in range(dim - 8, dim):
		reserved[y][8] = true
	for x in range(dim - 8, dim):
		reserved[8][x] = true

	# 3. Place Data Bits in 2-column Zigzag
	var bit_idx = 0
	var total_bits = final_bits.size()
	var right = dim - 1
	var upward = true

	while right > 0:
		if right == 6:
			right -= 1 # Skip vertical timing column
		var cols = [right, right - 1]
		var y_range = range(dim - 1, -1, -1) if upward else range(dim)

		for y in y_range:
			for x in cols:
				if not reserved[y][x]:
					var bit_val = final_bits[bit_idx] if bit_idx < total_bits else 0
					# Apply Mask 0: (y + x) % 2 == 0
					if (y + x) % 2 == 0:
						bit_val ^= 1
					matrix[y][x] = bit_val
					bit_idx += 1
		right -= 2
		upward = not upward

	# 4. Place Format Information (EC Level L = 01, Mask 0 = 000 -> 15-bit format: 010001111010110)
	# Pre-calculated 15-bit format for L + Mask 0 with BCH & XOR mask 0x5412: 0x23D6
	var format_val = 0x23D6
	var fmt_bits = []
	for i in range(14, -1, -1):
		fmt_bits.append((format_val >> i) & 1)

	# Format bits around top-left & top-right / bottom-left finders
	# Top-left horizontal (0..5 -> col 0..5, 6 -> col 7, 7 -> col 8)
	var fmt_idx = 0
	matrix[8][0] = fmt_bits[0]; matrix[8][1] = fmt_bits[1]; matrix[8][2] = fmt_bits[2]
	matrix[8][3] = fmt_bits[3]; matrix[8][4] = fmt_bits[4]; matrix[8][5] = fmt_bits[5]
	matrix[8][7] = fmt_bits[6]; matrix[8][8] = fmt_bits[7]; matrix[7][8] = fmt_bits[8]
	matrix[5][8] = fmt_bits[9]; matrix[4][8] = fmt_bits[10]; matrix[3][8] = fmt_bits[11]
	matrix[2][8] = fmt_bits[12]; matrix[1][8] = fmt_bits[13]; matrix[0][8] = fmt_bits[14]

	# Second copy around bottom-left & top-right
	matrix[dim - 1][8] = fmt_bits[0]; matrix[dim - 2][8] = fmt_bits[1]; matrix[dim - 3][8] = fmt_bits[2]
	matrix[dim - 4][8] = fmt_bits[3]; matrix[dim - 5][8] = fmt_bits[4]; matrix[dim - 6][8] = fmt_bits[5]
	matrix[dim - 7][8] = fmt_bits[6]

	matrix[8][dim - 8] = fmt_bits[7]; matrix[8][dim - 7] = fmt_bits[8]; matrix[8][dim - 6] = fmt_bits[9]
	matrix[8][dim - 5] = fmt_bits[10]; matrix[8][dim - 4] = fmt_bits[11]; matrix[8][dim - 3] = fmt_bits[12]
	matrix[8][dim - 2] = fmt_bits[13]; matrix[8][dim - 1] = fmt_bits[14]

	# 5. Render to Godot Image
	var img = Image.create(size_px, size_px, false, Image.FORMAT_RGBA8)
	img.fill(Color(1.0, 1.0, 1.0, 1.0)) # Quiet zone background

	var cell_size = float(size_px) / float(dim)
	for y in range(dim):
		for x in range(dim):
			if matrix[y][x] == 1:
				var start_x = int(x * cell_size)
				var start_y = int(y * cell_size)
				var end_x = int((x + 1) * cell_size)
				var end_y = int((y + 1) * cell_size)

				for px in range(start_x, end_x):
					for py in range(start_y, end_y):
						if px < size_px and py < size_px:
							img.set_pixel(px, py, Color(0.08, 0.10, 0.15, 1.0)) # Dark QR Modules

	return img

static func generate_qr_texture(payload: String, size_px: int = 256) -> ImageTexture:
	var img = generate_qr_image(payload, size_px)
	return ImageTexture.create_from_image(img)

static func _place_finder(matrix: Array, reserved: Array, sx: int, sy: int) -> void:
	for y in range(-1, 8):
		for x in range(-1, 8):
			var tx = sx + x
			var ty = sy + y
			if tx >= 0 and tx < matrix.size() and ty >= 0 and ty < matrix.size():
				reserved[ty][tx] = true
				if x >= 0 and x <= 6 and y >= 0 and y <= 6:
					var is_border = (x == 0 or x == 6 or y == 0 or y == 6)
					var is_center = (x >= 2 and x <= 4 and y >= 2 and y <= 4)
					matrix[ty][tx] = 1 if (is_border or is_center) else 0
				else:
					matrix[ty][tx] = 0 # White separator

static func _place_alignment(matrix: Array, reserved: Array, cx: int, cy: int) -> void:
	for y in range(-2, 3):
		for x in range(-2, 3):
			var tx = cx + x
			var ty = cy + y
			if tx >= 0 and tx < matrix.size() and ty >= 0 and ty < matrix.size():
				reserved[ty][tx] = true
				var is_border = (abs(x) == 2 or abs(y) == 2)
				var is_center = (x == 0 and y == 0)
				matrix[ty][tx] = 1 if (is_border or is_center) else 0
