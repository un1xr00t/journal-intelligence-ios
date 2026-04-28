# Journal Intelligence iOS

Flutter iOS client for Journal Intelligence, a self-hosted personal journal intelligence platform with AI analysis, guided writing, deep-linkable companion flows, and an iOS-first Liquid Glass UI.

## What This Repo Is

- An iOS-first Flutter app.
- A client for the backend at `https://journal.williamthomas.name`.
- A native+Flutter hybrid app with:
  - Flutter UI and state management
  - native iOS speech recognition
  - deep-link routing
  - CarPlay launch support
  - a home screen quick-entry widget

## Tech Stack

- Flutter / Dart
- iOS native Swift integrations
- `adaptive_platform_ui` for Liquid Glass-style UI
- `provider` for app state
- `dio` + `cookie_jar` + `dio_cookie_manager` for authenticated API access
- `flutter_secure_storage` for secure local storage
- `shared_preferences` for non-sensitive local preferences
- `image_picker`, `file_picker`, `archive`, `image` for media/import flows
- `share_plus`, `path_provider`, `syncfusion_flutter_pdf` for export/share flows
- `local_auth` for device authentication
- `flutter_markdown` for rendered AI output
- `audioplayers` for audio playback

## Product Areas In The App

### Main tab shell

The primary app shell is a 5-tab `AdaptiveScaffold`:

- `Today`: daily brief, trajectory, risk, and trend summary
- `Timeline`: entry history, living summary/insight, entry detail, edit flows, images
- `Write`: manual journal entry capture
- `Intelligence`: Ask My Journal entrypoint from the main nav
- `More`: full feature directory

### Implemented feature screens

These screens exist in `lib/screens/` and are part of the current client:

- `login_screen.dart`: username/password login, 2FA, passkey-related auth entry
- `splash_screen.dart`: boot/loading screen while auth restores
- `home_shell.dart`: 5-tab app shell
- `today_screen.dart`: daily brief and status overview
- `timeline_screen.dart`: paginated entries, summary card, reflection actions, attachments, edit flow
- `entry_detail_screen.dart`: individual entry view
- `write_screen.dart`: journal entry composition, including voice-entry support hooks
- `ask_journal_screen.dart`: RAG chat over journal entries
- `more_screen.dart`: feature index/hub
- `sage_screen.dart`: assistant chat experience with journal-aware context
- `saved_sage_chats_screen.dart`: saved Sage conversation browser
- `sage_settings_screen.dart`: Sage behavior/tone/preferences configuration
- `detective_screen.dart`: case list / detective mode overview
- `detective_case_screen.dart`: individual detective case workspace with tabs, evidence, photos, research, intelligence, export, and settings
- `early_warning_screen.dart`: AI alerts and escalation signals
- `fairness_ledger_screen.dart`: task/contribution/equity tracking
- `mental_health_screen.dart`: trends, crisis indicators, narrative, people impact
- `war_room_screen.dart`: triage-style action planning
- `budget_planner_screen.dart`: planning + AI-assisted financial comparison workflows
- `exit_plan_screen.dart`: structured roadmap / phased planning
- `my_story_screen.dart`: AI-generated personal narrative drafting
- `proof_vault_screen.dart`: folders, dated proof entries, photos, summaries
- `exports_screen.dart`: export generation and download/share flows
- `resources_screen.dart`: crisis and support resources
- `admin_screen.dart`: admin controls, users, invites, spend/usage views
- `settings_screen.dart`: account, memory, password, AI provider, tone, sessions, SMS, resources, security questions, and 2FA
- `onboarding_screen.dart`: onboarding, memory setup, provider setup, Day One import, SMS, and account setup
- `invite_access_screen.dart`: invite-token access flow
- `carplay_companion_screen.dart`: companion experience launched from CarPlay/deep links

### Present in the feature hub but still placeholder / not built out here

These are listed in the app UI but currently route to placeholder views rather than dedicated implementations:

- Contradictions
- Nervous System
- Patterns
- People Map
- People & Topics

## App Services And State

### Providers

- `lib/providers/auth_provider.dart`: auth state machine, login, 2FA, passkey auth, logout, cold-start session restore
- `lib/providers/launch_intent_provider.dart`: maps deep links/native launch intents into app tabs and companion flows

### Services

- `lib/services/api_service.dart`: source of truth for all backend API calls, token handling, refresh behavior, attachment/media uploads, and saved floatchat fallback storage
- `lib/services/ai_response_limits.dart`: shared Sage reply, living summary, and TTS chunk budgets
- `lib/services/launch_route_service.dart`: listens for native launch route events
- `lib/services/voice_entry_service.dart`: Flutter wrapper around native speech recognition channels
- `lib/services/sage_profile_service.dart`: local Sage settings and memory persistence

### Models

- `lib/models/detective_entry_draft.dart`: draft model for detective entry creation

### Shared widgets

- `lib/widgets/glass_card.dart`: reusable card surface
- `lib/widgets/section_header.dart`: shared section heading component

### Theme

- `lib/theme/app_theme.dart`: app theme and `JournalColors`

## Native iOS Pieces

This repo is not Flutter-only. It also contains native iOS integrations in `ios/`:

