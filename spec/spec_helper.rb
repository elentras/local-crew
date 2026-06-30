# frozen_string_literal: true

require "webmock/rspec"
require "tmpdir"

lib_root = File.expand_path("../.ai/scripts/lib", __dir__)
require File.join(lib_root, "ollama_client")
require File.join(lib_root, "binding_loader")
require File.join(lib_root, "ram_estimator")
require File.join(lib_root, "config")

WebMock.disable_net_connect!(allow_localhost: false)

RSpec.configure do |config|
  config.expect_with(:rspec) { |c| c.syntax = :expect }
end
