#!/usr/bin/env ruby
# frozen_string_literal: true

# Thin HTTP wrapper around BindingLoader, for n8n workflows that run
# as a sub-workflow (via the Execute Workflow node). Those execute in
# a more restricted runtime that doesn't load the Execute Command
# node, so they can't shell out to binding_loader.rb directly — but
# a plain HTTP Request node works everywhere. binding_loader.rb's CLI
# stays as the entry point for everything else (manual use, top-level
# workflows, other tooling); this server exists only to route around
# that one sub-workflow restriction.

require "sinatra"
require "json"
require_relative "lib/binding_loader"
require_relative "lib/config"

set :bind, "127.0.0.1"
set :port, 4567
set :bindings_root, ENV.fetch("LOCAL_CREW_ROOT", File.expand_path("..", __dir__))
# This is always a local dev tool, never a production deployment —
# force :development so Sinatra's host-authorization check uses its
# permissive default (any host), regardless of how it's invoked
# (plain `ruby server.rb` vs RACK_ENV=test under RSpec).
set :environment, :development

# Profile defaults to config.yml's 'profile' so workflows don't have
# to hardcode it — pass ?profile=<name> to use a different one.
get "/bindings/:role" do
  content_type :json
  profile = params[:profile] || LocalCrew::Config.new(root: settings.bindings_root).profile
  unless profile
    status 400
    next JSON.generate(error: "No profile given: pass ?profile=<name> or set 'profile' in config.yml")
  end

  loader = LocalCrew::BindingLoader.new(root: settings.bindings_root, profile_name: profile)
  JSON.generate(loader.for_role(params[:role]))
rescue LocalCrew::BindingLoader::Error => e
  status 404
  JSON.generate(error: e.message)
end
