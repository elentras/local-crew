#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "lib/ollama_client"
require_relative "lib/binding_loader"
require_relative "lib/ram_estimator"
require_relative "lib/config"

module LocalCrew
  # Orchestrates BindingLoader, OllamaClient and RamEstimator to
  # validate a binding against its profile and Ollama's real state.
  module CLI
    def self.run(argv, root: File.expand_path("..", __dir__))
      profile_name = argv.first || Config.new(root: root).profile
      unless profile_name
        raise BindingLoader::Error, "Usage: ruby validate_bindings.rb [profile_name] (or set 'profile' in config.yml)"
      end

      loader = BindingLoader.new(root: root, profile_name: profile_name)
      client = OllamaClient.new(loader.profile.fetch("ollama_host"))

      RamEstimator.new(
        profile: loader.profile,
        role_bindings: loader.role_bindings,
        installed_models: client.installed_models
      ).estimate!
    end
  end
end

if $PROGRAM_NAME == __FILE__
  begin
    result = LocalCrew::CLI.run(ARGV)
    result.warnings.each { |warning| warn "Warning: #{warning}" }
    puts format(
      "OK — %.1fGB / %.1fGB used by persistent models (%s)",
      result.total_persistent_gb, result.available_gb, result.persistent_roles.join(", ")
    )
  rescue LocalCrew::OllamaClient::Error, LocalCrew::BindingLoader::Error, LocalCrew::RamEstimator::Error => e
    warn "Validation failed:\n#{e.message}"
    exit 1
  end
end
