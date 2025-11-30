namespace :elements do
  desc "Repopulate elements for all current scrapes using the new parser"
  task repopulate: :environment do
    puts "=" * 80
    puts "Repopulating elements for all current scrapes"
    puts "=" * 80

    current_scrapes = Scrape.current.includes(:source).order(:id)
    total = current_scrapes.count
    
    puts "\nFound #{total} current scrapes to reparse"
    puts "\nStarting repopulation..."
    
    success_count = 0
    error_count = 0
    
    current_scrapes.each_with_index do |scrape, idx|
      begin
        regulation_code = scrape.elements.first&.regulation || "Unknown"
        print "\n[#{idx + 1}/#{total}] #{regulation_code} (Scrape ##{scrape.id})..."
        
        # Clear existing elements
        old_count = Element.unscoped.where(scrape: scrape).count
        Element.unscoped.where(scrape: scrape).delete_all
        
        # Reparse
        ParseScrapeElementsJob.perform_now(scrape.id)
        
        # Check new count
        new_count = scrape.elements.reload.count
        
        puts " ✓ (#{old_count} -> #{new_count} elements)"
        success_count += 1
        
      rescue => e
        puts " ✗ ERROR: #{e.message}"
        Rails.logger.error "Failed to reparse scrape #{scrape.id}: #{e.message}"
        Rails.logger.error e.backtrace.join("\n")
        error_count += 1
      end
    end
    
    puts "\n" + "=" * 80
    puts "Repopulation complete!"
    puts "  Successful: #{success_count}"
    puts "  Errors: #{error_count}"
    puts "=" * 80
  end
  
  desc "Repopulate elements for a specific regulation"
  task :repopulate_one, [:regulation_code] => :environment do |t, args|
    regulation_code = args[:regulation_code] || "AFS 2023:1"
    
    puts "Repopulating elements for #{regulation_code}..."
    
    # Find scrape by regulation code in URL
    url_pattern = regulation_code.gsub(/[^0-9]/, '')
    scrape = Scrape.joins(:source)
                   .where("sources.url LIKE ?", "%afs-#{url_pattern}%")
                   .first
    
    unless scrape
      puts "ERROR: No scrape found for #{regulation_code}"
      exit 1
    end
    
    puts "Found scrape ID: #{scrape.id}"
    
    # Clear and reparse
    old_count = Element.unscoped.where(scrape: scrape).count
    Element.unscoped.where(scrape: scrape).delete_all
    ParseScrapeElementsJob.perform_now(scrape.id)
    new_count = scrape.elements.reload.count
    
    puts "✓ Done: #{old_count} -> #{new_count} elements"
  end
end
