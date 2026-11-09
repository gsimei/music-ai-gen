# Pin npm packages by running ./bin/importmap

pin "application"
pin "jp_waveform", to: "jp_waveform.js"
pin "jp_motion", to: "jp_motion.js"
pin "@hotwired/turbo-rails", to: "turbo.min.js"
pin "@hotwired/stimulus", to: "stimulus.min.js"
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js"
pin_all_from "app/javascript/controllers", under: "controllers"
