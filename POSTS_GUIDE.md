# Posts Feature Guide

This Rails application includes a complete blog post management system. This is only accessible to team members with the "Privateer" or "Pirate" roles in the role group; "Honest Sailors" can only comment on posts. Here's how it works:

## Overview

The posts feature allows users to create, edit, publish, and manage blog posts. It includes a full CRUD (Create, Read, Update, Delete) interface with publishing capabilities.

## Database Schema

The `posts` table includes the following fields:
- `id` - Primary key
- `title` - Post title (required, max 255 characters)
- `content` - Post content (required, text field)
- `author` - Author name (required)
- `published_at` - Publication timestamp (nullable)
- `created_at` - Record creation timestamp
- `updated_at` - Record last update timestamp

## Key Features

### 1. Post Creation
- Navigate to `/posts/new` or click "Write New Post"
- Fill in title, author, and content
- Posts are saved as drafts by default (no `published_at` date)

### 2. Post Management
- View all posts at `/posts`
- See both published posts and drafts
- Visual indicators show publication status

### 3. Publishing System
- Posts start as drafts when created
- Use "Publish" button to make posts live
- Use "Unpublish" button to revert to draft status
- Published posts show publication date

### 4. Post Editing
- Edit any post via the "Edit" button
- Updates preserve publication status
- Form validation prevents empty required fields

### 5. Post Deletion
- Delete posts with confirmation dialog
- Permanent deletion (no soft delete implemented)

## Model Features

### Validations
```ruby
validates :title, presence: true, length: { maximum: 255 }
validates :content, presence: true
validates :author, presence: true
```

### Scopes
```ruby
scope :published, -> { where.not(published_at: nil) }
scope :recent, -> { order(created_at: :desc) }
```

### Instance Methods
```ruby
def published?          # Check if post is published
def publish!           # Publish the post now
def unpublish!         # Revert to draft status
```

## Routes

The application uses RESTful routes plus custom member actions:

```ruby
resources :posts do
  member do
    patch :publish
    patch :unpublish
  end
end
```

This generates:
- `GET /posts` - List all posts
- `GET /posts/:id` - Show individual post
- `GET /posts/new` - New post form
- `POST /posts` - Create post
- `GET /posts/:id/edit` - Edit post form
- `PATCH /posts/:id` - Update post
- `DELETE /posts/:id` - Delete post
- `PATCH /posts/:id/publish` - Publish post
- `PATCH /posts/:id/unpublish` - Unpublish post

## Views and UI

### Design Features
- Clean, modern interface with embedded CSS
- Responsive design that works on mobile
- Visual status indicators for published/draft posts
- Form validation with error display
- Confirmation dialogs for destructive actions

### Navigation
- Main navigation bar with links to posts
- Breadcrumb navigation on individual pages
- "Write New Post" prominently featured

## Getting Started

1. **View Posts**: Navigate to `/posts` to see all posts
2. **Create Post**: Click "Write New Post" and fill out the form
3. **Publish Post**: View your post and click "Publish" to make it live
4. **Edit Post**: Use the "Edit" button to modify existing posts
5. **Manage Posts**: Use publish/unpublish/delete as needed

## Sample Data

The application includes seed data with example posts:
- A welcome post (published)
- A Rails tutorial post (published)
- A draft post example (unpublished)

To reset sample data: `rails db:seed`

## File Structure

```
app/
├── models/
│   └── post.rb                 # Post model with validations
├── controllers/
│   └── posts_controller.rb     # Full CRUD + publish actions
├── views/
│   └── posts/
│       ├── index.html.erb      # Posts listing
│       ├── show.html.erb       # Individual post view
│       ├── new.html.erb        # New post form
│       └── edit.html.erb       # Edit post form
└── helpers/
    └── posts_helper.rb         # View helpers (auto-generated)

db/
├── migrate/
│   └── *_create_posts.rb       # Posts table migration
└── seeds.rb                    # Sample data

config/
└── routes.rb                   # RESTful routes + custom actions
```

## Future Enhancements

Potential improvements could include:
- User authentication and post ownership
- Categories and tags
- Rich text editor for content
- Image uploads
- Comments system
- SEO-friendly URLs (slugs)
- Post scheduling
- Search functionality
