#!/usr/bin/env python3
import urllib.request
import json
import ssl

ctx = ssl.create_default_context()
ctx.check_hostname = False
ctx.verify_mode = ssl.CERT_NONE

gateway_url = "https://dev-gateway.reallife-studycenter.org"
sync_key = "SCH_SYNC_KEY_PLACEHOLDER_8f3d"

def fetch_json(endpoint):
    url = gateway_url + endpoint
    req = urllib.request.Request(url, headers={
        'Accept': 'application/json',
        'X-Sync-Api-Key': sync_key,
        'X-Environment': 'development',
        'User-Agent': 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X)'
    })
    try:
        with urllib.request.urlopen(req, context=ctx) as resp:
            body = resp.read().decode('utf-8')
            return resp.status, json.loads(body)
    except urllib.error.HTTPError as e:
        body = e.read().decode('utf-8')
        try:
            return e.code, json.loads(body)
        except:
            return e.code, body
    except Exception as e:
        return 0, str(e)

print("==========================================================")
print("INSPECTING LIVE DEV GATEWAY STATE WITHOUT REPAIR")
print("==========================================================")

print("\n1. Staff Credentials Status:")
status_code, status_res = fetch_json('/api/v1/sync/staff-credentials-status')
print(f"HTTP {status_code}:", json.dumps(status_res, indent=2))

print("\n2. Latest Mobile Auth Diagnostic:")
diag_code, diag_res = fetch_json('/api/v1/sync/mobile-auth-diagnostic/latest')
print(f"HTTP {diag_code}:", json.dumps(diag_res, indent=2))
