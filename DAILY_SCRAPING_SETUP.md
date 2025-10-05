# Daily Automatic Scraping Setup

## ✅ Configuration Complete!

Your Nina scraping system is now configured for automatic daily scraping at **2:00 AM UTC** every day.

## 🔧 What's Been Set Up

### 1. DailyScrapeJob
- **File**: `app/jobs/daily_scrape_job.rb`
- **Purpose**: Runs daily to queue all enabled sources for scraping
- **Schedule**: Every day at 2:00 AM UTC (`0 2 * * *`)

### 2. GoodJob Cron Configuration
- **File**: `config/application.rb`
- **Cron job**: `daily_scrape` 
- **Class**: `DailyScrapeJob`
- **Schedule**: `0 2 * * *` (daily at 2 AM)

## 🚀 To Start Automatic Scraping

You need to run a GoodJob worker process. Choose one of these options:

### Option A: Run in Terminal (for testing)
```bash
cd /Users/martin/nina
bundle exec good_job start
```

### Option B: Run as Background Process
```bash
cd /Users/martin/nina
nohup bundle exec good_job start > log/goodjob.log 2>&1 &
```

### Option C: Using Screen/Tmux (recommended)
```bash
cd /Users/martin/nina
screen -S goodjob
bundle exec good_job start
# Press Ctrl+A, then D to detach
```

To reattach later: `screen -r goodjob`

## 📅 Schedule Details

- **Next run**: Tomorrow at 2:00 AM UTC (approximately 4.8 hours from now)
- **Frequency**: Every 24 hours
- **Content**: All 15 AFS 2023 Swedish regulations
- **Versioning**: Automatically detects and versions content changes

## 🔍 Monitoring

### Check if worker is running:
```bash
ps aux | grep good_job
```

### View recent scraping activity:
```bash
cd /Users/martin/nina
bin/rails scrape:status
```

### Check logs:
```bash
tail -f log/development.log | grep -E "(DailyScrapeJob|SourceScraperJob)"
```

## 🛠️ Production Deployment

For production deployment, consider using:
- **systemd** service (Linux)
- **launchd** daemon (macOS)  
- **Docker** with health checks
- **Process managers** like PM2 or Foreman

## 🎯 What Happens Daily

1. **2:00 AM UTC**: DailyScrapeJob executes
2. **Queue**: 15 SourceScraperJob tasks created
3. **Process**: Each Swedish regulation is scraped for `.provision` content
4. **Version**: Content changes are automatically versioned
5. **Log**: Results logged with word counts and status

## ✅ Verification

All components tested and working:
- ✅ DailyScrapeJob executes successfully
- ✅ Queues 15 scraping jobs correctly  
- ✅ GoodJob worker processes jobs
- ✅ Cron schedule configured properly
- ✅ Next execution: 2025-10-06 02:00:00 UTC

**Your Swedish regulation scraper is fully operational! 🇸🇪**