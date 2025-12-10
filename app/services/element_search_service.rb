class ElementSearchService
  def initialize(limit: 500)
    @limit = limit
  end

  # Search elements by text content
  # Returns array of Elements with hierarchy information
  # Only searches current elements from current scrapes
  # De-duplicates identical text within the same (regulation, chapter, section, AR) scope.
  def search(query)
    return [] if query.blank?

    escaped_query = escape_query(query)

    # Tag preference: prefer <p> over list items and generic containers
    tag_pref_sql = <<~SQL.squish
      CASE elements.tag_name
        WHEN 'p'  THEN 0
        WHEN 'li' THEN 1
        WHEN 'td' THEN 2
        WHEN 'th' THEN 3
        WHEN 'div' THEN 8
        ELSE 9
      END
    SQL

    scope = Element.unscoped
            .joins(:scrape)
            .where(elements: { current: true })
            .where(scrapes: { current: true })
            .where("elements.text_content ILIKE ?", "%#{escaped_query}%")

    # DISTINCT ON de-duplicates within the section scope by identical text
    # Use from to wrap the select in a subquery for compatibility with count/limit
    distinct_query = scope
      .select("DISTINCT ON (elements.regulation, elements.chapter, elements.section, elements.is_general_recommendation, elements.text_content) elements.*")
      .order(Arel.sql("elements.regulation, elements.chapter NULLS FIRST, elements.section NULLS FIRST, elements.is_general_recommendation, elements.text_content, #{tag_pref_sql}, elements.position_in_parent NULLS FIRST, elements.id"))
      .to_sql

    Element.from("(#{distinct_query}) AS elements")
      .limit(@limit)
  end

  private

  # Escape ILIKE special characters
  def escape_query(query)
    query.gsub("%", "\\%").gsub("_", "\\_")
  end
end
