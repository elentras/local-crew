# frozen_string_literal: true

source "https://rubygems.org"

# Tooling de validation pour .ai/ — pas de Rails, juste de quoi
# tester scripts/ sans dépendre d'un Ollama réel.
gem "rspec", "~> 3.13"
gem "webmock", "~> 3.24"
gem "json-schema", "~> 4.3"
gem "rake", "~> 13.2"

# HTTP wrapper around BindingLoader for n8n sub-workflows (see
# scripts/server.rb) — Execute Command isn't available in that
# execution context, plain HTTP is.
gem "sinatra", "~> 4.1"
gem "puma", "~> 6.4"
gem "rackup", "~> 2.2"
gem "rack-test", "~> 2.2"
