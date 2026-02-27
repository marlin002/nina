class HomeController < ApplicationController
  before_action :set_noindex

  def index
    @recent_searches = SearchQuery.recent
    @popular_searches = SearchQuery.popular
  end

  private

  def set_noindex
    if ENV["ALLOW_INDEXING"] == "true"
      response.headers["X-Robots-Tag"] = "index, follow"
    else
      response.headers["X-Robots-Tag"] = "noindex, nofollow"
    end
  end
end
