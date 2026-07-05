# Journal Intelligence iOS

<p align="center">
  <img src="assets/images/logo.png" alt="Journal Intelligence logo" width="120">
</p>

<p align="center">
  iOS-first journal intelligence for reflection, pattern detection, case-building, safety planning, and AI-assisted memory.
</p>

<p align="center">
  <img alt="Flutter" src="https://img.shields.io/badge/Flutter-iOS--first-02569B?logo=flutter&logoColor=white">
  <img alt="Swift" src="https://img.shields.io/badge/Native-Swift%20bridges-F05138?logo=swift&logoColor=white">
  <img alt="Self-hosted" src="https://img.shields.io/badge/Backend-Self--hosted-2E7D32">
  <img alt="Local-first" src="https://img.shields.io/badge/Data-Local--first%20sync-6A1B9A">
</p>

<p align="center">
  <img src="assets/images/readme/hero-overview.svg" alt="Journal Intelligence feature overview">
</p>

Journal Intelligence is not just a journaling app. It is a private, self-hosted personal intelligence system that helps turn raw entries into usable insight, searchable memory, structured evidence, and concrete next steps.

This Flutter iOS client connects to `https://journal.williamthomas.name` and combines Liquid Glass UI, native iOS integrations, local-first notification logic, and a broad set of specialized AI workflows for daily reflection, high-stakes documentation, and long-horizon planning.

## What's New

The latest release cycle turned Sage from a chat screen into an ambient presence, and turned one-off tools into synced, local-first systems.

- **Sage Inbox** — Sage now reaches out to you. After journaling, adaptive check-ins land in a personal inbox as real notes with email-style replies and instant notifications, tuned to use fewer AI calls while feeling more personal.
- **Hands-free Sage Voice Mode** — a full voice conversation loop with Sage, plus dedicated voice reflection sessions with stable speech capture.
- **Argument Tracker** — a mobile workspace that builds structured reports from conflict-related entries, feeds them into Sage's context, and supports Sage-powered in-place corrections.
- **Follow-Ups** — a live operational tracker for job applications, recruiter threads, paperwork, and waiting-on-someone loops, with priorities, reminder times, Today-screen pressure cards, photo attachments, and server sync.
- **Orbit Ledger** — a compact event log for tracking recurring requests, with one-tap quick-log chips, backfill support, swipe actions, and server-backed local-first sync.
- **Quiet Journal mode** — an alternate calm shell with calendar-driven history, a distraction-free composer, and silent background entry refresh.
- **Journal PIN lock** — device PIN unlock for restored sessions with haptic keypad feedback, draft preservation across locks, and an app-switcher privacy cover so backgrounded snapshots never show journal content.
- **ElevenLabs voices + lock screen audio** — Sage Alive and Sage Fast voices with restrained expressive cues, iOS lock screen playback controls, background audio, and pipelined TTS for fast time-to-first-audio.
- **Budget What-If Simulator** — rent/mortgage and utilities simulation, per-expense sliders, current-vs-what-if comparisons, and named saved scenarios.
- **Cross-device sync** — settings, Sage saved chats, Follow-Ups, and Orbit Ledger now restore from the server after login or reinstall, while staying local-first in daily use.
- **Siri capture** — Siri shortcut capture flow with persistent session restore and smart fallbacks.
- **Security hardening pass** — strict biometric-only Face ID, single-flight token refresh, and encrypted storage for location history (details below).

## Why This App Exists

- Capture what happened before it gets lost, whether that starts as writing, speech, SMS, Siri, a widget tap, or a CarPlay launch.
- Turn journal history into something usable with daily briefs, timeline insight, semantic search, per-entry reflections, and long-form assistant chat.
- Support real-life decision making with dedicated tools for early warning, mental health tracking, fairness analysis, evidence collection, budgeting, exit planning, and narrative drafting.
- Keep sensitive workflows grounded in iOS-native behavior with Face ID, passkeys, 2FA, PIN lock, session controls, local notifications, and native speech support.

## Product Tour

<p align="center">
  <img src="assets/images/readme/product-surfaces.svg" alt="Journal Intelligence product surfaces">
</p>

### Core journaling and memory capture

