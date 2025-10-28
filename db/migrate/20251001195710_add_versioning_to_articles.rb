class AddVersioningToArticles < ActiveRecord::Migration[7.2]
  def change
    add_column :articles, :current, :boolean, default: true, null: false
    add_column :articles, :version, :integer, default: 1, null: false
    add_column :articles, :superseded_at, :timestamp, null: true

    # Add indexes for performance
    add_index :articles, :current
    add_index :articles, [ :url, :source_id, :version ], name: 'index_articles_on_url_source_version'
    add_index :articles, [ :url, :source_id, :current ], name: 'index_articles_on_url_source_current'
  end
end
