# frozen_string_literal: true

require "yaml"

module LocalCrew
  # Reads .ai/config.yml, the single place that names the profile to
  # use when none is given explicitly. Mirrors how a gem usually
  # exposes one configuration object instead of letting every caller
  # hardcode its own default.
  class Config
    def initialize(root:)
      @root = root
    end

    # Name of the profile/binding to use when none is given
    # explicitly (CLI argument, server query param, ...). Nil if
    # config.yml is absent or doesn't declare one — callers decide
    # whether that's an error.
    def profile
      data["profile"]
    end

    private

    def data
      @data ||= File.exist?(path) ? YAML.load_file(path) : {}
    end

    def path
      File.join(@root, "config.yml")
    end
  end
end
