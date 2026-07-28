# StudyCenterHub Platform Architecture Specification
## Version: v1.0
## Milestone: StudyCenterHub Platform Architecture v1.0

This document serves as the permanent system architecture reference for StudyCenterHub. All future development, additions, and integrations must strictly adhere to the guidelines and boundaries established in this specification.

---

## 1. Platform Purpose

StudyCenterHub is a cross-platform, offline-first application designed for local study centers to manage constituent directories, scheduling, volunteer assignments, student check-ins, and automated phone/SMS communications. It is built to run native client apps on macOS, iOS, Android, and Windows, allowing customers to host, control, and own their data without relying on vendor-hosted server infrastructure.

---

## 2. Customer Ownership & Privacy Model

StudyCenterHub operates under a **Zero-Hosting** architecture model:
*   **Customer-Owned Infrastructure**: Customers pay for and manage their own Google Workspace accounts and external service providers (e.g., Twilio). We do not host their operational data.
*   **Data Control**: The customer owns their source of truth (Google Workspace) and local client storage (SQLite). We update the software, but the customer retains full physical custody of their databases and spreadsheets.

### The Customer Ownership Rule
> **Customer data belongs entirely to the customer and remains in customer-owned systems at all times. The Cloud Relay is a stateless transit buffer and must never become the source of truth, host customer databases, or maintain long-term application state.**

---

## 3. Platform Architecture Diagram

```
                 Customer's Google Workspace Cloud
             ┌─────────────────────────────────────────┐
             │ Google Sheets (Source of Truth)         │
             │ Google Drive (Storage for Assets/Photos) │
             │ Gmail & Calendar                        │
             └─────────────────────────────────────────┘
                                  ▲
                                  │ Google APIs (OAuth)
                                  ▼
                     ┌─────────────────────────┐
                     │ Godot Client App (Core) │
                     │   (UI, Business Logic,  │
                     │    Matching, Gemini)    │
                     └─────────────────────────┘
                                  ▲
                                  │ local queries
                                  ▼
                     ┌─────────────────────────┐
                     │ SQLite Operational DB   │
                     │  (Local Cache, Outbox)  │
                     └─────────────────────────┘
                                  ▲
                                  │ HTTP Sync Loop (/pull, /ack, /ivr-config)
                                  ▼
                     ┌─────────────────────────┐
                     │ Cloud Relay (SiteGround)│
                     │  (Stateless Event Queue)│
                     └─────────────────────────┘
                                  ▲
                                  │ Webhooks & TwiML
                                  ▼
                     ┌─────────────────────────┐
                     │ Twilio / Carrier Cloud  │
                     └─────────────────────────┘
```

---

## 4. Component Boundaries & Responsibilities

To maintain a clean and maintainable codebase, clear responsibilities are assigned to each architectural boundary.

### A. Godot Client Application
Godot is the core application runtime. All software behavior belongs in Godot.
*   **Responsibilities**:
    *   Renders the user interface (Rosters, Check-in kiosks, Admin settings).
    *   Enforces all permissions, business logic, and constituent status workflows.
    *   Performs caller-to-constituent matching by querying local SQLite directories.
    *   Integrates with the Gemini API to transcribe voicemails and compile summaries.
    *   Coordinates the sync engine (pulling/acknowledging events from the relay and flushing outbox items to Google Sheets).

### B. SQLite Operational Database
SQLite is the local database engine running inside the Godot client.
*   **Responsibilities**:
    *   Serves as the local presentation cache (for instant, zero-latency UI loading).
    *   Enables full app functionality offline.
    *   Tracks pending cloud mutations using a transactional outbox table (`event_outbox`).

### C. Google Workspace (Source of Truth)
The customer-owned Google Workspace is the cloud backend database.
*   **Responsibilities**:
    *   **Google Sheets**: Serves as the cloud database of record (Constituent lists, attendance logs, message archives).
    *   **Google Drive**: Hosts files and assets (e.g., student profile photos uploaded during kiosk check-in).

