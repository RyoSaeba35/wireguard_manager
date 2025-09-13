class AddFailedAttemptsToUsers < ActiveRecord::Migration[7.2]
  def change
    add_column :users, :failed_attempts, :integer
  end
end
