# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ZipCodeService do
  let(:zip_code) { '09856280' }
  let(:street_name) { 'Rua Colméias' }
  let(:city) { 'São Bernardo do Campo' }
  let(:uf) { 'SP' }
  let(:mock_viacep_response) do
    {
      'cep' => '09856-280',
      'logradouro' => 'Rua Colméias',
      'bairro' => 'Alvarenga',
      'localidade' => 'São Bernardo do Campo',
      'uf' => 'SP'
    }
  end
  let(:mock_viacep_search_response) do
    [
      { 'cep' => '09856-280', 'logradouro' => 'Rua Colméias', 'localidade' => 'São Bernardo do Campo', 'uf' => 'SP' }
    ]
  end

  before { allow(Utils::Logger).to receive(:info) }

  describe '.fetch_street_name_from_zip_code' do
    context 'when ViaCEP returns the address' do
      before do
        stub_request(:get, "https://viacep.com.br/ws/#{zip_code}/json/")
          .to_return(status: 200, body: mock_viacep_response.to_json,
                     headers: { 'Content-Type' => 'application/json' })
      end

      it 'requests ViaCEP with the given zip code' do
        ZipCodeService.fetch_street_name_from_zip_code(zip_code)
        expect(WebMock).to have_requested(:get, "https://viacep.com.br/ws/#{zip_code}/json/")
      end

      it 'returns the street name, city and uf' do
        result = ZipCodeService.fetch_street_name_from_zip_code(zip_code)
        expect(result).to eq({ street_name: street_name, city: city, uf: uf })
      end
    end

    context 'when ViaCEP returns an HTTP error' do
      before do
        stub_request(:get, "https://viacep.com.br/ws/#{zip_code}/json/")
          .to_return(status: 400, body: { 'erro' => true }.to_json)
      end

      it 'returns nil' do
        expect(ZipCodeService.fetch_street_name_from_zip_code(zip_code)).to be_nil
      end
    end

    context 'when ViaCEP returns 200 with an error flag (zip code not found)' do
      before do
        stub_request(:get, "https://viacep.com.br/ws/#{zip_code}/json/")
          .to_return(status: 200, body: { 'erro' => true }.to_json,
                     headers: { 'Content-Type' => 'application/json' })
      end

      it 'returns nil' do
        expect(ZipCodeService.fetch_street_name_from_zip_code(zip_code)).to be_nil
      end
    end
  end

  describe '.fetch_zip_code_by_street_name' do
    before do
      stub_request(:get, %r{viacep\.com\.br/ws/})
        .to_return(status: 200, body: mock_viacep_search_response.to_json,
                   headers: { 'Content-Type' => 'application/json' })
    end

    it 'requests ViaCEP using the provided uf (not a hardcoded state)' do
      ZipCodeService.fetch_zip_code_by_street_name(street_name, 'Rio de Janeiro', 'RJ')
      expect(WebMock).to have_requested(:get, %r{viacep\.com\.br/ws/RJ/})
    end

    it 'returns the parsed street data on success' do
      result = ZipCodeService.fetch_zip_code_by_street_name(street_name, city, uf)
      expect(result).to eq(mock_viacep_search_response)
    end

    context 'when no matching street is found' do
      before do
        stub_request(:get, %r{viacep\.com\.br/ws/}).to_return(status: 200, body: [].to_json,
                                                              headers: { 'Content-Type' => 'application/json' })
      end

      it 'returns an empty array' do
        result = ZipCodeService.fetch_zip_code_by_street_name('Nonexistent Street', city, uf)
        expect(result).to be_empty
      end
    end

    context 'when ViaCEP returns an error' do
      before do
        stub_request(:get, %r{viacep\.com\.br/ws/}).to_return(status: 400, body: { 'erro' => true }.to_json)
      end

      it 'returns nil' do
        expect(ZipCodeService.fetch_zip_code_by_street_name(street_name, city, uf)).to be_nil
      end
    end
  end
end
