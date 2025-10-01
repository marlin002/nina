# SourceScraperJob Documentation

The `SourceScraperJob` is a background job that fetches content from web sources, parses it, and stores it as articles in the database.

## Overview

- **Queue**: `scraping`
- **Retry Policy**: Up to 3 attempts with polynomial backoff
- **Error Handling**: Discards certain unrecoverable errors (401, 403, 429, invalid URLs)

## Features

### HTTP Fetching
- Uses Faraday HTTP client
- Configurable timeout and user agent from source settings
- Proper headers for web scraping (optimized for Swedish content)
- Accept-Language: sv-SE,sv;q=0.9,en-US;q=0.8,en;q=0.5
- UTF-8 charset specification
- Handles compressed responses
- Raises errors for failed HTTP requests

### HTML Parsing
- Uses Nokogiri for HTML parsing
- Attempts to find articles using common CSS selectors (in priority order):
  - `.paragraph` elements (primary selector for AV.se and government sites)
  - `article` elements
  - `.post`, `.entry`, `.article` classes
  - Swedish-specific selectors: `.nyhet`, `.artikel`, `.news-item`
  - Elements with "post", "article", "entry", "news", "nyhet", "artikel", or "paragraph" in class names
  - RSS/XML `item` elements
- Falls back to treating entire page as single article if no articles found
- Handles Swedish characters (å, ä, ö) correctly in UTF-8

### Content Extraction
- **Title**: Extracts from `h1`, `h2`, `h3`, `.title`, or similar elements
- **URL**: Resolves relative URLs to absolute URLs
- **Content Filtering**: Prioritizes `.provision` div content when present (for regulatory/legal documents)
  - If `.provision` div exists within article: extracts only that content and its children
  - If no `.provision` div: extracts full article content
- **Raw HTML**: Stores the filtered HTML content
- **Plain Text**: Cleaned text with scripts/styles removed and whitespace normalized

### Article Storage
- Creates new Article records for new content
- Updates existing articles if content has changed
- Prevents duplicates based on URL and source
- Sets `fetched_at` timestamp automatically
- Handles validation errors gracefully

## Usage

### Direct Job Execution
```ruby
# Run immediately (synchronous)
SourceScraperJob.perform_now(source_id)

# Enqueue for background processing
SourceScraperJob.perform_later(source_id)
```

### Using Source Model Methods
```ruby
source = Source.find(1)

# Enqueue for background processing
source.scrape!

# Run immediately (for testing)
source.scrape_now!
```

### Configuration via Source Settings
```ruby
source = Source.create!(
  url: "https://www.av.se/arbetsmiljoarbete-och-inspektioner/publikationer/foreskrifter/afs-20231/",
  settings: {
    timeout: 30,           # HTTP timeout in seconds
    user_agent: "Nina Swedish Content Scraper 1.0", # Custom user agent
    enabled: true,         # Whether source is active
    language: "sv-SE"      # Language preference for content
  }
)
```

## Example Output

The job processes a source and creates articles like this:

```ruby
# Input: https://example.com/blog
# Output: 
source.articles.each do |article|
  puts "Title: #{article.title}"
  puts "URL: #{article.url}"
  puts "Word Count: #{article.word_count}"
  puts "Content: #{article.content_summary}"
end
```

## Error Handling

### Retried Errors
- Network timeouts
- Connection errors
- 5xx HTTP errors
- Temporary DNS failures

### Discarded Errors (Not Retried)
- 401 Unauthorized
- 403 Forbidden
- 429 Too Many Requests
- Invalid URLs
- Source not found

### Logging
- Start/completion messages at INFO level
- Individual article creation/updates at INFO level
- Validation warnings at WARN level
- Full errors with backtrace at ERROR level

## Monitoring

Check job status in Rails console:
```ruby
# Total jobs in queue
GoodJob::Job.where(job_class: 'SourceScraperJob').count

# Recent job executions
GoodJob::Execution.where(job_class: 'SourceScraperJob').recent.limit(10)

# Failed jobs
GoodJob::Job.where(job_class: 'SourceScraperJob', finished_at: nil)
           .where.not(error: nil)
```

## Performance Considerations

- Jobs run in the `:scraping` queue
- Timeout configured per source (default 30s)
- Memory usage scales with HTML content size
- Uses database transactions for article storage
- Handles duplicate detection efficiently with database queries

## Testing

The job includes comprehensive error handling and can be tested with mock HTML content:

```ruby
# Test parsing logic
scraper = SourceScraperJob.new
articles = scraper.send(:parse_content, html_string, base_url)

# Test with real source
source = Source.create!(url: "https://httpbin.org/html")
SourceScraperJob.perform_now(source.id)
```