class CreateArticles < ActiveRecord::Migration[7.2]
  def change
    create_table :articles do |t|
      t.string :title
      t.string :url, null: false
      t.text :raw_html
      t.text :plain_text
      t.datetime :fetched_at
      t.references :source, null: false, foreign_key: true

      t.timestamps
    end

    add_index :articles, :url
    add_index :articles, :fetched_at
  end
end
