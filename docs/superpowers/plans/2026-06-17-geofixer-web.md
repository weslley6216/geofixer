# Geofixer Web Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the Google-Drive-polling cron with a Sinatra web app where the user uploads an `.xlsx` from their phone, it is processed asynchronously by an in-process worker, and the resulting `.csv` + log are served for download — all in one free Render web service.

**Architecture:** A modular `Sinatra::Base` app behind Puma. Uploads are saved to `tmp/jobs/<uuid>/`, registered in a thread-safe `JobRegistry`, and enqueued to a `JobQueue` whose single background thread runs each job through `JobRunner` (xlsx→csv via `XlsxConverter`, then the existing `AddressProcessor`). The status page auto-refreshes until the job is done, then shows download links. HTTP Basic Auth guards everything.

**Tech Stack:** Ruby 4.0.1, Sinatra, Puma, Rack::Auth::Basic, roo, the Phase 1 processing core. Tests with RSpec + Rack::Test.

---

## File Structure

**Create:**
- `web/xlsx_converter.rb` — `XlsxConverter.convert(xlsx, csv)`
- `web/job_registry.rb` — thread-safe job state map
- `web/job_runner.rb` — process one job directory end to end
- `web/job_queue.rb` — FIFO queue + single worker thread
- `web/app.rb` — `Web::App < Sinatra::Base` (routes + auth)
- `web/views/upload.erb`, `web/views/job.erb`
- `config.ru`, `config/puma.rb`
- `Dockerfile`, `.dockerignore`, `render.yaml`, `.env.example`
- `spec/web/*_spec.rb`, `spec/fixtures/sample.xlsx`

**Modify:** `Gemfile`, `README.md`

**Delete:** `main.rb`, `app/services/google_drive/**`, `spec/services/google_drive/**`

---

## Task 1: Remove the Drive/cron layer

**Files:**
- Delete: `main.rb`, `app/services/google_drive/base_service.rb`, `app/services/google_drive/downloader_service.rb`, `app/services/google_drive/uploader_service.rb`, `spec/services/google_drive/downloader_service_spec.rb`, `spec/services/google_drive/uploader_service_spec.rb`

- [ ] **Step 1: Delete the files**

```bash
git rm main.rb app/services/google_drive/*.rb spec/services/google_drive/*.rb
rmdir app/services/google_drive spec/services/google_drive 2>/dev/null || true
```

- [ ] **Step 2: Run the suite to confirm nothing else depended on them**

Run: `bundle exec rspec --format progress`
Expected: PASS, fewer examples than before (the google_drive specs are gone), 0 failures. `spec_helper`'s `Dir[...app/**/*.rb]` glob simply no longer finds the deleted files.

- [ ] **Step 3: Commit**

```bash
git add -A
git commit -m "Remove Google Drive services and cron entrypoint

Phase 2 replaces the Drive-polling cron with an on-demand upload web
app, so the Drive download/upload services, their specs and the Main
orchestrator are no longer used.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 2: Update dependencies

**Files:**
- Modify: `Gemfile`

- [ ] **Step 1: Rewrite the Gemfile**

Replace the whole file with:

```ruby
# frozen_string_literal: true

source 'https://rubygems.org'

ruby file: '.tool-versions'

gem 'csv'
gem 'dotenv'
gem 'i18n'
gem 'puma'
gem 'rackup'
gem 'roo'
gem 'sinatra'

group :test do
  gem 'caxlsx'
  gem 'rack-test'
  gem 'rspec'
  gem 'webmock'
