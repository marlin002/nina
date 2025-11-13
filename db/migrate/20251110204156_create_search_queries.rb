class CreateSearchQueries < ActiveRecord::Migration[7.2]
  def change
    create_table :search_queries do |t|
      t.string :query, null: false
      t.integer :match_count, null: false, default: 0

      t.timestamps
    end

    add_index :search_queries, :query
    add_index :search_queries, :created_at
  end
end
