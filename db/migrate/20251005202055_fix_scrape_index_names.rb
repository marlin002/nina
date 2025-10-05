class FixScrapeIndexNames < ActiveRecord::Migration[7.2]
  def change
    rename_index :scrapes, :index_articles_on_url_source_current, :index_scrapes_on_url_source_current
    rename_index :scrapes, :index_articles_on_url_source_version, :index_scrapes_on_url_source_version
  end
end
