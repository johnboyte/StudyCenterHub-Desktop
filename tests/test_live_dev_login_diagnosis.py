#!/usr/bin/env python3
import urllib.request
import json
import ssl

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

print("Testing POST with johnboytejr@gmail.com to", url)
data = json.dumps(payload).encode('utf-8')
req = urllib.request.Request(url, data=data, headers=headers, method="POST")

try:
    with urllib.request.urlopen(req, context=ctx) as resp:
        print("HTTP Status:", resp.status)
        body = resp.read().decode('utf-8')
        print("Response Body:", body)
except urllib.error.HTTPError as e:
        print("HTTP Error Status:", e.code)
        body = e.read().decode('utf-8')
        print("Response Body:", body)
except Exception as e:
    print("Error:", e)
