class ScrapesController < ApplicationController
  def index
    scrapes_unsorted = Scrape.joins(:source).includes(:source)
    
    # Sort by regulation number numerically (AFS 2023:1, 2023:2, etc.)
    @scrapes = scrapes_unsorted.sort_by do |scrape|
      regulation_number(scrape.source.url)
    end
    
    @stats = {
      total_scrapes: scrapes_unsorted.count,
      total_html_size: scrapes_unsorted.sum { |s| s.raw_html&.length || 0 },
      total_text_size: scrapes_unsorted.sum { |s| s.plain_text&.length || 0 },
      last_updated: scrapes_unsorted.maximum(:fetched_at)
    }
  end

  def raw
    @scrape = Scrape.find(params[:id])
    render html: @scrape.raw_html.html_safe, layout: 'raw_content'
  rescue ActiveRecord::RecordNotFound
    redirect_to scrapes_path, alert: 'Scrape not found'
  end

  private
  
  # Extract numeric regulation number from URL for proper sorting
  # e.g. "https://...afs-20231/" -> 1, "...afs-202310/" -> 10
  def regulation_number(url)
    match = url.match(/afs-2023(\d+)/)
    match ? match[1].to_i : 999 # Default to high number if no match
  end
end