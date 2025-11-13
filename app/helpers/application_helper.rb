module ApplicationHelper
  # Extract and format regulation number from source URL
  # e.g. "https://...afs-20231/" -> "1", "...afs-202310/" -> "10"
  def regulation_number(url)
    match = url.match(/afs-2023(\d+)/)
    match ? match[1] : "?"
  end

  # Format full regulation name
  # e.g. "https://...afs-20231/" -> "AFS 2023:1"
  def regulation_name(url)
    "AFS 2023:#{regulation_number(url)}"
  end

  # Extract article preview from a scrape using elements table
  # Reconstructs section 1 (§) and extracts plain text for preview
  def section_preview(scrape, length_limit = 200)
    return "No preview content available" unless scrape.is_a?(Scrape)

    begin
      # Reconstruct section 1 with all its content
      section_html = Element.reconstruct_section_with_advice(scrape, 1)[:section_html]

      if section_html.present?
        # Parse HTML and extract text content
        doc = Nokogiri::HTML(section_html)
        text = doc.text.gsub(/\s+/, " ").strip

        if text.present?
          preview = "1 § #{text}"
          preview.length > length_limit ?
                 "#{preview[0, length_limit - 3]}..." :
                 preview
        else
          "No preview content available"
        end
      else
        "No preview content available"
      end
    rescue => e
      Rails.logger.warn "Error extracting section preview: #{e.message}"
      "No preview content available"
    end
  end

  # Count the number of articles in HTML content
  # Counts .section-sign elements (e.g., "1 §", "2 §", etc.)
  def article_count(raw_html)
    return 0 if raw_html.blank?

    begin
      doc = Nokogiri::HTML(raw_html)
      doc.css(".section-sign").length
    rescue => e
      Rails.logger.warn "Error counting articles: #{e.message}"
      0
    end
  end

  # Count the number of general recommendations in HTML content
  # Counts div.general-recommendation elements
  def general_recommendation_count(raw_html)
    return 0 if raw_html.blank?

    begin
      doc = Nokogiri::HTML(raw_html)
      doc.css("div.general-recommendation").length
    rescue => e
      Rails.logger.warn "Error counting general recommendations: #{e.message}"
      0
    end
  end

  # Count the number of appendices in HTML content
  # Looks for h2 elements with an id that starts with "bilaga" (case-insensitive)
  def appendix_count(raw_html)
    return 0 if raw_html.blank?

    begin
      doc = Nokogiri::HTML(raw_html)
      doc.css("h2[id]").count { |h| h["id"].to_s.downcase.start_with?("bilaga") }
    rescue => e
      Rails.logger.warn "Error counting appendices: #{e.message}"
      0
    end
  end

  # Extract the subject part from the stored regulation title
  # e.g. "Systematiskt arbetsmiljöarbete – grundläggande skyldigheter för dig med arbetsgivaransvar (AFS 2023:1)"
  #   -> "Systematiskt arbetsmiljöarbete – grundläggande skyldigheter för dig med arbetsgivaransvar"
  def regulation_title_subject(title)
    return "Work Environment Regulation" if title.blank?

    # Remove the (AFS 2023:X) part from the end
    title.gsub(/\s*\(AFS\s+\d{4}:\d+\)\s*$/, "").strip
  end

  # Extract hierarchy for any given element in the raw_html
  # Returns hash with regulation, chapter (optional), section (optional), appendix (optional), transitional (optional), or general_recommendation (optional)
  def extract_hierarchy(element, doc, url)
    # If element is a heading, use the hierarchy of the next element
    if element.name =~ /^h[1-6]$/i
      next_element = find_next_content_element(element)
      return extract_hierarchy(next_element, doc, url) if next_element
    end

    regulation = extract_regulation_number(url)

    # Check for övergångsbestämmelser (transitional provisions)
    transitional = find_current_transitional(element, doc)
    if transitional
      return {
        regulation: regulation,
        transitional: true
      }
    end

    # Check for appendix
    appendix = find_current_appendix(element, doc)
    if appendix
      return {
        regulation: regulation,
        appendix: extract_appendix_number(appendix)
      }
    end

    # Regular hierarchy: chapter and section
    chapter = find_current_chapter(element, doc)
    section = find_current_section(element, doc)

    # If element itself is a section-sign, use it
    if element.name == "span" && element["class"].to_s.include?("section-sign")
      section = element
    end

    # Check if element is within a general recommendation (Allmänna råd)
    is_general_recommendation = in_general_recommendation?(element)

    {
      regulation: regulation,
      chapter: chapter ? extract_chapter_number(chapter) : nil,
      section: section ? extract_section_number(section) : nil,
      general_recommendation: is_general_recommendation
    }
  end

  # Extract regulation number from URL
  def extract_regulation_number(url)
    match = url.match(/afs-(\d{4})(\d+)/)
    match ? "AFS #{match[1]}:#{match[2]}" : nil
  end

  # Find next content element after a heading
  def find_next_content_element(heading)
    heading.xpath("following::*").each do |el|
      # Skip empty elements and only return content-bearing elements
      if el.text.strip.present? && ![ "script", "style", "button" ].include?(el.name)
        return el if [ "div", "p", "span", "li" ].include?(el.name)
      end
    end
    nil
  end

  # Find if element is within övergångsbestämmelser (transitional provisions)
  def find_current_transitional(element, doc)
    element.xpath("preceding::h2[@id]").reverse_each do |h2|
      id = h2["id"].to_s.downcase
      text = h2.text.strip.downcase

      # Check if this is övergångsbestämmelser
      if id.include?("overgang") || text.include?("övergång")
        return h2
      end

      # Stop if we hit a bilaga or chapter - övergångsbestämmelser comes after main content
      return nil if id.start_with?("bilaga") || h2.text.match?(/^\d+\s+kap\.?/i)
    end
    nil
  end

  # Check if element is within a general recommendation (Allmänna råd)
  def in_general_recommendation?(element)
    # Check if element or any of its ancestors is a div.general-recommendation
    ancestor = element.xpath("ancestor::div[@class='general-recommendation']").first
    !ancestor.nil?
  end

  # Find current appendix by walking backwards through h2 elements
  def find_current_appendix(element, doc)
    element.xpath("preceding::h2[@id]").reverse_each do |h2|
      return h2 if h2["id"].to_s.downcase.start_with?("bilaga")
    end
    nil
  end

  # Extract appendix number from appendix header
  def extract_appendix_number(appendix_h2)
    text = appendix_h2.text.strip.gsub(/[\u00A0\s]+/, " ")  # Normalize spaces including non-breaking spaces
    match = text.match(/Bilaga\s+(\d+|[A-Z])/i)
    match ? match[1] : nil
  end

  # Find current chapter by walking backwards through h2 and h3 elements
  def find_current_chapter(element, doc)
    # Check both h2 and h3 elements, as some documents use h3 for chapters
    element.xpath("preceding::h2 | preceding::h3").reverse_each do |heading|
      text = heading.text.strip.gsub(/[\u00A0\s]+/, " ")  # Normalize spaces
      return heading if text.match?(/^\d+\s+kap\.?/i)
    end
    nil
  end

  # Extract chapter number from chapter header
  def extract_chapter_number(chapter_heading)
    text = chapter_heading.text.strip.gsub(/[\u00A0\s]+/, " ")  # Normalize spaces
    match = text.match(/^(\d+)\s+kap\.?/i)
    match ? match[1].to_i : nil
  end

  # Find current section by looking for nearest preceding .section-sign element
  def find_current_section(element, doc)
    element.xpath("preceding::span[@class='section-sign']").last
  end

  # Extract section number from section-sign span
  def extract_section_number(section_span)
    text = section_span.text.strip
    match = text.match(/(\d+)\s*§/)
    return match[1].to_i if match

    # Fallback: try id attribute
    id = section_span["id"].to_s
    match = id.match(/(\d+)§/)
    match ? match[1].to_i : nil
  end
  # Robots meta content based on environment
  def robots_meta_content
    ENV["ALLOW_INDEXING"] == "true" ? "index, follow" : "noindex, nofollow"
  end

  def meta_description
    I18n.t("meta.description")
  end

  def meta_rights
    I18n.t("meta.rights")
  end
end
