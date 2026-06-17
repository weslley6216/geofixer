# frozen_string_literal: true

require 'dotenv/load' if ENV['RACK_ENV'] != 'production'
require_relative 'web/app'
require_relative 'web/job_runner'

registry = JobRegistry.new
Web::App.set :job_registry, registry
Web::App.set :job_queue, JobQueue.new(registry, JobRunner.new)

run Web::App
