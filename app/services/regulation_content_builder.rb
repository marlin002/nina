class RegulationContentBuilder
  # Build HTML content for a section (including general recommendations)
  # @param year [Integer] Year
  # @param number [Integer] Number
  # @param chapter [Integer, nil] Chapter number (nil for regulations without chapters)
  # @param section [Integer] Section number
  # @return [String, nil] HTML content or nil if section not found
  def self.section_html(year:, number:, chapter: nil, section:)
    code = Regulations::Code.from_year_and_number(year, number)

    # Find elements for this section
    elements = find_section_elements(code, chapter, section)
    return nil if elements.empty?

    # Separate normative and general recommendation elements
    normative_elements = elements.where(is_general_recommendation: false)
                                .order(:position_in_parent, :id)
    ar_elements = elements.where(is_general_recommendation: true)
                        .order(:position_in_parent, :id)

    # Build HTML: normative content first, then AR
    html_parts = []
    
    # Normative text
    normative_html = normative_elements.pluck(:html_snippet).join("\n")
    html_parts << normative_html if normative_html.present?

    # General recommendations (if any)
    if ar_elements.any?
      ar_html = ar_elements.pluck(:html_snippet).join("\n")
      # Wrap in general-recommendation div if not already wrapped
      if ar_html.present? && !ar_html.include?('class="general-recommendation"')
        html_parts << %(<div class="general-recommendation">\n#{ar_html}\n</div>)
      else
        html_parts << ar_html
      end
    end

    html_parts.join("\n")
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
      .where.not(text_content: [nil, ""])
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
      .where.not(text_content: [nil, ""])

    # Apply chapter filter
    if chapter.present?
      scope = scope.where(chapter: chapter)
    else
      scope = scope.where(chapter: nil)
    end

    scope
  end
end
