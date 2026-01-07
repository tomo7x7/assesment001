# Anonymous Assessment SaaS (PoC Blueprint)

This repository provides a documentation-first blueprint for building the PoC described in the product brief. It includes an engineer-facing spec, PoC roadmap, database schema, API definitions, and operational notes so the implementation can start immediately.

## Docs
- **Engineer Spec v0.1**: `docs/engineering-spec-v0.1.md`
- **PoC Roadmap**: `docs/poc-roadmap.md`
- **Repo/Env/API/DB/Jobs/Security**: `docs/repository-blueprint.md`

## Repository Layout (planned)
```
.
├── docs/
├── src/
│   ├── app/                # Next.js App Router (UI + API)
│   └── lib/                # API clients, services, utilities
├── supabase/
│   └── migrations/         # SQL migrations (schema + indexes)
└── .env.example            # Environment variables template
```

## Getting Started (once implementation begins)
1. Create a Supabase project and apply SQL migrations in `supabase/migrations`.
2. Copy `.env.example` to `.env.local` and fill in secrets.
3. Deploy to Vercel with GitHub integration and set env vars per environment.

> Note: This repository currently focuses on specification and schema scaffolding. UI and API implementations can follow the documents above.
