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
end