end
```

Removed: `google-apis-drive_v3`, `googleauth`, `pstore` (only googleauth needed pstore). Added: `puma`, `rackup`, `sinatra` (runtime); `caxlsx` (test-only, to generate the xlsx fixture), `rack-test`.

- [ ] **Step 2: Install**

Run: `bundle install`
Expected: resolves successfully; `sinatra`, `puma`, `rack-test`, `caxlsx` appear in `Gemfile.lock`; `googleauth`/`google-apis-drive_v3` removed.

- [ ] **Step 3: Confirm the suite still loads and passes**

Run: `bundle exec rspec --format progress`
Expected: PASS, 0 failures.

- [ ] **Step 4: Commit**

```bash
git add Gemfile Gemfile.lock
git commit -m "Swap Drive/OAuth gems for the web stack (sinatra, puma)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 3: XlsxConverter + test fixture

**Files:**
- Create: `web/xlsx_converter.rb`
- Create: `spec/web/xlsx_converter_spec.rb`
- Create: `spec/support/xlsx_helper.rb` (builds an xlsx fixture in a tmp path)

- [ ] **Step 1: Write a helper that builds an xlsx fixture**

Create `spec/support/xlsx_helper.rb`:

```ruby
# frozen_string_literal: true

require 'axlsx'
require 'tmpdir'

module XlsxHelper
  # Writes an .xlsx with the given rows (array of arrays) and returns its path.
  def write_xlsx(rows, path = File.join(Dir.mktmpdir, 'sample.xlsx'))
    package = Axlsx::Package.new
    package.workbook.add_worksheet(name: 'Sheet1') do |sheet|
      rows.each { |row| sheet.add_row(row) }
    end
    package.serialize(path)
    path
  end
end
```

- [ ] **Step 2: Write the failing test**

Create `spec/web/xlsx_converter_spec.rb`:

```ruby
# frozen_string_literal: true

require 'spec_helper'
require_relative '../support/xlsx_helper'
require_relative '../../web/xlsx_converter'

RSpec.describe XlsxConverter do
  include XlsxHelper

  it 'converts the first sheet of an xlsx into a csv with the same rows' do
    xlsx = write_xlsx([%w[Sequence Address], ['1', 'Rua A, 10'], ['2', 'Rua B, 20']])
    csv_path = File.join(Dir.mktmpdir, 'out.csv')

    XlsxConverter.convert(xlsx, csv_path)

    rows = CSV.read(csv_path)
    expect(rows).to eq([%w[Sequence Address], ['1', 'Rua A, 10'], ['2', 'Rua B, 20']])
  end
end
```

- [ ] **Step 3: Run it to verify it fails**

Run: `bundle exec rspec spec/web/xlsx_converter_spec.rb`
Expected: FAIL — `uninitialized constant XlsxConverter`.

- [ ] **Step 4: Implement**

Create `web/xlsx_converter.rb`:

```ruby
# frozen_string_literal: true

require 'roo'
require 'csv'

# Converts the first sheet of an .xlsx file into a UTF-8 .csv that
# AddressProcessor can read. Extracted from the old Main orchestrator.
class XlsxConverter
  def self.convert(xlsx_path, csv_path)
    xlsx = Roo::Spreadsheet.open(xlsx_path)
    CSV.open(csv_path, 'w', encoding: 'UTF-8') do |csv|
      xlsx.sheet(0).each_row_streaming { |row| csv << row.map(&:value) }
    end
    csv_path
  end
end
```

- [ ] **Step 5: Run it to verify it passes**

Run: `bundle exec rspec spec/web/xlsx_converter_spec.rb`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add web/xlsx_converter.rb spec/web/xlsx_converter_spec.rb spec/support/xlsx_helper.rb
git commit -m "Add XlsxConverter (xlsx -> csv)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 4: JobRegistry

**Files:**
- Create: `web/job_registry.rb`
- Create: `spec/web/job_registry_spec.rb`

- [ ] **Step 1: Write the failing test**

Create `spec/web/job_registry_spec.rb`:

