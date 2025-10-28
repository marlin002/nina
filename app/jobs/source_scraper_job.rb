class SourceScraperJob < ApplicationJob
  queue_as :scraping

  # Retry failed jobs up to 3 times with exponential backoff
  retry_on StandardError, wait: :polynomially_longer, attempts: 3

  # Don't retry certain errors
  discard_on ActiveRecord::RecordNotFound
  discard_on Faraday::UnauthorizedError
  discard_on Faraday::ForbiddenError
  discard_on Faraday::TooManyRequestsError
  discard_on URI::InvalidURIError

  def perform(source_id)
    @source = Source.find(source_id)

    Rails.logger.info "Starting scrape for source: #{@source.url}"

    # Fetch the HTML content from source page
    source_html = fetch_content(@source.url)

    # Extract title from source page
    regulation_title = extract_regulation_title(source_html)

    # Parse the HTML and extract scrapes
    scrapes_data = parse_content(source_html, @source.url, regulation_title)

    # Store the scrapes
    store_scrapes(scrapes_data)

    Rails.logger.info "Completed scrape for source: #{@source.url}. Found #{scrapes_data.length} scrapes."

  rescue => e
    Rails.logger.error "Error scraping source #{@source&.url}: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    raise
  end

  private

  def fetch_content(url)
    settings = @source.settings || {}

    connection = Faraday.new do |config|
      config.request :url_encoded
      config.response :raise_error
      config.adapter Faraday.default_adapter

      # Set timeout from source settings or default
      config.options.timeout = settings.fetch("timeout", 30).to_i
      config.options.open_timeout = 10
    end

    headers = {
      "User-Agent" => settings.fetch("user_agent", "Benina Swedish Content Scraper 1.0"),
      "Accept" => "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
      "Accept-Language" => "sv-SE,sv;q=0.9,en-US;q=0.8,en;q=0.5",
      "Accept-Charset" => "UTF-8,*;q=0.5",
      "Cache-Control" => "no-cache"
    }

    response = connection.get(url, nil, headers)

    unless response.success?
      raise "HTTP Error: #{response.status} - #{response.reason_phrase}"
    end

    response.body
  end

  def parse_content(html_content, base_url, regulation_title = nil)
    doc = Nokogiri::HTML(html_content)
    scrapes = []

    # Look specifically for .provision elements
    provision_element = doc.at_css(".provision")

    if provision_element
      scrape_data = extract_scrape_data(provision_element, base_url, regulation_title)
      if scrape_data
        scrapes << scrape_data
        Rails.logger.info "Found .provision content (#{scrape_data[:raw_html].length} chars)"
      else
        Rails.logger.warn "Found .provision element but could not extract scrape data"
      end
    else
      Rails.logger.warn "No .provision element found on page: #{base_url}"
    end

    scrapes
  end

  def extract_scrape_data(element, base_url, regulation_title = nil)
    # Use the source's configured URL, not content links
    # This ensures each source scrapes its intended URL

    # Extract content from the provision element and its children
    raw_html = element.to_html
    plain_text = extract_plain_text(element)

    {
      url: base_url,  # Use source's configured URL
      raw_html: raw_html,
      plain_text: plain_text,
      title: regulation_title
    }
  end

  def extract_regulation_title(html_content)
    begin
      doc = Nokogiri::HTML(html_content)
      title_element = doc.at_css("title")

      if title_element
        title_text = title_element.text.strip
        # Remove the trailing site name if present
        title_text = title_text.gsub(/, föreskrifter - Arbetsmiljöverket$/, "")
        # Decode HTML entities
        title_text = CGI.unescapeHTML(title_text)

        # Validate that it looks like a proper regulation title
        if title_text.match?(/AFS\s+\d{4}:\d+/)
          return title_text
        end
      end

      Rails.logger.warn "Could not extract regulation title from page"
      nil
    rescue => e
      Rails.logger.warn "Error extracting regulation title: #{e.message}"
      nil
    end
  end

  def extract_plain_text(element)
    # Remove script and style elements
    element = element.dup
    element.css("script, style, nav, footer, aside, .sidebar").remove

    # Get all text nodes and join with space
    text = element.xpath(".//text()").map(&:text).join(" ")

    # Normalize whitespace
    text.squish
  end


  def store_scrapes(scrapes_data)
    scrapes_data.each do |scrape_data|
      begin
        # Check if current scrape already exists for this URL + source
        existing_scrape = Scrape.find_by(url: scrape_data[:url], source: @source, current: true)

        if existing_scrape
          # Check if content has changed
          if content_changed?(existing_scrape, scrape_data)
            # Mark current scrape as historical
            existing_scrape.supersede!
            Rails.logger.info "Superseded scrape version #{existing_scrape.version} for URL: #{existing_scrape.url}"

            # Create new version
            new_version = Scrape.create!(
              url: scrape_data[:url],
              raw_html: scrape_data[:raw_html],
              plain_text: scrape_data[:plain_text],
              title: scrape_data[:title],
              source: @source,
              fetched_at: Time.current,
              version: existing_scrape.next_version_number,
              current: true
            )
            Rails.logger.info "Created new scrape version #{new_version.version} for URL: #{new_version.url}"
          else
            Rails.logger.debug "Scrape unchanged for URL: #{scrape_data[:url]}"
          end
        else
          # Create first version of scrape
          new_scrape = Scrape.create!(
            url: scrape_data[:url],
            raw_html: scrape_data[:raw_html],
            plain_text: scrape_data[:plain_text],
            title: scrape_data[:title],
            source: @source,
            fetched_at: Time.current,
            version: 1,
            current: true
          )
          Rails.logger.info "Created new scrape ID #{new_scrape.id} for URL: #{new_scrape.url}"
        end
      rescue ActiveRecord::RecordInvalid => e
        Rails.logger.warn "Failed to save scrape for URL '#{scrape_data[:url]}': #{e.message}"
      end
    end
  end

  def content_changed?(existing_scrape, new_data)
    existing_scrape.raw_html != new_data[:raw_html]
  end
end
