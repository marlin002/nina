class ScrapesController < ApplicationController
  before_action :set_scrape, only: [:show]

  def index
    @scrapes = Scrape.joins(:source)
                    .includes(:source)
                    .order('sources.url')
    
    @stats = {
      total_scrapes: @scrapes.count,
      total_html_size: @scrapes.sum { |s| s.raw_html&.length || 0 },
      total_text_size: @scrapes.sum { |s| s.plain_text&.length || 0 },
      last_updated: @scrapes.maximum(:fetched_at)
    }
  end

  def show
    # @scrape is set by before_action
  end

  def raw
    @scrape = Scrape.find(params[:id])
    render html: @scrape.raw_html.html_safe, layout: 'raw_content'
  rescue ActiveRecord::RecordNotFound
    redirect_to scrapes_path, alert: 'Scrape not found'
  end

  private

  def set_scrape
    @scrape = Scrape.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    redirect_to scrapes_path, alert: 'Scrape not found'
  end
end