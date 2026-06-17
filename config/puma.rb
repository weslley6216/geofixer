# frozen_string_literal: true

port ENV.fetch('PORT', 3000)
environment ENV.fetch('RACK_ENV', 'development')

# Single process so the in-memory JobRegistry and the worker thread are shared
# by every request.
workers 0
threads 1, 5
