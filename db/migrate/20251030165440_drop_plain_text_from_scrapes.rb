class DropPlainTextFromScrapes < ActiveRecord::Migration[7.2]
  def change
    remove_column :scrapes, :plain_text, :text
  end
end
