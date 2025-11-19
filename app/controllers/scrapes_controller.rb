class ScrapesController < ApplicationController
  include ApplicationHelper
  include ActionView::Helpers::TextHelper
  before_action :set_noindex, except: [ :about, :all ]

  def index
    scrapes_unsorted = Scrape.joins(:source).includes(:source)

    # Sort by regulation number numerically (AFS 2023:1, 2023:2, etc.)
    @scrapes = scrapes_unsorted.sort_by do |scrape|
      regulation_number(scrape.source.url)
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

    # Sort by regulation number numerically (AFS 2023:1, 2023:2, etc.)
    @scrapes = scrapes_unsorted.sort_by do |scrape|
      regulation_number(scrape.source.url)
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

    # Validate query length (min 2, max 100 characters)
    if @query.present? && @query.length > 100
      @query_error = I18n.t("search.errors.too_long")
      return
    end

    if @query.present?
      # Search elements for matching text content
      search_service = ElementSearchService.new(limit: 500)
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

  def about
    # Simple about page
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
    when "reference"
      # Sort by complete reference: regulation (year+number), chapter, section, appendix
      results.sort_by { |r| complete_reference_sort_key(r) }
    when "reference_desc"
      # Sort by complete reference descending
      results.sort_by { |r| complete_reference_sort_key(r) }.reverse
    when "relevance"
      # Default sort: by regulation then hierarchy (best for relevance)
      results.sort_by { |r| [ r[:reg_num].to_i, sort_hierarchy_key(r) ] }
    else
      # Default: by regulation then hierarchy
      results.sort_by { |r| [ r[:reg_num].to_i, sort_hierarchy_key(r) ] }
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
end
