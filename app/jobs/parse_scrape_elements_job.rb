class ParseScrapeElementsJob < ApplicationJob
  queue_as :default

  def perform(scrape_id)
    @scrape = Scrape.find(scrape_id)

    Rails.logger.info "Starting to parse elements for scrape ID: #{scrape_id}"

    # Clear existing elements for this scrape version
    Element.unscoped.where(scrape: @scrape, version: @scrape.version).destroy_all

    # Parse the HTML and create elements
    parse_html_to_elements

    Rails.logger.info "Completed parsing elements for scrape ID: #{scrape_id}"
  rescue => e
    Rails.logger.error "Error parsing elements for scrape #{scrape_id}: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    raise
  end

  private

  def parse_html_to_elements
    return if @scrape.raw_html.blank?

    @doc = Nokogiri::HTML(@scrape.raw_html)

    # Get the provision element as the root
    provision = @doc.at_css(".provision")
    return unless provision

    # Extract regulation info from URL
    @regulation_code = extract_regulation_number(@scrape.url)

    # Parse different major sections in order
    parse_preamble
    parse_sections_by_blocks
    parse_appendices
    parse_transitional_rules
  end

  # Parse preamble (before .rules section)
  def parse_preamble
    preamble = @doc.at_css(".preamble")
    return unless preamble

    position = 0
    preamble.children.each do |child|
      next unless child.is_a?(Nokogiri::XML::Element)
      next if child.text.strip.blank?

      create_element_from_node(
        child,
        regulation: @regulation_code,
        position: position
      )
      position += 1
    end
  end

  # Parse sections block-by-block (each § gets its own boundary)
  def parse_sections_by_blocks
    # Find all section signs in the document
    section_signs = @doc.css("span.section-sign")
    return if section_signs.empty?

    section_signs.each_with_index do |section_sign, idx|
      section_number = extract_section_number(section_sign)
      next unless section_number

      # Find the chapter for this section (look backward for chapter heading)
      chapter_number = find_chapter_for_section(section_sign)

      # Find the boundary: start from section_sign, end at next section_sign or major structure
      next_section_sign = section_signs[idx + 1]

      # Parse all content from this section sign up to the next boundary
      parse_section_block(
        section_sign: section_sign,
        section_number: section_number,
        chapter_number: chapter_number,
        next_section_sign: next_section_sign
      )
    end
  end

  # Parse a single section block (from section-sign to next section-sign)
  def parse_section_block(section_sign:, section_number:, chapter_number:, next_section_sign:)
    position = 0
    current = section_sign

    # Determine if we're in a general recommendation block
    in_ar_block = section_sign.ancestors(".general-recommendation").any?

    # Walk forward from section_sign until we hit the boundary
    loop do
      current = current.next_element
      break unless current

      # Stop at next section sign
      break if current == next_section_sign

      # Stop at major structural boundaries
      if current.name == "h2"
        # Check if it's a new chapter, appendix, or transitional heading
        break if is_major_structure_heading?(current)
      end

      # Skip empty nodes
      next if current.text.strip.blank?

      # Special handling for headings (h2-h6):
      # These are structural markers and should NOT be assigned to sections
      # Store them separately with section: nil
      if current.name.match?(/^h[2-6]$/)
        create_element_from_node(
          current,
          regulation: @regulation_code,
          chapter: chapter_number,
          section: nil,  # Headings don't belong to sections
          is_general_recommendation: false,
          position: position
        )
        position += 1
        next
      end

      # Create element for this node (assign to current section)
      is_ar = current.ancestors(".general-recommendation").any?

      create_element_from_node(
        current,
        regulation: @regulation_code,
        chapter: chapter_number,
        section: section_number,
        is_general_recommendation: is_ar,
        position: position
      )
      position += 1
    end
  end

  # Find chapter number for a section by looking backward for chapter heading
  def find_chapter_for_section(section_sign)
    # Look for h3 (and h2 for compatibility) chapter headings
    preceding_headings = section_sign.xpath("preceding::h2 | preceding::h3")
    chapter_heading = preceding_headings.reverse.find do |h|
      text = h.text.strip.gsub(/[\u00A0\s]+/, " ")
      text.match?(/^\d+\s+kap\.?/i)
    end

    return nil unless chapter_heading
    extract_chapter_number(chapter_heading)
  end

  # Check if h2 is a major structural heading (chapter, appendix, transitional)
  def is_major_structure_heading?(h2)
    return false unless h2.name == "h2"

    text = h2.text.strip.downcase
    id = h2["id"].to_s.downcase

    # Chapter heading
    return true if text.match?(/^\d+\s+kap\.?/i)

    # Appendix
    return true if id.start_with?("bilaga") || text.start_with?("bilaga")

    # Transitional
    return true if id.include?("overgang") || text.include?("övergång")

    false
  end

  # Parse appendices
  def parse_appendices
    # Find all h2 elements that are appendix headings
    appendix_headings = @doc.css("h2").select do |h2|
      id = h2["id"].to_s.downcase
      text = h2.text.strip.downcase
      id.start_with?("bilaga") || text.start_with?("bilaga")
    end

    appendix_headings.each_with_index do |heading, idx|
      appendix_id = extract_appendix_number(heading)
      next unless appendix_id

      # Find boundary: next appendix heading or transitional or end
      next_heading = appendix_headings[idx + 1]
      if next_heading.nil?
        # Check for transitional rules heading
        next_heading = @doc.css("h2").find do |h2|
          id = h2["id"].to_s.downcase
          text = h2.text.strip.downcase
          id.include?("overgang") || text.include?("övergång")
        end
      end

      position = 0
      current = heading

      loop do
        current = current.next_element
        break unless current
        break if current == next_heading
        break if current.name == "h2" && is_major_structure_heading?(current)

        next if current.text.strip.blank?

        create_element_from_node(
          current,
          regulation: @regulation_code,
          appendix: appendix_id,
          position: position
        )
        position += 1
      end
    end
  end

  # Parse transitional rules (Övergångsbestämmelser)
  def parse_transitional_rules
    transitional_heading = @doc.css("h2").find do |h2|
      id = h2["id"].to_s.downcase
      text = h2.text.strip.downcase
      id.include?("overgang") || text.include?("övergång")
    end

    return unless transitional_heading

    position = 0
    current = transitional_heading

    loop do
      current = current.next_element
      break unless current
      # Transitional rules typically run to end of document
      break if current.name == "h2" && is_major_structure_heading?(current)

      next if current.text.strip.blank?

      create_element_from_node(
        current,
        regulation: @regulation_code,
        is_transitional: true,
        position: position
      )
      position += 1
    end
  end

  # Create an element record from a Nokogiri node
  # Recursively processes children to capture searchable text at paragraph/list level
  def create_element_from_node(node, regulation:, chapter: nil, section: nil, appendix: nil, is_transitional: false, is_general_recommendation: false, position: 0)
    # Check if this is a content-bearing element worth storing
    if content_bearing_element?(node)
      text_content = extract_searchable_text(node)

      # Only create element if there's text
      if text_content.present?
        Element.create!(
          scrape: @scrape,
          tag_name: node.name,
          element_class: node["class"],
          element_id: node["id"],
          text_content: text_content,
          html_snippet: node.to_html,
          regulation: regulation,
          chapter: chapter,
          section: section,
          appendix: appendix,
          is_transitional: is_transitional,
          is_general_recommendation: is_general_recommendation,
          css_path: nil,
          position_in_parent: position,
          version: @scrape.version,
          current: @scrape.current
        )
      end
    end

    # Recursively process children to find more content-bearing elements
    child_position = 0
    node.children.each do |child|
      next unless child.is_a?(Nokogiri::XML::Element)

      # Check if child is in AR block
      child_is_ar = child.ancestors(".general-recommendation").any?

      create_element_from_node(
        child,
        regulation: regulation,
        chapter: chapter,
        section: section,
        appendix: appendix,
        is_transitional: is_transitional,
        is_general_recommendation: child_is_ar,
        position: child_position
      )
      child_position += 1
    end
  end

  # Check if element is content-bearing (worth storing for search)
  def content_bearing_element?(node)
    case node.name
    when "p", "td", "th", "dt", "dd", "blockquote"
      # These are actual content elements - always store
      true
    when "li"
      # Skip <li> if it contains <p> children - the <p> will be stored instead
      # This prevents duplicate text: both "<li><p>text</p></li>" and "<p>text</p>"
      # Only store <li> if it has direct text (no nested <p>)
      !node.at_css("p")
    when "h1", "h2", "h3", "h4", "h5", "h6"
      true
    when "div"
      # Skip wrapper divs that only contain other content-bearing elements
      # These are just styling containers (e.g. div.paragraph containing a <p>)
      klass = node["class"].to_s

      # Skip common wrapper classes (including dialog wrappers and table overlays)
      # Using word boundaries (\b) for most, but provision__ classes need special handling due to hyphens
      return false if klass.match?(/\b(paragraph|general-recommendation|document|root|rules)\b/)
      return false if klass.include?("provision__dialog") || klass.include?("provision__table-overlay")
      return false if klass == "provision" || klass.start_with?("provision ")

      # For other divs, only store if they have a meaningful class
      klass.present?
    else
      false
    end
  end

  # Extract searchable text (full text including nested formatting)
  def extract_searchable_text(node)
    text = node.text.strip.gsub(/[\u00A0\s]+/, " ")
    text.empty? ? nil : text
  end

  def extract_chapter_number(chapter_heading)
    text = chapter_heading.text.strip.gsub(/[\u00A0\s]+/, " ")
    match = text.match(/^(\d+)\s+kap\.?/i)
    match ? match[1].to_i : nil
  end

  def extract_section_number(section_span)
    text = section_span.text.strip
    match = text.match(/(\d+)\s*§/)
    return match[1].to_i if match

    id = section_span["id"].to_s
    match = id.match(/(\d+)§/)
    match ? match[1].to_i : nil
  end

  def extract_appendix_number(appendix_h2)
    text = appendix_h2.text.strip.gsub(/[\u00A0\s]+/, " ")
    match = text.match(/Bilaga\s+(\d+|[A-Z])/i)
    match ? match[1] : nil
  end

  def extract_regulation_number(url)
    match = url.match(/afs-(\d{4})(\d+)/)
    match ? "AFS #{match[1]}:#{match[2]}" : nil
  end

  def extract_text_content(element)
    # Extract only direct text content of this element, not from nested children
    # Use xpath with single . to get only immediate text nodes (not .//, which gets all descendants)
    text_nodes = element.xpath("./text()").map(&:text)
    text = text_nodes.join(" ").strip

    # Remove ALL whitespace including non-breaking spaces (\u00A0)
    # First normalize all whitespace including non-breaking spaces to regular spaces
    text = text.gsub(/[\u00A0\s]+/, " ").strip
    text.empty? ? nil : text
  end

  def build_css_path(element, parent_path)
    selector = element.name
    selector += ".#{element['class'].split.join('.')}" if element["class"]
    selector += "##{element['id']}" if element["id"]

    "#{parent_path} > #{selector}"
  end
end
