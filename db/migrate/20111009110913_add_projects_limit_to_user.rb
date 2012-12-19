class AddProjectsLimitToUser < ActiveRecord::Migration
  def change
    add_column :users, :projects_limit, :integer, :default => 1
  end
end
