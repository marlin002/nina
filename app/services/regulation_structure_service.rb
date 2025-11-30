class RegulationStructureService
  # Get the structure of a regulation (chapters, sections, appendices)
  # @param year [Integer] Year
  # @param number [Integer] Number
  # @return [Hash] Structure with chapters, sections_without_chapter, appendices
  def self.structure(year:, number:)
    code = Regulations::Code.from_year_and_number(year, number)

    # Find all current elements for this regulation
    elements = Element
      .joins(:scrape)
      .where(scrapes: { current: true })
      .where(regulation: code)

    # Build structure
    {
      code: code,
      year: year,
      number: number,
      chapters: build_chapters(elements),
      sections_without_chapter: build_sections_without_chapter(elements),
      appendices: build_appendices(elements)
    }
  end

  private

  # Build chapters array with their sections
  # @return [Array<Hash>] Array of {chapter: n, sections: [1, 2, 3]}
  def self.build_chapters(elements)
    # Get all chapter-section combinations
    chapter_sections = elements
      .where.not(chapter: nil, section: nil)
      .distinct
      .pluck(:chapter, :section)
      .group_by(&:first)

    # Sort and format
    chapter_sections.map do |chapter, pairs|
      {
        chapter: chapter,
        sections: pairs.map(&:last).uniq.sort
      }
    end.sort_by { |h| h[:chapter] }
  end

  # Build list of sections without chapters
  # @return [Array<Integer>] Section numbers
  def self.build_sections_without_chapter(elements)
    elements
      .where(chapter: nil)
      .where.not(section: nil)
      .distinct
      .pluck(:section)
      .sort
  end

  # Build list of appendices
  # @return [Array<String>] Appendix identifiers
  def self.build_appendices(elements)
    elements
      .where.not(appendix: nil)
      .distinct
      .pluck(:appendix)
      .sort
  end
end
