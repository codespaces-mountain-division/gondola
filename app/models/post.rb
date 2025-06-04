class Post < ApplicationRecord
  validates :title, presence: true, length: { maximum: 255 }
  validates :content, presence: true
  validates :author, presence: true

  scope :published, -> { where.not(published_at: nil) }
  scope :recent, -> { order(created_at: :desc) }

  def published?
    published_at.present?
  end

  def publish!
    update(published_at: Time.current)
  end

  def unpublish!
    update(published_at: nil)
  end
end