```ruby
# frozen_string_literal: true

require 'spec_helper'
require_relative '../../web/job_registry'

RSpec.describe JobRegistry do
  subject(:registry) { described_class.new }

  it 'creates a job in the queued state' do
    job = registry.create('abc')
    expect(job.id).to eq('abc')
    expect(job.status).to eq(:queued)
  end

  it 'fetches a created job' do
    registry.create('abc')
    expect(registry.fetch('abc').status).to eq(:queued)
  end

  it 'returns nil for an unknown job' do
    expect(registry.fetch('nope')).to be_nil
  end

  it 'updates attributes of a job' do
    registry.create('abc')
    registry.update('abc', status: :done, csv_path: '/tmp/x.csv')
    job = registry.fetch('abc')
    expect(job.status).to eq(:done)
    expect(job.csv_path).to eq('/tmp/x.csv')
  end
end
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bundle exec rspec spec/web/job_registry_spec.rb`
Expected: FAIL — `uninitialized constant JobRegistry`.

- [ ] **Step 3: Implement**

Create `web/job_registry.rb`:

```ruby
# frozen_string_literal: true

require 'monitor'

# Thread-safe in-memory map of job id -> Job. Holds the lifecycle status and
# the result file paths. No persistence: jobs are transient.
class JobRegistry
  Job = Struct.new(:id, :status, :csv_path, :log_path, :error, :created_at, keyword_init: true)

  def initialize
    @jobs = {}
    @monitor = Monitor.new
  end

  def create(id)
    @monitor.synchronize { @jobs[id] = Job.new(id: id, status: :queued, created_at: Time.now) }
  end

  def fetch(id)
    @monitor.synchronize { @jobs[id] }
  end

  def update(id, **attrs)
    @monitor.synchronize do
      job = @jobs[id]
      return nil unless job

      attrs.each { |key, value| job[key] = value }
      job
    end
  end

  def delete(id)
    @monitor.synchronize { @jobs.delete(id) }
  end

  def all
    @monitor.synchronize { @jobs.values }
  end
end
```

- [ ] **Step 4: Run it to verify it passes**

Run: `bundle exec rspec spec/web/job_registry_spec.rb`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add web/job_registry.rb spec/web/job_registry_spec.rb
git commit -m "Add thread-safe JobRegistry

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 5: JobRunner

**Files:**
- Create: `web/job_runner.rb`
- Create: `spec/web/job_runner_spec.rb`

- [ ] **Step 1: Write the failing test**

`JobRunner` wires `XlsxConverter` + `AddressProcessor`; both are already tested, so stub `AddressProcessor` to isolate the wiring.

Create `spec/web/job_runner_spec.rb`:

```ruby
# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require_relative '../support/xlsx_helper'
require_relative '../../web/job_runner'

RSpec.describe JobRunner do
  include XlsxHelper

  it 'converts the upload and runs AddressProcessor, returning the csv and log paths' do
    dir = Dir.mktmpdir
    write_xlsx([%w[Sequence Address], ['1', 'Rua A, 10']], File.join(dir, 'input.xlsx'))

    fake_processor = instance_double(AddressProcessor, process_file: nil)
    expect(AddressProcessor).to receive(:new) do |input, output_csv, output_log|
      expect(input).to eq(File.join(dir, 'input.csv'))
      expect(output_csv).to match(%r{/\d{2}-\d{2}-\d{4} Andreia Eslava\.csv$})
      expect(output_log).to match(%r{/\d{2}-\d{2}-\d{4} log_enderecos\.txt$})
      fake_processor
    end

    csv_path, log_path = described_class.new.run(dir)

    expect(File.exist?(File.join(dir, 'input.csv'))).to be true
    expect(csv_path).to end_with('Andreia Eslava.csv')
    expect(log_path).to end_with('log_enderecos.txt')
  end
end
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bundle exec rspec spec/web/job_runner_spec.rb`
Expected: FAIL — `uninitialized constant JobRunner`.

- [ ] **Step 3: Implement**

Create `web/job_runner.rb`:

