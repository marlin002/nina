class DailyScrapeJob < ApplicationJob
  queue_as :scraping
  
  # This job will be automatically scheduled by GoodJob cron
  def perform
    Rails.logger.info "Starting daily scrape of all enabled sources"
    
    enabled_sources = Source.current.select { |s| s.settings['enabled'] == true }
    queued_count = 0
    
    enabled_sources.each do |source|
      SourceScraperJob.perform_later(source.id)
      queued_count += 1
    end
    
    Rails.logger.info "Daily scrape completed: queued #{queued_count} scraping jobs"
    
    # Optional: Clean up old job records (keep last 100)
    GoodJob::Job.where(job_class: 'SourceScraperJob')
              .where('created_at < ?', 7.days.ago)
              .limit(1000)
              .delete_all
  end
end