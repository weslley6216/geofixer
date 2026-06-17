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
