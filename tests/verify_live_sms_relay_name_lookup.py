#!/usr/bin/env python3
"""
Verification probe for live Production Gateway SMS relay name lookup.
Queries https://app.reallife-studycenter.org/api/v1/sync/test-sms-relay-lookup.
Does NOT send real SMS messages to constituents.
"""
import urllib.request
import urllib.parse
import json
import sys

GATEWAY_URL = "https://app.reallife-studycenter.org"
SYNC_API_KEY = "SCH_SYNC_KEY_PLACEHOLDER_8f3d"

TEST_CASES = [
    {
        "description": "Known Constituent (E.164 format): McKenna Boykin",
        "phone": "+17073656637",
        "expected_name": "McKenna Boykin"
    },
    {
        "description": "Known Constituent (US formatted): Karadyn Merritt",
        "phone": "(864) 389-2093",
        "expected_name": "Karadyn Merritt"
    },
    {
        "description": "Known Constituent (Raw 10 digits): Mike Settle",
        "phone": "8643140297",
        "expected_name": "Mike Settle"
    },
    {
        "description": "Known Constituent (Title casing): Khalil Peake",
        "phone": "+1 864 607 4831",
        "expected_name": "Khalil Peake"
    },
    {
        "description": "Unknown Contact (Unlisted phone)",
        "phone": "+18645550222",
        "expected_name": "Unknown Contact"
    }
]

def check_endpoint():
    print("==================================================================")
    print("PROBING PRODUCTION GATEWAY SMS RELAY NAME LOOKUP")
    print(f"Target: {GATEWAY_URL}/api/v1/sync/test-sms-relay-lookup")
    print("==================================================================")

    endpoint_ready = False
    all_passed = True

    for tc in TEST_CASES:
        phone = tc["phone"]
        expected = tc["expected_name"]
        desc = tc["description"]

        url = f"{GATEWAY_URL}/api/v1/sync/test-sms-relay-lookup?phone={urllib.parse.quote(phone)}"
        headers = {
            "x-sync-api-key": SYNC_API_KEY,
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36"
        }
        req = urllib.request.Request(url, headers=headers)

        try:
            with urllib.request.urlopen(req, timeout=10) as resp:
                data = json.loads(resp.read().decode('utf-8'))
                endpoint_ready = True
                actual_name = data.get("constituent_name", "")
                sample_msg = data.get("forwarded_notification_sample", "")

                if actual_name == expected:
                    print(f"✅ PASS: {desc}")
                    print(f"   Input Phone: {phone} -> Resolved Name: '{actual_name}'")
                    first_line = sample_msg.split('\\n')[0] if sample_msg else ""
                    print(f"   Header: {first_line}")
                else:
                    print(f"❌ FAIL: {desc}")
                    print(f"   Expected '{expected}', got '{actual_name}'")
                    all_passed = False
        except urllib.error.HTTPError as e:
            err_body = e.read().decode('utf-8')
            print(f"⚠️  HTTP {e.code}: {desc} ({err_body.strip()})")
            all_passed = False
        except Exception as e:
            print(f"⚠️  Error: {e}")
            all_passed = False

    print("==================================================================")
    if endpoint_ready and all_passed:
        print("🎉 ALL PRODUCTION RELAY LOOKUP CHECKS PASSED ON LIVE SERVER!")
        return 0
    elif not endpoint_ready:
        print("ℹ️  Production gateway is running pre-deployment bundle.")
        print("   Upload 'builds/gateway_production/index.php' to SiteGround to activate.")
        return 1
    else:
        print("❌ Some checks failed on live server.")
        return 2

if __name__ == "__main__":
    sys.exit(check_endpoint())
