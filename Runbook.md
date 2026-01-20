Benina — Production Runbook
1. System overview

Application

Ruby on Rails (production)

App root: /home/rails/nina

App server: Puma

Ruby: 3.2.2 via RVM

Process management

Managed by systemd

Service: benina-web.service

Database

PostgreSQL

Production DB: nina_production

Connection via DATABASE_URL

Secrets & environment

Canonical environment file:
/etc/nina/nina.env

Loaded by systemd via EnvironmentFile=

2. File and responsibility map
Location	Purpose	Source of truth
/home/rails/nina	Application code	Git repository
/etc/systemd/system/benina-web.service	Service definition	Server
/etc/nina/nina.env	Secrets & env vars	Server
PostgreSQL cluster	Data	Server
.env.production	Not used	Deprecated

Important:
.env.production is not read by systemd and should not be relied upon in production.

3. Environment variables (required)

Defined in /etc/nina/nina.env:

DATABASE_URL=postgresql://nina:********@localhost/nina_production
SECRET_KEY_BASE=********
RAILS_ENV=production


Rules:

No export

No quotes unless required

File permissions: 600

Owner: root:root

4. Service management
Check status
sudo systemctl status benina-web.service

Restart application
sudo systemctl restart benina-web.service

View logs (last 100 lines)
sudo journalctl -u benina-web.service -n 100

Follow logs live
sudo journalctl -u benina-web.service -f

5. Deployment procedure (safe sequence)
5.1 Pull code
cd /home/rails/nina
git fetch origin
git pull

5.2 Install gems
bundle install --without development test

5.3 Run database migrations
RAILS_ENV=production bundle exec rails db:migrate


Silence with exit code 0 is normal if no migrations are pending.

5.4 Restart service
sudo systemctl restart benina-web.service

5.5 Verify health
sudo systemctl status benina-web.service

6. Production verification commands
Confirm Rails environment
RAILS_ENV=production bundle exec rails runner 'puts Rails.env'


Expected: production

Confirm database
RAILS_ENV=production bundle exec rails runner \
'puts ActiveRecord::Base.connection.current_database'


Expected: nina_production

Confirm secrets loaded
RAILS_ENV=production bundle exec rails runner \
'puts Rails.application.secret_key_base.present?'


Expected: true

7. Database diagnostics
Migration status
RAILS_ENV=production bundle exec rails db:migrate:status

Schema version
RAILS_ENV=production bundle exec rails db:version

8. Common failure modes and fixes
Service restarts repeatedly

Symptom

Active: activating (auto-restart)


Check

sudo journalctl -u benina-web.service -n 50


Likely causes

Missing env var in /etc/nina/nina.env

Syntax error in database.yml

Missing gem

KeyError: DATABASE_URL

Cause

DATABASE_URL missing from /etc/nina/nina.env

Fix

Add it

sudo systemctl daemon-reload

Restart service

Rails runs in CLI but not via systemd

Cause

CLI uses shell env

systemd uses only EnvironmentFile

Fix

Put all required variables in /etc/nina/nina.env

9. Security and hygiene rules

Never commit secrets to Git

Never rely on .env.production in production

/etc/nina/nina.env is the only supported secret source

Restart service after any env change

Keep DB migrations explicit and manual

10. Recovery checklist (worst case)

sudo systemctl stop benina-web.service

Check logs

Verify /etc/nina/nina.env

Verify database connectivity

Run rails db:migrate

Restart service

Verify health

11. Current system status (baseline)

Service running cleanly

Database reachable

Secrets resolved

Migrations applied

No configuration drift
