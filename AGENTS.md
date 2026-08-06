# AGENTS.md

Guidance for working in the Neutral Pip codebase (Flutter + Android). Formerly "PrivateAgent" — the package name (`com.neutralpip.app`), some file names, and history still reflect the old name.

## What this is

Neutral Pip is an Android **AI trading co-pilot** built with Flutter. It is a chat-first app: the user talks (text or voice) about markets, charts, and risk, and the assistant answers via either a user-configured trading backend (`POST {backend}/chat`) or a direct LLM call (OpenRouter / NVIDIA NIM / DeepSeek, all OpenAI-compatible chat endpoints).

**The app does not control the phone.** There is no accessibility service, no tap/click/swipe execution, no contact/SMS/call permissions, and no task-executor loop. The Android manifest grants only: `INTERNET`, `RECORD_AUDIO`, `POST_NOTIFICATIONS`, `SYSTEM_ALERT_WINDOW`, `FOREGROUND_SERVICE`, plus speech-recognition and TTS queries. Do not reintroduce phone-control capabilities; this is a structural guarantee, not just a UI choice.

## Commands

```bash
flutter pub get                 # resolve deps (uses local_plugins override)
flutter test                    # CI runs this; only test/ai_service_test.dart exists
flutter analyze                 # flutter_lints (analysis_options.yaml includes flutter_lints/flutter.yaml)
```

**Never run `flutter build` on this machine** — the EC2 box does not have enough RAM for Flutter/Gradle builds. All APK builds happen on Codemagic (pushed to GitHub, Codemagic builds automatically). Workflow for any code change: make the edit → `flutter analyze` only → commit → push to GitHub. Kill any local build jobs if one is accidentally started.

## Architecture / control flow

```
User input (voice, text, Telegram) → HomeScreen / TelegramService
  → trading_api_service (POST {backend}/chat, chart_url vision)  ┐
  → ai_service.sendMessage(isAgentMode: false) (direct-LLM fallback) ┘
  → reply text → VoiceService.speak() (TTS readout)
```

- **`lib/main.dart`** — main entry. Also defines `overlayMain()` (second engine entry point for the floating overlay, must keep `@pragma("vm:entry-point")`). Registers `onOverlayTask` callback and listens on `FlutterOverlayWindow.overlayListener` when the feature flag is on.
- **`lib/screens/home_screen.dart`** — main chat (trading-only). Sends via `TradingApiService.chat(...)` (backend URL set) or `AiService.sendMessage(..., isAgentMode: false)` (fallback). The mic button is always visible and routes speech to the same chat path; every assistant reply is read aloud with `VoiceService.speak`. Quick actions (Chart URL, Attach, Journal, Risk) and the secure-API trust badge live here. `app_shell.dart` and `home_dashboard.dart` are the shell / quick-action grid (`models/home_quick_action.dart` enum: `pasteUrl | askAi | upload | voice`).
- **`lib/services/`** — `ai_service.dart` (LLM client, chat + vision, system prompts), `trading_api_service.dart` (secure backend client), `voice_service.dart` (STT/TTS), `telegram_service.dart` (chat-only Telegram bridge, no action execution), plus `notification_service.dart`, `chat_history_service.dart`.
- **`lib/models/`** — `chat_message.dart` (incl. `ChatAttachment` for trading attachments), `saved_skill.dart` (legacy).
- **`android/app/src/main/kotlin/com/neutralpip/app/`** — `MainActivity.kt` only (FlutterActivity; channel registration for the old accessibility bridge is inert now that the service is not declared). `AgentAccessibilityService.kt` and `Test.kt` are dead leftovers, not part of the build.

## Dead code policy (keep these files, don't wire them in)

The following files are **legacy phone-control code** and must not be imported by new code, "cleaned up" by being wired in, or enabled:

- `lib/services/action_handler.dart`, `task_executor.dart`, `screen_automation_service.dart`, `app_launcher_service.dart`, `communication_service.dart`, `contacts_service.dart`, `alarm_service.dart`, `system_control_service.dart`, `shizuku_service.dart`, `recovery_engine.dart`, `skill_memory_service.dart`, `task_history_logger.dart`
- `lib/models/agent_action.dart` (its `AgentActionResult` class is also re-exported via `chat_message.dart` — keep that field for compilation)
- `lib/screens/task_history_screen.dart`
- `lib/overlay_main.dart` (floating overlay UI; still imports several dead services and is behind `FeatureFlags.floatingOverlayEnabled = false`)
- `android/app/src/main/kotlin/com/neutralpip/app/AgentAccessibilityService.kt`, `Test.kt`

