import sys
from PIL import Image

def decode_qr(image_path: str) -> str:
    img = Image.open(image_path).convert("L")
    w, h = img.size
    pixels = img.load()

    # Binarize image (black = 1, white = 0)
    # Threshold at 128
    threshold = 128
    grid_bin = []
    for y in range(h):
        row = []
        for x in range(w):
            row.append(1 if pixels[x, y] < threshold else 0)
        grid_bin.append(row)

    # Find Top-Left Finder Pattern (7x7 modules)
    # Scan horizontally to find 1:1:3:1:1 ratio
    finder_tl = None
    for y in range(h):
        runs = []
        last_val = grid_bin[y][0]
        count = 0
        for x in range(w):
            val = grid_bin[y][x]
            if val == last_val:
                count += 1
            else:
                runs.append((last_val, count, x - count))
                last_val = val
                count = 1
        runs.append((last_val, count, w - count))

        for i in range(len(runs) - 4):
            if runs[i][0] == 1 and runs[i+1][0] == 0 and runs[i+2][0] == 1 and runs[i+3][0] == 0 and runs[i+4][0] == 1:
                r1, r2, r3, r4, r5 = runs[i][1], runs[i+1][1], runs[i+2][1], runs[i+3][1], runs[i+4][1]
                total = r1 + r2 + r3 + r4 + r5
                mod_size = total / 7.0
                if abs(r1 - mod_size) < mod_size*0.5 and abs(r2 - mod_size) < mod_size*0.5 and abs(r3 - 3*mod_size) < mod_size*0.8 and abs(r4 - mod_size) < mod_size*0.5 and abs(r5 - mod_size) < mod_size*0.5:
                    finder_tl = (runs[i][2], y, mod_size)
                    break
        if finder_tl:
            break

    # If pure image matrix parsing:
    # Use qrcode / zxing / python fallback
    # Let's also check zbar / qrdecoder or OpenCV if available, or sample grid directly
    # For robust verification, sample matrix:
    # Finder top-left is at (finder_tl[0], finder_tl[1]) with module size finder_tl[2]
    # Let's locate top-right finder
    # Top-right finder is at top right
    # Scan from top-right
    if not finder_tl:
        return ""

    start_x, start_y, mod_size = finder_tl
    # Center of top-left finder is (start_x + 3.5*mod_size, start_y + 3.5*mod_size)
    # Find top-right finder center
    finder_tr = None
    for y in range(int(start_y), int(start_y + 7*mod_size)):
        runs = []
        last_val = grid_bin[y][0]
        count = 0
        for x in range(w):
            val = grid_bin[y][x]
            if val == last_val:
                count += 1
            else:
                runs.append((last_val, count, x - count))
                last_val = val
                count = 1
        runs.append((last_val, count, w - count))

        for i in range(len(runs) - 5, 0, -1):
            if i >= 0 and i+4 < len(runs):
                if runs[i][0] == 1 and runs[i+1][0] == 0 and runs[i+2][0] == 1 and runs[i+3][0] == 0 and runs[i+4][0] == 1:
                    r1, r2, r3, r4, r5 = runs[i][1], runs[i+1][1], runs[i+2][1], runs[i+3][1], runs[i+4][1]
                    total = r1 + r2 + r3 + r4 + r5
                    ms = total / 7.0
                    if abs(r1 - ms) < ms*0.5 and abs(r2 - ms) < ms*0.5 and abs(r3 - 3*ms) < ms*0.8 and abs(r4 - ms) < ms*0.5 and abs(r5 - ms) < ms*0.5:
                        if runs[i][2] > start_x + 10*mod_size:
                            finder_tr = (runs[i][2], y, ms)
                            break
        if finder_tr:
            break

    if not finder_tr:
        return ""

    # Estimate dimension
    dist_px = (finder_tr[0] + 3.5*finder_tr[2]) - (start_x + 3.5*mod_size)
    num_modules = int(round(dist_px / mod_size)) + 7

    # Sample matrix grid
    grid = []
    margin_x = start_x
    margin_y = start_y
    for r in range(num_modules):
        row = []
        cy = int(margin_y + (r + 0.5) * mod_size)
        for c in range(num_modules):
            cx = int(margin_x + (c + 0.5) * mod_size)
            if 0 <= cx < w and 0 <= cy < h:
                row.append(grid_bin[cy][cx])
            else:
                row.append(0)
        grid.append(row)

    # Read Format Info (Mask pattern & EC level)
    # Format bits at (8,0..5), (8,7..8), (7..0, 8)
    fmt_raw = 0
    coords = [(8,0), (8,1), (8,2), (8,3), (8,4), (8,5), (8,7), (8,8), (7,8), (5,8), (4,8), (3,8), (2,8), (1,8), (0,8)]
    for bx, (ry, rx) in enumerate(coords):
        if ry < num_modules and rx < num_modules:
            bit = grid[ry][rx]
            fmt_raw = (fmt_raw << 1) | bit

    fmt_unmasked = fmt_raw ^ 0x5412
    ec_level = (fmt_unmasked >> 13) & 3
    mask_pattern = (fmt_unmasked >> 10) & 7

    # Helper mask function
    def is_masked(r, c, pattern):
        if pattern == 0: return (r + c) % 2 == 0
        if pattern == 1: return r % 2 == 0
        if pattern == 2: return c % 3 == 0
        if pattern == 3: return (r + c) % 3 == 0
        if pattern == 4: return ((r // 2) + (c // 3)) % 2 == 0
        if pattern == 5: return ((r * c) % 2) + ((r * c) % 3) == 0
        if pattern == 6: return (((r * c) % 2) + ((r * c) % 3)) % 2 == 0
        if pattern == 7: return (((r + c) % 2) + ((r * c) % 3)) % 2 == 0
        return False

    # Reserved area map
    reserved = [[False]*num_modules for _ in range(num_modules)]
    # Finders
    for r in range(7):
        for c in range(7):
            reserved[r][c] = True
            reserved[r][num_modules - 7 + c] = True
            reserved[num_modules - 7 + r][c] = True
    # Timing
    for i in range(num_modules):
        reserved[6][i] = True
        reserved[i][6] = True
    # Format info
    for i in range(9):
        reserved[8][i] = True
        reserved[i][8] = True
    for i in range(num_modules - 8, num_modules):
        reserved[8][i] = True
        reserved[i][8] = True

    # Alignment pattern for V2+
    if num_modules >= 25:
        # V2 (25): 18,18; V3 (29): 22,22; V4 (33): 24,24; V5 (37): 28,28
        align_centers = []
        if num_modules == 25: align_centers = [18]
        elif num_modules == 29: align_centers = [22]
        elif num_modules == 33: align_centers = [24]
        elif num_modules == 37: align_centers = [28]
        elif num_modules == 41: align_centers = [30]
        for ac in align_centers:
            for r in range(ac - 2, ac + 3):
                for c in range(ac - 2, ac + 3):
                    if 0 <= r < num_modules and 0 <= c < num_modules:
                        reserved[r][c] = True

    # Traverse bits in 2-column zigzag
    data_bits = []
    c = num_modules - 1
    upward = True
    while c > 0:
        if c == 6:
            c -= 1
        cols = [c, c - 1]
        rows = range(num_modules - 1, -1, -1) if upward else range(num_modules)
        for r in rows:
            for col in cols:
                if not reserved[r][col]:
                    bit = grid[r][col]
                    if is_masked(r, col, mask_pattern):
                        bit ^= 1
                    data_bits.append(bit)
        c -= 2
        upward = not upward

    # Convert bits to bytes
    bytes_data = []
    for i in range(0, len(data_bits) - 7, 8):
        val = 0
        for b in range(8):
            val = (val << 1) | data_bits[i + b]
        bytes_data.append(val)

    # Parse Mode (first 4 bits)
    mode = (data_bits[0] << 3) | (data_bits[1] << 2) | (data_bits[2] << 1) | data_bits[3]
    # Byte mode = 4 (0100)
    # Character count length for V1-9 = 8 bits
    count = 0
    for i in range(4, 12):
        count = (count << 1) | data_bits[i]

    # Payload bytes start at bit 12
    payload_bytes = []
    bit_ptr = 12
    for _ in range(count):
        val = 0
        for b in range(8):
            if bit_ptr + b < len(data_bits):
                val = (val << 1) | data_bits[bit_ptr + b]
        payload_bytes.append(val)
        bit_ptr += 8

    return bytes(payload_bytes).decode('utf-8', errors='ignore')

if __name__ == "__main__":
    if len(sys.argv) >= 2:
        res = decode_qr(sys.argv[1])
        print("DECODED_VALUE:" + res)
