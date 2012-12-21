## Support for 1.8.x
unless Kernel.respond_to?(:require_relative)
  module Kernel
    def require_relative(path)
      require File.join(File.dirname(caller[0]), path.to_str)
    end
  end
end
##

require 'minitest/spec'
require 'minitest/autorun'
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
    [:login, :logout, :list_organizations, :show_organization,
     :show_vdc, :show_catalog, :show_catalog_item, :show_vapp,
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

      @connection.list_organizations.count.must_equal 0
    end

    it "should return the correct no. of organizations - 1" do
      stub_request(:get, @url).
        to_return(:status => 200,
         :body => "<OrgList><Org href='https://testhost.local/api/org/test-org-url' name='test-org'></Org></OrgList>",
         :headers => {})

      orgs = @connection.list_organizations
      orgs.count.must_equal 1
      orgs.must_be_kind_of Hash
      orgs.first.must_equal ['test-org', 'test-org-url']
    end
  end

  describe "show organization" do
    before { @url = "https://testuser%40testorg:testpass@testhost.local/api/org/test-org" }

    it "should return the correct no. of organizations - 1" do
      stub_request(:get, @url).
        to_return(:status => 200,
         :body => "<Link type='application/vnd.vmware.vcloud.catalog+xml' name='catalog_1' href='#{@connection.api_url}/catalog/catalog_1-url'></Link>",
         :headers => {})

      catalogs, vdcs, networks = @connection.show_organization("test-org")
      catalogs.count.must_equal 1
      catalogs.first.must_equal ["catalog_1", "catalog_1-url"]
    end

    it "should return the correct no. of vdcs - 1" do
      stub_request(:get, @url).
        to_return(:status => 200,
         :body => "<Link type='application/vnd.vmware.vcloud.vdc+xml' name='vdc_1' href='#{@connection.api_url}/vdc/vdc_1-url'></Link>",
         :headers => {})

      catalogs, vdcs, networks = @connection.show_organization("test-org")
      vdcs.count.must_equal 1
      vdcs.first.must_equal ["vdc_1", "vdc_1-url"]
    end

    it "should return the correct no. of networks - 1" do
      stub_request(:get, @url).
        to_return(:status => 200,
         :body => "<Link type='application/vnd.vmware.vcloud.orgNetwork+xml' name='network_1' href='#{@connection.api_url}/network/network_1-url'></Link>",
         :headers => {})

      catalogs, vdcs, networks = @connection.show_organization("test-org")
      networks.count.must_equal 1
      networks.first.must_equal ["network_1", "network_1-url"]
    end
  end

  describe "show catalog" do
    before { @url = "https://testuser%40testorg:testpass@testhost.local/api/catalog/test-catalog" }

    it "should return the correct no. of catalog items - 0" do
      stub_request(:get, @url).
        to_return(:status => 200,
         :body => "",
         :headers => {})

      description, items = @connection.show_catalog("test-catalog")
      items.count.must_equal 0
    end

    it "should return the correct no. of catalog items - 1" do
      stub_request(:get, @url).
        to_return(:status => 200,
         :body => "<CatalogItem type='application/vnd.vmware.vcloud.catalogItem+xml' name='catalog_item_1' href='#{@connection.api_url}/catalogItem/catalog_item_1-url'></CatalogItem>",
         :headers => {})

      description, items = @connection.show_catalog("test-catalog")
      items.first.must_equal ["catalog_item_1", "catalog_item_1-url"]
    end
  end

  describe "show vdc" do
    before { @url = "https://testuser%40testorg:testpass@testhost.local/api/vdc/test-vdc" }

    it "should return the correct no. of vapps - 1" do
      stub_request(:get, @url).
        to_return(:status => 200,
         :body => "<ResourceEntity type='application/vnd.vmware.vcloud.vApp+xml' name='vapp_1' href='#{@connection.api_url}/vApp/vapp-vapp_1-url'></CatalogItem>",
         :headers => {})

      description, items = @connection.show_vdc("test-vdc")
      items.first.must_equal ["vapp_1", "vapp_1-url"]
    end
  end

  describe "show catalog item" do
    before { @url = "https://testuser%40testorg:testpass@testhost.local/api/catalogItem/test-cat-item" }

    it "should return the correct no. of vapp templates - 1" do
      stub_request(:get, @url).
        to_return(:status => 200,
         :body => "<Entity type='application/vnd.vmware.vcloud.vAppTemplate+xml' name='vapp_templ_1' href='#{@connection.api_url}/vAppTemplate/vappTemplate-vapp_templ_1-url'></CatalogItem>",
         :headers => {})

      description, vapp_templates = @connection.show_catalog_item("test-cat-item")
      vapp_templates.first.must_equal ["vapp_templ_1", "vapp_templ_1-url"]
    end
  end

  describe "show vapp" do
    before { @url = "https://testuser%40testorg:testpass@testhost.local/api/vApp/vapp-test-vapp" }

    it "should return the correct status" do
      stub_request(:get, @url).
        to_return(:status => 200,
         :body => "<VApp name='test-vapp' status='4'></VApp>",
         :headers => {})

      name, description, status, ip, vms_hash = @connection.show_vapp("test-vapp")
      name.must_equal "test-vapp"
    end

    it "should return the correct status" do
      stub_request(:get, @url).
        to_return(:status => 200,
         :body => "<VApp name='test-vapp' status='4'></VApp>",
         :headers => {})

      name, description, status, ip, vms_hash = @connection.show_vapp("test-vapp")
      status.must_equal "running"
    end

    it "should return the correct IP" do
      stub_request(:get, @url).
        to_return(:status => 200,
         :body => "<VApp name='test-vapp'><IpAddress>127.0.0.1</IpAddress></VApp>",
         :headers => {})

      name, description, status, ip, vms_hash = @connection.show_vapp("test-vapp")
      ip.must_equal "127.0.0.1"
    end

    it "should return the correct no. of VMs - 1" do
      stub_request(:get, @url).
        to_return(:status => 200,
         :body => "<?xml version=\"1.0\" ?><VApp xmlns=\"http://www.vmware.com/vcloud/v1.5\" xmlns:rasd=\"http://schemas.dmtf.org/wbem/wscim/1/cim-schema/2/CIM_ResourceAllocationSettingData\"><Children><Vm name='vm_1' status='4' href='#{@connection.api_url}/vApp/vm-vm_1'><rasd:Connection ipAddress='127.0.0.1'></rasd:Connection></Vm></Children></VApp>",
         :headers => {})

      name, description, status, ip, vms_hash = @connection.show_vapp("test-vapp")
      vms_hash.count.must_equal 1
      vms_hash.first.must_equal ["vm_1", {:addresses=>["127.0.0.1"], :status=>"running", :id=>"vm_1"}]
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
        with(:body => "<?xml version=\"1.0\"?>\n<InstantiateVAppTemplateParams xmlns=\"http://www.vmware.com/vcloud/v1.5\" xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\" xmlns:ovf=\"http://schemas.dmtf.org/ovf/envelope/1\" name=\"vapp_name\" deploy=\"true\" powerOn=\"true\">\n  <Description>vapp_desc</Description>\n  <Source href=\"https://testhost.local/api/vAppTemplate/templ_id\"/>\n</InstantiateVAppTemplateParams>\n",
             :headers => {'Content-Type'=>'application/vnd.vmware.vcloud.instantiateVAppTemplateParams+xml'}).
        to_return(:status => 200, :headers => {:location => "#{@connection.api_url}/vApp/vapp-vapp_created"},
          :body => "<VApp><Task operationName=\"vdcInstantiateVapp\" href=\"#{@connection.api_url}/task/test-task_id\"></VApp>")

      vapp_id, task_id = @connection.create_vapp_from_template("vdc_id", "vapp_name", "vapp_desc", "templ_id")
      vapp_id.must_equal "vapp_created"
      task_id.must_equal "test-task_id"
    end
  end
end