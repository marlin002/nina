class Source < ApplicationRecord
  has_many :scrapes, dependent: :destroy

  validates :url, presence: true, format: { with: URI::DEFAULT_PARSER.make_regexp }
  validates :version, presence: true, numericality: { greater_than: 0 }

  # Custom uniqueness validation for current sources only
  validates :url, uniqueness: { scope: :current, conditions: -> { where(current: true) } }

  # Versioning scopes
  scope :current, -> { where(current: true) }
  scope :historical, -> { where(current: false) }
  scope :versions, -> { order(:version) }
  scope :for_url, ->(url) { where(url: url) }

  # Default scope: only show current sources
  default_scope { current }

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

  # Versioning methods
  def supersede!
    update!(current: false, superseded_at: Time.current)
  end

  def next_version_number
    max_version = Source.unscoped.where(url: url).maximum(:version) || 0
    max_version + 1
  end

  def all_versions
    Source.unscoped.where(url: url).versions
  end

  def previous_version
    Source.unscoped.where(url: url, version: version - 1).first
  end

  def next_version
    Source.unscoped.where(url: url, version: version + 1).first
  end

  def current_version?
    current
  end

  private

  def set_default_settings
    self.settings ||= {
      enabled: true,
      scrape_frequency: "daily",
      user_agent: "iAFS Swedish Content Scraper 1.0",
      timeout: 30,
      language: "sv-SE"
    }
  end
end
