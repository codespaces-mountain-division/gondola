Rails.application.routes.draw do
  root "hello#index"
  
  resources :posts do
    member do
      patch :publish
      patch :unpublish
    end
  end
end
