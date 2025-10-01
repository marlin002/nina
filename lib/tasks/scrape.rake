namespace :scrape do
  desc "Queue scraping jobs for all enabled sources"
  task :all => :environment do
    puts "🚀 Queueing scraping jobs for all enabled sources..."
    
    enabled_sources = Source.all.select { |s| s.settings['enabled'] == true }
    queued_count = 0
    
    enabled_sources.find_each do |source|
      source.scrape!
      queued_count += 1
      puts "  ✅ Queued: AFS 2023:#{source.url.split('/').last.split('-').last.gsub('afs','').gsub('2023','')}"
    end
    
    puts "\n📊 Summary:"
    puts "  Queued: #{queued_count} scraping jobs"
    puts "  Total jobs in queue: #{GoodJob::Job.where(job_class: 'SourceScraperJob').count}"
    
    puts "\n🔍 Monitor jobs with:"
    puts "  rails console: GoodJob::Job.where(job_class: 'SourceScraperJob')"
    puts "  Or check logs for scraping activity"
  end

  desc "Queue scraping jobs for recently added sources"
  task :recent => :environment do
    puts "🚀 Queueing scraping jobs for recently added sources..."
    
    recent_sources = Source.where(created_at: 1.hour.ago..).select { |s| s.settings['enabled'] == true }
    
    if recent_sources.any?
      queued_count = 0
      recent_sources.find_each do |source|
        source.scrape!
        queued_count += 1
        puts "  ✅ Queued: #{source.url}"
      end
      
      puts "\n📊 Queued #{queued_count} recent sources for scraping"
    else
      puts "  ℹ️  No recent sources found"
    end
  end

  desc "Show scraping status for all sources"
  task :status => :environment do
    puts "📋 Scraping Status Report"
    puts "=" * 50
    
    total_sources = Source.count
    enabled_sources = Source.all.count { |s| s.settings['enabled'] == true }
    sources_with_articles = Source.joins(:articles).distinct.count
    total_articles = Article.count
    
    puts "\n📊 Overall Statistics:"
    puts "  Sources: #{total_sources} total, #{enabled_sources} enabled"
    puts "  Articles: #{total_articles} total from #{sources_with_articles} sources"
    
    puts "\n🏛️ AV.se Regulation Status:"
    Source.order(:url).each_with_index do |source, index|
      afs_number = source.url.split('/').last.split('-').last.gsub('afs','').gsub('2023','')
      article_count = source.articles.count
      last_scraped = source.articles.maximum(:fetched_at)
      
      status = article_count > 0 ? "✅ #{article_count} articles" : "⏳ Not scraped yet"
      last_update = last_scraped ? " (last: #{last_scraped.strftime('%Y-%m-%d %H:%M')})" : ""
      
      puts "  AFS 2023:#{afs_number.ljust(2)} - #{status}#{last_update}"
    end
    
    puts "\n🔄 Active Jobs:"
    active_jobs = GoodJob::Job.where(job_class: 'SourceScraperJob', finished_at: nil)
    if active_jobs.any?
      puts "  #{active_jobs.count} scraping jobs in queue/running"
    else
      puts "  No active scraping jobs"
    end
  end
end