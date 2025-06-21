class Post < ApplicationRecord
  validates :title, presence: true, length: { maximum: 255 }
  validates :content, presence: true
  validates :author, presence: true

  # Serialize labels as JSON array
  serialize :labels, coder: JSON

  scope :published, -> { where.not(published_at: nil) }
  scope :recent, -> { order(created_at: :desc) }

  # Initialize labels as empty array if nil
  after_initialize :set_default_labels

  def published?
    published_at.present?
  end

  def publish!
    update(published_at: Time.current)
  end

  def unpublish!
    update(published_at: nil)
  end

  def add_label(label)
    self.labels = (labels || []) << label.strip unless label.blank? || labels&.include?(label.strip)
  end

  def remove_label(label)
    self.labels = (labels || []).reject { |l| l == label.strip }
  end

  private

  def set_default_labels
    self.labels ||= []
  end
end
