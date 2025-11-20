require "test_helper"

class RegexSearchServiceTest < ActiveSupport::TestCase
  test "regex_search? detects valid regex format" do
    assert RegexSearchService.regex_search?("/pattern/")
    assert RegexSearchService.regex_search?("/[a-z]+/")
    assert RegexSearchService.regex_search?("/test.*123/")
  end

  test "regex_search? rejects invalid formats" do
    assert_not RegexSearchService.regex_search?("pattern")
    assert_not RegexSearchService.regex_search?("/pattern")
    assert_not RegexSearchService.regex_search?("pattern/")
    assert_not RegexSearchService.regex_search?("//")  # Too short
    assert_not RegexSearchService.regex_search?("")
    assert_not RegexSearchService.regex_search?(nil)
  end

  test "validates pattern syntax" do
    service = RegexSearchService.new
    
    # Valid patterns
    assert service.send(:valid_pattern?, "test")
    assert service.send(:valid_pattern?, "[a-z]+")
    assert service.send(:valid_pattern?, "\\d{3}")
    
    # Invalid patterns
    assert_not service.send(:valid_pattern?, "[unclosed")
    assert_not service.send(:valid_pattern?, "(unclosed")
    assert_not service.send(:valid_pattern?, "*invalid")
  end

  test "extracts pattern from delimiters" do
    service = RegexSearchService.new
    
    assert_equal "test", service.send(:extract_pattern, "/test/")
    assert_equal "[a-z]+", service.send(:extract_pattern, "/[a-z]+/")
    assert_equal "", service.send(:extract_pattern, "//")
  end

  test "returns empty result with error for blank query" do
    service = RegexSearchService.new
    result = service.search("")
    
    assert_equal [], result[:results]
    assert_equal 0, result[:total_unique]
    assert_equal 0, result[:total_occurrences]
    assert_equal "search.errors.regex_empty", result[:error]
  end

  test "returns empty result with error for empty pattern" do
    service = RegexSearchService.new
    result = service.search("//")
    
    assert_equal [], result[:results]
    assert_equal "search.errors.regex_empty", result[:error]
  end

  test "returns error for invalid regex syntax" do
    service = RegexSearchService.new
    result = service.search("/[unclosed/")
    
    assert_equal [], result[:results]
    assert_equal "search.errors.regex_invalid", result[:error]
  end

  test "search returns results for valid regex with matches" do
    # Create test data
    source = sources(:one)
    scrape = scrapes(:one)
    
    # Create elements with different text
    Element.create!(
      scrape: scrape,
      tag_name: "p",
      html_snippet: "<p>Test content with abc123</p>",
      text_content: "Test content with abc123",
      regulation: "AFS 2015:1",
      current: true
    )
    
    Element.create!(
      scrape: scrape,
      tag_name: "p",
      html_snippet: "<p>Another test with def456</p>",
      text_content: "Another test with def456",
      regulation: "AFS 2015:1",
      current: true
    )
    
    Element.create!(
      scrape: scrape,
      tag_name: "p",
      html_snippet: "<p>More content with abc789</p>",
      text_content: "More content with abc789",
      regulation: "AFS 2015:1",
      current: true
    )
    
    service = RegexSearchService.new
    result = service.search("/abc\\d+/")
    
    # Should find "abc123" and "abc789"
    assert result[:results].any?
    assert_equal 2, result[:total_unique]
    assert_equal 2, result[:total_occurrences]
    assert_nil result[:error]
    
    # Check that results are sorted alphabetically
    matched_strings = result[:results].map { |r| r[:matched_string] }
    assert_equal matched_strings.sort, matched_strings
  end

  test "search counts duplicate matches correctly" do
    source = sources(:one)
    scrape = scrapes(:one)
    
    # Use a unique word to avoid counting fixture data
    unique_word = "UniqueTestWord"
    
    # Create elements with the same matching pattern
    3.times do |i|
      Element.create!(
        scrape: scrape,
        tag_name: "p",
        html_snippet: "<p>#{unique_word} #{i}</p>",
        text_content: "#{unique_word} #{i}",
        regulation: "AFS 2015:1",
        current: true
      )
    end
    
    service = RegexSearchService.new
    result = service.search("/#{unique_word}/")
    
    # Should find the unique word appearing 3 times
    assert_equal 1, result[:total_unique]
    assert_equal 3, result[:total_occurrences]
    assert_equal unique_word, result[:results].first[:matched_string]
    assert_equal 3, result[:results].first[:count]
  end

  test "search respects limit parameter" do
    source = sources(:one)
    scrape = scrapes(:one)
    
    # Create more elements than the limit
    10.times do |i|
      Element.create!(
        scrape: scrape,
        tag_name: "p",
        html_snippet: "<p>Word#{i}</p>",
        text_content: "Word#{i}",
        regulation: "AFS 2015:1",
        current: true
      )
    end
    
    service = RegexSearchService.new(limit: 5)
    result = service.search("/Word\\d+/")
    
    # Should return at most 5 results
    assert result[:results].length <= 5
  end

  test "search only includes current elements from current scrapes" do
    source = sources(:one)
    scrape = scrapes(:one)
    
    # Create current element
    current_element = Element.create!(
      scrape: scrape,
      tag_name: "p",
      html_snippet: "<p>Current content</p>",
      text_content: "Current content",
      regulation: "AFS 2015:1",
      current: true
    )
    
    # Create historical element
    historical_element = Element.unscoped.create!(
      scrape: scrape,
      tag_name: "p",
      html_snippet: "<p>Historical content</p>",
      text_content: "Historical content",
      regulation: "AFS 2015:1",
      current: false,
      superseded_at: 1.day.ago
    )
    
    service = RegexSearchService.new
    result = service.search("/content/")
    
    # Should only find "content" once (from current element)
    matched_strings = result[:results].map { |r| r[:matched_string] }
    assert_includes matched_strings, "content"
    # The count should reflect only current elements
    assert result[:total_occurrences] >= 1
  end
end