- `Write` is the fast path for manual journaling, with deep links, notification prefills, native voice-entry hooks, and draft preservation across PIN locks.
- `Write` supports **URL context attachments**: link a page as structured context for the AI without ever altering your raw entry text, alongside photo attachments in the Memory Context card.
- `Timeline` is the living record: paginated entries, AI summaries on tiles, edit/delete flows, swipe actions, bookmarks, reflections, and stabilized photo uploads with correct same-day ordering.
- `Timeline` also acts like an insight console: it pulls the best cached therapist-insight card for the preferred tone, falls back across tones when needed, regenerates on demand, reads the summary aloud with chunked TTS, and hands the full thread straight into Sage.
- **Quiet Journal** is an alternate app shell for low-noise journaling: calendar-first history browsing, day detail views, a keyboard-safe composer, and silent merging of newly saved entries.
- `Today` generates a daily brief with emotional state, risk, trajectory, trends, what matters most right now, and a **Follow-Up Pressure card** when open, overdue, or stale-waiting items need attention.
- `Ask My Journal` is a journal-wide RAG search experience that answers questions against your own entries and shows supporting matches.
- **Siri capture** lets you journal by voice through a Siri shortcut, with persistent session restore and native session sync so nothing is lost between launches.
- `Day One` import is built into onboarding so existing journal history can be brought forward instead of starting from zero.
- `SMS journaling` support lets the account verify a phone number and use text-based intake flows from the same system.

### Sage: the persistent assistant

- `Sage` is the long-form assistant experience with journal context, optional web search, saved conversations, attachments, route-based handoff flows, file review, image review, and track-aware coaching memory.
- **Sage Inbox** flips the interaction model: after you journal, Sage writes adaptive check-in notes to a personal inbox with instant notifications. Replies work like email threads, messages read like they came from someone who actually knows your history, and the whole loop is engineered to minimize AI calls.
- **Voice Mode** is a hands-free spoken conversation with Sage, complementing voice reflection sessions built on stable speech capture.
- **Saved chats sync across devices**, so a conversation started on the phone is there after a reinstall or on the simulator.
- A **local identity memory store** gives every AI surface shared, consistent context about who you are, and **reference context routing** lets Sage pull in the right journal entries, Argument Tracker reports, and Follow-Up state for the conversation at hand.
- Timeline posts continued in Sage carry **journal entry references** (entry id, date, source) as lightweight context hints instead of expensive attachments.
- Sage can ingest supported files and images inside chat — plain text formats, PDFs, `.docx`, `.odt`, markdown, structured text, and common image formats — and chat responses support full text selection and copy.

### Sage focus tracks

- Focus tracks are persistent coaching threads that help Sage remember what you are working on across sessions instead of treating every chat like a blank slate.
- Each track stores a `title`, `category`, `current goal`, `why this matters`, `next commitment`, `recent wins`, `stuck points`, `open loops`, `success markers`, `status`, and a check-in cadence.
- Built-in categories include `Breakup`, `Custody`, `Burnout`, `Finances`, `Sobriety`, `Leaving`, and `General`.
- Check-in cadence can be `Daily`, `Weekly`, or `When I Open Sage`, depending on how active or lightweight you want the thread to feel.
- Tracks can be marked as the primary track, paused, resumed, archived, or deleted, and Sage can mute a track for a single chat when you want a conversation to stay separate.
- Track check-ins capture what happened, mood, progress status, the win, the hard part, the next step, and whether the user confirmed the entry, giving Sage an ongoing record of momentum and friction instead of a single snapshot.
- When a track is active for the session, Sage injects that goal, the recent wins, stuck points, open loops, next commitment, cadence, and last check-in directly into the chat context.

### AI reflection and analysis

- Timeline insight uses the therapist insight backend to generate a living summary of recent entries, with cache-aware refresh behavior and race-safe swipe regeneration.
- Entry reflections support six tones: `therapist`, `detective`, `coach`, `friend`, `philosopher`, and `chaos_agent`.
- Timeline insight supports multiple summary voices: `therapist`, `best_friend`, `coach`, `mentor`, `inner_critic`, and `chaos_agent`.
- Timeline can continue directly into Sage with a trimmed, reliability-safe living-summary handoff so the next chat starts from the current emotional and narrative context.
- Anthropic **prompt caching** splits Sage prompts into stable and dynamic blocks so long-lived context is reused across turns instead of re-billed.
- People intelligence, mood trend data, rollups, contradictions, and pattern alerts are all part of the backend surface this client is wired to.

### Voice and audio

- **ElevenLabs integration** powers Sage's spoken replies with two voices — `Sage Alive` and `Sage Fast` — and supports restrained expressive cues like `[laughs]`, `[sighs]`, and `[whispers]` when appropriate.
- Voice keys are managed backend-only with secure entry and no local persistence.
- **iOS lock screen controls** for all generated AI audio: Now Playing metadata, play/pause/toggle, and 15-second seek via `MPRemoteCommandCenter`, with source-specific titles for Sage, Timeline Summary, and CarPlay Briefing.
- Background audio playback keeps long summaries and briefings running when the app is backgrounded.
- TTS chunk generation is **pipelined** with a smaller first chunk, so audio starts fast and stays smooth for long reads.

