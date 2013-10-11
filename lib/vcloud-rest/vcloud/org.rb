module VCloudClient
  class Connection
    ##
    # Fetch existing organizations and their IDs
    def get_organizations
      params = {
        'method' => :get,
        'command' => '/org'
      }

      response, headers = send_request(params)
      orgs = response.css('OrgList Org')

      results = {}
      orgs.each do |org|
        results[org['name']] = org['href'].gsub(/.*\/org\//, "")
      end
      results
    end

    ##
    # friendly helper method to fetch an Organization Id by name
    # - name (this isn't case sensitive)
    def get_organization_id_by_name(name)
      result = nil

      # Fetch all organizations
      organizations = get_organizations()

      organizations.each do |organization|
        if organization[0].downcase == name.downcase
          result = organization[1]
        end
      end
      result
    end


    ##
    # friendly helper method to fetch an Organization by name
    # - name (this isn't case sensitive)
    def get_organization_by_name(name)
      result = nil

      # Fetch all organizations
      organizations = get_organizations()

      organizations.each do |organization|
        if organization[0].downcase == name.downcase
          result = get_organization(organization[1])
        end
      end
      result
    end

    ##
    # Fetch details about an organization:
    # - catalogs
    # - vdcs
    # - networks
    def get_organization(orgId)
      params = {
        'method' => :get,
        'command' => "/org/#{orgId}"
      }

      response, headers = send_request(params)
      catalogs = {}
      response.css("Link[type='application/vnd.vmware.vcloud.catalog+xml']").each do |item|
        catalogs[item['name']] = item['href'].gsub(/.*\/catalog\//, "")
      end

      vdcs = {}
      response.css("Link[type='application/vnd.vmware.vcloud.vdc+xml']").each do |item|
        vdcs[item['name']] = item['href'].gsub(/.*\/vdc\//, "")
      end

      networks = {}
      response.css("Link[type='application/vnd.vmware.vcloud.orgNetwork+xml']").each do |item|
        networks[item['name']] = item['href'].gsub(/.*\/network\//, "")
      end

      tasklists = {}
      response.css("Link[type='application/vnd.vmware.vcloud.tasksList+xml']").each do |item|
        tasklists[item['name']] = item['href'].gsub(/.*\/tasksList\//, "")
      end

      { :catalogs => catalogs, :vdcs => vdcs, :networks => networks, :tasklists => tasklists }
    end
  end
end