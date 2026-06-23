#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "lib/ollama_client"
require_relative "lib/binding_loader"

module LocalCrew
  # Pulls, via Ollama's HTTP API, every model referenced by a binding
  # that isn't already installed. Never calls `ollama pull` as a
  # subprocess.
  module PullModels
    def self.run(argv, root: File.expand_path("..", __dir__), &on_progress)
      profile_name = argv.first
      raise BindingLoader::Error, "Usage: ruby pull_models.rb <profile_name>" unless profile_name

      loader = BindingLoader.new(root: root, profile_name: profile_name)
      client = OllamaClient.new(loader.profile.fetch("ollama_host"))
      installed = client.installed_models

      models_to_pull = loader.role_bindings.values.map { |config| config["model"] }.uniq.reject { |m| installed.key?(m) }

      models_to_pull.each do |model|
        client.pull(model, &on_progress)
      end

      models_to_pull
    end
  end
end

if $PROGRAM_NAME == __FILE__
  begin
    pulled = LocalCrew::PullModels.run(ARGV) do |progress|
      status = progress["status"]
      if progress["total"] && progress["completed"]
        percent = (progress["completed"].to_f / progress["total"] * 100).round(1)
        print "\r#{status} (#{percent}%)"
      else
        print "\r#{status}"
      end
      puts if status == "success"
    end

    if pulled.empty?
      puts "Every model in the binding is already installed."
    else
      puts "Installed models: #{pulled.join(', ')}"
    end
  rescue LocalCrew::OllamaClient::Error, LocalCrew::BindingLoader::Error => e
    warn "Pull failed:\n#{e.message}"
    exit 1
  end
end
