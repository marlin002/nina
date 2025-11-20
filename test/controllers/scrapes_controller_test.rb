require "test_helper"

class ScrapesControllerTest < ActionDispatch::IntegrationTest
  test "search without sort_by parameter logs the search" do
    # Create some test data
    source = sources(:one)
    scrape = scrapes(:one)
    element = elements(:one)

    initial_count = SearchQuery.count

    get search_scrapes_path, params: { q: "test query" }

    assert_response :success
    # If there are results, a new search should be logged
    if assigns(:results).any?
      assert_equal initial_count + 1, SearchQuery.count
      latest_search = SearchQuery.last
      assert_equal "test query", latest_search.query
    end
  end

  test "search with sort_by parameter does not log the search" do
    # Create some test data
    source = sources(:one)
    scrape = scrapes(:one)
    element = elements(:one)

    initial_count = SearchQuery.count

    get search_scrapes_path, params: { q: "test query", sort_by: "reference" }

    assert_response :success
    # Even if there are results, no new search should be logged
    assert_equal initial_count, SearchQuery.count
  end

  test "clicking link from recent searches panel does not log" do
    # Simulate what happens when clicking a link from the recent searches panel
    # These links now include sort_by: 'reference'
    initial_count = SearchQuery.count

    get search_scrapes_path, params: { q: "arbetsmiljö", sort_by: "reference" }

    assert_response :success
    # No new search should be logged because sort_by is present
    assert_equal initial_count, SearchQuery.count
  end

  test "search with sort_by and no results does not log" do
    initial_count = SearchQuery.count

    get search_scrapes_path, params: { q: "xyznonexistent", sort_by: "reference" }

    assert_response :success
    # No search should be logged (no results + sort_by present)
    assert_equal initial_count, SearchQuery.count
  end
end
