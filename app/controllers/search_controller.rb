class SearchController < ApplicationController
  include ApplicationHelper
  include ActionView::Helpers::TextHelper
  before_action :set_noindex

  def index
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
end