```ruby
# frozen_string_literal: true

require 'date'
require_relative 'xlsx_converter'
require_relative '../app/address_processor'

# Runs one upload to completion: convert the xlsx, then process it with the
# Phase 1 core. Returns [csv_path, log_path] of the generated results.
class JobRunner
  def initialize(output_label: ENV.fetch('OUTPUT_LABEL', 'Andreia Eslava'))
    @output_label = output_label
  end

  def run(dir)
    csv_path = File.join(dir, 'input.csv')
    XlsxConverter.convert(File.join(dir, 'input.xlsx'), csv_path)

    date = Date.today.strftime('%d-%m-%Y')
    output_csv = File.join(dir, "#{date} #{@output_label}.csv")
    output_log = File.join(dir, "#{date} log_enderecos.txt")

    AddressProcessor.new(csv_path, output_csv, output_log).process_file
    [output_csv, output_log]
  end
end
```

- [ ] **Step 4: Run it to verify it passes**

Run: `bundle exec rspec spec/web/job_runner_spec.rb`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add web/job_runner.rb spec/web/job_runner_spec.rb
git commit -m "Add JobRunner wiring XlsxConverter and AddressProcessor

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 6: JobQueue

**Files:**
- Create: `web/job_queue.rb`
- Create: `spec/web/job_queue_spec.rb`

- [ ] **Step 1: Write the failing test**

Use a fake runner so the test never touches the network, and poll the registry with a timeout.

Create `spec/web/job_queue_spec.rb`:

```ruby
# frozen_string_literal: true

require 'spec_helper'
require 'timeout'
require_relative '../../web/job_queue'
require_relative '../../web/job_registry'

RSpec.describe JobQueue do
  let(:registry) { JobRegistry.new }

  def wait_until(&block)
    Timeout.timeout(2) { sleep(0.01) until block.call }
  end

  it 'runs a queued job and records the result paths' do
    runner = double('runner', run: ['/tmp/x.csv', '/tmp/x.txt'])
    queue = described_class.new(registry, runner)
    registry.create('job1')

    queue.enqueue('job1', '/tmp/job1')
    wait_until { registry.fetch('job1').status == :done }

    job = registry.fetch('job1')
    expect(job.csv_path).to eq('/tmp/x.csv')
    expect(job.log_path).to eq('/tmp/x.txt')
  end

  it 'marks the job failed when the runner raises' do
    runner = double('runner')
    allow(runner).to receive(:run).and_raise('boom')
    queue = described_class.new(registry, runner)
    registry.create('job2')

    queue.enqueue('job2', '/tmp/job2')
    wait_until { registry.fetch('job2').status == :failed }

    expect(registry.fetch('job2').error).to eq('boom')
  end
end
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bundle exec rspec spec/web/job_queue_spec.rb`
Expected: FAIL — `uninitialized constant JobQueue`.

- [ ] **Step 3: Implement**

Create `web/job_queue.rb`:

```ruby
# frozen_string_literal: true

require_relative '../app/utils/logger'

# FIFO queue with a single background thread (started at boot inside the web
# process — not a separate Render worker). Runs one job at a time, which keeps
# the global CacheManager race-free and bounds resource use on the free tier.
class JobQueue
  def initialize(registry, runner)
    @registry = registry
    @runner = runner
    @queue = Thread::Queue.new
    @worker = Thread.new { work_loop }
  end

  def enqueue(job_id, dir)
    @queue << [job_id, dir]
  end

  private

  def work_loop
    loop { process(*@queue.pop) }
  end

  def process(job_id, dir)
    @registry.update(job_id, status: :running)
    csv_path, log_path = @runner.run(dir)
    @registry.update(job_id, status: :done, csv_path: csv_path, log_path: log_path)
  rescue StandardError => e
    Utils::Logger.warn("Job #{job_id} failed: #{e.message}")
    @registry.update(job_id, status: :failed, error: e.message)
  end
end
```

- [ ] **Step 4: Run it to verify it passes**

Run: `bundle exec rspec spec/web/job_queue_spec.rb`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add web/job_queue.rb spec/web/job_queue_spec.rb
git commit -m "Add JobQueue (single in-process worker thread)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 7: Web::App (routes, auth, views)

