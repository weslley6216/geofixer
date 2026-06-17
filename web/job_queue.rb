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
    csv_path, log_path = @runner.run(dir) do |processed, total|
      @registry.update(job_id, processed: processed, total: total)
    end
    @registry.update(job_id, status: :done, csv_path: csv_path, log_path: log_path)
  rescue StandardError => e
    Utils::Logger.warn("Job #{job_id} failed: #{e.message}")
    @registry.update(job_id, status: :failed, error: e.message)
  end
end
