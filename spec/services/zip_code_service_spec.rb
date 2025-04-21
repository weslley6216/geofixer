# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ZipCodeService do
  let(:zip_code) { '09856280' }
  let(:cache) { {} }
  let(:mock_viacep_response) do
    {
      'cep' => '09856-280',
      'logradouro' => 'Rua Colméias',
      'complemento' => '(Jd João de Barros)',
      'unidade' => '',
      'bairro' => 'Alvarenga',
      'localidade' => 'São Bernardo do Campo',
      'uf' => 'SP',
      'estado' => 'São Paulo',
      'regiao' => 'Sudeste',
      'ibge' => '3548708',
      'gia' => '6350',
      'ddd' => '11',
      'siafi' => '7075'
    }
  end
  let(:street_name) { 'Rua Colméias' }
  let(:city) { 'São Bernardo do Campo' }
  let(:normalized_street_name) { 'rua colmeias' }
  let(:encoded_street_name) { 'rua%20colmeias' }
  let(:mock_viacep_search_response) do
    [
      {
        'cep' => '09856-280',
        'logradouro' => 'Rua Colméias',
        'complemento' => '(Jd João de Barros)',
        'bairro' => 'Alvarenga',
        'localidade' => 'São Bernardo do Campo',
        'uf' => 'SP',
        'ibge' => '3548708',
        'gia' => '6350',
        'ddd' => '11',
        'siafi' => '7075'
      },
      {
        'cep' => '01000-000',
        'logradouro' => 'Rua Colméias',
        'complemento' => '(Outro Bairro)',
        'bairro' => 'Centro',
        'localidade' => 'São Paulo',
        'uf' => 'SP',
        'ibge' => '3550308',
        'gia' => '1004',
        'ddd' => '11',
        'siafi' => '6115'
      }
    ]
  end

  before do
    cache.clear
    allow(Utils::Logger).to receive(:info)
  end

  describe '.fetch_street_name_from_zip_code' do
    context 'when the zip code is in the cache' do
      before do
        cache[zip_code] = { street_name: street_name, city: city }
      end

      it 'returns the cached street name and city' do
        result = ZipCodeService.fetch_street_name_from_zip_code(zip_code, cache)
        expect(result).to eq({ street_name: street_name, city: city })
      end

      it 'does not make an HTTP request to ViaCEP' do
        expect(HTTParty).not_to receive(:get)
        ZipCodeService.fetch_street_name_from_zip_code(zip_code, cache)
      end
    end

    context 'when the zip code is not in the cache' do
      before do
        stub_request(:get, "https://viacep.com.br/ws/#{zip_code}/json/")
          .to_return(status: 200, body: mock_viacep_response.to_json, headers: { 'Content-Type' => 'application/json' })
      end

      it 'makes an HTTP request to ViaCEP with the correct zip code' do
        ZipCodeService.fetch_street_name_from_zip_code(zip_code, cache)
        expect(WebMock).to have_requested(:get, "https://viacep.com.br/ws/#{zip_code}/json/")
      end

      it 'parses the response and returns the street name and city' do
        result = ZipCodeService.fetch_street_name_from_zip_code(zip_code, cache)
        expect(result).to eq({ street_name: street_name, city: city })
      end

      it 'stores the street name and city in the cache' do
        ZipCodeService.fetch_street_name_from_zip_code(zip_code, cache)
        expect(cache[zip_code]).to eq({ street_name: street_name, city: city })
      end
    end

    context 'when ViaCEP returns an error' do
      before do
        stub_request(:get, "https://viacep.com.br/ws/#{zip_code}/json/")
          .to_return(status: 400, body: { 'erro' => true }.to_json, headers: { 'Content-Type' => 'application/json' })
      end

      it 'returns nil' do
        result = ZipCodeService.fetch_street_name_from_zip_code(zip_code, cache)
        expect(result).to be_nil
      end

      it 'does not store anything in the cache' do
        ZipCodeService.fetch_street_name_from_zip_code(zip_code, cache)
        expect(cache).to be_empty
      end
    end

    context 'when ViaCEP returns a 200 but with an error key (zip code not found)' do
      before do
        stub_request(:get, "https://viacep.com.br/ws/#{zip_code}/json/")
          .to_return(status: 200, body: { 'erro' => true }.to_json, headers: { 'Content-Type' => 'application/json' })
      end

      it 'returns nil' do
        result = ZipCodeService.fetch_street_name_from_zip_code(zip_code, cache)
        expect(result).to be_nil
      end

      it 'does not store anything in the cache' do
        ZipCodeService.fetch_street_name_from_zip_code(zip_code, cache)
        expect(cache).to be_empty
      end
    end
  end

  describe '.fetch_zip_code_by_street_name' do
    before do
      allow_any_instance_of(AddressNormalizerService).to receive(:clean_street_name).and_return('Rua Colméias')
      allow_any_instance_of(AddressNormalizerService).to receive(:remove_accents).with('Rua Colméias').and_return('Rua Colmeias')
      allow_any_instance_of(AddressNormalizerService).to receive(:remove_accents).with('rua colméias').and_return('rua colméias')
      stub_request(:get, "https://viacep.com.br/ws/SP/#{URI.encode_www_form_component(city)}/#{encoded_street_name}/json/")
        .to_return(status: 200, body: mock_viacep_search_response.to_json, headers: { 'Content-Type' => 'application/json' })
    end

    it 'makes an HTTP request to ViaCEP with the correct URL' do
      ZipCodeService.fetch_zip_code_by_street_name(street_name, city)
      expect(WebMock).to have_requested(:get, "https://viacep.com.br/ws/SP/#{URI.encode_www_form_component(city)}/#{encoded_street_name}/json/")
    end

    it 'returns the first street data that includes the cleaned street name (case-insensitive and accent-insensitive)' do
      result = ZipCodeService.fetch_zip_code_by_street_name(street_name, city)

      expect(result).to eq(mock_viacep_search_response)
    end

    context 'when no matching street is found' do
      before do
        stub_request(:get, /viacep\.com\.br/).to_return(status: 200, body: [].to_json,
                                                        headers: { 'Content-Type' => 'application/json' })
      end

      it 'returns nil' do
        result = ZipCodeService.fetch_zip_code_by_street_name('Nonexistent Street', city)

        expect(result).to be_empty
      end
    end

    context 'when ViaCEP returns an error' do
      before do
        stub_request(:get, /viacep\.com\.br/).to_return(status: 400, body: { 'erro' => true }.to_json,
                                                        headers: { 'Content-Type' => 'application/json' })
      end

      it 'returns nil' do
        result = ZipCodeService.fetch_zip_code_by_street_name(street_name, city)

        expect(result).to be_nil
      end
    end
  end
end
