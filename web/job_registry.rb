# frozen_string_literal: true

require 'monitor'

# Thread-safe in-memory map of job id -> Job. Holds the lifecycle status and
# the result file paths. No persistence: jobs are transient.
class JobRegistry
  Job = Struct.new(:id, :status, :csv_path, :log_path, :error, :created_at, :processed, :total,
                   keyword_init: true)

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
