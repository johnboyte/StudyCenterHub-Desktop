# Product Decisions (PD Log)

Single source of truth for architectural, domain, and product governance decisions. Every future story must reference existing Product Decisions instead of redefining architecture or user experience patterns.

---

## I. Product & Domain Decisions

### [PD-003] Standard Desktop Responsive Layout (55%/45% Split)

- **Decision ID**: PD-003
- **Title**: Standard Desktop Responsive Layout (55%/45% Split)
- **Status**: APPROVED
- **Decision**: The Directory interface uses an `HSplitContainer` dividing the Roster panel (left) and Person Workspace panel (right) at a default `55% / 45%` split proportion. Minimum window resolution is set to `900 x 700` with zero horizontal scrollbars.
- **Reason**: Provides visual balance, fast scanning speed, and optimal space allocation for native desktop displays.
- **Implementation Notes**: Configured in `directory_view.tscn` with `SplitOffset` and responsive container flags. Visual compliance verified at `1280x850`, `1600x900`, and `900x750`.
- **Affected Stories**: DIR-SPR1-005A, DIR-SPR1-005A-R, DIR-SPR1-005B

---

### [PD-004] 5-Section Person Workspace Structure

- **Decision ID**: PD-004
- **Title**: 5-Section Person Workspace Structure
- **Status**: APPROVED
- **Decision**: The Person Workspace features a permanent top header (Full Name, Human ID, Status, Year) and a 5-tab section navigation bar:
  1. **Overview**: Operational summary, contact summary, activity counters.
  2. **Profile**: Sub-sections for Contact, Roles & Access, Registration Review, Credentials.
  3. **Participation**: Sub-sections for Pathways, Sessions, Attendance History.
  4. **Communications**: Direct Actions (`Call`, `Text`, `Email`), Communication History, Check-in Messages.
  5. **History**: Notes, Attendance Events, Communication Events, Credential Events, Profile Changes.
- **Reason**: Standardizes constituent profile access and ensures consistent, scalable workspace navigation across all sub-systems.
- **Implementation Notes**: Built into `directory_view.gd` and `directory_view.tscn`. All unpopulated sub-sections display clean, informative empty-state cards.
- **Affected Stories**: DIR-SPR1-005B

---

### [PD-006] Organization Feature Visibility & Subscription Licensing

- **Decision ID**: PD-006
- **Title**: Organization Feature Visibility & Subscription Licensing
- **Status**: APPROVED
- **Decision**: Organization-level feature toggles determine which major application capabilities are available based on the customer's subscription tier. When a feature module is disabled, it:
  1. Disappears from navigation sidebars and top bars.
  2. Disappears from UI screens, home dashboard action tiles, and workspace cards.
  3. Disappears from active staff user workflows.
  4. Cannot be accessed through backend APIs or local SQLite services.
- **Reason**: Simplifies staff user experience by preventing UI clutter from unpurchased or inactive features, and guarantees strict backend security boundaries.
- **Implementation Notes**: Resolved dynamically in `app_shell.gd` and `home_view.gd` by evaluating `enabled_modules` stored in SQLite `app_settings` and Google Workspace.
- **Affected Stories**: SHELL-SPR1-001, HOME-SPR1-001, DIR-SPR1-006, DIR-SPR1-007, and all future module stories.

---

### [PD-007] Administrator Configuration First

- **Decision ID**: PD-007
- **Title**: Administrator Configuration First
- **Status**: APPROVED
- **Decision**: Whenever practical, application behavior shall be driven by administrator-configurable data rather than hardcoded values. Developers must assume configuration first for:
  - Note Types
  - Credential Types
  - Communication Categories
  - Session Types
  - Tags
  - Roles
  - Pathways
  - Templates
  - Organization Vocabulary
  Hardcoding operational values should be the rare exception requiring explicit justification.
- **Reason**: Empowers study center administrators to configure operational rules, taxonomy, and workflows without requiring developer code deployments.
- **Implementation Notes**: Sub-systems must store taxonomy/type definitions in database lookup tables (or `app_settings`) and expose management UI controls to admins. Replaces and expands former `PD-005`.
- **Affected Stories**: DIR-SPR1-006, DIR-SPR1-007, and all upcoming domain stories.

---

### [PD-008] Warm & Welcoming Desktop Design System

- **Decision ID**: PD-008
- **Title**: Warm & Welcoming Desktop Design System
- **Status**: APPROVED
- **Decision**: The entire StudyCenterHub Desktop interface adopts the "Warm & Welcoming" visual design system:
  1. **Left Navigation Sidebar**: Deep Navy (`#1E2430`) persistent sidebar with StudyCenterHub brand header, 10 primary navigation items (`Home`, `People`, `Communications`, `Attendance`, `Schedules`, `Volunteers`, `Pathways`, `Administration`, `Reports`, `Settings`), and bottom staff profile card (`John Smith - Executive Director`). Active item highlighted with Warm Terracotta pill (`#E05A36`).
  2. **Top Greeting & Header Bar**: Personalized welcome header (*"Good morning, John!"*), date indicator, search/notification triggers, and **"Today's Team Leader: [ Dropdown ]"** selector bound dynamically to SQLite `ACTIVE_SUPERVISOR`.
  3. **Canvas Background**: Warm Light Off-White (`#F7F9FC`).
  4. **Action Cards & Tiles**: Clean White (`#FFFFFF`) cards with rounded corners (`14px`), subtle borders (`#E2E8F0`), and color-coded icon accents.
