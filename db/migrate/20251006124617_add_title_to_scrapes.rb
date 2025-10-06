class AddTitleToScrapes < ActiveRecord::Migration[7.2]
  def change
    add_column :scrapes, :title, :text
  end
end
