class AddVersioningToSources < ActiveRecord::Migration[7.2]
  def change
    add_column :sources, :current, :boolean, default: true, null: false
    add_column :sources, :version, :integer, default: 1, null: false
    add_column :sources, :superseded_at, :timestamp, null: true

    # Add indexes for performance
    add_index :sources, :current
    add_index :sources, [ :url, :version ], name: 'index_sources_on_url_version'
    add_index :sources, [ :url, :current ], name: 'index_sources_on_url_current'

    # Remove the old unique constraint on URL since we now allow multiple versions
    remove_index :sources, :url
    # Add new unique constraint on URL + current to ensure only one current version per URL
    add_index :sources, [ :url, :current ], unique: true, where: "current = true", name: 'index_sources_on_url_current_unique'
  end
end
