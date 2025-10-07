# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).

puts "🌱 Seeding database with Swedish Work Environment Authority regulations..."

# Swedish Work Environment Authority (Arbetsmiljöverket) AFS 2023 regulations
# These are the 15 main work environment regulations from 2023
regulation_urls = [
  "https://www.av.se/arbetsmiljoarbete-och-inspektioner/publikationer/foreskrifter/afs-20231/",   # Systematiskt arbetsmiljöarbete
  "https://www.av.se/arbetsmiljoarbete-och-inspektioner/publikationer/foreskrifter/afs-20232/",   # Planering och organisering
  "https://www.av.se/arbetsmiljoarbete-och-inspektioner/publikationer/foreskrifter/afs-20233/",   # Arbetsmiljöutbildning
  "https://www.av.se/arbetsmiljoarbete-och-inspektioner/publikationer/foreskrifter/afs-20234/",   # Arbetsplatsens utformning
  "https://www.av.se/arbetsmiljoarbete-och-inspektioner/publikationer/foreskrifter/afs-20235/",   # Användning av arbetsutrustning
  "https://www.av.se/arbetsmiljoarbete-och-inspektioner/publikationer/foreskrifter/afs-20236/",   # Personlig skyddsutrustning
  "https://www.av.se/arbetsmiljoarbete-och-inspektioner/publikationer/foreskrifter/afs-20237/",   # Manuell hantering
  "https://www.av.se/arbetsmiljoarbete-och-inspektioner/publikationer/foreskrifter/afs-20238/",   # Bildskärmsarbete
  "https://www.av.se/arbetsmiljoarbete-och-inspektioner/publikationer/foreskrifter/afs-20239/",   # Buller
  "https://www.av.se/arbetsmiljoarbete-och-inspektioner/publikationer/foreskrifter/afs-202310/",  # Vibrationer
  "https://www.av.se/arbetsmiljoarbete-och-inspektioner/publikationer/foreskrifter/afs-202311/",  # Optisk strålning
  "https://www.av.se/arbetsmiljoarbete-och-inspektioner/publikationer/foreskrifter/afs-202312/",  # Elektromagnetiska fält
  "https://www.av.se/arbetsmiljoarbete-och-inspektioner/publikationer/foreskrifter/afs-202313/",  # Kemiska arbetsmiljörisker
  "https://www.av.se/arbetsmiljoarbete-och-inspektioner/publikationer/foreskrifter/afs-202314/",  # Biologiska arbetsmiljörisker
  "https://www.av.se/arbetsmiljoarbete-och-inspektioner/publikationer/foreskrifter/afs-202315/"   # Organisatorisk och social arbetsmiljö
]

# Standard settings for all AV.se sources
standard_settings = {
  enabled: true,
  timeout: 30,
  user_agent: "Benina Swedish Content Scraper 1.0",
  language: "sv-SE",
  scrape_frequency: "weekly",  # Regulations don't change frequently
  source_type: "government_regulation"
}

# Create or find each source
created_count = 0
existing_count = 0

regulation_urls.each_with_index do |url, index|
  begin
    # Use unscoped to check all versions, but find current version
    existing_source = Source.unscoped.find_by(url: url, current: true)
    
    if existing_source
      existing_count += 1
      puts "  ♻️  Found existing source #{index + 1}/#{regulation_urls.length}: AFS 2023:#{index + 1}"
    else
      source = Source.create!(
        url: url,
        settings: standard_settings,
        version: 1,
        current: true
      )
      created_count += 1
      puts "  ✅ Created source #{index + 1}/#{regulation_urls.length}: AFS 2023:#{index + 1}"
    end
    
  rescue => e
    puts "  ❌ Error creating source for #{url}: #{e.message}"
  end
end

puts "\n📊 Seeding Summary:"
puts "  Created: #{created_count} new sources"
puts "  Existing: #{existing_count} sources already existed"
puts "  Total: #{Source.count} sources in database"

if created_count > 0
  puts "\n🚀 Would you like to queue scraping jobs for the new sources? (Run in Rails console:)"
  puts "  Source.where(created_at: 1.minute.ago..).find_each(&:scrape!)"
end

puts "\n🎉 Database seeding completed successfully!"
