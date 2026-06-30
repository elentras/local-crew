# frozen_string_literal: true

ENV["LOCAL_CREW_ROOT"] = File.expand_path("fixtures", __dir__)

require "rack/test"
require_relative "../.ai/scripts/server"

RSpec.describe "BindingLoader HTTP server" do
  include Rack::Test::Methods

  def app
    Sinatra::Application
  end

  before do
    # Rack::Test defaults to Host: example.org, which Sinatra's
    # host-authorization check rejects. n8n's real requests carry
    # Host: localhost naturally (from the URL), so this only matters
    # for tests.
    header "Host", "localhost"
  end

  it "defaults to the profile declared in config.yml when none is given" do
    get "/bindings/backend_dev"

    expect(last_response.status).to eq(200)
    body = JSON.parse(last_response.body)
    expect(body).to include("role" => "backend_dev", "model" => "qwen2.5-coder:14b")
  end

  it "uses the profile given via ?profile= over config.yml's default" do
    get "/bindings/backend_dev?profile=test-profile"

    expect(last_response.status).to eq(200)
    body = JSON.parse(last_response.body)
    expect(body).to include("role" => "backend_dev", "model" => "qwen2.5-coder:14b")
  end

  it "returns 404 with an error message when the role is unknown" do
    get "/bindings/ghost"

    expect(last_response.status).to eq(404)
    expect(JSON.parse(last_response.body)["error"]).to match(/absent/)
  end
end
