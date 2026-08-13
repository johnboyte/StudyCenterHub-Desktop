import sys
import qrcode
from PIL import Image

def generate_qr(payload: str, output_path: str, size_px: int = 256):
    qr = qrcode.QRCode(
        version=None,
        error_correction=qrcode.constants.ERROR_CORRECT_M,
        box_size=10,
        border=2,
    )
    qr.add_data(payload)
    qr.make(fit=True)
    img = qr.make_image(fill_color="#141E2B", back_color="white").convert("RGBA")
    if size_px > 0:
        img = img.resize((size_px, size_px), Image.Resampling.LANCZOS)
    img.save(output_path, "PNG")

if __name__ == "__main__":
    if len(sys.argv) >= 3:
        payload_arg = sys.argv[1]
        out_path_arg = sys.argv[2]
        size_arg = int(sys.argv[3]) if len(sys.argv) >= 4 else 256
        generate_qr(payload_arg, out_path_arg, size_arg)
