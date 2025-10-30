class ScrapesController < ApplicationController
  include ApplicationHelper
  include ActionView::Helpers::TextHelper
  before_action :set_noindex

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
  end

  def search
    @query = params[:q].to_s.strip
    @sort_by = params[:sort_by].to_s.strip
    @results = []

    # Validate query length (min 2, max 100 characters)
    if @query.present? && (@query.length < 2 || @query.length > 100)
      @query_error = "Sökfras måste vara mellan 2 och 100 tecken."
      return
    end

    if @query.present?
      log_search_query

      # Search elements for matching text content
      search_service = ElementSearchService.new(limit: 500)
      elements = search_service.search(@query)

      # Map elements to result hashes with hierarchy info
      @results = elements.map do |element|
        {
          element_id: element.id,
          element_text: element.text_content,
          regulation: element.regulation,
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

      log_search_results
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

    render html: highlight(@scrape.raw_html, @query).html_safe, layout: "raw_content"
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

  # Apply sorting based on sort_by parameter
  def apply_sort(results, sort_by)
    case sort_by
    when "reference"
      results.sort_by { |r| [ r[:regulation], sort_hierarchy_key(r) ] }
    when "reference_desc"
      results.sort_by { |r| [ r[:regulation], sort_hierarchy_key(r) ] }.reverse
    when "relevance"
      # Default sort: by regulation then hierarchy (best for relevance)
      results.sort_by { |r| [ r[:reg_num].to_i, sort_hierarchy_key(r) ] }
    else
      # Default: by regulation then hierarchy
      results.sort_by { |r| [ r[:reg_num].to_i, sort_hierarchy_key(r) ] }
    end
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

  def log_search_query
    log_data = {
      event: "search_query",
      query: @query,
      timestamp: Time.current.iso8601
    }
    Rails.logger.info(log_data.to_json)
  end

  def log_search_results
    log_data = {
      event: "search_results",
      query: @query,
      results_count: @results.size,
      timestamp: Time.current.iso8601
    }
    Rails.logger.info(log_data.to_json)
  end

  # Set protection against robot indexing. See also Robots.txt and <meta..> in Application.html.erb
  def set_noindex
    response.headers["X-Robots-Tag"] = "noindex, nofollow"
  end
end
