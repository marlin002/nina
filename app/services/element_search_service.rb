class ElementSearchService
  def initialize(limit: 500)
    @limit = limit
  end

  # Search elements by text content
  # Returns array of Elements with hierarchy information
  # Only searches current elements from current scrapes
  def search(query)
    return [] if query.blank?

    escaped_query = escape_query(query)

    Element.unscoped
      .where(current: true)
      .where("text_content ILIKE ?", "%#{escaped_query}%")
      .includes(:scrape)
      .where(scrapes: { current: true })
      .limit(@limit)
  end

  private

  # Escape ILIKE special characters
  def escape_query(query)
    query.gsub("%", "\\%").gsub("_", "\\_")
  end
end
