require_relative 'support/spec_helper'

describe VCloudClient::Connection do
  let(:vcloud_params) { credentials }

  let(:auth_string) {
    "#{vcloud_params[:username]}%40#{vcloud_params[:org]}:#{vcloud_params[:password]}"
  }

  let(:base_url) { extract_host(vcloud_params[:host]) }

  let(:connection) {
    VCloudClient::Connection.new(vcloud_params[:host], vcloud_params[:username],
                                vcloud_params[:password], vcloud_params[:org],
                                vcloud_params[:api_version])
  }

  describe "Extensibility" do
    it "gets" do
      VCR.use_cassette('extensibility/extensibility') do
        connection.login
        extensions = connection.get_extensibility

        expect(extensions[:down_service]).to eq("https://cloud.ipcoop.com/api/service")
        expect(extensions[:down_apidefinitions]).to eq("https://cloud.ipcoop.com/api/apidefinitions")
        expect(extensions[:down_files]).to eq("https://cloud.ipcoop.com/api/files")
      end
    end
  end
end
