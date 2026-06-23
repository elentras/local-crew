# frozen_string_literal: true

module LocalCrew
  # Cross-checks a binding, its profile, and the models actually
  # installed in Ollama to estimate the effective RAM budget of
  # persistent roles, and verify that every referenced model exists.
  class RamEstimator
    class Error < StandardError; end

    BYTES_PER_GB = 1024**3

    # Threshold above which a keep_alive is considered "persistent":
    # long enough to reasonably overlap with another model loading in
    # a real working session. -1 (forever) is always persistent.
    PERSISTENT_THRESHOLD_SECONDS = 300

    # Safety margin under available_for_models_gb below which we warn
    # without blocking validation.
    WARNING_MARGIN_RATIO = 0.10

    DURATION_PATTERN = /\A(\d+)(s|m|h)\z/

    Result = Struct.new(:total_persistent_gb, :available_gb, :persistent_roles, :warnings, keyword_init: true)

    def initialize(profile:, role_bindings:, installed_models:)
      @profile = profile
      @role_bindings = role_bindings
      @installed_models = installed_models
    end

    def estimate!
      errors = missing_model_errors
      raise Error, errors.join("\n") unless errors.empty?

      persistent = @role_bindings.select { |_role, config| persistent?(config["keep_alive"]) }
      total_gb = persistent.sum { |_role, config| @installed_models.fetch(config["model"], 0) }.fdiv(BYTES_PER_GB)
      available_gb = @profile.fetch("available_for_models_gb")

      errors = []
      warnings = []

      if total_gb > available_gb
        errors << format(
          "Estimated persistent RAM (%.1fGB) exceeds available_for_models_gb (%.1fGB) — affected roles: %s",
          total_gb, available_gb, persistent.keys.join(", ")
        )
      elsif total_gb > available_gb * (1 - WARNING_MARGIN_RATIO)
        warnings << format("RAM margin < 10%%: %.1fGB used out of %.1fGB available", total_gb, available_gb)
      end

      max_concurrent = @profile.fetch("max_concurrent_models")
      if persistent.size > max_concurrent
        errors << "#{persistent.size} persistent models configured, max_concurrent_models allows #{max_concurrent}"
      end

      raise Error, errors.join("\n") unless errors.empty?

      Result.new(total_persistent_gb: total_gb, available_gb: available_gb, persistent_roles: persistent.keys, warnings: warnings)
    end

    private

    def persistent?(keep_alive)
      return true if keep_alive == -1
      return false unless keep_alive.is_a?(String)

      seconds(keep_alive) >= PERSISTENT_THRESHOLD_SECONDS
    end

    def seconds(value)
      match = DURATION_PATTERN.match(value)
      raise Error, "Invalid keep_alive: #{value.inspect}" unless match

      amount = match[1].to_i
      case match[2]
      when "s" then amount
      when "m" then amount * 60
      when "h" then amount * 3600
      end
    end

    def missing_model_errors
      @role_bindings.filter_map do |role, config|
        model = config["model"]
        next if @installed_models.key?(model)

        "Role #{role}: model #{model.inspect} not found in Ollama (ollama pull #{model})"
      end
    end
  end
end
