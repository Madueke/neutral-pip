# AGENTS.md

Guidance for working in the Neutral Pip codebase (Flutter + Android). Formerly "PrivateAgent" — the package name and some history still reflect the old name.

## What this is

Neutral Pip is an Android AI agent ("AI trading co-pilot") built with Flutter. It drives the phone through the Android **Accessibility Service**: it dumps the UI tree, sends it to an LLM (OpenRouter / NVIDIA NIM / DeepSeek, all OpenAI-compatible chat endpoints), gets back a JSON action, and executes it natively (tap by coordinates or text, type, scroll, global back/home). It also has a "Trading Mode" that analyzes chart screenshots/URLs via a user-configured backend — that path must never perform device taps.

## Commands

```bash
flutter pub get                 # resolve deps (uses local_plugins override)
flutter test                    # CI runs this; only test/ai_service_test.dart exists
flutter analyze                 # flutter_lints (analysis_options.yaml includes flutter_lints/flutter.yaml)
```

**Never run `flutter build` on this machine** — the EC2 box does not have enough RAM for Flutter/Gradle builds. All APK builds happen on Codemagic (pushed to GitHub, Codemagic builds automatically). Workflow for any code change: make the edit → `flutter analyze` only → commit → push to GitHub. Kill any local build jobs if one is accidentally started.

## Architecture / control flow

```
User input (voice, text, Telegram) → AiService → LLM returns JSON action
  → ActionHandler.execute() dispatch → (execute_task → TaskExecutor loop) → ScreenAutomationService
  → MethodChannel "com.neutralpip/accessibility" → MainActivity.kt → AgentAccessibilityService.kt
```

- **`lib/main.dart`** — main entry. Also defines `overlayMain()` (second engine entry point for the floating overlay, must keep `@pragma("vm:entry-point")`). Registers `onOverlayTask` callback and listens on `FlutterOverlayWindow.overlayListener` when the feature flag is on.
- **`lib/overlay_main.dart`** — floating overlay chat UI (617 lines). Currently **disabled**: `lib/config/feature_flags.dart` sets `floatingOverlayEnabled = false` (overlay was temporarily disabled to stabilize; the implementation stays behind the flag). Don't "fix" this by enabling it without testing the overlay engine path.
- **`lib/services/`** — the meat. `ai_service.dart` (LLM client + system prompts), `action_handler.dart` (JSON action → service dispatch), `task_executor.dart` (multi-step loop + task system prompt + `_extractJson` robustness), `screen_automation_service.dart` (Dart bridge to native), plus `telegram_service.dart`, `trading_api_service.dart`, `skill_memory_service.dart`, `recovery_engine.dart`, `task_history_logger.dart`, and small wrappers (`app_launcher`, `communication`, `contacts`, `alarm`, `system_control`, `shizuku`, `voice`, `notification`, `chat_history`).
- **`android/app/src/main/kotlin/com/neutralpip/app/`** — native side:
  - `AgentAccessibilityService.kt` — screen dump (`dumpScreen` flattens the tree, filters zero-size/invisible nodes), `clickByText` (exact→contains, non-editable preference), `clickAtCoordinates`, `typeText` (ACTION_SET_TEXT, not per-key IME events), `pressEnter` (IME_ENTER action → keyboard action node → tap in IME window bottom-right), `scroll`, `swipe`, `longPressAt`, global actions, `takeScreenshot` (API 30+), `getCurrentPackage`.
  - `MainActivity.kt` — `MethodChannel "com.neutralpip/accessibility"` and `EventChannel "com.neutralpip/accessibility_events"` (click/scroll events pushed to Dart). `BackgroundEngineReceiver` re-registers the channel on the cached engine (`myCachedEngine`) so background engines (e.g., overlay) can use it too.
- **`lib/models/`** — `agent_action.dart` (LLM JSON action + `availableActions` list), `chat_message.dart`, `saved_skill.dart`.

## The two LLM prompt vocabularies (keep in sync!)

There are two separate action sets, each with a system prompt, a Dart dispatcher, and a native handler:

1. **Chat/agent mode** — `_systemPrompt` in `ai_service.dart:66`, dispatched by the `switch` in `action_handler.dart:37`. Actions: `open_app`, `launch_package`, `make_call`, `send_sms`, `search_contact`, `set_alarm`, `set_timer`, `set_volume`, `set_brightness`, `run_adb_command`, `send_email`, `open_url`, `read_screen`, `click_element`, `type_on_screen`, `scroll_screen`, `press_back`, `execute_task`.
2. **TaskExecutor loop** — `_taskSystemPrompt` in `task_executor.dart:53`. Actions: `click_text`, `click_at`, `type_text`, `press_enter`, `scroll`, `swipe`, `press_back`, `press_home`, `open_app`, `wait`, `done`.

If you add/rename an action, update the prompt, the dispatcher, and (for task mode) the `RecoveryEngine` heuristics that reference action names (`recovery_engine.dart:37,55`). `AgentAction.availableActions` (`models/agent_action.dart:20`) is a separate, partly stale list — it is not the source of truth for the dispatcher.

## AI service gotchas (`lib/services/ai_service.dart`)