### Specialized workspaces

- `Detective Mode` turns journal material into case files with evidence logs, photos, uploads, research, AI intelligence refresh, chat sessions, compressed summaries, and PDF export.
- `Argument Tracker` documents conflicts as structured reports with readable quotes, supports in-place and Sage-powered corrections, and feeds report context into Sage conversations.
- `Follow-Ups` tracks live operational threads — job applications, recruiter pings, interview prep, networking, paperwork — with overdue/due-soon/waiting/done states, four priority levels, per-task reminder times, quick-start chips, task workspaces with comments and photo attachments, swipe edit/delete, and Ask Sage handoffs.
- `Orbit Ledger` is a pure historical request log with quick-log chips, type/urgency/time metadata, backfill date-time pickers, compact scan-friendly cards, and swipe actions.
- `Early Warning` watches for recurring danger patterns, matched spikes, signal confidence, active people/topics/keywords, and allows dismissal or rebuild.
- `My Mental Health` focuses on mood trends, averages, crisis indicators, and refreshed narrative interpretation.
- `Fairness Ledger` tracks recurring tasks, manual contributions, work-share distribution, and AI-generated fairness summaries.
- `Proof Vault` organizes folders, dated proof items, quick logs, file attachments, cached or regenerated vault summaries, quick-start presets (including a `Neglect` category), and **backup exports** for taking evidence with you.
- `Exit Plan` supports phased planning, tasks, notes, attachments, exports, share tokens, and structured life-change roadmapping.
- `Budget Planner` stores plans, runs AI comparisons with cached tips, and includes a **What-If Simulator**: rent/mortgage and utilities inputs, per-expense sliders, item-by-item current-vs-what-if tables with subtotals, and named saved comparisons that persist across sessions.
- `My Story` assembles a reusable narrative draft from journal history, case files, and user context.
- `War Room` gives a triage-oriented action space for urgent decisions.
- `Exports` can generate purpose-built packets such as `Weekly Digest`, `Incident Packet`, `Pattern Report`, `Therapy Summary`, and `Facts Chronology`.

### Adaptive notification nudges

<p align="center">
  <img src="assets/images/readme/adaptive-nudges.svg" alt="Adaptive notification nudges flow">
</p>

This is one of the most distinctive parts of the app and it deserves more than a one-line mention.

- Notification nudges are local iPhone notifications, not a generic push campaign.
- The app supports scheduled morning, evening, and weekly Wyatt reminders.
- It also supports saved-place geofence nudges for arrival and exit transitions like `home`, `work`, and other custom places.
- **Follow-Up reminders** add pressure where it counts: overdue items, due-soon items, and stale waiting threads generate their own notifications, with higher-priority tasks earning earlier and extra reminders.
- **Sage Inbox check-ins** arrive as instant notifications after journaling, timed adaptively rather than on a fixed clock.
- Nudges can deep-link straight into `Write` with a prefilled prompt, into `Follow-Ups`, or into `Sage` with an auto-send handoff — with stale-prefill protection so old notification content never re-injects into a fresh Write screen.
- When explainable journal-pattern prompts are enabled, the app analyzes recent timeline entries locally, looks for signals like home stress, work-to-home transitions, family language, later-day Wyatt mentions, and heavier stress windows, then rewrites notification copy to fit that pattern.
- The UI explains why a nudge became smarter instead of hiding the reasoning behind a black box.
- Location history and learned movement patterns stay on-device — now in **encrypted secure storage** — and the reminders work without APNs.

## iOS-Native Experience

- Liquid Glass-style navigation and surfaces via `adaptive_platform_ui`.
- Native speech recognition service bridged into Flutter for voice capture, voice reflection sessions, and hands-free Sage conversations.
- Siri shortcut capture with persistent session restore and native session sync.
- Lock screen media controls and background audio for generated AI speech via a native `MPRemoteCommandCenter` bridge.
- Home screen Quick Entry widget with shortcuts into `Write`, `Today`, and `Sage`.
- CarPlay launcher with routes for `Companion`, `Voice Entry`, `Briefing`, `Today`, `Ask Sage`, and `Detective`.
- Deep-link and launch-intent routing for flows like `/today`, `/timeline`, `/write`, `/ask`, `/sage`, `/follow-ups`, `/detective`, `/settings`, `/carplay`, `/budget`, `/resources`, and `/notification-nudges`.
- Haptic-rich PIN keypad with native-feeling Cupertino interactions.
- Invite-token access flows for shared or gated entry points.

## Security And Privacy

