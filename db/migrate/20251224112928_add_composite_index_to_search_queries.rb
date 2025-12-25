class AddCompositeIndexToSearchQueries < ActiveRecord::Migration[7.2]
  def change
    # 1. Add the new high-performance index for your scopes
    add_index :search_queries, [ :created_at, :query ]

    # 2. Remove the old index because it is now redundant.
    #    (The new index handles searches for 'created_at' just fine on its own)
    remove_index :search_queries, name: "index_search_queries_on_created_at"
  end
end
