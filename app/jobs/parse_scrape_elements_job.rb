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
    regulation = extract_regulation_number(@scrape.url)

    # Recursively parse all elements
    parse_element_tree(provision, regulation, position: 0, parent_path: ".provision")
  end

  def parse_element_tree(element, regulation, position: 0, parent_path: "")
    position = 0

    element.children.each do |child|
      next if child.is_a?(Nokogiri::XML::Text) && child.text.strip.blank?

      if child.is_a?(Nokogiri::XML::Text)
        next  # Skip pure text nodes
      end

      # Extract hierarchy information
      hierarchy = extract_hierarchy_for_element(child)
      hierarchy[:regulation] ||= regulation

      # Extract element attributes
      css_path = build_css_path(child, parent_path)
      tag_name = child.name
      element_class = child["class"]
      element_id = child["id"]
      text_content = extract_text_content(child)
      html_snippet = child.to_html

      # Create element record
      Element.create!(
        scrape: @scrape,
        tag_name: tag_name,
        element_class: element_class,
        element_id: element_id,
        text_content: text_content,
        html_snippet: html_snippet,
        regulation: hierarchy[:regulation],
        chapter: hierarchy[:chapter],
        section: hierarchy[:section],
        appendix: hierarchy[:appendix],
        is_transitional: hierarchy[:is_transitional],
        is_general_recommendation: hierarchy[:is_general_recommendation],
        css_path: css_path,
        position_in_parent: position,
        version: @scrape.version,
        current: @scrape.current
      )

      position += 1

      # Recursively parse children
      parse_element_tree(child, regulation, parent_path: css_path)
    end
  end

  def extract_hierarchy_for_element(element)
    # Simplified hierarchy extraction based on element type and context
    hierarchy = {
      chapter: nil,
      section: nil,
      appendix: nil,
      is_transitional: false,
      is_general_recommendation: false
    }

    # Check if in general recommendation
    if in_general_recommendation?(element)
      hierarchy[:is_general_recommendation] = true
    end

    # Check for transitional provisions heading
    if find_preceding_transitional(element).present?
      hierarchy[:is_transitional] = true
    elsif (appendix_heading = find_preceding_appendix(element)).present?
      hierarchy[:appendix] = extract_appendix_number(appendix_heading)
    else
      # Regular content: extract chapter and section
      if (chapter_heading = find_preceding_chapter(element)).present?
        hierarchy[:chapter] = extract_chapter_number(chapter_heading)
      end

      if (section_span = find_preceding_section(element)).present?
        hierarchy[:section] = extract_section_number(section_span)
      end
    end

    hierarchy
  end

  def in_general_recommendation?(element)
    ancestor = element.xpath("ancestor::div[@class='general-recommendation']").first
    !ancestor.nil?
  end

  def find_preceding_transitional(element)
    element.xpath("preceding::h2[@id]").reverse_each do |h2|
      id = h2["id"].to_s.downcase
      text = h2.text.strip.downcase
      return h2 if id.include?("overgang") || text.include?("övergång")
      return nil if id.start_with?("bilaga") || h2.text.match?(/^\d+\s+kap\.?/i)
    end
    nil
  end

  def find_preceding_appendix(element)
    element.xpath("preceding::h2[@id]").reverse_each do |h2|
      return h2 if h2["id"].to_s.downcase.start_with?("bilaga")
    end
    nil
  end

  def find_preceding_chapter(element)
    element.xpath("preceding::h2 | preceding::h3").reverse_each do |heading|
      text = heading.text.strip.gsub(/[\u00A0\s]+/, " ")
      return heading if text.match?(/^\d+\s+kap\.?/i)
    end
    nil
  end

  def find_preceding_section(element)
    element.xpath("preceding::span[@class='section-sign']").last
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
