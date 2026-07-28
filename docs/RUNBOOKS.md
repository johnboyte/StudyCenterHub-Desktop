# Operational Runbooks & Deployment Procedures

Canonical operational procedures for staff authentication bootstrap, production releases, database backups, and emergency production resets.

---

## 1. Production Release Workflow

### Pre-Release Checklist
- [ ] Confirm development branch tests pass completely.
- [ ] Verify zero database schema or structural breaking changes exist without forward-only migrations.
- [ ] Review `docs/PRODUCT_DECISIONS.md` and `docs/STORY_STATUS.md`.

### Production Build Export & Deploy Commands
1. **Export macOS App Bundle**:
   Export a release app bundle from Godot Editor (`Export -> Mac OSX -> Release`).
2. **Deploy Node.js Communications Gateway**:
   Update the cloud server deployment for the Node gateway containing signature validator proxy updates:
   ```bash
   git checkout main
   git merge dev
   git push origin main
   ```

### Post-Release 5-Minute Smoke Test
- [ ] Launch Godot Desktop application with production variable (`STUDYCENTERHUB_ENV=production`).
- [ ] Confirm environment label in app header displays "PRODUCTION" (Slate Accent Theme).
- [ ] Check-in page loads check-in search inputs.
- [ ] Directory screen loads constituent roster.
- [ ] Person Workspace loads constituent details across all 5 tabs.
- [ ] Confirm Kiosk mode launches correctly.

---

## 2. Staff Authentication & Local Credentials Runbook

1. **Staff Profile Creation**:
   * Create the staff record inside the Directory screen.
2. **Assign Kiosk PIN and Badge Credentials**:
   * Navigate to the **Credentials** sub-tab in the Directory detailed card.
   * Enter a 4-digit PIN for self check-in access, and issue/scan a QR barcode token.
3. **Admin Exits**:
   * Exiting fullscreen Kiosk Mode requires entering the supervisor's active PIN credential to return to the workspace dashboard.

---

## 3. Emergency Production Reset Runbook

> [!CAUTION]
> **HIGH RISK OPERATION**: Perform ONLY when the database requires explicit schema re-initialization. Never perform on active production without taking a verified backup of the SQLite file first.

1. **Locate and Backup SQLite File**:
   Copy the active production database `studycenterhub_production.db` from standard macOS Application Support path:
   ```bash
   cp "/Users/johnboyte/Library/Application Support/Godot/app_userdata/StudyCenterHub - Desktop/studycenterhub_production.db" ./backup_studycenterhub_production.db
   ```
2. **Wipe and Re-run Database Schema**:
   Deleting the database file will force the Godot application to run all SQLite migrations from scratch upon launch:
   ```bash
   rm "/Users/johnboyte/Library/Application Support/Godot/app_userdata/StudyCenterHub - Desktop/studycenterhub_production.db"
   ```
3. **Re-enter Settings**:
   Launch the application to generate the clean database schema, then update Twilio configuration keys inside the Administration Settings panel.