- Access tokens are kept in memory; refresh uses an HttpOnly cookie managed by `CookieJar`, with **single-flight refresh** so concurrent 401s trigger exactly one `/auth/refresh`.
- Login supports username/password, TOTP-based 2FA, backup codes, passkey authentication, and Face ID or Touch ID convenience sign-in — with `biometricOnly` enforced so the device passcode cannot bypass biometric sign-in.
- A **Journal PIN** locks restored sessions locally, survives app relaunches, preserves in-progress drafts, and avoids false re-lock triggers during in-app navigation.
- An opaque **app-switcher privacy cover** guarantees backgrounded snapshots never expose journal content.
- Saved-place coordinates and location-trigger history live in `FlutterSecureStorage` with automatic one-time migration that deletes any plaintext copies.
- Biometric credentials are wiped on explicit sign-out, while session-expiry keeps Face ID resume working.
- Recovery questions, session management, password change, and AI-provider configuration all live in the app.
- All authenticated API calls go through `lib/services/api_service.dart`.
- This repo is a client for a self-hosted system rather than a generic SaaS journaling front end.

## Local-First, Server-Backed Sync

Every synced feature follows the same discipline: render from local cache instantly, push changes to the server in the background, and hydrate from the server after login, 2FA, passkey auth, or reinstall.

- App settings, notification preferences, Sage settings, and shell mode sync through `/api/settings` with dirty-state tracking and deterministic conflict behavior.
- Follow-Ups sync tasks, comments, and photo attachments via multipart upload — with generation checks so stale background pushes can never overwrite newer saves.
- Orbit Ledger entries and Sage saved chats restore automatically to any device.
- Biometric credentials and the Journal PIN deliberately stay device-local and are never included in server-backed settings.

## Main App Areas

The primary shell is a five-tab `AdaptiveScaffold`:

- `Today`
- `Timeline`
- `Write`
- `Intelligence`
- `More`

The `More` hub expands into the broader product surface:

- `Inbox` (Sage Inbox)
- `Sage`
- `Ask My Journal`
- `Detective Mode`
- `Exit Plan`
- `Fairness Ledger`
- `Follow-Ups`
- `My Mental Health`
- `My Story`
- `War Room`
- `Argument Tracker`
- `Proof Vault`
- `Exports`
- `Early Warning`
- `Orbit Ledger`
- `Budget Planner`
- `Resources`
- `Settings`
- `Admin`

A separate **Quiet Journal** shell mode replaces the full app surface with a calm, calendar-first journaling experience when that is all you want open.

## Repo Highlights

- `lib/screens/` contains the app surface, including feature-heavy screens like `sage_inbox_screen.dart`, `sage_voice_mode_screen.dart`, `argument_tracker_screen.dart`, `follow_ups_screen.dart`, `orbit_ledger_screen.dart`, `quiet_journal_shell.dart`, `detective_case_screen.dart`, `exit_plan_screen.dart`, `proof_vault_screen.dart`, and `timeline_screen.dart`.
- `lib/services/api_service.dart` is the source of truth for backend communication, auth refresh, uploads, exports, Sage, voice, invite access, and all feature APIs.
- `lib/services/notification_nudge_service.dart` contains the local-first adaptive notification system.
- `lib/services/user_settings_sync_service.dart` implements local-first, server-backed settings sync.
- `lib/services/follow_up_tasks_service.dart` and `lib/services/orbit_ledger_service.dart` implement the synced workspace stores.
- `lib/providers/auth_provider.dart`, `lib/providers/app_lock_provider.dart`, and `lib/providers/launch_intent_provider.dart` handle auth state, PIN lock, and route-driven launches.
- `ios/Runner/` contains the native speech, notification, launch-route, CarPlay, and remote-audio-control bridge code (`RemoteAudioControlBridge.swift`).
- `ios/JournalQuickEntryWidget/` contains the home-screen widget extension.

## Tech Stack

- Flutter and Dart
- Native iOS Swift integrations
- `adaptive_platform_ui`
- `provider`
- `dio`, `cookie_jar`, `dio_cookie_manager`
- `flutter_secure_storage`
- `shared_preferences`
- `local_auth`
- `flutter_markdown`
- `audioplayers`
- `image_picker`, `file_picker`, `archive`, `image`
- `share_plus`, `path_provider`, `syncfusion_flutter_pdf`

## Current Gaps In This Client

These features are present in the hub but still route to placeholder views in this repo:

- `Contradictions`
- `Nervous System`
- `Patterns`
- `People Map`
- `People & Topics`

## Development Notes

- Source-of-truth project instructions live in `codex/Project Instructions/`.
- API usage should always be checked against `API_REFERENCE.md` and `ROUTE_MAP.md`.
- Timeline summary behavior is documented in `timeline_master_summary_contract.md`.
- The app is iOS-first, but the Flutter Android scaffold is still present in the repo.
