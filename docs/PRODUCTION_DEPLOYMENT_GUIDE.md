# Production Deployment Guide

This guide describes how to deploy the minimal durable Cloud Relay on **SiteGround** (using native PHP), configure **Twilio** webhook routing, map **Google Workspace** sheets as the source of truth, and configure a new customer instance.

---

## 1. Cloud Relay Deployment on SiteGround (Native PHP)

The Cloud Relay is a native PHP script that interfaces with carrier webhooks and exposes sync endpoints for the Godot client. It runs natively on all SiteGround shared hosting plans (including the StartUp plan) without requiring any Node.js Manager, background SSH daemons, or custom compilation.

### Step 1: Create a Subdomain
1. Sign in to the customer's **SiteGround Site Tools**.
2. Navigate to **Domain** -> **Subdomains** and create a subdomain (e.g., `app.reallife-studycenter.org`).
3. Note the folder created under the subdomain root path in File Manager.

### Step 2: Upload Files
Copy the contents of the `gateway/` directory from the repository directly into the subdomain root directory. The directory structure should look like this:
```text
app.reallife-studycenter.org/
├── .htaccess (Locks down security and configures routing)
├── config.php (Stores secure API keys)
├── index.php (Central PHP routing controller)
└── database/
    ├── relay.db (Automatically created on startup)
    └── ivr_config.json (Automatically created on sync)
```

### Step 3: Configure Your Secure Sync API Key
To secure sync communication between Godot and the relay:
1. Open the **`config.php`** file in your SiteGround File Manager.
2. Replace `'your_secure_api_key_here'` with a strong, random password:
   ```php
   'SYNC_API_KEY' => 's3cr3t_p@ssw0rd_h3r3'
   ```
3. Save changes. 
*(Note: Because this is a PHP file, its contents are executed server-side and can never be read or downloaded by visitors. Additionally, the `.htaccess` file denies direct access to `.db`, `.json`, and `config.php` files for defense-in-depth security).*

### Step 4: Verify Deployment (Health Check)
Open your web browser and navigate to your subdomain's health check URL:
`https://app.reallife-studycenter.org/api/v1/health` (or `https://app.reallife-studycenter.org/health`).

You should receive a successful JSON response:
```json
{
  "status": "ok",
  "database": "connected",
  "timestamp": "2026-07-23 12:00:00 UTC"
}
```
If you see this, your Cloud Relay is fully live and successfully connected to SQLite!

---

## 2. Twilio Webhook Configuration

Twilio uses the Cloud Relay to query IVR parameters and relay raw SMS and voicemail events.

1. Sign in to the customer's **Twilio Console**.
2. Go to **Phone Numbers** -> **Active Numbers** and select the active number.
3. Scroll to the **Voice & Fax** section:
   * **Configure With**: Webhooks, TwiML Bin, Function, Studio, or Proxy.
   * **A Call Comes In**: Select **Webhook**.
   * **URL**: Set to `https://<your-subdomain>/api/v1/webhooks/twilio/voice-prompt`
   * **HTTP Method**: Set to `POST`.
4. Scroll to the **Messaging** section:
   * **Configure With**: Webhooks, TwiML Bin, Function, Studio, or Proxy.
   * **A Message Comes In**: Select **Webhook**.
   * **URL**: Set to `https://<your-subdomain>/api/v1/webhooks/twilio/sms`
   * **HTTP Method**: Set to `POST`.
5. Save the configuration.

---

## 3. Google Workspace Configuration (Source of Truth)

The StudyCenterHub app synchronizes constituents, attendance, signups, and communications back to Google Sheets.

### Step 1: Create a Google Cloud Project & Credentials
1. Go to the [Google Cloud Console](https://console.cloud.google.com/).
2. Create a new project (e.g., `StudyCenterHub`).
3. Enable the **Google Sheets API** and **Google Drive API** under **APIs & Services** -> **Library**.
4. Go to **APIs & Services** -> **Credentials**:
   * Click **Create Credentials** -> **OAuth client ID**.
   * Select **Desktop App** as the application type.
   * Download the OAuth client secrets JSON file.

### Step 2: Configure Client Settings
On the first run of the Godot client app, go to the **Administration/Settings** page:
1. Import the downloaded Google client secrets JSON.
2. Complete the OAuth sign-in flow (giving the app permissions to manage Google Drive files and Google Sheets).
3. The app will automatically provision the Google Drive folder structure (including a subfolder for check-in photos) and create the standard sheets (`StudyCenterHub Directory`, `StudyCenterHub Attendance`).

---

## 4. Launching & Initial Sync

Once the relay and customer cloud integrations are configured:
1. Open the **StudyCenterHub** desktop application.
2. Navigate to **Administration** -> **Phone Settings**:
   * Input the **Gateway Server URL** (e.g., `https://app.reallife-studycenter.org`).
   * Input the **Gateway Sync API Key** matching the server's `SYNC_API_KEY`.
   * Configure the on-call forwarding number, greeting text, and IVR menu routing tree.
3. Save changes. Saving configuration parameters automatically invokes a sync and pushes the IVR menus up to the Cloud Relay (`ivr_config.json` cache).
4. The system is now fully operational!

---

## 5. Architectural Integrity Cheat Sheet

Keep these core guidelines in mind during updates:
* **The Relay has zero business logic**: It must never match callers, verify student grades, or process transcriptions. It acts as an event buffer.
* **Godot is the App**: All Gemini audio transcription, constituent profile lookups, and workflows run locally in the client.
* **Google Workspace is the Source of Truth**: SQLite acts as a local operational cache. All mutations must go to the `event_outbox` to be synced to Sheets.
