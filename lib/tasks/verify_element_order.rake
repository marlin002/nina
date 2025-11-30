namespace :verify do
  desc "Verify that elements can be rebuilt in correct order from raw_html"
  task element_order: :environment do
    require 'nokogiri'

    # Get a sample of current scrapes with sections
    scrapes = Scrape.joins(:elements)
                    .where(current: true, elements: { current: true })
                    .where.not(elements: { section: nil })
                    .distinct
                    .limit(5)

    if scrapes.empty?
      puts "No scrapes with sections found"
      exit
    end

    scrapes.each do |scrape|
      puts "\n" + "="*80
      puts "Verifying scrape: #{scrape.url}"
      puts "="*80

      # Parse raw HTML
      doc = Nokogiri::HTML(scrape.raw_html)

      # Get unique sections from this scrape
      sections = scrape.elements
                       .where(current: true)
                       .where.not(section: nil)
                       .select(:regulation, :chapter, :section, :is_general_recommendation)
                       .distinct
                       .limit(3)

      sections.each do |section_ref|
        puts "\n--- Section: #{section_ref.regulation}, " \
             "Chapter: #{section_ref.chapter || 'N/A'}, " \
             "Section: #{section_ref.section}, " \
             "AR: #{section_ref.is_general_recommendation} ---"

        # Get elements for this section, ordered by position_in_parent
        elements = scrape.elements
                         .where(current: true,
                                regulation: section_ref.regulation,
                                chapter: section_ref.chapter,
                                section: section_ref.section,
                                is_general_recommendation: section_ref.is_general_recommendation)
                         .where.not(text_content: nil)
                         .where.not(text_content: "")
                         .order(:position_in_parent, :id)

        puts "Found #{elements.count} elements"

        if elements.count == 0
          puts "  (Skipping - no elements with text)"
          next
        end

        # Normalize text: strip and collapse whitespace (including non-breaking spaces)
        normalize = ->(text) { text.strip.gsub(/[\u00A0\s]+/, " ") }
        
        # Get normalized text from elements
        element_texts = elements.map { |e| normalize.call(e.text_content || "") }.reject(&:empty?)
        
        # Parse the HTML and extract text from the section in document order
        # Find all text nodes in the HTML that match our element texts
        html_doc = Nokogiri::HTML(scrape.raw_html)
        all_html_texts = html_doc.xpath("//text()").map { |node| normalize.call(node.text) }.reject(&:empty?)
        
        # Find positions of our element texts in the HTML text sequence
        positions = []
        element_texts.each_with_index do |elem_text, idx|
          html_pos = all_html_texts.index(elem_text)
          if html_pos
            positions << { elem_idx: idx, html_pos: html_pos, text: elem_text[0..50] }
          else
            # Text might be a substring or combined - try to find partial match
            html_pos = all_html_texts.index { |html_text| html_text.include?(elem_text) || elem_text.include?(html_text) }
            if html_pos
              positions << { elem_idx: idx, html_pos: html_pos, text: elem_text[0..50], partial: true }
            end
          end
        end
        
        # Check if positions are in ascending order
        is_ordered = positions.each_cons(2).all? { |a, b| a[:html_pos] <= b[:html_pos] }
        
        coverage = (positions.size.to_f / element_texts.size * 100).round(1)
        puts "  Matched #{positions.size}/#{element_texts.size} elements (#{coverage}%)"
        
        if is_ordered
          puts "  ✓ Elements are in correct order!"
        else
          puts "  ✗ Elements are NOT in correct order!"
          puts "  Expected vs actual order:"
          positions.sort_by { |p| p[:html_pos] }.each_with_index do |p, i|
            marker = p[:elem_idx] == i ? " " : "⚠"
            partial_marker = p[:partial] ? "~" : " "
            puts "    #{marker}#{partial_marker} elem[#{p[:elem_idx]}] html[#{p[:html_pos]}]: #{p[:text]}..."
          end
        end

        # Show first 3 elements as sample
        puts "\n  First 3 elements in order:"
        elements.limit(3).each_with_index do |elem, i|
          text_preview = elem.text_content&.strip&.gsub(/\s+/, ' ')&.[](0..60) || "(empty)"
          puts "    #{i+1}. [#{elem.tag_name}] pos=#{elem.position_in_parent}: #{text_preview}..."
        end
      end
    end

    puts "\n" + "="*80
    puts "Verification complete"
    puts "="*80
  end
end
