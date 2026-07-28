# StudyCenterHub Desktop

StudyCenterHub Desktop is a native cross-platform desktop application built with Godot 4.7+ and local SQLite storage for managing Study Center constituent directories, attendance, and daily operations offline.

---

## 📚 Master Documentation Index

All project documentation is consolidated into **6 canonical governance files**:

1. **[Product Decisions](docs/PRODUCT_DECISIONS.md)** (`docs/PRODUCT_DECISIONS.md`): Single source of truth for architectural, domain, and UI governance decisions (`[PD-001]` through `[PD-005]`).
2. **[Story Status](docs/STORY_STATUS.md)** (`docs/STORY_STATUS.md`): Active story tracking, upcoming backlog, technical debt, and known issues.
3. **[Architecture Specification](docs/ARCHITECTURE.md)** (`docs/ARCHITECTURE.md`): System topology, domain services, database schemas, and CORS/environment specs.
4. **[Development Standards](docs/DEVELOPMENT_STANDARDS.md)** (`docs/DEVELOPMENT_STANDARDS.md`): The 8-step implementation workflow, CLI developer commands, testing rules, and coding conventions.
5. **[Operational Runbooks](docs/RUNBOOKS.md)** (`docs/RUNBOOKS.md`): Production deployment steps, staff authentication bootstrap, and emergency database resets.
6. **[Strategic Roadmap](docs/ROADMAP.md)** (`docs/ROADMAP.md`): Operational vision and multi-phase roadmap (Phases 1–10).

---

## 🚀 Quick Development Commands

### Run Godot Automated Test Suite
```bash
/Users/johnboyte/Downloads/Godot.app/Contents/MacOS/Godot --headless -s tests/test_dir_spr1_005b.gd
```

### Run GUI Visual Review Runner
```bash
/Users/johnboyte/Downloads/Godot.app/Contents/MacOS/Godot --path /Users/johnboyte/Development/StudyCenterHub-Desktop/study-center-hub---desktop app/scenes/visual_review_runner.tscn
```
