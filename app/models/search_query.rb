class SearchQuery < ApplicationRecord
  validates :query, presence: true
  validates :match_count, presence: true, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  # Limit searches to last year
  scope :recent_year, -> { where(created_at: 1.year.ago..) }
  scope :recent, -> { recent_year.order(created_at: :desc).limit(20) }
  scope :popular, -> { recent_year.group(:query).select("search_queries.query, COUNT(*) as search_count, MAX(search_queries.match_count) as match_count, MAX(search_queries.created_at) as last_searched").order("search_count DESC, last_searched DESC").limit(20) }

  def self.log_search(query, match_count)
    cleaned = QuerySanitizer.clean(query)
    return if cleaned.blank? || match_count.to_i <= 0

    create!(query: cleaned, match_count: match_count)
  end

  def time_ago
    time_diff = Time.current - created_at
    case time_diff
    when 0...60
      "just now"
    when 60...3600
      "#{(time_diff / 60).to_i} min ago"
    when 3600...86400
      "#{(time_diff / 3600).to_i} h ago"
    when 86400...604800
      "#{(time_diff / 86400).to_i} d ago"
    else
      "#{(time_diff / 604800).to_i} w ago"
    end
  end
end
