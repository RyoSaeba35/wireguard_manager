# db/migrate/[timestamp]_create_settings.rb
class CreateSettings < ActiveRecord::Migration[6.1]
  def change
    create_table :settings do |t|
      t.string :key, null: false, unique: true
      t.string :value
      t.timestamps
    end
  end
end
