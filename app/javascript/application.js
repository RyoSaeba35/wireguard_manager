// Configure your import map in config/importmap.rb. Read more: https://github.com/rails/importmap-rails
import { Turbo } from "@hotwired/turbo-rails"
Turbo.session.drive = false

import "bootstrap"

// Import Splide JavaScript only (CSS is already in layout)
import Splide from "@splidejs/splide";
window.Splide = Splide; // Make Splide globally available
import "controllers"
