# Server roadmap (deferred — Flutter standalone ships first)

1. Framework: Dart Frog or NestJS/Fastify; Postgres + Prisma/TypeORM; Redis only for
   arena queues when concurrency demands it.
2. Implement this repo's `backend/openapi.yaml` routes over `AppRepository` semantics.
3. WS/SSE: broadcast persisted events (persist-then-broadcast, idempotency keys).
4. Workers: arena scheduler + review pipeline as background jobs with cancellation.
5. Auth: API keys/OAuth; credentials server-side only; clients get short-lived tokens.
6. Migrations: versioned SQL; Hive local boxes migrate via `LocalAppStore.migrate()`.
7. Leaderboard: per-mode Elo from exported v1.0 records; min-games gate; anti-duplication.
