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
    # Get all chapter-section combinations and normalize to integers
    raw_pairs = elements
      .where.not(chapter: nil)
      .where.not(section: nil)
      .distinct
      .pluck(:chapter, :section)

    normalized = raw_pairs.map do |ch, sec|
      [ safe_int(ch), safe_int(sec) ]
    end.reject { |ch, sec| ch.nil? || sec.nil? }

    grouped = normalized.group_by { |ch, _sec| ch }

    grouped.map do |chapter, pairs|
      sections = pairs.map { |_ch, sec| sec }.uniq.sort
      { chapter: chapter, sections: sections }
    end.sort_by { |h| h[:chapter] }
  end

  # Build list of sections without chapters
  # @return [Array<Integer>] Section numbers
  def self.build_sections_without_chapter(elements)
    secs = elements
      .where(chapter: nil)
      .where.not(section: nil)
      .distinct
      .pluck(:section)

    secs.map { |s| safe_int(s) }.compact.uniq.sort
  end

  # Build list of appendices
  # @return [Array<String>] Appendix identifiers
  def self.build_appendices(elements)
    elements
      .where.not(appendix: nil)
      .distinct
      .pluck(:appendix)
      .map { |a| a.to_s.strip }
      .reject(&:blank?)
      .uniq
      .sort
  end

  # Safely convert to integer, returning nil if not a clean integer
  def self.safe_int(value)
    return nil if value.nil?
    return value if value.is_a?(Integer)

    str = value.to_s.strip
    return nil if str.empty?
    return str.to_i if str.match?(/^\d+$/)

    nil
  end
end
