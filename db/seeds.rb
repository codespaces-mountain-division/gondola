# This file should contain all the record creation needed to seed the database with its default values.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).

# Create sample posts
Post.create!([
  {
    title: "Welcome to Our Blog",
    content: "This is our first blog post! We're excited to share our thoughts and ideas with you. 

This platform allows authors to write, edit, and publish posts with a simple and clean interface. You can create drafts and publish them when ready.

Stay tuned for more exciting content!",
    author: "Admin",
    published_at: 1.day.ago,
    labels: ["welcome", "announcement", "blog"]
  },
  {
    title: "Getting Started with Rails",
    content: "Ruby on Rails is a powerful web application framework that follows the convention over configuration principle.

Here are some key benefits of Rails:
- Rapid development
- Clean and readable code
- Strong community support
- Extensive library ecosystem

Whether you're building a simple blog or a complex web application, Rails provides the tools you need to get started quickly.",
    author: "Developer",
    published_at: 2.hours.ago,
    labels: ["rails", "tutorial", "programming", "web-development"]
  },
  {
    title: "Draft Post Example",
    content: "This is an example of a draft post. It hasn't been published yet, so it won't be visible to regular visitors.

Draft posts are useful for:
- Working on content over time
- Getting feedback before publishing
- Scheduling future content

You can easily publish this post when you're ready!",
    author: "Content Writer",
    labels: ["draft", "example"]
    # Note: no published_at date, so this remains a draft
  }
])

puts "Created #{Post.count} posts"
