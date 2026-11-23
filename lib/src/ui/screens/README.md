# `lib/src/ui/screens/` — Flutter screens (thin)

Role: Flutter-only pages; layout + input, sequencing lives in backend.

Owns: 9 screens — `play`/`game`/`arena`/`review`/`agent_setup`/`stats`/
  `settings`/`watch`/`variant_replay` + migration target `ui/backend/`.

Talks to: `ui/backend/*` use-cases, `ui/widgets/*`, `ui/providers`
  seams; render `ui_models.dart` + `game_mirror.dart` view state.

Never imports: `storage/local_store`, `hive`, domain engines directly
  (migration in flight — see `architecture_test.dart` status notes).

Debug logs: `agent-setup` (connection probes); screens otherwise rely
  on backend tags with `gameId`/`tournamentId`/`seq` correlation.
