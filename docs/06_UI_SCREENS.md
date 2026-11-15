# UI screen inventory

**Latest navigation prototype:** see [Complete Screen UI Design](21_COMPLETE_SCREEN_UI_DESIGN.md).

The UI-only preview branch has a navigable Flutter catalog with **120 screen destinations across 19 modules**, for Windows and Android. It uses fictional data and shared layout templates. It does **not** mean 120 production workflows are implemented.

## Existing detailed Flutter UI preserved

- Six-stage admission wizard: student, guardians, academic placement, documents, fees and review.
- Admission document statuses and configurable conditional deadlines are described, but trusted upload/finalization is not connected.
- Student directory: demo student search, filtering, responsive desktop table/mobile cards and read-only profile.

## New UI preview

The main app shell on the design branch exposes all module groups, global screen/action search, the assigned-campus concept, responsive desktop navigation and Android bottom navigation. Preview templates include cards/dashboards, tables, forms, payment-allocation calculations, attendance marking, cash reconciliation, approval review, slips and sync status.

For authoritative domain decisions, consult [Confirmed Decisions](10_DECISIONS.md), [Security Baseline](15_SECURITY_BASELINE.md), and [Complete Screen UI Design](21_COMPLETE_SCREEN_UI_DESIGN.md).

**Implementation safety:** No real authentication, permission-protected database reads, financial posting, storage uploads, sync or backup is performed by these UI previews. Flutter analyzer, widget tests and platform builds require local verification before merging the design PR. The SQL under supabase/drafts remains undeployed.
