# db/migrate/20261025180000_add_access_jti_to_refresh_tokens.rb
#
# Links each refresh token to the access token issued with it, so
# DELETE /api/logout can sign out one device instead of all of them.
class AddAccessJtiToRefreshTokens < ActiveRecord::Migration[7.2]
  def change
    add_column :refresh_tokens, :access_jti, :string
    add_index :refresh_tokens, :access_jti
  end
end
