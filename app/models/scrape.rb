class Scrape < ApplicationRecord
  belongs_to :source
  has_many :elements, dependent: :destroy

  validates :source, presence: true
  validates :url, presence: true, url: true
  validates :version, presence: true, numericality: { only_integer: true, greater_than: 0 }

  # Versioning scopes
  scope :current, -> { where(current: true) }
  scope :historical, -> { where(current: false) }
  scope :versions, -> { order(:version) }
  scope :for_url, ->(url) { where(url: url) }

  # Default scope: only show current scrapes
  default_scope { current }

  # Original scopes (now apply to current scrapes only by default)
  scope :recent, -> { order(fetched_at: :desc) }
  scope :by_source, ->(source) { where(source: source) }
  scope :today, -> { where(fetched_at: Date.current.all_day) }

  before_save :set_fetched_at
  after_save :enqueue_element_parsing, if: :should_parse_elements?

  def display_name
    "Scrape #{id} - #{url}"
  end

  def content_summary(limit = 200)
    return "No content" if elements.blank?

    text = elements.limit(5).map(&:text_content).compact.join(" ").strip
    text.blank? ? "No content" : text.truncate(limit)
  end

  def has_content?
    raw_html.present? || elements.exists?
  end

  def domain
    source&.domain
  end

  # Check if scrape content needs to be refreshed
  def stale?(hours = 24)
    fetched_at < hours.hours.ago
  end

  # Versioning methods
  def supersede!
    update!(current: false, superseded_at: Time.current)
  end

  def next_version_number
    max_version = Scrape.unscoped.where(url: url, source: source).maximum(:version) || 0
    max_version + 1
  end

  def all_versions
    Scrape.unscoped.where(url: url, source: source).versions
  end

  def previous_version
    Scrape.unscoped.where(url: url, source: source, version: version - 1).first
  end

  def next_version
    Scrape.unscoped.where(url: url, source: source, version: version + 1).first
  end

  def current_version?
    current
  end

  private

  def set_fetched_at
    self.fetched_at ||= Time.current
  end

  def should_parse_elements?
    # Parse elements if:
    # 1. This is a new scrape (just created)
    # 2. The raw HTML has changed
    # 3. The scrape was marked as current
    new_record? || raw_html_changed? || current_changed?
  end

  def enqueue_element_parsing
    ParseScrapeElementsJob.perform_later(id)
  end
end
