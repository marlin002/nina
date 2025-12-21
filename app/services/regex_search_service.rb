class RegexSearchService
  TIMEOUT_SECONDS = 2

  # Check if query is in regex format (/pattern/)
  def self.regex_search?(query)
    query.to_s.start_with?("/") && query.to_s.end_with?("/") && query.to_s.length > 2
  end

  def initialize(limit: AppConstants::MAX_SEARCH_RESULTS)
    @limit = limit
  end

  # Execute regex search and return frequency hash
  # Returns: { results: [{matched_string: "...", count: n}], total_unique: n, total_occurrences: n, error: nil }
  # On error: { results: [], total_unique: 0, total_occurrences: 0, error: "message" }
  def search(query)
    return empty_result_with_error("search.errors.regex_empty") if query.blank?

    # Extract pattern from /pattern/
    pattern = extract_pattern(query)
    return empty_result_with_error("search.errors.regex_empty") if pattern.blank?

    # Validate regex syntax in Ruby first
    unless valid_pattern?(pattern)
      return empty_result_with_error("search.errors.regex_invalid")
    end

    # Execute database query with timeout protection
    begin
      results = execute_regex_query(pattern)

      total_unique = results.length
      total_occurrences = results.sum { |r| r[:count] }

      {
        results: results,
        total_unique: total_unique,
        total_occurrences: total_occurrences,
        error: nil
      }
    rescue ActiveRecord::StatementInvalid => e
      if e.message.include?("timeout") || e.message.include?("canceling statement")
        empty_result_with_error("search.errors.regex_timeout")
      else
        Rails.logger.error("Regex search error: #{e.message}")
        empty_result_with_error("search.errors.regex_invalid")
      end
    rescue => e
      Rails.logger.error("Unexpected regex search error: #{e.message}")
      empty_result_with_error("search.errors.regex_invalid")
    end
  end

  private

  # Extract pattern from /pattern/ format
  def extract_pattern(query)
    query.to_s[1..-2]
  end

  # Validate regex syntax using Ruby's Regexp
  def valid_pattern?(pattern)
    Regexp.new(pattern)
    true
  rescue RegexpError
    false
  end

  # Execute PostgreSQL regex query with timeout protection
  # Returns array of hashes: [{matched_string: "text", count: 5}, ...]
  def execute_regex_query(pattern)
    results = []

    # Use a transaction to scope the timeout to this query only
    ActiveRecord::Base.transaction do
      # Set timeout for this specific query
      ActiveRecord::Base.connection.execute("SET LOCAL statement_timeout = '#{TIMEOUT_SECONDS}s'")

      # PostgreSQL query to extract all matches and count them
      # regexp_matches with 'gi' flag: global (all matches), case-insensitive
      sql = ActiveRecord::Base.sanitize_sql_array([
        <<-SQL,
          SELECT matched_string, COUNT(*) as count
          FROM (
            SELECT unnest(regexp_matches(text_content, ?, 'gi')) as matched_string
            FROM elements
            WHERE current = true
              AND scrape_id IN (SELECT id FROM scrapes WHERE current = true)
              AND text_content ~* ?
          ) matches
          GROUP BY matched_string
          ORDER BY matched_string ASC
          LIMIT ?
        SQL
        pattern,
        pattern,
        @limit
      ])

      # Execute with parameterized query (SQL injection safe)
      raw_results = ActiveRecord::Base.connection.execute(sql)

      # Convert to array of hashes with symbolized keys
      results = raw_results.map do |row|
        {
          matched_string: row["matched_string"],
          count: row["count"].to_i
        }
      end
    end

    results
  end

  # Return empty result hash with error message
  def empty_result_with_error(error_key)
    {
      results: [],
      total_unique: 0,
      total_occurrences: 0,
      error: error_key
    }
  end
end
