# frozen_string_literal: true

require 'sinatra/base'
require 'securerandom'
require 'fileutils'
require 'rack/utils'
require_relative 'job_registry'
require_relative 'job_queue'

module Web
  class App < Sinatra::Base
    JOBS_DIR = ENV.fetch('JOBS_DIR', 'tmp/jobs')
    JOB_TTL_SECONDS = 3600

    configure do
      set :views, File.expand_path('views', __dir__)
      enable :logging
      # Served behind Render's proxy on a dynamic hostname and guarded by Basic
      # Auth, so Sinatra's host allow-list only gets in the way here.
      set :host_authorization, permitted_hosts: []
      %w[BASIC_AUTH_USER BASIC_AUTH_PASSWORD].each do |var|
        raise "#{var} must be set" if ENV[var].to_s.empty?
      end
    end

    use Rack::Auth::Basic, 'Geofixer' do |user, pass|
      Rack::Utils.secure_compare(user.to_s, ENV['BASIC_AUTH_USER'].to_s) &
        Rack::Utils.secure_compare(pass.to_s, ENV['BASIC_AUTH_PASSWORD'].to_s)
    end

    get '/' do
      erb :upload
    end

    post '/upload' do
      file = params[:file]
      unless valid_xlsx?(file)
        @error = 'Envie um arquivo .xlsx'
        halt 422, erb(:upload)
      end

      sweep_old_jobs
      id = SecureRandom.uuid
      dir = File.join(JOBS_DIR, id)
      FileUtils.mkdir_p(dir)
      FileUtils.cp(file[:tempfile].path, File.join(dir, 'input.xlsx'))

      settings.job_registry.create(id)
      settings.job_queue.enqueue(id, dir)
      redirect "/jobs/#{id}"
    end

    get '/jobs/:id' do
      @job = settings.job_registry.fetch(params[:id])
      halt 404, 'Job não encontrado' unless @job
      erb :job
    end

    get '/jobs/:id/download/:kind' do
      job = settings.job_registry.fetch(params[:id])
      halt 404 unless job && job.status == :done
      path = params[:kind] == 'csv' ? job.csv_path : job.log_path
      halt 404 unless path && File.exist?(path)
      send_file path, disposition: 'attachment'
    end

    private

    def valid_xlsx?(file)
      file.is_a?(Hash) && file[:filename].to_s.downcase.end_with?('.xlsx') && file[:tempfile]
    end

    def sweep_old_jobs
      cutoff = Time.now - JOB_TTL_SECONDS
      settings.job_registry.all.each do |job|
        next if job.created_at > cutoff

        FileUtils.rm_rf(File.join(JOBS_DIR, job.id))
        settings.job_registry.delete(job.id)
      end
    end
  end
end
