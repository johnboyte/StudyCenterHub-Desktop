#!/usr/bin/env python3
"""
Apple Wallet PKPass Signer Utility
Generates icon & logo assets, manifest.json, signs it using OpenSSL PKCS7 detached signature, and zips into a valid .pkpass bundle.
"""

import sys
import os
import json
import zlib
import struct
import hashlib
import subprocess
import zipfile

def create_png(width, height, r, g, b, alpha=255):
    png_sig = b'\x89PNG\r\n\x1a\n'
    ihdr_data = struct.pack('>IIBBBBB', width, height, 8, 6, 0, 0, 0)
    ihdr_crc = zlib.crc32(b'IHDR' + ihdr_data)
    ihdr_chunk = struct.pack('>I', len(ihdr_data)) + b'IHDR' + ihdr_data + struct.pack('>I', ihdr_crc)
    
    row_bytes = b'\x00' + struct.pack('BBBB', r, g, b, alpha) * width
    raw_data = row_bytes * height
    compressed_data = zlib.compress(raw_data)
    idat_crc = zlib.crc32(b'IDAT' + compressed_data)
    idat_chunk = struct.pack('>I', len(compressed_data)) + b'IDAT' + compressed_data + struct.pack('>I', idat_crc)
    
    iend_crc = zlib.crc32(b'IEND')
    iend_chunk = struct.pack('>I', 0) + b'IEND' + struct.pack('>I', iend_crc)
    return png_sig + ihdr_chunk + idat_chunk + iend_chunk

def ensure_pass_assets(pass_dir):
    assets = {
        "icon.png": (29, 29, 218, 165, 32),
        "icon@2x.png": (58, 58, 218, 165, 32),
        "logo.png": (160, 50, 0, 0, 0),
        "logo@2x.png": (320, 100, 0, 0, 0),
        "logo@3x.png": (480, 150, 0, 0, 0),
        "thumbnail.png": (90, 90, 218, 165, 32),
        "thumbnail@2x.png": (180, 180, 218, 165, 32)
    }
    project_root = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    logo_src_1x = os.path.join(project_root, "assets", "cards", "pass_logo.png")
    logo_src_2x = os.path.join(project_root, "assets", "cards", "pass_logo@2x.png")
    logo_src_3x = os.path.join(project_root, "assets", "cards", "pass_logo@3x.png")

    for filename, (w, h, r, g, b) in assets.items():
        file_path = os.path.join(pass_dir, filename)
        if not os.path.exists(file_path):
            if filename == "logo.png" and os.path.exists(logo_src_1x):
                import shutil
                shutil.copyfile(logo_src_1x, file_path)
            elif filename == "logo@2x.png" and os.path.exists(logo_src_2x):
                import shutil
                shutil.copyfile(logo_src_2x, file_path)
            elif filename == "logo@3x.png" and os.path.exists(logo_src_3x):
                import shutil
                shutil.copyfile(logo_src_3x, file_path)
            else:
                with open(file_path, "wb") as f:
                    f.write(create_png(w, h, r, g, b))

def generate_manifest(pass_dir):
    manifest = {}
    for root, _, files in os.walk(pass_dir):
        for f in files:
            if f in ['manifest.json', 'signature'] or f.startswith('.'):
                continue
            full_path = os.path.join(root, f)
            rel_path = os.path.relpath(full_path, pass_dir)
            with open(full_path, 'rb') as fp:
                manifest[rel_path] = hashlib.sha1(fp.read()).hexdigest()
    
    manifest_path = os.path.join(pass_dir, 'manifest.json')
    with open(manifest_path, 'w') as fp:
        json.dump(manifest, fp, indent=2)
    return manifest_path

def sign_manifest(manifest_path, cert_path, key_path, wwdr_path, signature_path):
    cmd = [
        'openssl', 'smime', '-sign',
        '-signer', cert_path,
        '-inkey', key_path,
        '-certfile', wwdr_path,
        '-in', manifest_path,
        '-out', signature_path,
        '-outform', 'DER',
        '-binary'
    ]
    res = subprocess.run(cmd, capture_output=True, text=True)
    return res.returncode == 0, res.stderr

def build_pkpass(pass_dir, output_pkpass_path):
    with zipfile.ZipFile(output_pkpass_path, 'w', zipfile.ZIP_DEFLATED) as zf:
        for root, _, files in os.walk(pass_dir):
            for f in files:
                if f.startswith('.'):
                    continue
                full_path = os.path.join(root, f)
                rel_path = os.path.relpath(full_path, pass_dir)
                zf.write(full_path, rel_path)

if __name__ == '__main__':
    if len(sys.argv) < 6:
        print("Usage: sign_pkpass.py <pass_dir> <cert.pem> <key.pem> <wwdr.pem> <output.pkpass>")
        sys.exit(1)

    p_dir = sys.argv[1]
    cert = sys.argv[2]
    key = sys.argv[3]
    wwdr = sys.argv[4]
    out_pkpass = sys.argv[5]

    ensure_pass_assets(p_dir)
    m_path = generate_manifest(p_dir)
    sig_path = os.path.join(p_dir, 'signature')
    ok, err = sign_manifest(m_path, cert, key, wwdr, sig_path)
    if not ok:
        print(f"Error signing manifest: {err}")
        sys.exit(1)

    build_pkpass(p_dir, out_pkpass)
    print(f"Successfully generated signed .pkpass bundle at {out_pkpass}")
