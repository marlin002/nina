class RegulationContentBuilder
  # Build content for a section with separate provision and general_advice
  # @param year [Integer] Year
  # @param number [Integer] Number
  # @param chapter [Integer, nil] Chapter number (nil for regulations without chapters)
  # @param section [Integer] Section number
  # @return [Hash, nil] Hash with :provision and :general_advice keys, or nil if section not found
  def self.section_content(year:, number:, chapter: nil, section:)
    code = Regulations::Code.from_year_and_number(year, number)

    # Find elements for this section
    elements = find_section_elements(code, chapter, section)
    return nil if elements.empty?

    # Separate normative and general recommendation elements
    normative_elements = elements.where(is_general_recommendation: false)
                                .order(:position_in_parent, :id)
    ar_elements = elements.where(is_general_recommendation: true)
                        .order(:position_in_parent, :id)

    # Build normative requirement HTML
    normative_html = normative_elements.pluck(:html_snippet).join("\n")
    normative_html = nil if normative_html.blank?

    # Build authoritative guidance HTML (excluding "Allmänna råd" heading)
    authoritative_html = nil
    if ar_elements.any?
      # Filter out the "Allmänna råd" heading element
      ar_elements_without_heading = ar_elements.reject do |element|
        element.tag_name == "div" &&
        element.element_class == "h2" &&
        element.text_content&.strip&.match?(/^Allmänna råd$/i)
      end

      if ar_elements_without_heading.any?
        ar_html = ar_elements_without_heading.map(&:html_snippet).join("\n")
        authoritative_html = ar_html if ar_html.present?
      end
    end

    {
      normative_requirement: normative_html,
      authoritative_guidance: authoritative_html,
      informational_guidance: nil
    }
  end

  # Build HTML content for an appendix
  # @param year [Integer] Year
  # @param number [Integer] Number
  # @param appendix [String] Appendix identifier (e.g. "1", "2A")
  # @return [String, nil] HTML content or nil if appendix not found
  def self.appendix_html(year:, number:, appendix:)
    code = Regulations::Code.from_year_and_number(year, number)

    elements = Element
      .joins(:scrape)
      .where(scrapes: { current: true })
      .where(regulation: code, appendix: appendix)
      .where.not(text_content: [ nil, "" ])
      .order(:position_in_parent, :id)

    return nil if elements.empty?

    elements.pluck(:html_snippet).join("\n")
  end

  private

  # Find elements for a section
  def self.find_section_elements(code, chapter, section)
    scope = Element
      .joins(:scrape)
      .where(scrapes: { current: true })
      .where(regulation: code, section: section)
      .where.not(text_content: [ nil, "" ])

    # Apply chapter filter
    if chapter.present?
      scope = scope.where(chapter: chapter)
    else
      scope = scope.where(chapter: nil)
    end

    scope
  end
end
