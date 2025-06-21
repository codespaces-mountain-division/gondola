require "test_helper"

class PostTest < ActiveSupport::TestCase
  test "should not save post without title" do
    post = Post.new(content: "Some content", author: "Test Author")
    assert_not post.save
  end

  test "should not save post without content" do
    post = Post.new(title: "Test Title", author: "Test Author")
    assert_not post.save
  end

  test "should not save post without author" do
    post = Post.new(title: "Test Title", content: "Some content")
    assert_not post.save
  end

  test "should save valid post" do
    post = Post.new(title: "Test Title", content: "Some content", author: "Test Author")
    assert post.save
  end

  test "should be unpublished by default" do
    post = Post.create(title: "Test Title", content: "Some content", author: "Test Author")
    assert_not post.published?
  end

  test "should be published after calling publish!" do
    post = Post.create(title: "Test Title", content: "Some content", author: "Test Author")
    post.publish!
    assert post.published?
    assert_not_nil post.published_at
  end

  test "should be unpublished after calling unpublish!" do
    post = Post.create(title: "Test Title", content: "Some content", author: "Test Author")
    post.publish!
    post.unpublish!
    assert_not post.published?
    assert_nil post.published_at
  end

  test "should initialize with empty labels array" do
    post = Post.new
    assert_equal [], post.labels
  end

  test "should serialize labels as JSON array" do
    post = Post.create!(title: "Test", content: "Content", author: "Author", labels: ["tech", "rails"])
    assert_equal ["tech", "rails"], post.labels

    # Reload from database to ensure serialization works
    post.reload
    assert_equal ["tech", "rails"], post.labels
  end

  test "should handle empty labels" do
    post = Post.create!(title: "Test", content: "Content", author: "Author", labels: [])
    assert_equal [], post.labels
  end

  test "should add labels" do
    post = Post.new(title: "Test", content: "Content", author: "Author")
    post.add_label("tech")
    post.add_label("rails")
    assert_equal ["tech", "rails"], post.labels
  end

  test "should not add duplicate labels" do
    post = Post.new(title: "Test", content: "Content", author: "Author")
    post.add_label("tech")
    post.add_label("tech")
    assert_equal ["tech"], post.labels
  end

  test "should remove labels" do
    post = Post.new(title: "Test", content: "Content", author: "Author", labels: ["tech", "rails", "tutorial"])
    post.remove_label("rails")
    assert_equal ["tech", "tutorial"], post.labels
  end

  test "should handle blank labels gracefully" do
    post = Post.new(title: "Test", content: "Content", author: "Author")
    post.add_label("")
    post.add_label("  ")
    post.add_label(nil)
    assert_equal [], post.labels
  end
end
