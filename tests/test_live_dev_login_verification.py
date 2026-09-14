#!/usr/bin/env python3
import urllib.request
import json
import ssl
import sys

ctx = ssl.create_default_context()
ctx.check_hostname = False
ctx.verify_mode = ssl.CERT_NONE

url = "https://dev-gateway.reallife-studycenter.org/api/v1/mobile/auth/login"
payload = {
    "identifier": "johnboytejr@gmail.com",
    "pin": "123456"
}
headers = {
    "Content-Type": "application/json",
    "Accept": "application/json",
    "X-Environment": "development",
    "User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X)"
}

def do_login(label):
    print(f"\n--- {label} ---")
    data = json.dumps(payload).encode('utf-8')
    req = urllib.request.Request(url, data=data, headers=headers, method="POST")

    try:
        with urllib.request.urlopen(req, context=ctx) as resp:
            status = resp.status
            body_text = resp.read().decode('utf-8')
            res = json.loads(body_text)
            print("HTTP Status:", status)
            print("Response Payload:", res)
            if status == 200 and res.get("success") is True:
                print(f"✅ {label}: PASS!")
                return True
            else:
                print(f"❌ {label}: FAIL!")
                return False
    except urllib.error.HTTPError as e:
        body_text = e.read().decode('utf-8')
        print(f"❌ {label} HTTP Error {e.code}: {body_text}")
        return False
    except Exception as e:
        print(f"❌ {label} EXCEPTION:", e)
        return False

print("==========================================================")
print("VERIFYING LIVE DEVELOPMENT MOBILE LOGIN ENDPOINT")
print("==========================================================")

t1 = do_login("Initial Test Request")
t2 = do_login("Repeat Test Request (Persistence Verification)")

if t1 and t2:
    print("\n==========================================================")
    print("ALL LIVE LOGIN VERIFICATIONS PASSED 100%!")
    print("==========================================================")
    sys.exit(0)
else:
    print("\n==========================================================")
    print("LIVE LOGIN VERIFICATION FAILED!")
    print("==========================================================")
    sys.exit(1)