- `ios/Runner/AppDelegate.swift`: Flutter app bootstrap
- `ios/Runner/SceneDelegate.swift`: configures speech channels and launch-route event channels
- `ios/Runner/LaunchRouteStreamHandler.swift`: queues and emits deep-link launch routes into Flutter
- `ios/Runner/SpeechRecognitionService.swift`: native speech-to-text service used by voice entry
- `ios/Runner/CarPlaySceneDelegate.swift`: CarPlay grid launcher for companion, voice, briefing, Today, Sage, and Detective routes
- `ios/JournalQuickEntryWidget/JournalQuickEntryWidget.swift`: home-screen widget for quick entry and app shortcuts

The iOS workspace and CocoaPods files are also present:

- `ios/Runner.xcodeproj`
- `ios/Runner.xcworkspace`
- `ios/Podfile`
- `ios/Podfile.lock`
- `ios/Pods/`

## Deep Links And Companion Routing

The app already handles route-driven launches for:

- `/today`
- `/timeline`
- `/write`
- `/compose`
- `/ask`
- `/intelligence`
- `/sage`
- `/detective`
- `/more`
- `/settings`
- `/carplay`

## Backend/API Surface The Client Targets

The client is wired around these backend areas:

- auth, session restore, 2FA, passkeys, security questions
- journal entries, entry detail, edit, delete, bookmark, attachments
- write/upload flows
- Today brief
- therapist insight / living-summary-style timeline insight
- Ask My Journal RAG
- Sage / floating chat saved conversations
- reflections per entry
- settings and AI provider configuration
- onboarding / memory
- people intelligence
- mental health dashboard
- mood trends, rollups, patterns, contradictions
- decision assistant
- exit-plan flows

Reference docs for exact routes live under `codex/Project Instructions/`, especially:

- `API_REFERENCE.md`
- `ROUTE_MAP.md`
- `timeline_master_summary_contract.md`

## Repo Layout

```text
.
├── AGENTS.md
├── README.md
├── pubspec.yaml
├── assets/
│   └── images/
│       └── logo.png
├── android/                         # Flutter Android scaffold is present
├── ios/
│   ├── Runner/
│   ├── Runner.xcodeproj/
│   ├── Runner.xcworkspace/
│   ├── JournalQuickEntryWidget/
│   ├── Podfile
│   └── Pods/
├── lib/
│   ├── main.dart
│   ├── models/
│   ├── providers/
│   ├── screens/
│   ├── services/
│   ├── theme/
│   └── widgets/
├── docs/
│   └── timeline_insight_enrichment_notes.md
└── codex/
    ├── Context/
    └── Project Instructions/
```

## `lib/` Inventory

```text
lib/
├── main.dart
├── models/
│   └── detective_entry_draft.dart
├── providers/
│   ├── auth_provider.dart
│   └── launch_intent_provider.dart
├── screens/
│   ├── admin_screen.dart
│   ├── ask_journal_screen.dart
│   ├── budget_planner_screen.dart
│   ├── carplay_companion_screen.dart
│   ├── detective_case_screen.dart
│   ├── detective_screen.dart
│   ├── early_warning_screen.dart
│   ├── entry_detail_screen.dart
│   ├── exit_plan_screen.dart
│   ├── exports_screen.dart
│   ├── fairness_ledger_screen.dart
│   ├── home_shell.dart
│   ├── invite_access_screen.dart
│   ├── login_screen.dart
│   ├── mental_health_screen.dart
│   ├── more_screen.dart
│   ├── my_story_screen.dart
│   ├── onboarding_screen.dart
│   ├── proof_vault_screen.dart
│   ├── resources_screen.dart
│   ├── sage_screen.dart
│   ├── sage_settings_screen.dart
│   ├── saved_sage_chats_screen.dart
│   ├── settings_screen.dart
│   ├── splash_screen.dart
│   ├── timeline_screen.dart
│   ├── today_screen.dart
│   ├── war_room_screen.dart
│   └── write_screen.dart
├── services/
│   ├── api_service.dart
│   ├── launch_route_service.dart
│   ├── sage_profile_service.dart
│   └── voice_entry_service.dart
├── theme/
│   └── app_theme.dart
└── widgets/
    ├── glass_card.dart
    └── section_header.dart
```

## Internal Project Docs

The repo includes internal build/reference material under `codex/Project Instructions/`:

- `PROJECT_INSTRUCTIONS.md`
- `FLUTTER_ARCHITECTURE.md`
- `API_REFERENCE.md`
- `DESIGN_SYSTEM.md`
- `ROUTE_MAP.md`
- `timeline_master_summary_contract.md`
- `YELLOW_UNDERLINE_FIX.md`
- `api_reference_answers.md`

There are also backend/web reference copies under `codex/Context/`, including files such as:

- `Admin.jsx`
- `BudgetPlanner.jsx`
- `EarlyWarning.jsx`
- `Exports.jsx`
- `FairnessLedger.jsx`
- `FloatingChat.jsx`
- `InviteAccess.jsx`
- `Onboarding.jsx`
- `ProofVault.jsx`
- `Timeline.jsx`
- `Today.jsx`
- supporting route copies like `floating_chat_routes.py` and `onboarding_routes.py`

Those files are useful for context and parity work, but this repository is the iOS client, not the backend/web source of truth.

## Local Development

```bash
flutter pub get
flutter run
```

Useful project commands:

```bash
flutter analyze
flutter test
```

## Notes

- The app is iOS-first even though the default Flutter `android/` scaffold is still present.
- All client API calls are centralized in `lib/services/api_service.dart`.
- The repo already contains generated iOS dependency artifacts like `Pods/` and workspace files.
- The existing GitHub README used to be a starter placeholder; this one is intended to document the actual shipped/client-side surface area in the repo.
