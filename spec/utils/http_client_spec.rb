# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Utils::HttpClient do
  let(:url) { 'https://example.com/api/resource' }

  before { allow(Utils::Logger).to receive(:warn) }

  describe '.get_json' do
    it 'returns the parsed JSON body on a successful response' do
      stub_request(:get, url)
        .to_return(status: 200, body: { 'street' => 'Rua A' }.to_json,
                   headers: { 'Content-Type' => 'application/json' })

      expect(described_class.get_json(url)).to eq({ 'street' => 'Rua A' })
    end

    it 'parses JSON arrays as well as objects' do
      stub_request(:get, url).to_return(status: 200, body: [{ 'a' => 1 }].to_json)

      expect(described_class.get_json(url)).to eq([{ 'a' => 1 }])
    end

    it 'returns nil on a non-success HTTP status' do
      stub_request(:get, url).to_return(status: 500, body: 'oops')

      expect(described_class.get_json(url)).to be_nil
    end

    it 'returns nil when the body is not valid JSON' do
      stub_request(:get, url).to_return(status: 200, body: 'not json')

      expect(described_class.get_json(url)).to be_nil
    end

    it 'sets open and read timeouts on the request' do
      stub_request(:get, url).to_return(status: 200, body: '{}')
      fake_http = instance_spy(Net::HTTP, get: instance_double(Net::HTTPOK, body: '{}', is_a?: true))
      allow(Net::HTTP).to receive(:new).and_return(fake_http)

      described_class.get_json(url, timeout: 7)

      expect(fake_http).to have_received(:open_timeout=).with(7)
      expect(fake_http).to have_received(:read_timeout=).with(7)
    end

    it 'retries on a timeout and succeeds on a later attempt' do
      stub_request(:get, url)
        .to_timeout.then
        .to_return(status: 200, body: { 'ok' => true }.to_json)

      expect(described_class.get_json(url, retries: 1)).to eq({ 'ok' => true })
    end

    it 'returns nil after exhausting retries on persistent timeouts' do
      stub_request(:get, url).to_timeout

      expect(described_class.get_json(url, retries: 2)).to be_nil
      expect(Utils::Logger).to have_received(:warn).with(/failed after 3 attempts/)
    end
  end
end
