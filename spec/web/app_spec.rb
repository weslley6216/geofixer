# frozen_string_literal: true

ENV['BASIC_AUTH_USER'] = 'tester'
ENV['BASIC_AUTH_PASSWORD'] = 'secret'

require 'spec_helper'
require 'rack/test'
require_relative '../support/xlsx_helper'
require_relative '../../web/app'

RSpec.describe Web::App do
  include Rack::Test::Methods
  include XlsxHelper

  def app = Web::App

  let(:registry) { JobRegistry.new }
  let(:queue) { instance_spy(JobQueue) }

  before do
    Web::App.set(:job_registry, registry)
    Web::App.set(:job_queue, queue)
    authorize 'tester', 'secret'
  end

  it 'rejects requests without valid credentials' do
    basic_authorize 'tester', 'wrong'
    get '/'
    expect(last_response.status).to eq(401)
  end

  it 'serves the upload form' do
    get '/'
    expect(last_response).to be_ok
    expect(last_response.body).to include('Processar')
  end

  it 'serves the stylesheet' do
    get '/style.css'
    expect(last_response).to be_ok
    expect(last_response.headers['Content-Type']).to include('css')
  end

  it 'accepts an xlsx upload, creates a job and enqueues it' do
    xlsx = write_xlsx([%w[Sequence Address], ['1', 'Rua A, 10']])
    post '/upload', file: Rack::Test::UploadedFile.new(xlsx, 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet')

    expect(last_response.status).to eq(302)
    id = last_response.headers['Location'][%r{/jobs/(.+)}, 1]
    expect(registry.fetch(id).status).to eq(:queued)
    expect(queue).to have_received(:enqueue).with(id, end_with(id))
  end

  it 'rejects a non-xlsx upload' do
    post '/upload', file: Rack::Test::UploadedFile.new(__FILE__, 'text/plain')
    expect(last_response.status).to eq(422)
    expect(last_response.body).to include('xlsx')
  end

  it 'shows the status page for a known job' do
    registry.create('abc')
    get '/jobs/abc'
    expect(last_response).to be_ok
    expect(last_response.body).to include('Processando')
  end

  it 'returns 404 for an unknown job' do
    get '/jobs/nope'
    expect(last_response.status).to eq(404)
  end

  it 'shows how many addresses were processed while running' do
    registry.create('abc')
    registry.update('abc', status: :running, processed: 40, total: 100)

    get '/jobs/abc'
    expect(last_response.body).to include('40/100')
  end

  it 'serves the csv download when the job is done' do
    path = File.join(Dir.mktmpdir, 'out.csv')
    File.write(path, "col\n")
    registry.create('abc')
    registry.update('abc', status: :done, csv_path: path)

    get '/jobs/abc/download/csv'
    expect(last_response).to be_ok
    expect(last_response.headers['Content-Disposition']).to include('attachment')
  end
end
