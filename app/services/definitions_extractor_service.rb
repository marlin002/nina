class DefinitionsExtractorService
  HEADER_BEGREPP = "begrepp".freeze
  HEADER_BETYDELSE = "betydelse".freeze

  def self.call
    new.call
  end

  def call
    definitions = {}

    scrape_html_snippets.each do |raw_html|
      extract_definitions_from_html(raw_html, definitions)
    end

    definitions.values.sort_by { |definition| definition[:begrepp].downcase }
  end

  private

  def scrape_html_snippets
    Scrape.where.not(raw_html: [ nil, "" ]).pluck(:raw_html)
  end

  def extract_definitions_from_html(raw_html, definitions)
    return if raw_html.blank?

    document = Nokogiri::HTML(raw_html)
    document.css("table").each do |table|
      extract_definitions_from_table(table, definitions)
    end
  end

  def extract_definitions_from_table(table, definitions)
    rows = table.css("tr")
    return if rows.empty?

    header_context = find_header_context(rows)
    return if header_context.nil?

    header_row_index = header_context[:row_index]
    begrepp_index = header_context[:begrepp_index]
    betydelse_index = header_context[:betydelse_index]

    rows[(header_row_index + 1)..].to_a.each do |row|
      cells = row.css("th,td")
      next if cells.size <= [ begrepp_index, betydelse_index ].max

      begrepp = normalize_begrepp(cells[begrepp_index].text)
      betydelse = normalize_text(cells[betydelse_index].text)
      next if begrepp.blank? || betydelse.blank?

      normalized_begrepp = begrepp.downcase
      normalized_betydelse = betydelse.downcase
      dedupe_key = "#{normalized_begrepp}\u0000#{normalized_betydelse}"

      definitions[dedupe_key] ||= { begrepp: begrepp, betydelse: betydelse }
    end
  end

  def find_header_context(rows)
    rows.each_with_index do |row, row_index|
      header_cells = row.css("th,td")
      next if header_cells.empty?

      normalized_headers = header_cells.map { |cell| normalize_text(cell.text).downcase }
      begrepp_index = normalized_headers.index(HEADER_BEGREPP)
      betydelse_index = normalized_headers.index(HEADER_BETYDELSE)
      next if begrepp_index.nil? || betydelse_index.nil?

      return {
        row_index: row_index,
        begrepp_index: begrepp_index,
        betydelse_index: betydelse_index
      }
    end

    nil
  end

  def normalize_text(text)
    text.to_s.gsub("\u00A0", " ").squish
  end

  def normalize_begrepp(text)
    normalize_text(text).sub(/\A[[:alpha:]]\s*\)\s*/i, "")
  end
end
