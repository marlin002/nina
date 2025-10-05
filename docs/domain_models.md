# Domain Models for Content Scraping

This document describes the domain models for scraped content in the Nina application.

## Models Overview

### Source Model

Represents a content source to be scraped (URL + settings).

**Fields:**
- `url`: The URL to scrape (required, unique)
- `settings`: JSON field for scraping configuration
- `created_at`, `updated_at`: Timestamps

**Example:**
```ruby
source = Source.create!(
  url: "https://example.com/feed.xml",
  settings: {
    enabled: true,
    scrape_frequency: "daily",
    user_agent: "Nina Scraper 1.0",
    timeout: 30
  }
)
```

**Methods:**
- `domain`: Returns the domain from the URL
- `display_name`: Returns a human-readable name (currently the URL)

### Scrape Model

Represents scraped `.provision` content with metadata from web scraping. Each scrape contains the complete provision element and its children from legal/regulatory documents.

**Fields:**
- `url`: Scraped content URL (required)
- `raw_html`: Original HTML content
- `plain_text`: Extracted text content
- `fetched_at`: When the content was fetched (auto-set)
- `source_id`: Foreign key to Source
- `created_at`, `updated_at`: Timestamps

**Example:**
```ruby
scrape = Scrape.create!(
  url: "https://example.com/content/1",
  raw_html: "<h1>Title</h1><p>Content...</p>",
  plain_text: "Title\n\nContent...",
  source: source
)
```

**Methods:**
- `display_name`: Display name with ID and URL
- `content_summary(limit)`: Summary of content
- `has_content?`: Check if scrape has content
- `word_count`: Number of words in plain text
- `reading_time_minutes`: Estimated reading time
- `stale?(hours)`: Check if content needs refresh

**Scopes:**
- `recent`: Order by fetched_at descending
- `by_source(source)`: Filter by source
- `today`: Scrapes fetched today

## Usage Examples

### Creating a Source and Scrapes

```ruby
# Create a source
source = Source.create!(url: "https://news.example.com/feed")

# Create scrapes from scraping
scrape = Scrape.create!(
  url: "https://news.example.com/breaking-news",
  raw_html: scraped_html,
  plain_text: extracted_text,
  source: source
)

# Access relationships
puts "Source has #{source.scrapes.count} scrapes"
puts "Scrape from #{scrape.source.domain}"
```

### Querying

```ruby
# Get recent scrapes
recent_scrapes = Scrape.recent.limit(10)

# Get scrapes from a specific source
source_scrapes = Scrape.by_source(source)

# Get scrapes that need refreshing
stale_scrapes = Scrape.all.select(&:stale?)

# Get reading statistics
total_words = Scrape.sum(&:word_count)
avg_reading_time = Scrape.average(:reading_time_minutes)
```

## Database Schema

The models create the following tables:

- `sources`: URL, settings (JSON), timestamps, unique index on URL
- `scrapes`: URL, HTML/text content, fetched_at, source FK, indexes on URL and fetched_at

Foreign key constraint ensures referential integrity between scrapes and sources.
