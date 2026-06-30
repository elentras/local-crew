# frozen_string_literal: true

RSpec.describe LocalCrew::Config do
  it "reads the profile declared in config.yml" do
    config = described_class.new(root: File.expand_path("../fixtures", __dir__))

    expect(config.profile).to eq("test-profile")
  end

  it "returns nil when config.yml is absent" do
    Dir.mktmpdir do |empty_root|
      config = described_class.new(root: empty_root)

      expect(config.profile).to be_nil
    end
  end
end
