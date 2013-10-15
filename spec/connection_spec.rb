## Support for 1.8.x
unless Kernel.respond_to?(:require_relative)
  module Kernel
    def require_relative(path)
      require File.join(File.dirname(caller[0]), path.to_str)
    end
  end
end
##

require 'minitest/autorun'
require 'minitest/spec'
require 'webmock/minitest'
require_relative '../lib/vcloud-rest/connection'

describe VCloudClient::Connection do
  before do
    @args = {:host => 'https://testhost.local',
            :username => 'testuser',
            :password => 'testpass',
            :org => 'testorg',
            :api_version => "5.1"}

    @connection = VCloudClient::Connection.new(@args[:host], @args[:username],
                                          @args[:password], @args[:org], @args[:api_version])
  end

  describe "correct initialization" do
    it "cannot be created with no arguments" do
      lambda {
        VCloudClient::Connection.new
      }.must_raise ArgumentError
    end

    it "must be created with at least 4 arguments" do
      VCloudClient::Connection.new(@args[:host], @args[:username], @args[:password],
                                  @args[:org], @args[:api_version]).must_be_instance_of VCloudClient::Connection
    end

    it "must construct the correct api url" do
      @connection.api_url.must_equal "https://testhost.local/api"
    end
  end

  describe "supported APIs" do
    [:login, :logout, :get_organizations, :get_organization,
     :get_vdc, :get_catalog, :get_catalog_item, :get_vapp,
     :delete_vapp, :poweroff_vapp, :poweron_vapp,
     :create_vapp_from_template].each do |method|
      it "must respond to #{method}" do
        @connection.must_respond_to method
      end
    end

    [:send_request, :convert_vapp_status].each do |method|
      it "must not respond to #{method}" do
        @connection.wont_respond_to method
      end
    end
  end

  describe "check status" do
    it "should return correct status for existing codes" do
      @connection.send(:convert_vapp_status, 8).must_equal "stopped"
    end

    it "should return a default for unexisting codes" do
      @connection.send(:convert_vapp_status, 999).must_equal "Unknown 999"
    end
  end

  describe "login" do
    before { @url = "https://testuser%40testorg:testpass@testhost.local/api/sessions" }

    it "should send the correct Accept header for API version 5.1 (default)" do
      stub_request(:post, @url).
        with(:headers => {'Accept'=>'application/*+xml;version=5.1'}).
        to_return(:status => 200, :body => "", :headers => {:x_vcloud_authorization => "test_auth_code"})

      @connection.login
    end

    it "should send the correct Accept header for API version 1.5" do
      stub_request(:post, @url).
        with(:headers => {'Accept'=>'application/*+xml;version=1.5'}).
        to_return(:status => 200, :body => "", :headers => {:x_vcloud_authorization => "test_auth_code"})

      connection = VCloudClient::Connection.new(@args[:host], @args[:username], @args[:password],
                                    @args[:org], "1.5")
      connection.login
    end

    it "should handle correctly a success response" do
      stub_request(:post, @url).
        to_return(:status => 200, :body => "", :headers => {:x_vcloud_authorization => "test_auth_code"})

      @connection.login
      @connection.auth_key.wont_be_nil
    end

    it "should handle correctly a success response with empty headers" do
      stub_request(:post, @url).
        to_return(:status => 200, :body => "", :headers => {})

      lambda {
        @connection.login
      }.must_raise RuntimeError
    end

    it "should raise an exception for unauthorized access" do
      stub_request(:post, @url).
        to_return(:status => 401, :body => "", :headers => {})

      lambda {
        @connection.login
      }.must_raise VCloudClient::UnauthorizedAccess
    end
  end

  describe "list organizations" do
    before { @url = "https://testuser%40testorg:testpass@testhost.local/api/org" }

    it "should return the correct no. of organizations - 0" do
      stub_request(:get, @url).
        to_return(:status => 200,
         :body => "",
         :headers => {})

      @connection.get_organizations.count.must_equal 0
    end

    it "should return the correct no. of organizations - 1" do
      stub_request(:get, @url).
        to_return(:status => 200,
         :body => "<OrgList><Org href='https://testhost.local/api/org/test-org-url' name='test-org'></Org></OrgList>",
         :headers => {})

      orgs = @connection.get_organizations
      orgs.count.must_equal 1
      orgs.must_be_kind_of Hash
      orgs.first.must_equal ['test-org', 'test-org-url']
    end


    it "should return only the organisation id as a value" do
      stub_request(:get, @url).
          to_return(:status => 200,
                    :body => "<OrgList><Org href='https://testhost.local/api/org/test-org-url' name='test-org'></Org></OrgList>",
                    :headers => {})

      orgs = @connection.get_organizations
      orgs.values.first.must_match(/^(\w+-)+\w+$/)
    end
  end

  describe "get organization" do
    before { @url = "https://testuser%40testorg:testpass@testhost.local/api/org/test-org" }

    it "should return the correct no. of organizations - 1" do
      stub_request(:get, @url).
        to_return(:status => 200,
         :body => "<Link type='application/vnd.vmware.vcloud.catalog+xml' name='catalog_1' href='#{@connection.api_url}/catalog/catalog_1-url'></Link>",
         :headers => {})

      catalog_get = @connection.get_organization("test-org")
      catalog_get[:catalogs].count.must_equal 1
      catalog_get[:catalogs].first.must_equal ["catalog_1", "catalog_1-url"]
    end

    it "should return the correct no. of vdcs - 1" do
      stub_request(:get, @url).
        to_return(:status => 200,
         :body => "<Link type='application/vnd.vmware.vcloud.vdc+xml' name='vdc_1' href='#{@connection.api_url}/vdc/vdc_1-url'></Link>",
         :headers => {})

      vdcs_get = @connection.get_organization("test-org")
      vdcs_get[:vdcs].count.must_equal 1
      vdcs_get[:vdcs].first.must_equal ["vdc_1", "vdc_1-url"]
    end

    it "should return the correct no. of networks - 1" do
      stub_request(:get, @url).
        to_return(:status => 200,
         :body => "<Link type='application/vnd.vmware.vcloud.orgNetwork+xml' name='network_1' href='#{@connection.api_url}/network/network_1-url'></Link>",
         :headers => {})

      networks_get = @connection.get_organization("test-org")
      networks_get[:networks].count.must_equal 1
      networks_get[:networks].first.must_equal ["network_1", "network_1-url"]
    end
  end

  describe "show catalog" do
    before { @url = "https://testuser%40testorg:testpass@testhost.local/api/catalog/test-catalog" }

    it "should return the correct no. of catalog items - 0" do
      stub_request(:get, @url).
        to_return(:status => 200,
         :body => "",
         :headers => {})

      catalog_get = @connection.get_catalog("test-catalog")
      catalog_get[:items].count.must_equal 0
    end

    it "should return the correct no. of catalog items - 1" do
      stub_request(:get, @url).
        to_return(:status => 200,
         :body => "<CatalogItem type='application/vnd.vmware.vcloud.catalogItem+xml' name='catalog_item_1' href='#{@connection.api_url}/catalogItem/catalog_item_1-url'></CatalogItem>",
         :headers => {})

      catalog_get = @connection.get_catalog("test-catalog")
      catalog_get[:items].first.must_equal ["catalog_item_1", "catalog_item_1-url"]
    end
  end

  describe "show vdc" do
    before { @url = "https://testuser%40testorg:testpass@testhost.local/api/vdc/test-vdc" }

    it "should return the correct no. of vapps - 1" do
      stub_request(:get, @url).
        to_return(:status => 200,
         :body => "<Vdc name='test-vdc'>
                    <ResourceEntity type='application/vnd.vmware.vcloud.vApp+xml'
                    name='vapp_1'
                    href='#{@connection.api_url}/vApp/vapp-vapp_1-url'>
                    </ResourceEntity>
                  </Vdc>",
         :headers => {})

      vdc_get = @connection.get_vdc("test-vdc")
      vdc_get[:vapps].first.must_equal ["vapp_1", "vapp_1-url"]
    end
  end

  describe "show catalog item" do
    before { @url = "https://testuser%40testorg:testpass@testhost.local/api/catalogItem/test-cat-item" }

    it "should return the correct no. of vapp templates - 1" do
      stub_request(:get, @url).
        to_return(:status => 200,
         :body => "<Entity type='application/vnd.vmware.vcloud.vAppTemplate+xml' name='vapp_templ_1' href='#{@connection.api_url}/vAppTemplate/vappTemplate-vapp_templ_1-url'></CatalogItem>",
         :headers => {})

      stub_request(:get, "https://testuser%40testorg:testpass@testhost.local/api/vAppTemplate/vappTemplate-vapp_templ_1-url").
          with(:headers => {'Accept'=>'application/*+xml;version=5.1', 'Accept-Encoding'=>'gzip, deflate', 'User-Agent'=>'Ruby'}).
          to_return(:status => 200, :body => "", :headers => {})

      catalog_item_get = @connection.get_catalog_item("test-cat-item")
      catalog_item_get[:items].first[:id].must_equal "vapp_templ_1-url"
      catalog_item_get[:items].first[:name].must_equal "vapp_templ_1"
    end
  end

  describe "show vapp" do
    before { @url = "https://testuser%40testorg:testpass@testhost.local/api/vApp/vapp-test-vapp" }

    it "should return the correct status" do
      stub_request(:get, @url).
        to_return(:status => 200,
         :body => "<VApp name='test-vapp' status='4'></VApp>",
         :headers => {})

      vapp_get = @connection.get_vapp("test-vapp")
      vapp_get[:name].must_equal "test-vapp"
    end

    it "should return the correct status" do
      stub_request(:get, @url).
        to_return(:status => 200,
         :body => "<VApp name='test-vapp' status='4'></VApp>",
         :headers => {})

      vapp_get = @connection.get_vapp("test-vapp")
      vapp_get[:status].must_equal "running"
    end

    it "should return the correct IP" do
      stub_request(:get, @url).
        to_return(:status => 200,
         :body => "<VApp name='test-vapp'><IpAddress>127.0.0.1</IpAddress></VApp>",
         :headers => {})

      vapp_get = @connection.get_vapp("test-vapp")
      vapp_get[:ip].must_equal "127.0.0.1"
    end

    it "should return the correct no. of VMs - 1" do
      stub_request(:get, @url).
        to_return(:status => 200,
         :body => "<?xml version=\"1.0\" ?><VApp xmlns=\"http://www.vmware.com/vcloud/v1.5\" xmlns:rasd=\"http://schemas.dmtf.org/wbem/wscim/1/cim-schema/2/CIM_ResourceAllocationSettingData\"><Children><Vm name='vm_1' status='4' href='#{@connection.api_url}/vApp/vm-vm_1'><rasd:Connection vcloud:ipAddress='127.0.0.1'></rasd:Connection></Vm></Children></VApp>",
         :headers => {})

      vapp_get = @connection.get_vapp("test-vapp")
      vapp_get[:vms_hash].count.must_equal 1
      vapp_get[:vms_hash].first.must_equal ["vm_1", {:addresses=>["127.0.0.1"], :status=>"running", :id=>"vm_1", :vapp_scoped_local_id => ""}]
    end
  end

  describe "delete vapp" do
    before { @url = "https://testuser%40testorg:testpass@testhost.local/api/vApp/vapp-test-vapp" }

    it "should send the correct request" do
      stub_request(:delete, @url).
        to_return(:status => 200,
            :headers => {:location => "#{@connection.api_url}/task/test-deletion_task"})

      task_id = @connection.delete_vapp("test-vapp")
      task_id.must_equal "test-deletion_task"
    end
  end

  describe "poweroff vapp" do
    before { @url = "https://testuser%40testorg:testpass@testhost.local/api/vApp/vapp-test-vapp/action/undeploy" }

    it "should send the correct content-type and payload" do
      stub_request(:post, @url).
        with(:body => "<?xml version=\"1.0\"?>\n<UndeployVAppParams xmlns=\"http://www.vmware.com/vcloud/v1.5\">\n  <UndeployPowerAction>powerOff</UndeployPowerAction>\n</UndeployVAppParams>\n",
             :headers => {'Content-Type'=>'application/vnd.vmware.vcloud.undeployVAppParams+xml'}).
        to_return(:status => 200,
             :headers => {:location => "#{@connection.api_url}/task/test-poweroff_task"})

      task_id = @connection.poweroff_vapp("test-vapp")
      task_id.must_equal "test-poweroff_task"
    end
  end

  describe "poweron vapp" do
    before { @url = "https://testuser%40testorg:testpass@testhost.local/api/vApp/vapp-test-vapp/power/action/powerOn" }

    it "should send the correct request" do
      stub_request(:post, @url).
        to_return(:status => 200,
            :headers => {:location => "#{@connection.api_url}/task/test-startup_task"})

      task_id = @connection.poweron_vapp("test-vapp")
      task_id.must_equal "test-startup_task"
    end
  end

  describe "create vapp" do
    before { @url = "https://testuser%40testorg:testpass@testhost.local/api/vdc/vdc_id/action/instantiateVAppTemplate" }

    it "should send the correct content-type and payload" do
      # TODO: this test seems to fail under 1.8.7
      stub_request(:post, @url).
        with(:body => "<?xml version=\"1.0\"?>\n<InstantiateVAppTemplateParams xmlns=\"http://www.vmware.com/vcloud/v1.5\" xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\" xmlns:ovf=\"http://schemas.dmtf.org/ovf/envelope/1\" name=\"vapp_name\" deploy=\"true\" powerOn=\"false\">\n  <Description>vapp_desc</Description>\n  <Source href=\"https://testhost.local/api/vAppTemplate/templ_id\"/>\n</InstantiateVAppTemplateParams>\n",
             :headers => {'Content-Type'=>'application/vnd.vmware.vcloud.instantiateVAppTemplateParams+xml'}).
        to_return(:status => 200, :headers => {:location => "#{@connection.api_url}/vApp/vapp-vapp_created"},
          :body => "<VApp><Task operationName=\"vdcInstantiateVapp\" href=\"#{@connection.api_url}/task/test-task_id\"></VApp>")

      vapp_created = @connection.create_vapp_from_template("vdc_id", "vapp_name", "vapp_desc", "templ_id")
      vapp_created[:vapp_id].must_equal "vapp_created"
      vapp_created[:task_id].must_equal "test-task_id"
    end
  end

  describe "compose vapp from vm" do
    before { @url = "https://testuser%40testorg:testpass@testhost.local/api/vdc/vdc_id/action/composeVApp" }

    it "should send the correct content-type and payload" do
      # TODO: this test seems to fail under 1.8.7
      stub_request(:post, @url).
        with(:body => "<?xml version=\"1.0\"?>\n<ComposeVAppParams xmlns=\"http://www.vmware.com/vcloud/v1.5\" xmlns:ovf=\"http://schemas.dmtf.org/ovf/envelope/1\" name=\"vapp_name\">\n  <Description>vapp_desc</Description>\n  <InstantiationParams>\n    <NetworkConfigSection>\n      <ovf:Info>Configuration parameters for logical networks</ovf:Info>\n      <NetworkConfig networkName=\"vapp_net\">\n        <Configuration>\n          <IpScopes>\n            <IpScope>\n              <IsInherited>false</IsInherited>\n              <Gateway>10.250.254.253</Gateway>\n              <Netmask>255.255.255.0</Netmask>\n              <IpRanges>\n                <IpRange>\n                  <StartAddress>10.250.254.1</StartAddress>\n                  <EndAddress>10.250.254.100</EndAddress>\n                </IpRange>\n              </IpRanges>\n            </IpScope>\n          </IpScopes>\n          <ParentNetwork href=\"https://testhost.local/api/network/guid\"/>\n          <FenceMode>natRouted</FenceMode>\n          <Features>\n            <FirewallService>\n              <IsEnabled>false</IsEnabled>\n            </FirewallService>\n          </Features>\n        </Configuration>\n      </NetworkConfig>\n    </NetworkConfigSection>\n  </InstantiationParams>\n  <SourcedItem>\n    <Source href=\"https://testhost.local/api/vAppTemplate/vm-vm_id\" name=\"vm_name\"/>\n    <InstantiationParams>\n      <NetworkConnectionSection type=\"application/vnd.vmware.vcloud.networkConnectionSection+xml\" href=\"https://testhost.local/api/vAppTemplate/vm-vm_id/networkConnectionSection/\">\n        <ovf:Info>Network config for sourced item</ovf:Info>\n        <PrimaryNetworkConnectionIndex>0</PrimaryNetworkConnectionIndex>\n        <NetworkConnection network=\"vapp_net\">\n          <NetworkConnectionIndex>0</NetworkConnectionIndex>\n          <IsConnected>true</IsConnected>\n          <IpAddressAllocationMode>POOL</IpAddressAllocationMode>\n        </NetworkConnection>\n      </NetworkConnectionSection>\n    </InstantiationParams>\n    <NetworkAssignment containerNetwork=\"vapp_net\" innerNetwork=\"vapp_net\"/>\n  </SourcedItem>\n  <AllEULAsAccepted>true</AllEULAsAccepted>\n</ComposeVAppParams>\n",
       :headers => {'Accept'=>'application/*+xml;version=5.1', 'Accept-Encoding'=>'gzip, deflate', 'Content-Type'=>'application/vnd.vmware.vcloud.composeVAppParams+xml'}).
        to_return(:status => 200, :headers => {:location => "#{@connection.api_url}/vApp/vapp-vapp_created"},
          :body => "<VApp><Task operationName=\"vdcComposeVapp\" href=\"#{@connection.api_url}/task/test-task_id\"></VApp>")


      ## vapp_created = @connection.compose_vapp_from_vm("vdc_id",   "vapp_name", "vapp_desc", "templ_id")
      vapp_created = @connection.compose_vapp_from_vm("vdc_id", "vapp_name", "vapp_desc", { "vm_name" => "vm_id" }, { :name => "vapp_net", :gateway => "10.250.254.253", :netmask => "255.255.255.0", :start_address => "10.250.254.1", :end_address => "10.250.254.100", :fence_mode => "natRouted", :ip_allocation_mode => "POOL", :parent_network =>  "guid", :enable_firewall => "false" })
      vapp_created[:vapp_id].must_equal "vapp_created"
      vapp_created[:task_id].must_equal "test-task_id"
    end
  end

  describe "vapp network config" do
    before { @url = "https://testuser%40testorg:testpass@testhost.local/api/vApp/vapp-test-vapp/networkConfigSection" }

    it "should send the correct content-type and payload" do
      stub_request(:get, "https://testuser%40testorg:testpass@testhost.local/api/vApp/vapp-test-vapp/networkConfigSection").
        to_return(:status => 200,
          :body => "<?xml version=\"1.0\"?>\n<NetworkConfigSection>\n<NetworkConfig networkName=\"test-network\">\n<Description>This is a special place-holder used for disconnected network interfaces.</Description>\n<Configuration>\n<IpScopes>\n<IpScope>\n<IsInherited>true</IsInherited>\n<Gateway>196.254.254.254</Gateway>\n<Netmask>255.255.0.0</Netmask>\n<Dns1>196.254.254.254</Dns1>\n</IpScope>\n</IpScopes><ParentNetwork name=\"guid\" id=\"tst-par\" href=\"https://testhost.local/api/admin/network/tst-par\"/>\n<FenceMode>isolated</FenceMode>\n</Configuration>\n<IsDeployed>false</IsDeployed>\n</NetworkConfig>\n</NetworkConfigSection>\n",
      )

      stub_request(:put, "https://testuser%40testorg:testpass@testhost.local/api/vApp/vapp-test-vapp/networkConfigSection").
        with(:body => "<?xml version=\"1.0\"?>\n<NetworkConfigSection>\n<NetworkConfig networkName=\"test-network\">\n<Description>This is a special place-holder used for disconnected network interfaces.</Description>\n<Configuration>\n<IpScopes>\n<IpScope>\n<IsInherited>true</IsInherited>\n<Gateway>196.254.254.254</Gateway>\n<Netmask>255.255.0.0</Netmask>\n<Dns1>196.254.254.254</Dns1>\n</IpScope>\n</IpScopes><ParentNetwork name=\"guid\" id=\"tst-par\" href=\"https://testhost.local/api/admin/network/tst-par\"/>\n<FenceMode>isolated</FenceMode>\n</Configuration>\n<IsDeployed>false</IsDeployed>\n</NetworkConfig>\n</NetworkConfigSection>\n",
             :headers => {'Accept'=>'application/*+xml;version=5.1', 'Accept-Encoding'=>'gzip, deflate', 'Content-Length'=>'593', 'Content-Type'=>'application/vnd.vmware.vcloud.networkConfigSection+xml', 'User-Agent'=>'Ruby'}).
        to_return(:status => 200, :body => "", :headers => {:location => "#{@connection.api_url}/task/test-vapp_network_task"})

      task_id = @connection.set_vapp_network_config("test-vapp",
                                          {:name => "test-network", :id => 'tst-id'},
                                          { :parent_network => {:name => "guid", :id => 'tst-par'} })
      task_id.must_equal "test-vapp_network_task"
    end

    describe "VApp Edge" do
      it "should retrieve public IP with natRouted and portForwarding" do
        stub_request(:get, @url).
          to_return(:status => 200,
           :body => "<?xml version=\"1.0\" ?><VApp xmlns=\"http://www.vmware.com/vcloud/v1.5\"
           xmlns:rasd=\"http://schemas.dmtf.org/wbem/wscim/1/cim-schema/2/CIM_ResourceAllocationSettingData\">
             <NetworkConfigSection><NetworkConfig><Configuration>
              <FenceMode>natRouted</FenceMode>
              <Features>
                <NatService>
                  <NatType>portForwarding</NatType>
                </NatService>
              </Features>
              <RouterInfo>
                <ExternalIp>10.0.0.1</ExternalIp>
              </RouterInfo>
            </Configuration></NetworkConfig></NetworkConfigSection></VApp>",
           :headers => {})

        edge_id = @connection.get_vapp_edge_public_ip("test-vapp")
        edge_id.must_equal "10.0.0.1"
      end

      it "should raise an exception if not natRouted" do
        stub_request(:get, @url).
          to_return(:status => 200,
           :body => "<?xml version=\"1.0\" ?><VApp xmlns=\"http://www.vmware.com/vcloud/v1.5\"
           xmlns:rasd=\"http://schemas.dmtf.org/wbem/wscim/1/cim-schema/2/CIM_ResourceAllocationSettingData\">
             <NetworkConfigSection><NetworkConfig><Configuration>
              <FenceMode>isolated</FenceMode>
              <Features>
                <NatService>
                  <NatType>portForwarding</NatType>
                </NatService>
              </Features>
              <RouterInfo>
                <ExternalIp>10.0.0.1</ExternalIp>
              </RouterInfo>
            </Configuration></NetworkConfig></NetworkConfigSection></VApp>",
           :headers => {})

        lambda {
          edge_id = @connection.get_vapp_edge_public_ip("test-vapp")
        }.must_raise VCloudClient::InvalidStateError
      end

      it "should raise an exception if NatType is not portForwarding" do
        stub_request(:get, @url).
          to_return(:status => 200,
           :body => "<?xml version=\"1.0\" ?><VApp xmlns=\"http://www.vmware.com/vcloud/v1.5\"
           xmlns:rasd=\"http://schemas.dmtf.org/wbem/wscim/1/cim-schema/2/CIM_ResourceAllocationSettingData\">
             <NetworkConfigSection><NetworkConfig><Configuration>
              <FenceMode>natRouted</FenceMode>
              <Features>
                <NatService>
                  <NatType>ipTranslation</NatType>
                </NatService>
              </Features>
              <RouterInfo>
                <ExternalIp>10.0.0.1</ExternalIp>
              </RouterInfo>
            </Configuration></NetworkConfig></NetworkConfigSection></VApp>",
           :headers => {})

        lambda {
          edge_id = @connection.get_vapp_edge_public_ip("test-vapp")
        }.must_raise VCloudClient::InvalidStateError
      end
    end

    describe "VApp Port Forwarding Rules" do
      it "should retrieve the correct Nat Rules" do
        stub_request(:get, @url).
          to_return(:status => 200,
           :body => "<?xml version=\"1.0\" ?><VApp xmlns=\"http://www.vmware.com/vcloud/v1.5\"
           xmlns:rasd=\"http://schemas.dmtf.org/wbem/wscim/1/cim-schema/2/CIM_ResourceAllocationSettingData\">
             <NetworkConfigSection><NetworkConfig><Configuration>
              <FenceMode>natRouted</FenceMode>
              <Features>
                <NatService>
                  <NatType>portForwarding</NatType>
                  <NatRule>
                    <Id>1</Id>
                    <VmRule>
                      <ExternalIpAddress>10.0.0.1</ExternalIpAddress>
                      <ExternalPort>80</ExternalPort>
                      <VAppScopedVmId>11111111-1111-1111-1111-111111111111</VAppScopedVmId>
                      <VmNicId>0</VmNicId>
                      <InternalPort>80</InternalPort>
                      <Protocol>TCP</Protocol>
                    </VmRule>
                  </NatRule>
                </NatService>
              </Features>
            </Configuration></NetworkConfig></NetworkConfigSection></VApp>",
           :headers => {})

        natrules = @connection.get_vapp_port_forwarding_rules("test-vapp")
        natrules.count.must_equal 1
        natrules.first.must_equal ["1", {:ExternalIpAddress=>"10.0.0.1", :ExternalPort=>"80", :VAppScopedVmId=>"11111111-1111-1111-1111-111111111111", :VmNicId=>"0", :InternalPort=>"80", :Protocol=>"TCP"}]
      end
    end
  end

  describe "vm network config" do
    before { @url = "https://testuser%40testorg:testpass@testhost.local/api/vApp/vm-test-vm/networkConnectionSection" }

    it "should send the correct content-type and payload" do
      stub_request(:put, @url).
      with(:body => "<?xml version=\"1.0\"?>\n<NetworkConnectionSection xmlns=\"http://www.vmware.com/vcloud/v1.5\" xmlns:ovf=\"http://schemas.dmtf.org/ovf/envelope/1\">\n  <ovf:Info>VM Network configuration</ovf:Info>\n  <PrimaryNetworkConnectionIndex>0</PrimaryNetworkConnectionIndex>\n  <NetworkConnection network=\"test-network\" needsCustomization=\"true\">\n    <NetworkConnectionIndex>0</NetworkConnectionIndex>\n    <IsConnected>true</IsConnected>\n  </NetworkConnection>\n</NetworkConnectionSection>\n",
             :headers => {'Content-Type'=>'application/vnd.vmware.vcloud.networkConnectionSection+xml'}).
        to_return(:status => 200,
             :headers => {:location => "#{@connection.api_url}/task/test-vm_network_task"})

      task_id = @connection.set_vm_network_config("test-vm", "test-network")
      task_id.must_equal "test-vm_network_task"
    end
  end

  describe "vm guest customization" do
    before { @url = "https://testuser%40testorg:testpass@testhost.local/api/vApp/vm-test-vm/guestCustomizationSection" }

    it "should send the correct content-type and payload" do
      stub_request(:put, @url).
      with(:body => "<?xml version=\"1.0\"?>\n<GuestCustomizationSection xmlns=\"http://www.vmware.com/vcloud/v1.5\" xmlns:ovf=\"http://schemas.dmtf.org/ovf/envelope/1\">\n  <ovf:Info>VM Guest Customization configuration</ovf:Info>\n  <ComputerName>test-name</ComputerName>\n</GuestCustomizationSection>\n",
             :headers => {'Content-Type'=>'application/vnd.vmware.vcloud.guestCustomizationSection+xml'}).
        to_return(:status => 200,
             :headers => {:location => "#{@connection.api_url}/task/test-vm_guest_task"})

      task_id = @connection.set_vm_guest_customization("test-vm", "test-name")
      task_id.must_equal "test-vm_guest_task"
    end
  end

  describe "show vm details" do
    before { @url = "https://testuser%40testorg:testpass@testhost.local/api/vApp/vm-test-vm" }

    it "should send the correct content-type and payload" do
      stub_request(:get, @url).
        to_return(:status => 200,
          :body => "
            <?xml version=\"1.0\"?>
            <Vm xmlns=\"http://www.vmware.com/vcloud/v1.5\"
                xmlns:ovf=\"http://schemas.dmtf.org/ovf/envelope/1\"
                status=\"8\"
                name=\"test-vm\">
                <ovf:OperatingSystemSection>
                  <ovf:Description>Test OS</ovf:Description>
                </ovf:OperatingSystemSection>
                <GuestCustomizationSection>
                  <Enabled>true</Enabled>
                  <AdminPasswordEnabled>false</AdminPasswordEnabled>
                  <AdminPasswordAuto>false</AdminPasswordAuto>
                  <AdminPassword>testpass</AdminPasswordEnabled>
                  <ResetPasswordRequired>false</ResetPasswordRequired>
                  <ComputerName>testcomputer</ComputerName>
                </GuestCustomizationSection></Vm>
                ")

      vm_get = @connection.get_vm("test-vm")
      vm_get[:os_desc].must_equal "Test OS"
      vm_get[:guest_customizations].wont_be_nil
    end
  end

  describe "show vm details" do
    before { @url = "https://testuser%40testorg:testpass@testhost.local/api/vApp/vm-test-vm/virtualHardwareSection" }

    it "should retrieve the correct number of CPUs" do
      stub_request(:get, @url).
        to_return(:status => 200,
          :body =>   "
                <?xml version=\"1.0\" encoding=\"UTF-8\"?>
                <VApp xmlns:vcloud=\"http://www.vmware.com/vcloud/v1.5\"
                      xmlns:rasd=\"http://schemas.dmtf.org/wbem/wscim/1/cim-schema/2/CIM_ResourceAllocationSettingData\"
                      xmlns:ovf=\"http://schemas.dmtf.org/ovf/envelope/1\"
                      xmlns:vssd=\"http://schemas.dmtf.org/wbem/wscim/1/cim-schema/2/CIM_VirtualSystemSettingData\"
                      xmlns:vmw=\"http://www.vmware.com/schema/ovf\"
                      xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\"
              >
               <ovf:VirtualHardwareSection>
                <ovf:Item vcloud:href=\"https://testhost.local/api/vApp/vm-test-vm/virtualHardwareSection/cpu\" vcloud:type=\"application/vnd.vmware.vcloud.rasdItem+xml\">
                    <rasd:AllocationUnits>hertz * 10^6</rasd:AllocationUnits>
                    <rasd:Description>Number of Virtual CPUs</rasd:Description>
                    <rasd:ElementName>1 virtual CPU(s)</rasd:ElementName>
                    <rasd:InstanceID>4</rasd:InstanceID>
                    <rasd:Reservation>0</rasd:Reservation>
                    <rasd:ResourceType>3</rasd:ResourceType>
                    <rasd:VirtualQuantity>1</rasd:VirtualQuantity>
                    <rasd:Weight>0</rasd:Weight>
                    <Link rel=\"edit\" type=\"application/vnd.vmware.vcloud.rasdItem+xml\" href=\"https://testhost.local/api/vApp/vm-test-vm/virtualHardwareSection/cpu\"/>
                </ovf:Item>
                <ovf:Item vcloud:href=\"https://testhost.local/api/vApp/vm-test-vm/virtualHardwareSection/memory\" vcloud:type=\"application/vnd.vmware.vcloud.rasdItem+xml\">
                    <rasd:AllocationUnits>byte * 2^20</rasd:AllocationUnits>
                    <rasd:Description>Memory Size</rasd:Description>
                    <rasd:ElementName>2048 MB of memory</rasd:ElementName>
                    <rasd:InstanceID>5</rasd:InstanceID>
                    <rasd:Reservation>0</rasd:Reservation>
                    <rasd:ResourceType>4</rasd:ResourceType>
                    <rasd:VirtualQuantity>2048</rasd:VirtualQuantity>
                    <rasd:Weight>0</rasd:Weight>
                    <Link rel=\"edit\" type=\"application/vnd.vmware.vcloud.rasdItem+xml\" href=\"https://testhost.local/api/vApp/vm-test-vm/virtualHardwareSection/memory\"/>
                </ovf:VirtualHardwareSection>
                </VApp>")
      vm_get = @connection.get_vm_info("test-vm")

      vm_get["cpu"][:name].must_equal "1 virtual CPU(s)"
      vm_get["memory"][:name].must_equal "2048 MB of memory"
    end
  end

  describe "poweron vm" do
    before { @url = "https://testuser%40testorg:testpass@testhost.local/api/vApp/vm-test-vm/power/action/powerOn" }

    it "should send the correct request" do
      stub_request(:post, @url).
        to_return(:status => 200,
            :headers => {:location => "#{@connection.api_url}/task/test-startup_task"})

      task_id = @connection.poweron_vm("test-vm")
      task_id.must_equal "test-startup_task"
    end
  end

end
