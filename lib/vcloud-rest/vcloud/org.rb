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
    # - task lists
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

    ##
    # Fetch tasks from a given task list
    #
    # Note: id can be retrieved using get_organization
    def get_tasks_list(id)
      params = {
        'method' => :get,
        'command' => "/tasksList/#{id}"
      }

      response, headers = send_request(params)

      tasks = []

      response.css('Task').each do |task|
        id = task['href'].gsub(/.*\/task\//, "")
        operation = task['operationName']
        status = task['status']
        error = nil
        error = task.css('Error').first['message'] if task['status'] == 'error'
        start_time = task['startTime']
        end_time = task['endTime']
        user_canceled = task['cancelRequested'] == 'true'

        tasks << {
          :id => id,
          :operation => operation,
          :status => status,
          :error => error,
          :start_time => start_time,
          :end_time => end_time,
          :user_canceled => user_canceled
         }
      end
      tasks
    end

    ##
    # Cancel a given task
    #
    # The task will be marked for cancellation
    def cancel_task(id)
      params = {
        'method' => :post,
        'command' => "/task/#{id}/action/cancel"
      }

      # Nothing useful is returned here
      # If return code is 20x return true
      send_request(params)
      true
    end
  end
end