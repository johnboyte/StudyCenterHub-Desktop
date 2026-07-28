# Development Standards & Workflows

Canonical standards for developer CLI workflows, testing procedures, code style, and demo data management across StudyCenterHub projects.

---

## 1. Standard Implementation Workflow (8 Steps)

Every future feature story MUST strictly execute this 8-step workflow:

1. **Read Documentation**: Review canonical `README.md` and related topic docs.
2. **Read Product Decisions**: Review `docs/PRODUCT_DECISIONS.md` for binding design rules.
3. **Read Architecture**: Review `docs/ARCHITECTURE.md` to ensure structural alignment.
4. **Read Story Status**: Verify story sequence and active status in `docs/STORY_STATUS.md`.
5. **Verify No Conflicts**: Confirm zero architectural or schema contradictions exist.
6. **Implement Story**: Write modular, clean code adhering to existing project standards.
7. **Update Documentation**: Record any new product decisions in `docs/PRODUCT_DECISIONS.md` and update `docs/STORY_STATUS.md`.
8. **Produce Completion Report**: Present deliverables, test results, visual verification, and git status to Product Owner.

---

## 2. Desktop Application Development Commands (Godot 4.7+)

### Run Headless Test Suites
```bash
/Users/johnboyte/Downloads/Godot.app/Contents/MacOS/Godot --headless -s tests/test_dir_spr1_005b.gd
```

### Run Native Window GUI Visual Review Capture
```bash
/Users/johnboyte/Downloads/Godot.app/Contents/MacOS/Godot --path /Users/johnboyte/Development/StudyCenterHub-Desktop/study-center-hub---desktop app/scenes/visual_review_runner.tscn
```

---

## 3. Node.js Communications Gateway Development Commands (Node.js 20)

### Gateway Service Installation
```bash
cd /Users/johnboyte/Development/StudyCenterHub-Desktop/study-center-hub---desktop/gateway
npm run setup
```

### Start Gateway Server Locally
```bash
# To run pointing to the Staging SQLite database:
DATABASE_FILE="/Users/johnboyte/Library/Application Support/Godot/app_userdata/StudyCenterHub - Desktop/studycenterhub_staging.db" npm run dev

# To run pointing to the Production SQLite database:
DATABASE_FILE="/Users/johnboyte/Library/Application Support/Godot/app_userdata/StudyCenterHub - Desktop/studycenterhub_production.db" npm run dev
```

### Start Cloudflare Tunnel (Stable Webhook Forwarding)
Cloudflare Tunnel is pre-configured in the repository `.bin` folder. Start the tunnel:
```bash
./.bin/cloudflared tunnel --url http://localhost:3001
```
Copy the generated `trycloudflare.com` URL and paste it as the Voice webhook inside your Twilio number console.

Configure local `.env` settings to enable request validation:
```env
TWILIO_AUTH_TOKEN=your_real_or_test_twilio_auth_token
ENFORCE_TWILIO_SIGNATURE=1
```

---

## 4. Code & Testing Conventions

1. **Explicit Type Hints**: In GDScript, always specify explicit parameter and return types (e.g. `func get_person_details(uuid: String) -> Dictionary:`).
2. **Null Safety**: Always wrap optional string/dictionary lookups in string conversion guards to prevent runtime type errors (e.g. `String(dict.get("key")) if dict.get("key") != null else ""`).
3. **Tree-Safe Node Cleanup**: When clearing child nodes inside dynamic container controls, use explicit node freeing (`child.free()`) to prevent `queue_free()` warnings when nodes are not attached to an active SceneTree.
4. **Zero Production Mutation in Tests**: Automated test suites must verify that read-only UI operations and workspace views generate zero database side effects and zero outbox entries.
