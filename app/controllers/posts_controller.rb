class PostsController < ApplicationController
  before_action :set_post, only: [:show, :edit, :update, :destroy, :publish, :unpublish]

  def index
    @posts = Post.recent
  end

  def show
  end

  def new
    @post = Post.new
  end

  def create
    @post = Post.new(post_params)
    
    if @post.save
      redirect_to @post, notice: 'Post was successfully created.'
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @post.update(post_params)
      redirect_to @post, notice: 'Post was successfully updated.'
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @post.destroy
    redirect_to posts_path, notice: 'Post was successfully deleted.'
  end

  def publish
    @post.publish!
    redirect_to @post, notice: 'Post was published.'
  end

  def unpublish
    @post.unpublish!
    redirect_to @post, notice: 'Post was unpublished.'
  end

  private

  def set_post
    @post = Post.find(params[:id])
  end

  def post_params
    permitted_params = params.require(:post).permit(:title, :content, :author, :labels)
    
    # Process labels from comma-separated string to array
    if permitted_params[:labels].present?
      if permitted_params[:labels].is_a?(String)
        # Convert comma-separated string to array
        permitted_params[:labels] = permitted_params[:labels].split(',').map(&:strip).reject(&:blank?)
      else
        # Already an array, just clean it up
        permitted_params[:labels] = permitted_params[:labels].reject(&:blank?)
      end
    else
      # Ensure empty labels is an empty array
      permitted_params[:labels] = []
    end
    
    permitted_params
  end
end
