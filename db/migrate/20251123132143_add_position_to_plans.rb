class AddPositionToPlans < ActiveRecord::Migration[7.2]
  def change
    add_column :plans, :position, :integer
  end
end
