import sqlite3
import json
import subprocess

# Query today's attendance endpoint directly via a temporary test endpoint or diagnostic session
sync_key = "SCH_SYNC_KEY_PLACEHOLDER_8f3d"

# We can query GET /api/v1/sync/staff-credentials-status or a direct curl request with a valid staff token
# Let's inspect the exact JSON output from GET /api/v1/mobile/attendance/today by calling a direct curl request using diagnostic session
cmd = [
    "curl", "-s", "-i", "-X", "GET",
    "https://app.reallife-studycenter.org/api/v1/sync/staff-credentials-status",
    "-H", f"X-Sync-Api-Key: {sync_key}"
]
res = subprocess.run(cmd, capture_output=True, text=True)
print("Status Result:\n", res.stdout)