**Files:**
- Create: `web/app.rb`, `web/views/upload.erb`, `web/views/job.erb`
- Create: `spec/web/app_spec.rb`

- [ ] **Step 1: Write the views**

Create `web/views/upload.erb`:

```erb
<!doctype html>
<html lang="pt-BR">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Geofixer</title>
  <style>
    body { font-family: system-ui, sans-serif; max-width: 30rem; margin: 2rem auto; padding: 0 1rem; }
    button { font-size: 1.1rem; padding: 0.6rem 1.2rem; margin-top: 1rem; }
    input[type=file] { font-size: 1rem; }
    .error { color: #b00; }
  </style>
</head>
<body>
  <h1>Geofixer</h1>
  <% if @error %><p class="error"><%= @error %></p><% end %>
  <form action="/upload" method="post" enctype="multipart/form-data">
    <input type="file" name="file" accept=".xlsx" required>
    <button type="submit">Processar</button>
  </form>
</body>
</html>
```

Create `web/views/job.erb`:

```erb
<!doctype html>
<html lang="pt-BR">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <% if %i[queued running].include?(@job.status) %><meta http-equiv="refresh" content="3"><% end %>
  <title>Geofixer</title>
  <style>body { font-family: system-ui, sans-serif; max-width: 30rem; margin: 2rem auto; padding: 0 1rem; }</style>
</head>
<body>
  <h1>Geofixer</h1>
  <% case @job.status
     when :queued, :running %>
    <p>⏳ Processando… a página atualiza sozinha.</p>
  <% when :done %>
    <p>✅ Pronto!</p>
    <p><a href="/jobs/<%= @job.id %>/download/csv">Baixar CSV</a></p>
    <p><a href="/jobs/<%= @job.id %>/download/log">Baixar log</a></p>
    <p><a href="/">Processar outro</a></p>
  <% when :failed %>
    <p>❌ Falhou: <%= @job.error %></p>
    <p><a href="/">Voltar</a></p>
  <% end %>
</body>
</html>
```

- [ ] **Step 2: Write the failing test**

Create `spec/web/app_spec.rb`:

```ruby
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

  it 'serves the csv download when the job is done' do
    path = File.join(Dir.mktmpdir, 'out.csv')
    File.write(path, 'col\n')
    registry.create('abc')
    registry.update('abc', status: :done, csv_path: path)

    get '/jobs/abc/download/csv'
    expect(last_response).to be_ok
    expect(last_response.headers['Content-Disposition']).to include('attachment')
  end
end
```

- [ ] **Step 3: Run it to verify it fails**

Run: `bundle exec rspec spec/web/app_spec.rb`
Expected: FAIL — `uninitialized constant Web::App`.

- [ ] **Step 4: Implement**

Create `web/app.rb`:

```ruby
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
```

- [ ] **Step 5: Run it to verify it passes**

Run: `bundle exec rspec spec/web/app_spec.rb`
Expected: PASS.

- [ ] **Step 6: Run the whole suite**

Run: `bundle exec rspec --format progress`
Expected: PASS, 0 failures.

- [ ] **Step 7: Commit**

```bash
git add web/app.rb web/views spec/web/app_spec.rb
git commit -m "Add Sinatra web app: upload, status, download, basic auth

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 8: Boot wiring (config.ru + puma)

**Files:**
- Create: `config.ru`, `config/puma.rb`

- [ ] **Step 1: Write config.ru**

Create `config.ru`:

```ruby
# frozen_string_literal: true

require 'dotenv/load' if ENV['RACK_ENV'] != 'production'
require_relative 'web/app'
require_relative 'web/job_runner'

registry = JobRegistry.new
Web::App.set :job_registry, registry
Web::App.set :job_queue, JobQueue.new(registry, JobRunner.new)

