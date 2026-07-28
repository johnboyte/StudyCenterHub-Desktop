# Project Rules & Customizations

## Architecture & Integration Standards

### Cloud Relay vs. Native Application Boundaries
The cloud relay exists only because external services (Twilio, future webhook integrations) require a publicly accessible endpoint. It is infrastructure, not part of the application server logic.
* **Minimal Durable Relay**: The relay must remain provider-agnostic, accepting raw/normalized events, temporarily buffering them, and exposing secure pull/ack endpoints. It must not perform caller profile matching, permissions, workflow decisions, transcription processing, or maintain customer application state.
* **Configuration Origin**: IVR/phone configurations and general app settings must originate in Godot, save to local SQLite cache, synchronize to the customer-owned Google Workspace, and publish automatically to the relay cache.
* **Godot is the Application**: All business logic, UI, reports, and workflow processing live in the Godot client.
* **Google Workspace is the Source of Truth**: SQLite is the local cache, Google Sheets is the cloud source of truth.

### UI & Input Controls Standards
* **App-Wide Blinking Cursor / Caret Rule**: All user-entered text controls (`LineEdit` and `TextEdit`) across all views MUST explicitly enable blinking carets (`caret_blink = true`) and set dark high-contrast caret colors (`add_theme_color_override("caret_color", Color(0.12, 0.16, 0.22, 1.0))`) to guarantee the typing cursor is clearly visible on light theme input controls app-wide.
* **Date Format Standard & Smart Unformatted Entry Rule**: All date displays and user date inputs MUST conform to `MM/DD/YYYY` format in UI controls and convert to ISO `YYYY-MM-DD` for database persistence. When users type unformatted 8-digit strings (e.g. `"08221965"` for August 22, 1965) or 6-digit strings (`"082226"`), date inputs and normalizer helpers MUST automatically format them into `MM/DD/YYYY` (`08/22/1965`) and normalize to canonical ISO `YYYY-MM-DD` (`1965-08-22`).
* **Button Hover Contrast Rule**: All styled button controls MUST explicitly override `font_hover_color`, `font_pressed_color`, and `font_focus_color` to guarantee text remains clearly legible on light/hover backgrounds without defaulting to invisible white text.
* **Modal Dialog Close 'X' Window Rule**: All modal dialog windows (`Window`) MUST connect `dialog.close_requested` to their primary Cancel/Close button action so clicking the top-right `X` window control executes identical unsaved-changes protection and cleanup logic as clicking the bottom Cancel button.
* **CheckBox Text High-Contrast Rule**: All `CheckBox` controls across all views MUST explicitly override `font_color` (`Color(0.12, 0.18, 0.26, 1.0)` / `#1F2937`), `font_pressed_color`, and `font_hover_color` (`#E05936`) so checkbox labels are crisp and readable on light backgrounds instead of defaulting to low-contrast white text.
* **Automatic Staging App Launch Rule**: Always launch the staging application (`STUDYCENTERHUB_ENV=staging /Users/johnboyte/Downloads/Godot.app/Contents/MacOS/Godot --path /Users/johnboyte/Development/StudyCenterHub-Desktop/study-center-hub---desktop`) after completing any code change to the app so the user can immediately test and inspect changes in the live staging environment.
