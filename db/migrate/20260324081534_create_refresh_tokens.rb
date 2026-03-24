# db/migrate/XXXXXX_create_refresh_tokens.rb
class CreateRefreshTokens < ActiveRecord::Migration[7.2]
  def change
    create_table :refresh_tokens do |t|
      t.string :jti, null: false
      t.integer :user_id, null: false
      t.datetime :exp, null: false

      t.timestamps
    end

    add_index :refresh_tokens, :jti, unique: true
    add_index :refresh_tokens, :exp
    add_index :refresh_tokens, :user_id
    add_foreign_key :refresh_tokens, :users
  end
end