### D. Cloud Relay
The Cloud Relay is a lightweight, minimal server hosted on the customer's SiteGround site.
*   **Responsibilities**:
    *   Exposes public endpoints to receive incoming webhook events from Twilio (and future carriers).
    *   Caches the active IVR configuration (`ivr_config.json`) published by the Godot app.
    *   Returns immediate, provider-required responses (such as TwiML dial-routing or carrier compliance messages) statelessly.
    *   Temporarily buffers events in a durable queue (`inbound_event_queue`) with duplicate protection using unique event IDs.
    *   Exposes secure `/pull` and `/ack` endpoints for client sync.

### E. Twilio and Carriers
*   **Responsibilities**:
    *   Routes phone calls and SMS carriers to the Cloud Relay webhook endpoints.
    *   Executes call-handling operations based on TwiML responses returned by the relay.

---

## 5. The Sync & Compliance Model

The sync pipeline consists of two decoupled loops:

### 1. Inbound Event Pipeline (Carriers -> Relay -> Godot)
1.  Twilio sends an incoming voice or SMS webhook payload to the relay.
2.  The relay parses SMS body text for compliance keywords (`STOP`, `QUIT`, `CANCEL`, `UNSUBSCRIBE`, `START`, `UNSTOP`, `YES`, and `HELP`) and immediately returns the carrier-mandated auto-replies.
3.  The relay buffers the event in `inbound_event_queue` using `INSERT OR IGNORE` with the `MessageSid` or `CallSid` as a unique constraint to prevent duplicate processing.
4.  The Godot client executes a sync loop, calling `POST /sync/pull` to retrieve all buffered events.
5.  Godot processes the events (matching constituents, updating consent flags, transcribing audio) and sends `POST /sync/ack` with the IDs.
6.  The relay purges the acknowledged IDs from its buffer.

### 2. Outbox Sync Pipeline (Godot -> Google Sheets)
1.  All client modifications are recorded as events in SQLite's `event_outbox`.
2.  A background worker (`outbox_sync_worker.gd`) reads pending outbox events.
3.  The worker flushes mutations to the mapped Google Sheets/Drive directories.
4.  Once verified, the outbox event is marked as synchronized.

---

## 6. Architectural Decision Rules

### The Architectural Default Rule
> **Any feature that can live in the Godot application must live in the Godot application. The Cloud Relay exists only because external carriers require a publicly accessible endpoint to receive immediate responses. It must remain a minimal, provider-agnostic transit relay without business logic.**

All developers and AI agents must preserve these boundaries. Do not implement caller profiles, messaging workflows, dashboard reporting, or transcriptions inside the Cloud Relay.

---

## 7. UI & UX Conventions

### App-Wide Date Format Standard & Smart Unformatted Entry Rule
* **Month/Day/Year (`MM/DD/YYYY`)**: All user-facing UI date displays, date picker labels, and input fields MUST format and accept dates in Month/Day/Year (`MM/DD/YYYY`) format.
* **Smart Unformatted Digit Parsing**: Unformatted digit inputs (e.g. typing `"08221965"` for August 22, 1965 or `"082226"`) MUST be automatically parsed and formatted as `MM/DD/YYYY` (`08/22/1965`) in UI controls upon blur/submission and normalized to ISO `YYYY-MM-DD` (`1965-08-22`).
* **Internal Canonical Normalization**: Domain services (`schedules_service.gd`, etc.) automatically normalize `MM/DD/YYYY`, `MMDDYYYY`, or `YYYY-MM-DD` inputs into canonical ISO `YYYY-MM-DD` for database queries and SQLite storage.
* **Blinking Cursor Standard**: All user input text controls (`LineEdit` / `TextEdit`) must enable `caret_blink = true` with high-contrast caret styling app-wide.
