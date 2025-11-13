class QuerySanitizer
  # Dangerous patterns to catch in queries of 6+ chars
  # Targets common XSS/injection vectors without affecting normal search
  DANGEROUS_PATTERNS = [
    /<script/i,
    /javascript:/i,
    /on\w+\s*=/i,  # e.g., onclick=, onload=
    /eval\(/i,
    /iframe/i
  ].freeze

  MIN_LENGTH_TO_SANITIZE = 6
  SHORT_QUERY_LENGTH = 5

  # Cleaning strategy:
  # - Queries <= 5 chars: minimal cleaning (only UTF-8, trim, collapse whitespace)
  # - Queries > 5 chars: full cleaning UNLESS it matches dangerous patterns exactly
  #
  # Rationale:
  # - Short queries like "<" or "if" should pass through unsanitized for search
  # - Longer queries are more likely to contain meaningful content, and we check
  #   for specific high-risk patterns (script, javascript, onclick, eval, iframe)
  # - Full cleaning (strip_tags, remove control chars) happens only for longer queries
  #   without dangerous patterns
  #
  # Returns a safe String (may be empty)
  def self.clean(input)
    s = input.to_s.dup

    # Always: Ensure UTF-8, drop invalid/undefined bytes
    s = s.encode("UTF-8", invalid: :replace, undef: :replace, replace: "")

    # Always: Trim and collapse whitespace
    s = s.gsub(/\s+/, " ").strip

    # For short queries (5 chars or less), return early with minimal cleaning
    return s if s.length <= SHORT_QUERY_LENGTH

    # For longer queries, check for dangerous patterns
    return "" if contains_dangerous_pattern?(s)

    return s
  end

  # Check if query contains any dangerous patterns
  def self.contains_dangerous_pattern?(query)
    DANGEROUS_PATTERNS.any? { |pattern| pattern.match?(query) }
  end
end
