class AddLabelsToPosts < ActiveRecord::Migration[7.1]
  def change
    add_column :posts, :labels, :text, default: '[]'
  end
end