- **Reason**: Establishes a cohesive, modern desktop design language that feels inviting, accessible, and comfortable for staff working long daily shifts.
- **Implementation Notes**: Implemented across `app_shell.tscn`, `home_view.tscn`, and `directory_view.tscn`.
- **Affected Stories**: SHELL-SPR1-001, HOME-SPR1-001, DIR-SPR1-006, DIR-SPR1-007

---

### [PD-009] Dynamic Role-Based Privilege Engine (RBAC)

- **Decision ID**: PD-009
- **Title**: Dynamic Role-Based Privilege Engine (RBAC)
- **Status**: APPROVED
- **Decision**: User access rights are governed by a granular Role-Based Access Control (RBAC) engine. Navigation menus, admin settings, report exports, and action buttons evaluate the signed-in user's role and assigned permission privileges before rendering:
  - **Administrator / Executive Director**: Unrestricted access to all enabled modules, organization settings, white-label branding, and security controls.
  - **Supervisor / Team Leader**: Operational access to constituent directory, check-ins, shift notes, and communications; restricted from security & billing config.
  - **Staff User**: Standard operational access to assigned sessions, constituent search, and attendance check-in.
  - **Volunteer / Kiosk Mode**: Restricted check-in kiosk view only.
  If a user lacks permission for a module or action, the control is hidden or disabled dynamically.
- **Reason**: Prevents unauthorized data access, protects privacy, and streamlines UI for non-admin staff.
- **Implementation Notes**: Evaluated centrally via `rbac_service.gd` and applied during `AppShell` view routing.
- **Affected Stories**: SHELL-SPR1-001, ADM-SPR1-001, and all feature module stories.

---

### [PD-010] White-Label Branding & Customizable Vocabulary Sub-system

- **Decision ID**: PD-010
- **Title**: White-Label Branding & Customizable Vocabulary Sub-system
- **Status**: APPROVED
- **Decision**: The MinistryHub platform provides front-end administrative controls for complete white-label customization:
  1. **Branding & Theme Engine**: Organizations can upload custom logos and configure primary accent colors (`primary_brand_color`, `sidebar_bg_color`, `card_accent_color`). UI theme styles rebind dynamically at runtime without restarting the app.
  2. **Custom Vocabulary Dictionary**: Organizations can customize core system terminology in the front-end settings:
     - *"Constituent"* → *"Student"*, *"Member"*, *"Client"*, or *"Guest"*
     - *"Session"* → *"Class"*, *"Group"*, or *"Service"*
     - *"Supervisor"* → *"Team Leader"*, *"Shift Manager"*, or *"Director"*
     - *"Pathway"* → *"Growth Track"*, *"Discipleship Steps"*, or *"Milestones"*
     All labels, headers, and UI text update dynamically across all screens based on the active vocabulary dictionary.
- **Reason**: Allows diverse ministries (study centers, churches, campus ministries, non-profit community centers) to tailor the application to match their unique identity, brand, and terminology.
- **Implementation Notes**: Vocabulary mapping dictionary stored in SQLite `app_settings` and Google Workspace settings, exposed via `vocabulary_service.gd`.
- **Affected Stories**: SHELL-SPR1-001, HOME-SPR1-001, ADM-SPR1-001, and all feature views.

---

## II. Architectural Decisions

### [PD-001] Offline-First Local Storage Architecture

- **Decision ID**: PD-001
- **Title**: Offline-First Local Storage Architecture
- **Status**: APPROVED
- **Decision**: All constituent roster data, attendance logs, and local workspace interactions are read and written locally via SQLite (`sqlite_database.gd`). Write operations append to an outbox queue (`outbox_sync_worker.gd`).
- **Reason**: The desktop application must remain instant, robust against network drops, and capable of operating completely offline in study center locations.
- **Implementation Notes**: Implemented via SQLite database wrappers, domain services (`person_service.gd`, `directory_read_service.gd`), and outbox sync table. See `docs/ARCHITECTURE.md`.
- **Affected Stories**: DIR-SPR1-001A, DIR-SPR1-001B, DIR-SPR1-002, DIR-SPR1-003, DIR-SPR1-005A, DIR-SPR1-005B

---

### [PD-002] Read-Only Presentation Layer Isolation

- **Decision ID**: PD-002
- **Title**: Read-Only Presentation Layer Isolation
- **Status**: APPROVED
- **Decision**: Directory UI views (`directory_view.gd`) and visual workspace presentation components interact with the database exclusively through dedicated read services (`directory_read_service.gd`). UI views never perform direct raw SQL mutations or mutate domain models directly.
- **Reason**: Guarantees zero side effects or unintended database mutations during visual rendering, filtering, search, and tab navigation.
- **Implementation Notes**: Enforced in `directory_view.gd` and verified via automated test assertions in `test_dir_spr1_005a.gd` and `test_dir_spr1_005b.gd`. See `docs/DEVELOPMENT_STANDARDS.md`.
- **Affected Stories**: DIR-SPR1-001B, DIR-SPR1-002, DIR-SPR1-005A, DIR-SPR1-005B
