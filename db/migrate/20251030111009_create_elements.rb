class CreateElements < ActiveRecord::Migration[7.2]
  def change
    create_table :elements do |t|
      # Foreign key
      t.bigint :scrape_id, null: false

      # Element identification
      t.string :tag_name, null: false
      t.string :element_class
      t.string :element_id
      
      # Content
      t.text :text_content
      t.text :html_snippet, null: false
      
      # Hierarchy information
      t.string :regulation
      t.integer :chapter
      t.integer :section
      t.string :appendix
      t.boolean :is_transitional, default: false, null: false
      t.boolean :is_general_recommendation, default: false, null: false
      
      # Path information for reconstruction
      t.text :css_path
      t.integer :position_in_parent
      
      # Versioning (align with scrape versioning)
      t.integer :version, default: 1, null: false
      t.boolean :current, default: true, null: false
      t.datetime :superseded_at, precision: nil

      t.timestamps
    end

    add_index :elements, :scrape_id
    add_index :elements, [:scrape_id, :current]
    add_index :elements, [:scrape_id, :version]
    add_index :elements, [:tag_name]
    add_index :elements, [:regulation]
    add_index :elements, [:chapter]
    add_index :elements, [:section]
    add_index :elements, [:appendix]
    add_index :elements, [:is_transitional]
    add_index :elements, [:is_general_recommendation]

    add_foreign_key :elements, :scrapes
  end
end
