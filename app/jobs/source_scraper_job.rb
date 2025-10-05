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
    
    # Fetch the HTML content
    html_content = fetch_content(@source.url)
    
    # Parse the HTML and extract scrapes
    scrapes_data = parse_content(html_content, @source.url)
    
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
      config.options.timeout = settings.fetch('timeout', 30).to_i
      config.options.open_timeout = 10
    end
    
    headers = {
      'User-Agent' => settings.fetch('user_agent', 'Nina Swedish Content Scraper 1.0'),
      'Accept' => 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
      'Accept-Language' => 'sv-SE,sv;q=0.9,en-US;q=0.8,en;q=0.5',
      'Accept-Charset' => 'UTF-8,*;q=0.5',
      'Cache-Control' => 'no-cache'
    }
    
    response = connection.get(url, nil, headers)
    
    unless response.success?
      raise "HTTP Error: #{response.status} - #{response.reason_phrase}"
    end
    
    response.body
  end
  
  def parse_content(html_content, base_url)
    doc = Nokogiri::HTML(html_content)
    scrapes = []
    
    # Look specifically for .provision elements
    provision_element = doc.at_css('.provision')
    
    if provision_element
      scrape_data = extract_scrape_data(provision_element, base_url)
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
  
  def extract_scrape_data(element, base_url)
    # Extract content URL (prefer links within the element, fallback to base_url)
    content_url = extract_content_url(element, base_url)
    
    # Extract content from the provision element and its children
    raw_html = element.to_html
    plain_text = extract_plain_text(element)
    
    {
      url: content_url,
      raw_html: raw_html,
      plain_text: plain_text.strip
    }
  end
  
  def extract_content_url(element, base_url)
    # Look for links within the content
    link = element.at_css('a[href]')
    if link
      href = link['href']
      return resolve_url(href, base_url) if href.present?
    end
    
    # Fallback to base URL
    base_url
  end
  
  def extract_plain_text(element)
    # Remove script and style elements
    element = element.dup
    element.css('script, style, nav, footer, aside, .sidebar').remove
    
    # Extract text and clean it up
    text = element.text
    
    # Normalize whitespace
    text.gsub(/\s+/, ' ').strip
  end
  
  def resolve_url(url, base_url)
    return url if url =~ /^https?:\/\//
    
    base_uri = URI.parse(base_url)
    
    if url.start_with?('/')
      # Absolute path
      "#{base_uri.scheme}://#{base_uri.host}#{url}"
    else
      # Relative path
      base_path = File.dirname(base_uri.path)
      base_path = '/' if base_path == '.'
      "#{base_uri.scheme}://#{base_uri.host}#{base_path}/#{url}"
    end
  rescue URI::InvalidURIError
    base_url
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
    existing_scrape.raw_html != new_data[:raw_html] ||
      existing_scrape.plain_text != new_data[:plain_text]
  end
end
