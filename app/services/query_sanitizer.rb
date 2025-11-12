class QuerySanitizer
  # Rudimentary cleaning of user-provided search queries
  # - force UTF-8, drop invalid bytes
  # - strip HTML tags
  # - remove zero-width and control characters
  # - collapse whitespace
  # - trim
  # Returns a safe String (may be empty)
  def self.clean(input)
    s = input.to_s.dup
    # Ensure UTF-8, drop invalid/undefined bytes
    s = s.encode("UTF-8", invalid: :replace, undef: :replace, replace: "")

    # Strip any HTML tags
    s = ActionController::Base.helpers.strip_tags(s)

    # Remove zero-width characters and general control chars
    # Zero-width: U+200B..U+200D, U+2060, U+FEFF
    s = s.gsub(/[\u200B-\u200D\u2060\uFEFF]/, "")
    s = s.gsub(/[[:cntrl:]]/, " ")

    # Collapse all whitespace to single spaces
    s = s.gsub(/\s+/, " ")

    # Trim
    s.strip
  end
end
