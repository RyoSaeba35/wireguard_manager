class EncryptClashApiSecret < ActiveRecord::Migration[7.2]
  def up
    Server.find_each(&:save!)
  end

  def down
    # Cannot reverse encryption
  end
end
