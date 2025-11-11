class RemoveUniquenessFromSearchQueries < ActiveRecord::Migration[7.2]
  def change
    remove_index :search_queries, :query
  end
end
