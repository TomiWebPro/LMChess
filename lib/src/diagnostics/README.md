# `lib/src/diagnostics/` — Leveled logging + DevTools sink

Role: Logging contracts + the `AppLog` service both UI and backend share.

Owns: `app_log.dart` (`AppLog`, levels, buffer, sinks, `appLogProvider`),
  `backend_log.dart` (`BackendLog` UI-free contract + `NoopBackendLog`).

Talks to: `dart:developer` (default sink) + injected `AppLogSink`s;
  backend logs via `BackendLog` (`gameId`/`tournamentId` named params).

Never imports: any domain layer (`chess/`…`ui/`), `package:flutter`
  material/widgets — only `flutter_riverpod` for the provider seam.

Debug logs: defines the tag convention (`engine-adapter`, `LocalAppStore`,
  `openai-provider`, …) — tags are caller-supplied, never invented here.
