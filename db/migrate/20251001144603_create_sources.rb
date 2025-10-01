class CreateSources < ActiveRecord::Migration[7.2]
  def change
    create_table :sources do |t|
      t.string :url, null: false
      t.text :settings

      t.timestamps
    end
    
    add_index :sources, :url, unique: true
  end
end
