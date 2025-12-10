namespace :regulations do
  desc "Diagnose parsing issues for a specific regulation section"
  task :diagnose, [ :regulation_code, :chapter, :section ] => :environment do |t, args|
    regulation_code = args[:regulation_code] || "AFS 2023:3"
    chapter = args[:chapter]&.to_i
    section = args[:section]&.to_i || 4
    chapter = 2 if chapter.nil? && regulation_code == "AFS 2023:3"

    puts "=" * 80
    puts "Diagnosing: #{regulation_code}, Chapter #{chapter}, Section #{section}"
    puts "=" * 80

    # Find the scrape
    scrape = Scrape.joins(:source)
                   .includes(:source)
                   .where("sources.url LIKE ?", "%afs-#{regulation_code.gsub(/[^0-9]/, '')}%")
                   .first

    unless scrape
      puts "ERROR: No scrape found for #{regulation_code}"
      exit 1
    end

    puts "\nScrape ID: #{scrape.id}"
    puts "URL: #{scrape.url}"
    puts "Fetched at: #{scrape.fetched_at}"

    # Parse the HTML
    doc = Nokogiri::HTML(scrape.raw_html)

    # Find all section signs
    all_sections = doc.css("span.section-sign").map do |sign|
      text = sign.text.strip
      match = text.match(/(\d+)\s*§/)
      next unless match

      {
        number: match[1].to_i,
        id: sign["id"],
        text: text
      }
    end.compact.sort_by { |s| s[:number] }

    puts "\nAll sections found in HTML: #{all_sections.map { |s| s[:number] }.join(', ')}"

    # Find the target section sign
    target_section_sign = doc.css("span.section-sign").find do |sign|
      text = sign.text.strip
      text.match?(/#{section}\s*§/)
    end

    unless target_section_sign
      puts "\nERROR: Could not find section #{section} § in HTML"
      exit 1
    end

    puts "\n--- RAW HTML STRUCTURE ---"
    puts "Section sign ID: #{target_section_sign['id']}"

    # Find preceding chapter heading
    preceding_h2s = target_section_sign.xpath("preceding::h2")
    chapter_h2 = preceding_h2s.reverse.find do |h2|
      h2.text.strip.match?(/^\d+\s+kap\.?/i)
    end

    if chapter_h2
      puts "Preceding chapter heading: #{chapter_h2.text.strip}"
    else
      puts "No chapter heading found"
    end

    # Find the next section sign (boundary)
    all_section_signs = doc.css("span.section-sign")
    current_index = all_section_signs.index(target_section_sign)
    next_section_sign = all_section_signs[current_index + 1] if current_index

    puts "\nSection #{section} boundaries:"
    puts "  Start: span.section-sign##{target_section_sign['id']}"
    if next_section_sign
      puts "  End: span.section-sign##{next_section_sign['id']} (#{next_section_sign.text.strip})"
    else
      puts "  End: (next major structure or end of document)"
    end

    # Show the content between these boundaries
    puts "\n--- CONTENT IN HTML BLOCK ---"
    current = target_section_sign
    count = 0
    max_nodes = 20

    while current && count < max_nodes
      current = current.next_element
      break unless current
      break if current == next_section_sign

      if current.name == "h2" || current.name == "h3"
        # Stop at next major heading
        break
      end

      if current.text.strip.length > 0
        preview = current.text.strip[0..80].gsub(/\s+/, " ")
        puts "  #{current.name}.#{current['class']}: #{preview}"
      end
      count += 1
    end

    # Now check what elements are in the database
    puts "\n--- ELEMENTS IN DATABASE ---"
    elements = scrape.elements.where(chapter: chapter, section: section).order(:position_in_parent, :id)

    puts "Found #{elements.count} elements for chapter #{chapter}, section #{section}"
    puts "\nFirst 20 elements:"
    elements.limit(20).each_with_index do |el, idx|
      text_preview = el.text_content.to_s.strip[0..60].gsub(/\s+/, " ")
      puts "  #{idx + 1}. #{el.tag_name}.#{el.element_class} [AR: #{el.is_general_recommendation}] : #{text_preview}"
    end

    # Check for foreign strings
    foreign_strings = [ "Vem föreskrifterna riktar sig till", "1 §", "Tidsplanering", "5 §" ]
    puts "\n--- CHECKING FOR FOREIGN STRINGS ---"
    foreign_strings.each do |foreign|
      matching = elements.where("text_content ILIKE ?", "%#{foreign}%")
      if matching.any?
        puts "  ❌ FOUND '#{foreign}' in #{matching.count} element(s)"
        matching.each do |el|
          puts "     - #{el.tag_name}: #{el.text_content.to_s.strip[0..80]}"
        end
      else
        puts "  ✓ No '#{foreign}' found"
      end
    end
  end
end
