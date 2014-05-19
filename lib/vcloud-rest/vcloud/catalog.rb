module VCloudClient
  class Connection
    ##
    # Fetch details about a given catalog
    def get_catalog(catalogId)
      params = {
        'method' => :get,
        'command' => "/catalog/#{catalogId}"
      }

      response, headers = send_request(params)
      description = response.css("Description").first
      description = description.text unless description.nil?

      items = {}
      response.css("CatalogItem[type='application/vnd.vmware.vcloud.catalogItem+xml']").each do |item|
        items[item['name']] = item['href'].gsub(/.*\/catalogItem\//, "")
      end
      { :id => catalogId, :description => description, :items => items }
    end

    ##
    # Friendly helper method to fetch an catalog id by name
    # - organization hash (from get_organization/get_organization_by_name)
    # - catalog name
    def get_catalog_id_by_name(organization, catalogName)
      result = nil

      organization[:catalogs].each do |catalog|
        if catalog[0].downcase == catalogName.downcase
          result = catalog[1]
        end
      end

      result
    end

    ##
    # Friendly helper method to fetch an catalog by name
    # - organization hash (from get_organization/get_organization_by_name)
    # - catalog name
    def get_catalog_by_name(organization, catalogName)
      result = nil

      organization[:catalogs].each do |catalog|
        if catalog[0].downcase == catalogName.downcase
          result = get_catalog(catalog[1])
        end
      end

      result
    end

    ##
    # Fetch details about a given catalog item:
    # - description
    # - vApp templates
    def get_catalog_item(catalogItemId)
      params = {
        'method' => :get,
        'command' => "/catalogItem/#{catalogItemId}"
      }

      response, headers = send_request(params)
      description = response.css("Description").first
      description = description.text unless description.nil?

      items = []
      # manage two different types of catalog items: vAppTemplate and media
      if response.css("Entity[type='application/vnd.vmware.vcloud.vAppTemplate+xml']").length > 0
        response.css("Entity[type='application/vnd.vmware.vcloud.vAppTemplate+xml']").each do |item|
          itemId = item['href'].gsub(/.*\/vAppTemplate\/vappTemplate\-/, "")

          # Fetch the catalogItemId information
          params = {
            'method' => :get,
            'command' => "/vAppTemplate/vappTemplate-#{itemId}"
          }
          response, headers = send_request(params)

          # VMs Hash for all the vApp VM entities
          vms_hash = {}
          response.css("/VAppTemplate/Children/Vm").each do |vmElem|
            vmName = vmElem["name"]
            vmId = vmElem["href"].gsub(/.*\/vAppTemplate\/vm\-/, "")

            # Add the VM name/id to the VMs Hash
            vms_hash[vmName] = { :id => vmId }
          end

          items << { :id => itemId,
                     :name => item['name'],
                     :vms_hash => vms_hash }
        end
        return { :id => catalogItemId, :description => description, :items => items, :type => 'vAppTemplate' }
      elsif response.css("Entity[type='application/vnd.vmware.vcloud.media+xml']").length > 0
        name = response.css("Entity[type='application/vnd.vmware.vcloud.media+xml']").first['name']
        return { :id => catalogItemId, :description => description, :name => name, :type => 'media' }
      else
        @logger.warn 'WARNING: either this catalog item is empty or contains something not managed by vcloud-rest'
        return { :id => catalogItemId, :description => description, :type => 'unknown' }
    end

    ##
    # friendly helper method to fetch an catalogItem  by name
    # - catalogId (use get_catalog_name(org, name))
    # - catalagItemName
    def get_catalog_item_by_name(catalogId, catalogItemName)
      result = nil
      catalogElems = get_catalog(catalogId)

      catalogElems[:items].each do |k, v|
        if (k.downcase == catalogItemName.downcase)
          result = get_catalog_item(v)
        end
      end

      result
    end
  end
end