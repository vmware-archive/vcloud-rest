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
        items[item['name']] = item['href'].gsub("#{@api_url}/catalogItem/", "")
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

      items = {}
      response.css("Entity[type='application/vnd.vmware.vcloud.vAppTemplate+xml']").each do |item|
        items[item['name']] = item['href'].gsub("#{@api_url}/vAppTemplate/vappTemplate-", "")
      end
      { :description => description, :items => items }
    end

    ##
    # friendly helper method to fetch an catalogItem  by name
    # - catalogId (use get_catalog_name(org, name))
    # - catalagItemName
    def get_catalog_item_by_name(catalogId, catalogItemName)
      result = nil
      catalogElems = get_catalog(catalogId)

      catalogElems[:items].each do |catalogElem|

        catalogItem = get_catalog_item(catalogElem[1])
        if catalogItem[:items][catalogItemName]
          # This is a vApp Catalog Item

          # fetch CatalogItemId
          catalogItemId = catalogItem[:items][catalogItemName]

          # Fetch the catalogItemId information
          params = {
            'method' => :get,
            'command' => "/vAppTemplate/vappTemplate-#{catalogItemId}"
          }
          response, headers = send_request(params)

          # VMs Hash for all the vApp VM entities
          vms_hash = {}
          response.css("/VAppTemplate/Children/Vm").each do |vmElem|
            vmName = vmElem["name"]
            vmId = vmElem["href"].gsub("#{@api_url}/vAppTemplate/vm-", "")

            # Add the VM name/id to the VMs Hash
            vms_hash[vmName] = { :id => vmId }
          end
        result = { catalogItemName => catalogItemId, :vms_hash => vms_hash }
        end
      end
      result
    end
  end
end