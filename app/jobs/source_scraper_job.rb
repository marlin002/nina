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
    
    # Parse the HTML and extract articles
    articles_data = parse_content(html_content, @source.url)
    
    # Store the articles
    store_articles(articles_data)
    
    Rails.logger.info "Completed scrape for source: #{@source.url}. Found #{articles_data.length} articles."
    
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
      'Accept-Encoding' => 'gzip, deflate',
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
    articles = []
    
    # Try to find articles using common patterns (including Swedish sites)
    article_selectors = [
      '.paragraph',  # Primary selector for AV.se and similar sites
      'article',
      '.post', '.entry', '.article',
      '[class*="post"]', '[class*="article"]', '[class*="entry"]',
      '.news-item', '.nyhet', '.artikel',  # Swedish news patterns
      '[class*="news"]', '[class*="nyhet"]', '[class*="artikel"]',
      '[class*="paragraph"]',
      'item', '.item'
    ]
    
    found_articles = false
    
    article_selectors.each do |selector|
      elements = doc.css(selector)
      next if elements.empty?
      
      elements.each do |element|
        article_data = extract_article_data(element, base_url)
        if article_data && article_data[:title].present?
          articles << article_data
          found_articles = true
        end
      end
      
      break if found_articles && articles.any?
    end
    
    # If no articles found with selectors, treat the whole page as one article
    if articles.empty?
      article_data = extract_article_data(doc, base_url)
      articles << article_data if article_data && article_data[:title].present?
    end
    
    articles
  end
  
  def extract_article_data(element, base_url)
    # Extract title
    title = extract_title(element)
    return nil if title.blank?
    
    # Extract article URL (prefer links within the element, fallback to base_url)
    article_url = extract_article_url(element, base_url)
    
    # Extract content - focus on .provision if it exists, otherwise use full element
    content_element = extract_provision_content(element)
    raw_html = content_element.to_html
    plain_text = extract_plain_text(content_element)
    
    {
      title: title.strip,
      url: article_url,
      raw_html: raw_html,
      plain_text: plain_text.strip
    }
  end
  
  def extract_title(element)
    # Try different title selectors in order of preference
    title_selectors = ['h1', 'h2', 'h3', '.title', '[class*="title"]', 'title']
    
    title_selectors.each do |selector|
      title_element = element.at_css(selector)
      if title_element && title_element.text.present?
        return title_element.text.strip
      end
    end
    
    # Fallback: use first text content if it looks like a title
    first_text = element.text.strip.split("\n").first
    return first_text if first_text && first_text.length < 200
    
    nil
  end
  
  def extract_article_url(element, base_url)
    # Look for links within the article
    link = element.at_css('a[href]')
    if link
      href = link['href']
      return resolve_url(href, base_url) if href.present?
    end
    
    # Fallback to base URL
    base_url
  end
  
  def extract_provision_content(element)
    # Look for .provision div within the element
    provision = element.at_css('.provision')
    
    if provision
      Rails.logger.debug "Found .provision content, using it instead of full element"
      return provision
    else
      Rails.logger.debug "No .provision found, using full element"
      return element
    end
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
  
  def store_articles(articles_data)
    articles_data.each do |article_data|
      begin
        # Check if article already exists
        existing_article = Article.find_by(url: article_data[:url], source: @source)
        
        if existing_article
          # Update existing article if content has changed
          if content_changed?(existing_article, article_data)
            existing_article.update!(
              title: article_data[:title],
              raw_html: article_data[:raw_html],
              plain_text: article_data[:plain_text],
              fetched_at: Time.current
            )
            Rails.logger.info "Updated article: #{article_data[:title]}"
          else
            Rails.logger.debug "Article unchanged: #{article_data[:title]}"
          end
        else
          # Create new article
          Article.create!(
            title: article_data[:title],
            url: article_data[:url],
            raw_html: article_data[:raw_html],
            plain_text: article_data[:plain_text],
            source: @source,
            fetched_at: Time.current
          )
          Rails.logger.info "Created new article: #{article_data[:title]}"
        end
      rescue ActiveRecord::RecordInvalid => e
        Rails.logger.warn "Failed to save article '#{article_data[:title]}': #{e.message}"
      end
    end
  end
  
  def content_changed?(existing_article, new_data)
    existing_article.title != new_data[:title] ||
      existing_article.raw_html != new_data[:raw_html] ||
      existing_article.plain_text != new_data[:plain_text]
  end
end
