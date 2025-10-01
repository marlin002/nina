class Article < ApplicationRecord
  belongs_to :source

  validates :url, presence: true, format: { with: URI::DEFAULT_PARSER.make_regexp }
  validates :title, presence: true
  
  scope :recent, -> { order(fetched_at: :desc) }
  scope :by_source, ->(source) { where(source: source) }
  scope :today, -> { where(fetched_at: Date.current.all_day) }
  
  before_validation :set_fetched_at, if: -> { fetched_at.nil? }
  
  def display_title
    title.present? ? title.truncate(80) : url
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
  
  # Check if article content needs to be refreshed
  def stale?(hours = 24)
    fetched_at < hours.hours.ago
  end
  
  private
  
  def set_fetched_at
    self.fetched_at = Time.current
  end
end