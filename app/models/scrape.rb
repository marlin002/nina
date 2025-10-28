class Scrape < ApplicationRecord
  belongs_to :source

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

  def display_name
    "Scrape #{id} - #{url}"
  end

  def content_summary(limit = 200)
    return "No content" if plain_text.blank?

    plain_text.strip.truncate(limit)
  end

  def has_content?
    raw_html.present? || plain_text.present?
  end

  def word_count
    return 0 if plain_text.blank?

    plain_text.split.count
  end

  def reading_time_minutes
    # Average reading speed: 200 words per minute
    (word_count / 200.0).ceil
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
end
