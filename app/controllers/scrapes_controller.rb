class ScrapesController < ApplicationController
  include ApplicationHelper
  include ActionView::Helpers::TextHelper
  before_action :set_noindex, except: [ :about, :all ]

  def index
    scrapes_unsorted = Scrape.joins(:source).includes(:source)

    # Sort by regulation number numerically (AFS 2023:1, 2023:2, etc.)
    @scrapes = scrapes_unsorted.sort_by do |scrape|
      regulation_number(scrape.source.url).to_i
    end

    @stats = {
      total_scrapes: scrapes_unsorted.count,
      total_articles: scrapes_unsorted.sum { |s| article_count(s.raw_html) },
      total_general_recommendations: scrapes_unsorted.sum { |s| general_recommendation_count(s.raw_html) },
      total_appendices: scrapes_unsorted.sum { |s| appendix_count(s.raw_html) },
      last_updated: scrapes_unsorted.maximum(:fetched_at)
    }

    @recent_searches = SearchQuery.recent
    @popular_searches = SearchQuery.popular
  end

  def all
    scrapes_unsorted = Scrape.joins(:source).includes(:source)

    # Sort by regulation number numerically with zero-padding (AFS 2023:01, 2023:02, etc.)
    @scrapes = scrapes_unsorted.sort_by do |scrape|
      regulation_number(scrape.source.url).to_i
    end

    @stats = {
      total_scrapes: scrapes_unsorted.count,
      total_articles: scrapes_unsorted.sum { |s| article_count(s.raw_html) },
      total_general_recommendations: scrapes_unsorted.sum { |s| general_recommendation_count(s.raw_html) },
      total_appendices: scrapes_unsorted.sum { |s| appendix_count(s.raw_html) },
      last_updated: scrapes_unsorted.maximum(:fetched_at)
    }
  end

  def search
    @query = QuerySanitizer.clean(params[:q])
    @sort_by = params[:sort_by].to_s.strip
    @results = []
    @regex_results = nil

    # Validate query length (min 2, max 100 characters)
    if @query.present? && @query.length > 100
      @query_error = I18n.t("search.errors.too_long")
      return
    end

    if @query.present?
      # Check if this is a regex search
      if RegexSearchService.regex_search?(@query)
        # Execute regex search
        regex_service = RegexSearchService.new(limit: AppConstants::MAX_SEARCH_RESULTS)
        @regex_results = regex_service.search(@query)

        # Set error if regex search failed
        if @regex_results[:error].present?
          @query_error = I18n.t(@regex_results[:error])
          @regex_results = nil
        end
        # Note: Regex searches are NOT logged (like sorted searches)
      else
        # Normal search: use ElementSearchService
        search_service = ElementSearchService.new(limit: AppConstants::MAX_SEARCH_RESULTS)
        elements = search_service.search(@query)

        # Map elements to result hashes with hierarchy info
        @results = elements.map do |element|
          {
            element_id: element.id,
            element_text: element.text_content,
            regulation: element.regulation,
            chapter: element.chapter,
            section: element.section,
            appendix: element.appendix,
            is_general_recommendation: element.is_general_recommendation,
            is_transitional: element.is_transitional,
            construct_type: determine_construct_type(element),
            hierarchy_label: format_hierarchy_label(element),
            complete_reference: format_complete_reference(element),
            scrape: element.scrape,
            subject: regulation_title_subject(element.scrape.title),
            regulation_name: regulation_name(element.scrape.source.url),
            reg_num: extract_regulation_number(element.scrape.source.url)
          }
        end

        # Sort based on parameter
        @results = apply_sort(@results, @sort_by)

        # Log search query with match count only for new searches (not sort operations)
        # Only log if there are results AND no sort_by parameter is present
        SearchQuery.log_search(@query, @results.size) if @results.any? && @sort_by.blank?
      end
    end
  end

  def about
    # Simple about page
  end

  def api_info
    # API documentation and sandbox page
  end

  def dev_reference_lookup
    @reference = params[:reference].to_s.strip
    @result = nil
    @error = nil
    @prev_reference = nil
    @next_reference = nil

    if @reference.present?
      begin
        # Parse the reference string (e.g., "AFS 2023:10, 13 kap., 10 §")
        parsed = parse_reference(@reference)

        if parsed[:error]
          @error = parsed[:error]
        else
          # Find elements matching the reference directly
          elements = find_elements_by_parsed_reference(parsed)

          if elements.empty?
            @error = "No elements found for reference: #{parsed[:regulation]}" +
                     (parsed[:chapter] ? ", #{parsed[:chapter]} kap." : "") +
                     (parsed[:section] ? ", #{parsed[:section]} §" : "") +
                     (parsed[:is_ar] ? ", AR" : "")
          else
            # Build result
            @result = {
              regulation: parsed[:regulation],
              chapter: parsed[:chapter],
              section: parsed[:section],
              is_general_recommendation: parsed[:is_ar],
              elements: elements,
              html: elements.map(&:html_snippet).join("\n"),
              text: elements.map(&:text_content).join("\n")
            }

            # Find previous and next sections for navigation
            if parsed[:section].present?
              @prev_reference = find_previous_section(parsed)
              @next_reference = find_next_section(parsed)
            end
          end
        end
      rescue => e
        @error = "Error parsing reference: #{e.message}"
      end
    end
  end

  def raw
    @scrape = Scrape.find(params[:id])
    @query = params[:q].to_s.strip

    # Set content for layout
    @regulation_name = regulation_name(@scrape.source.url)
    @regulation_title = regulation_title_subject(@scrape.title)
    @source_url = @scrape.source.url
    @article_count = article_count(@scrape.raw_html)
    @general_recommendation_count = general_recommendation_count(@scrape.raw_html)
    @appendix_count = appendix_count(@scrape.raw_html)

    html = @scrape.raw_html.to_s

    # If a specific element was clicked in the search results, try to focus that snippet
    if params[:focus_element_id].present?
      element = @scrape.elements.current.find_by(id: params[:focus_element_id])
      html = inject_focus_snippet(html, element) if element
    end

    highlighted_html = highlight_raw_html(html, @query)

    render html: highlighted_html.html_safe, layout: "raw_content"
  rescue ActiveRecord::RecordNotFound
    redirect_to scrapes_path, alert: "Scrape not found"
  end

  private

  # Determine what construct an element belongs to
  def determine_construct_type(element)
    if element.is_transitional?
      :transitional
    elsif element.appendix.present?
      :appendix
    elsif element.section.present?
      :section
    end
  end

  # Format hierarchy label for display
  def format_hierarchy_label(element)
    parts = []

    if element.is_transitional?
      parts << "Övergångsbestämmelser"
    elsif element.appendix.present?
      parts << "Bilaga #{element.appendix}"
    end

    if element.section.present?
      parts << "#{element.section} §"
    end

    if element.is_general_recommendation && element.section.present?
      parts << "AR"
    end

    parts.join(" · ")
  end

  # Format complete reference including regulation and hierarchy
  # e.g., "AFS 2023:1, 3 kap., 5 §, AR" (using short-hand labels)
  def format_complete_reference(element)
    parts = [ element.regulation ]

    if element.is_transitional?
      parts << "ÖB"
    elsif element.appendix.present?
      parts << "Bilaga #{element.appendix}"
    else
      # Add chapter if present
      if element.chapter.present?
        parts << "#{element.chapter} kap."
      end

      # Add section if present
      if element.section.present?
        parts << "#{element.section} §"
      end
    end

    if element.is_general_recommendation && element.section.present?
      parts << "AR"
    end

    parts.join(", ")
  end

  # Wrap the first occurrence of an element's HTML snippet in a focus wrapper
  # so the browser can scroll to and highlight it.
  def inject_focus_snippet(html, element)
    snippet = element&.html_snippet.to_s
    return html if snippet.blank?

    idx = html.index(snippet)
    return html unless idx

    before = html[0...idx]
    after  = html[(idx + snippet.length)..] || ""

    before + %(<span id="focus" class="element-focus">#{snippet}</span>) + after
  end

  # Lightweight highlighter for raw HTML that preserves existing tags
  # (unlike ActionView::Helpers::TextHelper.highlight, which escapes HTML).
  def highlight_raw_html(html, query)
    query = query.to_s.strip
    return html if query.blank?

    pattern = Regexp.escape(query)
    html.gsub(/(#{pattern})/i, '<mark>\1</mark>')
  end

  # Apply sorting based on sort_by parameter
  def apply_sort(results, sort_by)
    case sort_by
    when "reference_desc"
      # Sort by reference descending
      results.sort_by { |r| complete_reference_sort_key(r) }.reverse
    when "relevance"
      # Sort by regulation then hierarchy (best for relevance)
      results.sort_by { |r| [ r[:reg_num].to_i, sort_hierarchy_key(r) ] }
    when "relevance_desc"
      # Sort by regulation then hierarchy (best for relevance)
      results.sort_by { |r| [ r[:reg_num].to_i, sort_hierarchy_key(r) ] }.reverse
    else
      # Default: by reference: regulation (year+number), chapter, section, appendix
      results.sort_by { |r| complete_reference_sort_key(r) }
    end
  end

  # Create sort key based on complete reference for natural sorting
  # Zero-pads regulation, chapter, and section numbers for proper numeric sorting
  # e.g., "AFS 2023:01, 05 kap., 065 §" sorts before "AFS 2023:13, 02 kap., 010 §"
  def complete_reference_sort_key(result)
    parts = []

    # Regulation with zero-padded number (e.g., "AFS 2023:01")
    reg_num_padded = result[:reg_num].to_i.to_s.rjust(2, "0")
    parts << "AFS 2023:#{reg_num_padded}"

    if result[:is_transitional]
      parts << "ÖB"
    elsif result[:appendix].present?
      # Appendix with zero-padding
      appendix_padded = result[:appendix].to_s.rjust(2, "0")
      parts << "Bilaga #{appendix_padded}"
    else
      # Chapter with zero-padding (if present)
      if result[:chapter].present?
        chapter_padded = result[:chapter].to_i.to_s.rjust(3, "0")
        parts << "#{chapter_padded} kap."
      end

      # Section with zero-padding (if present)
      if result[:section].present?
        section_padded = result[:section].to_i.to_s.rjust(3, "0")
        parts << "#{section_padded} §"
      end
    end

    # Add AR if it's a general recommendation
    if result[:is_general_recommendation] && result[:section].present?
      parts << "AR"
    end

    parts.join(", ")
  end

  # Create sort key for hierarchy (sections first, then subsections, then appendices)
  def sort_hierarchy_key(result)
    if result[:is_transitional]
      [ 2, 0, 0 ]  # Transitional rules at end
    elsif result[:appendix].present?
      [ 1, result[:appendix].to_i, 0 ]  # Appendices
    elsif result[:section].present?
      [ 0, result[:section], result[:is_general_recommendation] ? 1 : 0 ]  # Sections, with advice after
    else
      [ 3, 0, 0 ]  # Fallback
    end
  end

  # Extract regulation number from URL for sorting
  # e.g. "https://...afs-20231/" -> "1", "...afs-202310/" -> "10"
  def extract_regulation_number(url)
    match = url.match(/afs-2023(\d+)/)
    match ? match[1] : "999"
  end

  # Robots header: allow indexing only if explicitly enabled
  def set_noindex
    if ENV["ALLOW_INDEXING"] == "true"
      response.headers["X-Robots-Tag"] = "index, follow"
    else
      response.headers["X-Robots-Tag"] = "noindex, nofollow"
    end
  end

  # Parse a reference string like "AFS 2023:10, 13 kap., 10 §" or "AFS 2023:10, 13 kap., 10 §, AR"
  def parse_reference(reference)
    result = { error: nil, regulation: nil, chapter: nil, section: nil, is_ar: false }

    # Extract regulation (e.g., "AFS 2023:10")
    if reference =~ /AFS\s+(\d{4}):(\d+)/i
      result[:regulation] = "AFS #{$1}:#{$2}"
    else
      result[:error] = "Invalid regulation format. Expected format like 'AFS 2023:10'"
      return result
    end

    # Extract chapter (e.g., "13 kap.")
    if reference =~ /(\d+)\s+kap\./i
      result[:chapter] = $1.to_i
    end

    # Extract section (e.g., "10 §")
    if reference =~ /(\d+)\s*§/i
      result[:section] = $1.to_i
    end

    # Check for AR (Allmänna råd / General recommendation)
    result[:is_ar] = reference =~ /\bAR\b/i ? true : false

    result
  end

  # Find elements matching the parsed reference directly from elements table
  def find_elements_by_parsed_reference(parsed)
    # Join with scrapes to ensure we only get elements from current scrapes
    query = Element.joins(:scrape).where(scrapes: { current: true }, regulation: parsed[:regulation])

    # Add chapter filter if present
    query = query.where(chapter: parsed[:chapter]) if parsed[:chapter].present?
    query = query.where(chapter: nil) unless parsed[:chapter].present?

    # Add section filter if present
    query = query.where(section: parsed[:section]) if parsed[:section].present?

    # Filter by general recommendation if specified
    if parsed[:is_ar]
      # Only show AR when explicitly requested
      query = query.where(is_general_recommendation: true)
    end
    # When section is specified without AR, show both section text and its allmänna råd

    # Only select elements that have text_content
    query = query.where.not(text_content: nil).where.not(text_content: "")

    # Prefer <p> over list items and containers, and de-duplicate identical text within the section
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

    # Wrap in subquery to avoid DISTINCT ON issues with count
    distinct_query = query
      .select("DISTINCT ON (elements.text_content) elements.*")
      .order(Arel.sql("elements.text_content, #{tag_pref_sql}, elements.is_general_recommendation, elements.position_in_parent NULLS FIRST, elements.id"))
      .to_sql

    Element.from("(#{distinct_query}) AS elements")
  end

  # Find the previous section for navigation
  def find_previous_section(parsed)
    return nil unless parsed[:section].present?

    # Get all sections for this regulation, ordered by chapter and section
    sections = Element.joins(:scrape)
                      .where(scrapes: { current: true }, regulation: parsed[:regulation])
                      .where.not(section: nil)
                      .select(:chapter, :section)
                      .distinct
                      .order(:chapter, :section)

    # Find current position
    current_index = sections.index do |s|
      s.chapter == parsed[:chapter] && s.section == parsed[:section]
    end

    return nil unless current_index && current_index > 0

    # Get previous section
    prev = sections[current_index - 1]
    build_reference_string(parsed[:regulation], prev.chapter, prev.section, parsed[:is_ar])
  end

  # Find the next section for navigation
  def find_next_section(parsed)
    return nil unless parsed[:section].present?

    # Get all sections for this regulation, ordered by chapter and section
    sections = Element.joins(:scrape)
                      .where(scrapes: { current: true }, regulation: parsed[:regulation])
                      .where.not(section: nil)
                      .select(:chapter, :section)
                      .distinct
                      .order(:chapter, :section)

    # Find current position
    current_index = sections.index do |s|
      s.chapter == parsed[:chapter] && s.section == parsed[:section]
    end

    return nil unless current_index && current_index < sections.length - 1

    # Get next section
    next_sec = sections[current_index + 1]
    build_reference_string(parsed[:regulation], next_sec.chapter, next_sec.section, parsed[:is_ar])
  end

  # Build a reference string from components
  def build_reference_string(regulation, chapter, section, is_ar = false)
    parts = [ regulation ]
    parts << "#{chapter} kap." if chapter.present?
    parts << "#{section} §" if section.present?
    parts << "AR" if is_ar
    parts.join(", ")
  end
end