run Web::App
```

- [ ] **Step 2: Write the puma config**

Create `config/puma.rb`:

```ruby
# frozen_string_literal: true

port ENV.fetch('PORT', 3000)
environment ENV.fetch('RACK_ENV', 'development')
workers 0
threads 1, 5
```

(`workers 0` keeps a single process so the in-memory registry and worker thread are shared by all requests.)

- [ ] **Step 3: Smoke-test that the app boots**

Run:

```bash
BASIC_AUTH_USER=u BASIC_AUTH_PASSWORD=p bundle exec puma -C config/puma.rb config.ru &
PUMA_PID=$!
sleep 2
curl -s -u u:p localhost:3000/ | grep -q Processar && echo BOOT_OK
kill "$PUMA_PID"
```

Expected: prints `BOOT_OK`.

- [ ] **Step 4: Commit**

```bash
git add config.ru config/puma.rb
git commit -m "Add config.ru and puma config; wire real registry/queue at boot

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 9: Containerization & Render blueprint

**Files:**
- Create: `Dockerfile`, `.dockerignore`, `render.yaml`, `.env.example`

- [ ] **Step 1: Dockerfile**

Create `Dockerfile`:

```dockerfile
FROM ruby:4.0.1-slim

RUN apt-get update -qq \
  && apt-get install -y --no-install-recommends build-essential \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY Gemfile Gemfile.lock .tool-versions ./
RUN bundle config set --local without 'test' \
  && bundle install --jobs 4

COPY . .

ENV RACK_ENV=production
CMD ["bundle", "exec", "puma", "-C", "config/puma.rb", "config.ru"]
```

- [ ] **Step 2: .dockerignore**

Create `.dockerignore`:

```
.git
tmp
files
logs
spec
docs
.env
config/credentials.json
config/token.yml
```

- [ ] **Step 3: render.yaml**

Create `render.yaml`:

```yaml
services:
  - type: web
    name: geofixer
    runtime: docker
    plan: free
    envVars:
      - key: GOOGLE_API_KEY
        sync: false
      - key: BASIC_AUTH_USER
        sync: false
      - key: BASIC_AUTH_PASSWORD
        sync: false
      - key: OUTPUT_LABEL
        sync: false
```

- [ ] **Step 4: .env.example**

Create `.env.example`:

```
GOOGLE_API_KEY=
BASIC_AUTH_USER=
BASIC_AUTH_PASSWORD=
OUTPUT_LABEL=Andreia Eslava
```

- [ ] **Step 5: Build the image to verify it is valid**

Run: `docker build -t geofixer .`
Expected: build succeeds. (If Docker is unavailable in this environment, skip with a note; the Dockerfile is still reviewed.)

- [ ] **Step 6: Commit**

```bash
git add Dockerfile .dockerignore render.yaml .env.example
git commit -m "Containerize and add Render blueprint

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 10: Docs

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Rewrite the README**

Replace the "O que ele faz" / cron sections so they describe the web flow. Required content:
- The app is a web page where you upload an `.xlsx` and download the corrected `.csv` + log.
- Local run: `cp .env.example .env`, fill it in, `bundle exec puma -C config/puma.rb config.ru`, open `http://localhost:3000`.
- Deploy: push to a repo connected to Render as a Docker web service (or use `render.yaml`); set `GOOGLE_API_KEY`, `BASIC_AUTH_USER`, `BASIC_AUTH_PASSWORD` (and optional `OUTPUT_LABEL`).
- Note that it is a single free Render web service that sleeps when idle.

- [ ] **Step 2: Commit**

```bash
git add README.md
git commit -m "Rewrite README for the web upload flow

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Final verification

- [ ] Run `bundle exec rspec --format progress` → all pass, 0 failures.
- [ ] Confirm no remaining references to the Drive/cron stack: `grep -rn "google_drive\|GoogleDrive\|googleauth\|HTTParty" app web spec` returns nothing.
- [ ] Push: `git push origin main`.
