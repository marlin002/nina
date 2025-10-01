class Source < ApplicationRecord
  has_many :articles, dependent: :destroy

  validates :url, presence: true, uniqueness: true, format: { with: URI::DEFAULT_PARSER.make_regexp }
  
  # Store settings as JSON
  serialize :settings, coder: JSON
  
  # Provide default settings
  after_initialize :set_default_settings, if: :new_record?
  
  scope :active, -> { where(active: true) }
  
  def display_name
    url
  end
  
  # Get the domain from the URL
  def domain
    URI.parse(url).host
  rescue URI::InvalidURIError
    nil
  end
  
  # Enqueue a scraping job for this source
  def scrape!
    SourceScraperJob.perform_later(id)
  end
  
  # Enqueue a scraping job to run immediately
  def scrape_now!
    SourceScraperJob.perform_now(id)
  end
  
  private
  
  def set_default_settings
    self.settings ||= {
      enabled: true,
      scrape_frequency: 'daily',
      user_agent: 'Nina Swedish Content Scraper 1.0',
      timeout: 30,
      language: 'sv-SE'
    }
  end
end