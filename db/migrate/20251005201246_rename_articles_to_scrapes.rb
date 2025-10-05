class RenameArticlesToScrapes < ActiveRecord::Migration[7.2]
  def change
    rename_table :articles, :scrapes
  end
end
