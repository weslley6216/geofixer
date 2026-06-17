# frozen_string_literal: true

require 'spec_helper'
require 'timeout'
require_relative '../../web/job_queue'
require_relative '../../web/job_registry'

RSpec.describe JobQueue do
  let(:registry) { JobRegistry.new }

  def wait_until
    Timeout.timeout(2) { sleep(0.01) until yield }
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
    allow(Utils::Logger).to receive(:warn)
    runner = double('runner')
    allow(runner).to receive(:run).and_raise('boom')
    queue = described_class.new(registry, runner)
    registry.create('job2')

    queue.enqueue('job2', '/tmp/job2')
    wait_until { registry.fetch('job2').status == :failed }

    expect(registry.fetch('job2').error).to eq('boom')
  end
end