They remain because `overlay_main.dart` and the legacy dashboard still import them; deleting them breaks compilation. The user-facing app is 100% trading-only regardless. If a future pass decommissions the overlay entry point in `main.dart` and `FeatureFlags.floatingOverlayEnabled`, these can be deleted together.

## AI service gotchas (`lib/services/ai_service.dart`)

- Defaults: DeepSeek `https://api.deepseek.com` / `deepseek-chat`. NVIDIA NIM base `https://integrate.api.nvidia.com/v1` (default model `z-ai/glm-5.2`), OpenRouter `https://openrouter.ai/api/v1`.
- All config lives in `SharedPreferences`: `api_key`, `api_base_url`, `api_model`, `api_temperature`, `api_max_tokens`, `api_use_system_prompt`, `telegram_bot_token`, `telegram_enabled`, `telegram_chat_ids` (StringList), `trading_backend_url`, `themeMode`, `onboarding_completed`. Legacy keys `api_max_steps`, `api_disable_max_steps`, `api_use_screen_compression`, `trading_mode_enabled` are no longer surfaced in the UI but are still read/written by `ai_service.dart` for backwards compatibility — safe to leave.
- `saveSettings` strips a `Bearer ` prefix from pasted keys.
- `<think>...</think>` blocks are stripped from responses (streaming strips them on the fly, tracking `inThinkBlock`).
- The GLM default model gets a forced `_effectiveMaxTokens` floor of 4096 (reasoning models burn the 1024 default on thinking).
- Conversation history is capped at 20 messages in memory (not persisted; `chat_history_service.dart` handles persistence).
- Retries up to 4 times on chat; the 30-minute HTTP timeout is applied per request.
- Requests always send `HTTP-Referer: https://github.com/neutralpip/neutral-pip` and `X-Title: Neutral Pip` headers (OpenRouter attribution).

## Trading backend rules (`lib/services/trading_api_service.dart`)

- **TRADING MODE: never add tap-based execution.** The trading path must not depend on `ScreenAutomationService`/`TaskExecutor`/`ActionHandler` and must never call taps/swipes. Only screenshots (`captureChartScreenshot`) are allowed there — and the current UI no longer uses it.
- When a backend URL is set, chat posts to `{backend}/chat` with `message`, `history`, `attachments` (metadata only), and singular `chart_url` (first URL attachment wins). Any non-200 / missing `reply` falls through to the direct AI call.
- `analyze()` is a stub returning mock data (backend endpoint `POST /analyze` is future work).
- The trading UI screens (`risk_dashboard_screen.dart`, `journal_screen.dart`) use shared widgets: `SignalChip`, `PriceText`, `RiskBar`, `StatCard`, `TradingAvatar` in `lib/widgets/`.

## Persistence / files

- `chat_history.jsonl`-style persistence handled by `chat_history_service.dart` in the app documents dir.
- `skills_memory.jsonl` and `task_history.jsonl` are written only by the legacy dead-code services above; they are no longer produced by the trading app.

## Testing

- Only `test/ai_service_test.dart` exists (tests NVIDIA URL detection, free-model filtering, defaults). No widget tests for the app itself. The local plugins have their own tests but are separate packages.
- `flutter test` must stay green — CI gates on it.

## Project structure notes

- `pubspec.yaml` declares a **dependency override**: `flutter_overlay_window` → `./local_plugins/flutter_overlay_window` (a vendored fork with Java-based overlay service). Changes to the overlay plugin affect the app build directly.
- `local_plugins/agent_native/` is a generated plugin scaffold (method-channel template) that is **not referenced anywhere** in the app — leave it alone or remove it, but don't wire it in.
- minSdk 26 (Android 8.0), applicationId `com.neutralpip.app`. Release APKs are also checked for Android 15/16's 16 KB native-library alignment.
- UI theme: dark trading co-pilot theme in `lib/config/theme.dart` (`AppColors` with `amber` primary, `surfaceDark` cards, `bear` = red); overlay uses JetBrains Mono via `google_fonts`. Screens: `home_screen.dart` (main chat), `settings_screen.dart`, `onboarding_screen.dart`.
- Notable uncommitted local change: `android/gradle.properties` has duplicated `org.gradle.jvmargs`/`org.gradle.daemon=false` lines (memory-constrained build tweak, 1 GiB heap). Don't commit this accidentally.

## Git history context

Recent work: rebrand (PrivateAgent → Neutral Pip), dark trading UI redesign, **phone-control removal (trading-only app)**, voice chat in trading mode (STT + TTS readout), trading co-pilot chat with chart vision, Telegram scheduled analysis push, and overlay plugin stabilization (currently flag-disabled). Commits use conventional-style messages.
