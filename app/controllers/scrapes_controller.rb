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
    @context = 60

    @results = []

    if @query.present?
      log_search_query
      # Escape % and _ for ILIKE
      escaped = @query.gsub("%", '\\%').gsub("_", '\\_')
      scrapes = Scrape.joins(:source).includes(:source)
                      .where("plain_text ILIKE ?", "%#{escaped}%")

      pattern = Regexp.new(Regexp.escape(@query), Regexp::IGNORECASE)

      scrapes.find_each do |scrape|
        text = scrape.plain_text.to_s
        next if text.empty?

        reg_num = regulation_number(scrape.source.url)

        text.to_enum(:scan, pattern).each do
          md = Regexp.last_match
          start_i, end_i = md.begin(0), md.end(0)

          lead_i = [ start_i - @context, 0 ].max
          trail_i = [ end_i + @context, text.length ].min

          leading = text[lead_i...start_i]
          match_text = text[start_i...end_i]
          trailing = text[end_i...trail_i]

          snippet_text = "#{leading}#{match_text}#{trailing}".strip

          @results << {
            snippet_text: snippet_text,
            leading: leading,
            match: match_text,
            trailing: trailing,
            regulation: regulation_name(scrape.source.url),
            subject: regulation_title_subject(scrape.title),
            scrape: scrape,
            reg_num: reg_num,
            position: start_i
          }
        end
      end

      # Sort by regulation number ascending, then by order of appearance within the text
      @results.sort_by! { |r| [ r[:reg_num], r[:position] ] }

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

  def anonymize_ip
    ip = request.remote_ip
    return nil unless ip

    # Keep only first two octets for IPv4, first 48 bits for IPv6
    if ip.include?(".")
      ip.split(".")[0..1].join(".") + ".x.x"
    elsif ip.include?(":")
      ip.split(":")[0..2].join(":") + ":x:x:x:x:x"
    else
      "unknown"
    end
  end

  def anonymize_session_id
    return nil unless session.id
    Digest::SHA256.hexdigest(session.id.to_s)[0..15]
  end

  # Set protection against robot indexing. See also Robots.txt and <meta..> in Application.html.erb
  def set_noindex
    response.headers["X-Robots-Tag"] = "noindex, nofollow"
  end

  # Extract numeric regulation number from URL for proper sorting
  # e.g. "https://...afs-20231/" -> 1, "...afs-202310/" -> 10
  def regulation_number(url)
    match = url.match(/afs-2023(\d+)/)
    match ? match[1].to_i : 999 # Default to high number if no match
  end

  def snippet_pattern_for(query, context_words)
    escaped = Regexp.escape(query)
    before = "(?:\\S+\\s+){0,#{context_words}}?"
    after = "(?:\\s+\\S+){0,#{context_words}}"

    /#{before}(#{escaped})#{after}/i
  end
end
