class SearchQuery < ApplicationRecord
  validates :query, presence: true
  before_validation :normalize_query
  validates :match_count, presence: true, numericality: { only_integer: true, greater_than: 0 }

  # Limit searches to last 30 days.
  scope :recent, -> {
    where(created_at: 30.days.ago..)
      .group(:query)
      .select("query, MAX(created_at) as created_at, MAX(match_count) as match_count")
      .order("created_at DESC")
      .limit(20)
  }
  scope :popular, -> {
    where(created_at: 30.days.ago..)
      .group(:query)
      .select("query, COUNT(*) as search_count, MAX(match_count) as match_count, MAX(created_at) as last_searched")
      .order("search_count DESC, last_searched DESC")
      .limit(20)
  }

  def self.log_search(query, match_count)
    return if query.blank? || match_count.to_i <= 0

    begin
      create!(query: query, match_count: match_count)
    rescue ActiveRecord::RecordInvalid => e
      Rails.logger.warn("Failed to log search query: #{e.message}")
    end
  end

  def normalize_query
    self.query = QuerySanitizer.clean(query).to_s
  end
end
