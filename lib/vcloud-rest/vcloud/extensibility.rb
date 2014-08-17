module VCloudClient
  class Connection
    def get_extensibility
      params = {
        'method' => :get,
        'command' => "/extensibility"
      }

      response, headers = send_request(params)

      down_service = response.css("Link[@rel='down:service']").first['href']
      down_apidefinitions = response.css("Link[@rel='down:apidefinitions']").first['href']
      down_files = response.css("Link[@rel='down:files']").first['href']

      {
        :down_service => down_service,
        :down_apidefinitions => down_apidefinitions,
        :down_files => down_files,
      }
    end
  end
end
