class ScrapesController < ApplicationController
  include ApplicationHelper
  
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
    @results = []

    if @query.present?
      # Escape % and _ for ILIKE
      escaped = @query.gsub('%', '\\%').gsub('_', '\\_')
      scrapes = Scrape.joins(:source).includes(:source)
                      .where("plain_text ILIKE ?", "%#{escaped}%")

      # Spaces in the query should match both regular spaces and NBSP in content
      q = normalize_nbsp_spaces(@query).strip
      escaped = Regexp.escape(q)
      flex = escaped.gsub(/\s+/, '[\s\u00A0]+')
      pattern = Regexp.new(flex, Regexp::IGNORECASE)

      scrapes.find_each do |scrape|
        reg_num = regulation_number(scrape.source.url)
        begin
          fragment = Nokogiri::HTML::DocumentFragment.parse(scrape.raw_html.to_s)
          # Ensure deterministic synthetic ids so anchors work in raw view
          assign_synthetic_ids!(fragment)

          # Build context index for this fragment
          context_index = extract_context_index(fragment)

          seen = {}
          # Traverse text nodes for precise, deep matches and dedup by nearest ancestor element with an id
          fragment.traverse do |n|
            next unless n.text?
            t = n.text.to_s
            next unless t.match?(pattern)

            el = n.parent
            next if el.nil?
            # Bubble up to the nearest element with an id
            target = el
            while target && target['id'].to_s.strip.empty?
              target = target.parent
            end
            next if target.nil?

            eid = target['id']
            next if seen[eid]

            full = target.text.to_s.strip
            next if full.empty?

            ctx = context_index[eid]
            # Prefer the nearest actual § to avoid traversal order issues
            effective_par = find_nearest_paragraph_number(target)
            effective_ctx = {
              kap: ctx&.dig(:kap),
              paragraf: effective_par || ctx&.dig(:paragraf),
              bilaga: ctx&.dig(:bilaga)
            }
            ctx_label = format_context_label(effective_ctx)
            reg_label = compose_regulation_context(regulation_name(scrape.source.url), effective_ctx)

            @results << {
              element_text: full,
              element_id: eid,
              regulation: regulation_name(scrape.source.url),
              display_label: reg_label,
              subject: regulation_title_subject(scrape.title),
              context_label: ctx_label,
              scrape: scrape,
              reg_num: reg_num
            }
            seen[eid] = true
          end
        rescue => e
          Rails.logger.warn "Search parse error for scrape #{scrape.id}: #{e.message}"
        end
      end

      # Optional sorting: by regulation (default) or by text, ascending/descending
      sort = params[:sort].to_s
      dir = params[:dir].to_s
      case sort
      when 'text'
        @results.sort_by! { |r| collapse_whitespace(r[:element_text]).downcase }
      else # 'reg' or unspecified
        @results.sort_by! { |r| [r[:reg_num], r[:element_id].to_s] }
      end
      @results.reverse! if dir == 'desc'
    end
  end

  def raw
    @scrape = Scrape.find(params[:id])
    
    # Set content for layout
    @regulation_name = regulation_name(@scrape.source.url)
    @regulation_title = regulation_title_subject(@scrape.title)
    @source_url = @scrape.source.url
    @article_count = article_count(@scrape.raw_html)
    @general_recommendation_count = general_recommendation_count(@scrape.raw_html)
    @appendix_count = appendix_count(@scrape.raw_html)

    # Enrich raw HTML with synthetic IDs and global highlights for query matches
    enriched_html = enrich_html_with_ids_and_highlights(@scrape.raw_html, params[:q])
    
    render html: enriched_html.html_safe, layout: 'raw_content'
  rescue ActiveRecord::RecordNotFound
    redirect_to scrapes_path, alert: 'Scrape not found'
  end

  private
  
  # Extract numeric regulation number from URL for proper sorting
  # e.g. "https://...afs-20231/" -> 1, "...afs-202310/" -> 10
  def regulation_number(url)
    match = url.match(/afs-2023(\d+)/)
    match ? match[1].to_i : 999 # Default to high number if no match
  end
end
