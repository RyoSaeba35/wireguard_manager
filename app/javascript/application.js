// Configure your import map in config/importmap.rb. Read more: https://github.com/rails/importmap-rails
import "@hotwired/turbo-rails"
import "bootstrap"

// Import Splide JavaScript only (CSS is already in layout)
import Splide from "@splidejs/splide";
window.Splide = Splide; // Make Splide globally available
