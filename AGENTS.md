# AGENTS.md

This file provides guidance to WARP (warp.dev) when working with code in this repository.

## Project Overview

**Benina** (module name `Benina`, repo folder `nina`) is a Ruby on Rails 7.2 application that scrapes, parses, and serves Swedish Work Environment Authority (Arbetsmiljöverket) regulations (AFS 2023 series). It provides both a web UI (Swedish-language) and a read-only JSON API for searching and browsing regulation content.

The data source is 15 AFS 2023 regulation pages on av.se. Content is fetched via Faraday, parsed with Nokogiri, and stored as structured `Element` records in PostgreSQL.

## Build & Development Commands

```bash
# Setup
bundle install
bin/rails db:create db:migrate db:seed   # seeds 15 AFS regulation sources

# Run dev server (Rails + Tailwind watcher)
bin/dev                                   # uses Procfile.dev

# Run Rails server only
bin/rails server

# Database
bin/rails db:migrate
bin/rails db:rollback
bin/rails db:seed                         # idempotent, creates Source records

# Tests (Minitest)
bin/rails test                            # all tests
bin/rails test test/models/               # directory
bin/rails test test/services/regex_search_service_test.rb          # single file
bin/rails test test/services/regex_search_service_test.rb:15       # single test by line

# Linting
bin/rubocop                               # rubocop-rails-omakase style
bin/rubocop -a                            # auto-correct

# Security scan
bin/brakeman

# Background jobs (GoodJob, backed by PostgreSQL)
bundle exec good_job start                # starts cron + worker
```

## Architecture

### Domain Model (regulation hierarchy)

The app models Swedish government regulations with this structure:

- **Source** → a regulation URL on av.se (e.g. AFS 2023:3)
- **Scrape** → a fetched HTML snapshot of a Source, versioned (`current`/`historical`)
- **Element** → a parsed HTML fragment from a Scrape, tagged with hierarchy metadata

Element hierarchy fields: `regulation` (e.g. "AFS 2023:3"), `chapter`, `section`, `appendix`, `is_transitional`, `is_general_recommendation`. All three models use soft-versioning via `current` boolean + `version` integer + `superseded_at` timestamp, with `default_scope { current }`. Use `.unscoped` to query historical records.

### Data Pipeline

1. **DailyScrapeJob** (cron, 2 AM UTC) → enqueues **SourceScraperJob** per enabled Source
2. **SourceScraperJob** → fetches HTML via Faraday, extracts `.provision` element, creates/versions Scrape
3. **ParseScrapeElementsJob** (auto-triggered after Scrape commit) → walks Nokogiri DOM to create Element records with chapter/section/appendix/transitional/AR metadata

### Key Services

- `Regulations::Code` — parses/builds regulation codes like "AFS 2023:3" from year+number or URLs
- `RegulationStructureService` — returns chapter/section/appendix structure for a regulation
- `RegulationContentBuilder` — assembles section HTML (normative vs. authoritative guidance) and appendix HTML
- `ElementSearchService` — ILIKE text search across current Elements with DISTINCT ON dedup
- `RegexSearchService` — PostgreSQL `regexp_matches` search with statement timeout protection
- `QuerySanitizer` — input sanitization; short queries (≤5 chars) pass through, longer queries checked for XSS patterns

### API (JSON, read-only, no auth)

All endpoints under `/api/v1/` — see `API.md` for full documentation. Key routes:

- `GET /api/v1/regulations` — list all
- `GET /api/v1/regulations/:year/:number/structure` — chapters, sections, appendices
- `GET /api/v1/regulations/:year/:number/sections/:section` — section content (without chapter)
- `GET /api/v1/regulations/:year/:number/chapters/:chapter/sections/:section` — section content (with chapter)
- `GET /api/v1/regulations/:year/:number/appendices/:appendix` — appendix content

API controllers inherit from `Api::V1::BaseController` (ActionController::API) which provides error handling and parameter validation.

### Web UI

Server-rendered views using Hotwire (Turbo + Stimulus), Tailwind CSS, and importmap (no Node/webpack). UI language is Swedish (locale files in `config/locales/sv.yml`). Controllers: `HomeController`, `SearchController` (web search with regex support), `ScrapesController` (regulation browsing, raw HTML viewer), `AboutController`.

### Constants & Configuration

- `AppConstants::MAX_SEARCH_RESULTS` (500) in `lib/app_constants.rb`
- GoodJob cron config in `config/application.rb`
- Tailwind config via `tailwindcss-rails` gem

## Conventions

- Application UI language: **Swedish**. Code and developer-facing text: **English**.
- Regulation domain terms: Föreskrifter (Regulations), Kapitel (Chapters), Paragrafer (Sections/§), Stycken (Paragraphs), Allmänna råd (General recommendations), Bilagor (Appendices), Övergångsbestämmelser (Transitional rules).
- Sections (paragrafer/§) are the primary unit users interact with.
- Lean code style, extendable toward Rails best practices.
- Linting follows `rubocop-rails-omakase`.
- Tests use Minitest with fixtures (`test/fixtures/`).

## Production

Deployed on Linux, managed by systemd (`benina-web.service`). Secrets in `/etc/nina/nina.env`. See `Runbook.md` for deployment, diagnostics, and recovery procedures.