- Defaults: DeepSeek `https://api.deepseek.com` / `deepseek-chat`. NVIDIA NIM base `https://integrate.api.nvidia.com/v1` (default model `z-ai/glm-5.2`), OpenRouter `https://openrouter.ai/api/v1`.
- All config lives in `SharedPreferences`: `api_key`, `api_base_url`, `api_model`, `api_max_steps`, `api_disable_max_steps`, `api_temperature`, `api_max_tokens`, `api_use_screen_compression`, `api_use_system_prompt`, `telegram_bot_token`, `telegram_enabled`, `telegram_chat_ids` (StringList), `trading_backend_url`, `trading_mode_enabled`, `themeMode`, `onboarding_completed`.
- `saveSettings` strips a `Bearer ` prefix from pasted keys.
- `<think>...</think>` blocks are stripped from responses (streaming strips them on the fly, tracking `inThinkBlock`).
- The GLM default model gets a forced `_effectiveMaxTokens` floor of 4096 (reasoning models burn the 1024 default on thinking).
- Conversation history is capped at 20 messages in memory (not persisted; `chat_history_service.dart` handles persistence).
- `sendTaskMessage` retries up to 4 times; the 30-minute HTTP timeout is applied per request.
- Requests always send `HTTP-Referer: https://github.com/neutralpip/neutral-pip` and `X-Title: Neutral Pip` headers (OpenRouter attribution).

## Native channel gotchas

- Dart bridge `ScreenAutomationService` wraps every invoke with a **3-second timeout** (`screen_automation_service.dart:15`). Slow native work that exceeds this throws `TimeoutException`; `dumpScreen`/`takeScreenshot` swallow errors and return empty/null instead.
- Native side filters out anything from the app's own package (`com.neutralpip.app`) so it never automates itself. Keep this when adding methods.
- `takeScreenshot` requires **Android 11 (API 30+)**; below that the channel returns `UNSUPPORTED_VERSION`.
- Common native errors surfaced to Dart: `SERVICE_NOT_RUNNING`, `SCREENSHOT_FAILED`. `waitUntilReady()`/`isServiceRunning()` (`ping` / `isServiceRunning`) are the readiness checks — TaskExecutor refuses to run if the accessibility service is off.
- `getCurrentPackage()` (native) returns the app's own package when its window is active/focused so the TaskExecutor knows to press Home before the first dump.
- Logging: Dart → native logging goes through `logToNative` (visible under logcat tag `NeutralPipDart`); Kotlin logs use `NeutralPipKotlin`/`NeutralPip` tags.

## Trading Mode rules

`trading_api_service.dart` and `screen_automation_service.dart` carry an explicit convention (comments repeated throughout):

- **TRADING MODE: never add tap-based execution.** Trading path must not depend on `ScreenAutomationService`/`TaskExecutor`/`ActionHandler` and must never call taps/swipes. Only screenshots (`captureChartScreenshot`) are allowed there.
- When a backend URL is set, chat posts to `{backend}/chat` with `message`, `history`, `attachments` (metadata only), and singular `chart_url` (first URL attachment wins). Any non-200 / missing `reply` falls through to the direct AI call.
- `analyze()` is a stub returning mock data (backend endpoint `POST /analyze` is future work).
- The trading UI screens (`risk_dashboard_screen.dart`, `journal_screen.dart`) use shared widgets: `SignalChip`, `PriceText`, `RiskBar`, `StatCard`, `TradingAvatar` in `lib/widgets/`.

## Persistence / files

- `skills_memory.jsonl` and `task_history.jsonl` in the app documents dir. Skill memory matches by Jaccard similarity on keywords (> 0.6 to hit, > 0.8 to merge/update); steps are replayed when a skill is "reliable". File-based, no DB.
- `task_history.jsonl` records `{goal, status, total_tokens, steps_taken, trace, timestamp}`; `getAnalytics()` computes success rate.

## Testing

- Only `test/ai_service_test.dart` exists (tests NVIDIA URL detection, free-model filtering, defaults). No widget tests for the app itself. The local plugins have their own tests but are separate packages.
- `flutter test` must stay green — CI gates on it.

## Project structure notes

- `pubspec.yaml` declares a **dependency override**: `flutter_overlay_window` → `./local_plugins/flutter_overlay_window` (a vendored fork with Java-based overlay service). Changes to the overlay plugin affect the app build directly.
- `local_plugins/agent_native/` is a generated plugin scaffold (method-channel template) that is **not referenced anywhere** in the app — leave it alone or remove it, but don't wire it in.
- `android/app/src/main/kotlin/com/neutralpip/app/Test.kt` exists as a leftover/scratch file; not part of the build.
- minSdk 26 (Android 8.0), applicationId `com.neutralpip.app`. Release APKs are also checked for Android 15/16's 16 KB native-library alignment.
- UI theme: dark trading co-pilot theme in `lib/config/theme.dart` (`AppColors` with `amber` primary, `surfaceDark` cards, `bear` = red); overlay uses JetBrains Mono via `google_fonts`. Screens: `home_screen.dart` (main chat, 2000+ lines), `settings_screen.dart` (1200 lines), `onboarding_screen.dart` (1400 lines).
- Notable uncommitted local change: `android/gradle.properties` has duplicated `org.gradle.jvmargs`/`org.gradle.daemon=false` lines (memory-constrained build tweak, 1 GiB heap). Don't commit this accidentally.

## Git history context

Recent work: rebrand (PrivateAgent → Neutral Pip), dark trading UI redesign, trading co-pilot mode, chart vision analysis, Telegram scheduled analysis push, and overlay plugin stabilization (currently flag-disabled). Commits use conventional-style messages.
