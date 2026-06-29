class AddFrenchTranslationsToPlan < ActiveRecord::Migration[7.2]
  def change
    add_column :plans, :name_fr, :string
    add_column :plans, :description_fr, :text
  end
end
