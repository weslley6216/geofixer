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
