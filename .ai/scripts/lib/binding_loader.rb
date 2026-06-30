# frozen_string_literal: true

require "yaml"
require "json"
require "json-schema"

module LocalCrew
  # Loads a binding and its profile by name, and validates the
  # binding's structure against schema/bindings.schema.json. A role
  # only exists here as a binding key — this file knows nothing about
  # installed models or the RAM budget, that's RamEstimator's job.
  class BindingLoader
    class Error < StandardError; end

    SCHEMA_PATH = File.expand_path("../../schema/bindings.schema.json", __dir__)

    def initialize(root:, profile_name:)
      @root = root
      @profile_name = profile_name
    end

    def profile
      @profile ||= load_yaml(File.join(@root, "profiles", "#{@profile_name}.yml"))
    end

    def role_bindings
      @role_bindings ||= begin
        bindings = load_yaml(File.join(@root, "bindings", "#{@profile_name}.yml"))
        validate_schema!(bindings)
        bindings
      end
    end

    # Resolved config for a given role, ready to be serialized as
    # JSON for an external consumer (e.g. an n8n workflow).
    def for_role(role_name)
      config = role_bindings[role_name]
      raise Error, "Role #{role_name.inspect} is absent from binding #{@profile_name}" unless config

      config.merge("role" => role_name)
    end

    private

    def load_yaml(path)
      raise Error, "File not found: #{path}" unless File.exist?(path)

      YAML.load_file(path)
    end

    def validate_schema!(bindings)
      schema = JSON.parse(File.read(SCHEMA_PATH))
      # validate_schema: false keeps the gem from fetching the
      # draft-07 meta-schema over the network to validate our schema
      # itself — we're validating the data, not the schema.
      errors = JSON::Validator.fully_validate(schema, bindings, validate_schema: false)
      raise Error, "Binding #{@profile_name} is invalid:\n#{errors.join("\n")}" unless errors.empty?
    end
  end
end

if $PROGRAM_NAME == __FILE__
  require "optparse"
  require_relative "config"

  options = {}
  OptionParser.new do |parser|
    parser.on("--role ROLE", "Role to resolve") { |value| options[:role] = value }
    parser.on("--profile PROFILE", "Profile/binding name (defaults to config.yml's 'profile')") { |value| options[:profile] = value }
  end.parse!(ARGV)

  root = File.expand_path("../..", __dir__)
  options[:profile] ||= LocalCrew::Config.new(root: root).profile

  unless options[:role] && options[:profile]
    warn "Usage: ruby binding_loader.rb --role <role> [--profile <profile>] (or set 'profile' in config.yml)"
    exit 1
  end

  loader = LocalCrew::BindingLoader.new(root: root, profile_name: options[:profile])

  begin
    puts JSON.generate(loader.for_role(options[:role]))
  rescue LocalCrew::BindingLoader::Error => e
    warn e.message
    exit 1
  end
end
