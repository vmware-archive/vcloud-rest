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

  describe "VCloudClient::Connection#new" do
    it "cannot be created without arguments" do
      expect {
        VCloudClient::Connection.new
      }.to raise_error ArgumentError
    end

    it "must require credentials and API version" do
      conn = VCloudClient::Connection.new(*vcloud_params)
      expect(conn).to be_instance_of VCloudClient::Connection
    end

    it "must construct the correct api url" do
      expect(connection.api_url).to eq "#{vcloud_params[:host]}/api"
    end
  end

  describe "#login" do
    it "should be able to login with API version 5.1 (default)" do
      VCR.use_cassette('login/login_5.1') do
        connection.login
        expect(connection.auth_key).not_to be_nil
      end
    end

    it "should be able to login with API version 1.5" do
      vcloud_params[:api_version] = '1.5'
      VCR.use_cassette('login/login_1.5') do
        connection.login
        expect(connection.auth_key).not_to be_nil
      end
    end

    it "should raise an exception for unauthorized access" do
      vcloud_params[:username] = 'wrong'
      vcloud_params[:password] = 'wrong'

      VCR.use_cassette('login/wrong_login') do
        expect {
          connection.login
        }.to raise_error VCloudClient::UnauthorizedAccess
      end
    end

    it "captures the extension url from the login response" do
      VCR.use_cassette('login/login_5.1') do
        connection.login

        expect(connection.extensibility).to eq("https://testurl.local/api/extensibility")
      end
    end
    
    it "captures nil if there is not extentisibility in respponse" do
      VCR.use_cassette('login/login_no_extensibility') do
        connection.login

        expect(connection.extensibility).to be_nil
      end
    end
  end

  describe "#logout" do
    it "should be able to logout after a login" do
      VCR.use_cassette('login/logout') do
        connection.login
        connection.logout
      end
    end
  end

  describe "Organization management" do
    context "#get_organizations" do
      it "should list organizations" do
        VCR.use_cassette('orgs/get_orgs') do
          connection.login
          orgs = connection.get_organizations
          expect(orgs.count).to eq 1
          expect(orgs).to be_kind_of Hash
          expect(orgs).to eq({"Test" => "562f56be-fa9f-48bd-a5fe-a0f9b0acceae"})
        end
      end
    end

    context "#get_organization" do
      it "should return organization's details by org ID" do
        VCR.use_cassette('orgs/get_org_by_id') do
          connection.login
          org_details = connection.get_organization("562f56be-fa9f-48bd-a5fe-a0f9b0acceae")

          expect(org_details).to eq ({
                :catalogs => {
                    "Test_catalog" => "6aff519e-9eb8-4831-b10c-92b22534567b",
                    "Test_catalog2" => "9b335990-b163-46d3-869c-4d3cfe80dabf"},
                :vdcs => {"Test_vdc" => "69aaefa5-b18b-40d3-ac0b-7a536707a2a1"},
                :networks =>
                  {"Test_network1" => "163b1865-6176-4498-9048-be056aaa6e5e",
                   "Test_network2" => "3782a2eb-e408-4764-8986-1ae5fc033363",
                   "Test_network3" => "6e9ced1c-ee39-4a39-aed8-c619c8693029"},
                :tasklists => {nil => "562f56be-fa9f-48bd-a5fe-a0f9b0acceae"}
              })
        end
      end
    end

    context "#get_organization_by_name" do
      it "should return organization's details by org name" do
        VCR.use_cassette('orgs/get_org_by_name') do
          connection.login
          org_details = connection.get_organization_by_name("Test")

          expect(org_details).to eq ({
                :catalogs => {
                    "Test_catalog" => "6aff519e-9eb8-4831-b10c-92b22534567b",
                    "Test_catalog2" => "9b335990-b163-46d3-869c-4d3cfe80dabf"},
                :vdcs => {"Test_vdc" => "69aaefa5-b18b-40d3-ac0b-7a536707a2a1"},
                :networks =>
                  {"Test_network1" => "163b1865-6176-4498-9048-be056aaa6e5e",
                   "Test_network2" => "3782a2eb-e408-4764-8986-1ae5fc033363",
                   "Test_network3" => "6e9ced1c-ee39-4a39-aed8-c619c8693029"},
                :tasklists => {nil => "562f56be-fa9f-48bd-a5fe-a0f9b0acceae"}
              })
        end
      end
    end
  end

  describe "VDC management" do
    context "#get_vdc" do
      it "should retrieve VDC's details" do
        VCR.use_cassette('vdcs/get_vdc_by_id') do
          connection.login
          vdc_details = connection.get_vdc("69aaefa5-b18b-40d3-ac0b-7a536707a2a1")

          expect(vdc_details).to eq({
                     :id => "69aaefa5-b18b-40d3-ac0b-7a536707a2a1",
                     :name => "Test_vdc",
                     :disks => {},
                     :description => "VDC 1",
                     :vapps =>
                      {"Test_vapp1" => "65b4dbc9-b0b1-46e4-a420-8f8147369f8b",
                       "Test_vapp2" => "d73600c2-955c-472e-b95f-8981844b37e0"},
                     :networks =>
                      {"Test_network1" => "163b1865-6176-4498-9048-be056aaa6e5e",
                       "Test_network2" => "3782a2eb-e408-4764-8986-1ae5fc033363",
                       "Test_network3" => "6e9ced1c-ee39-4a39-aed8-c619c8693029"},
                     :templates =>
                      {"Test_vapp_template1" => "89e33fd7-04a7-4b5f-830b-2423c41089e3",
                       "Test_vapp_template2" => "fa134a0d-cfbe-4ed5-aa99-f6e384e77e7b"}
                    })
        end
      end
    end

    context "#get_vdc_by_name" do
      it "should retrieve VDC's details" do
        VCR.use_cassette('vdcs/get_vdc_by_name') do
          connection.login
          org_details = connection.get_organization_by_name("Test")
          vdc_details = connection.get_vdc_by_name(org_details, "Test_vdc")

          expect(vdc_details).to eq({
                     :id => "69aaefa5-b18b-40d3-ac0b-7a536707a2a1",
                     :name => "Test_vdc",
                     :disks => {},
                     :description => "VDC 1",
                     :vapps =>
                      {"Test_vapp1" => "65b4dbc9-b0b1-46e4-a420-8f8147369f8b",
                       "Test_vapp2" => "d73600c2-955c-472e-b95f-8981844b37e0"},
                     :networks =>
                      {"Test_network1" => "163b1865-6176-4498-9048-be056aaa6e5e",
                       "Test_network2" => "3782a2eb-e408-4764-8986-1ae5fc033363",
                       "Test_network3" => "6e9ced1c-ee39-4a39-aed8-c619c8693029"},
                     :templates =>
                      {"Test_vapp_template1" => "89e33fd7-04a7-4b5f-830b-2423c41089e3",
                       "Test_vapp_template2" => "fa134a0d-cfbe-4ed5-aa99-f6e384e77e7b"}
                    })
        end
      end
    end
  end

  describe "Catalog management" do
    context "show catalog" do
      it "should retrieve catalog's details by ID" do
        VCR.use_cassette('catalogs/get_catalog_by_id') do
          connection.login
          catalog_details = connection.get_catalog("6aff519e-9eb8-4831-b10c-92b22534567b")

          expect(catalog_details).to eq({
               :id => "6aff519e-9eb8-4831-b10c-92b22534567b",
               :description => "Catalog description",
               :items =>  {
                 "Test_catalog_item1" => "f0212516-1e41-49f1-b034-fde4bd321456",
                 "Test_catalog_item2" => "694439b1-9197-42d0-8555-a891cde5f026"}
              })
        end
      end

      it "should retrieve catalog's details by name" do
        VCR.use_cassette('catalogs/get_catalog_by_name') do
          connection.login
          org_details = connection.get_organization_by_name("Test")
          catalog_details = connection.get_catalog_by_name(org_details, "Test_catalog")

          expect(catalog_details).to eq({
               :id => "6aff519e-9eb8-4831-b10c-92b22534567b",
               :description => "Catalog description",
               :items =>  {
                 "Test_catalog_item1" => "f0212516-1e41-49f1-b034-fde4bd321456",
                 "Test_catalog_item2" => "694439b1-9197-42d0-8555-a891cde5f026"}
               })
        end
      end
    end

    context "#get_catalog_item" do
      it "should retrieve catalog item's details" do
        VCR.use_cassette('catalogs/get_item_by_id') do
          connection.login
          item_details = connection.get_catalog_item("f0212516-1e41-49f1-b034-fde4bd321456")

          expect(item_details).to eq({
                  :id => "f0212516-1e41-49f1-b034-fde4bd321456",
                  :description => "",
                  :items =>
                    [{:id => "89e33fd7-04a7-4b5f-830b-2423c41089e3",
                      :name => "Test_catalog_item1",
                      :vms_hash =>  {
                        "Test_vm1" =>
                          {:id => "dbe6d81d-13c4-4e9d-855e-da0c19c9f6aa"}
                      }
                  }],
                  :type => "vAppTemplate"})
        end
      end

    end

    context "#get_catalog_item_by_name" do
      it "should retrieve catalog item's details" do
        VCR.use_cassette('catalogs/get_item_by_name') do
          connection.login
          item_details = connection.get_catalog_item_by_name(
                                  "9b335990-b163-46d3-869c-4d3cfe80dabf",
                                  "Test_catalog_item1")

          expect(item_details).to eq({
                  :id => "f0212516-1e41-49f1-b034-fde4bd321456",
                  :description => "",
                  :items =>
                    [{:id => "89e33fd7-04a7-4b5f-830b-2423c41089e3",
                      :name => "Test_catalog_item1",
                      :vms_hash =>  {
                        "Test_vm1" =>
                          {:id => "dbe6d81d-13c4-4e9d-855e-da0c19c9f6aa"}
                      }
                  }],
                  :type => "vAppTemplate"})
        end
      end
    end
  end

  describe "VApp management" do
    context "#get_vapp" do
      it "should show VApp's details" do
        VCR.use_cassette('vapps/show_vapp_by_id') do
          connection.login
          vapp_details = connection.get_vapp("65b4dbc9-b0b1-46e4-a420-8f8147369f8b")

          expect(vapp_details).to eq(
            {:id => "65b4dbc9-b0b1-46e4-a420-8f8147369f8b",
             :name => "Test_vapp1",
             :description => "VApp Description example",
             :status => "running",
             :ip => "10.202.4.6",
             :networks =>
              [{:id => "e2ef960c-f0a4-44de-96d6-8a541620b780",
                :name => "Test_network1",
                :scope =>
                 {:gateway => "10.202.4.1",
                  :netmask => "255.255.254.0",
                  :fence_mode => "bridged",
                  :parent_network => "Test_network1",
                  :retain_network => "false"}}],
             :vapp_snapshot => nil,
             :vms_hash =>
              {"Test_vm1" =>
                {:addresses => ["10.202.4.6", "10.202.4.3"],
                 :status => "running",
                 :id => "9bb33684-8642-4279-8af2-24eed5f129a6",
                 :vapp_scoped_local_id => "00000000-12c0-4ee7-92c8-0190e1f900a6"}}})
        end
      end
    end

    context "#get_vapp" do
      it "should retrieve catalog's details by name" do
        VCR.use_cassette('vapps/show_vapp_by_name') do
          connection.login
          org_details = connection.get_organization_by_name("Test")
          vapp_details = connection.get_vapp_by_name(
                              org_details,
                              "Test_vdc",
                              "Test_vapp1")

          expect(vapp_details).to eq(
            {:id => "65b4dbc9-b0b1-46e4-a420-8f8147369f8b",
             :name => "Test_vapp1",
             :description => "VApp Description example",
             :status => "running",
             :ip => "10.202.4.6",
             :networks =>
              [{:id => "e2ef960c-f0a4-44de-96d6-8a541620b780",
                :name => "Test_network1",
                :scope =>
                 {:gateway => "10.202.4.1",
                  :netmask => "255.255.254.0",
                  :fence_mode => "bridged",
                  :parent_network => "Test_network1",
                  :retain_network => "false"}}],
             :vapp_snapshot => nil,
             :vms_hash =>
              {"Test_vm1" =>
                {:addresses => ["10.202.4.6", "10.202.4.3"],
                 :status => "running",
                 :id => "9bb33684-8642-4279-8af2-24eed5f129a6",
                 :vapp_scoped_local_id => "00000000-12c0-4ee7-92c8-0190e1f900a6"}}})
        end
      end
    end

    context "#poweroff_vapp" do
      it "should power off a given vapp" do
        VCR.use_cassette('vapps/poweroff_vapp') do
          connection.login
          task_id = connection.poweroff_vapp("65b4dbc9-b0b1-46e4-a420-8f8147369f8b")
          expect(task_id).to eq "ae791b59-4c9f-4fe2-9916-703f1fc3cbd5"
        end
      end
    end

    context "#poweron_vapp" do
      it "should power on a given vapp" do
        VCR.use_cassette('vapps/poweron_vapp') do
          connection.login
          task_id = connection.poweron_vapp("65b4dbc9-b0b1-46e4-a420-8f8147369f8b")
          expect(task_id).to eq "c046ef5b-1ff9-4079-b204-5369dbeeec37"
        end
      end
    end

    context "#reboot_vapp" do
      it "should reboot a given vapp" do
        VCR.use_cassette('vapps/reboot_vapp') do
          connection.login
          task_id = connection.reboot_vapp("65b4dbc9-b0b1-46e4-a420-8f8147369f8b")
          expect(task_id).to eq "d9305e73-972b-4d64-81bb-3404a585ef15"
        end
      end
    end

    context "#suspend_vapp" do
      it "should suspend a given vapp" do
        VCR.use_cassette('vapps/suspend_vapp') do
          connection.login
          task_id = connection.suspend_vapp("65b4dbc9-b0b1-46e4-a420-8f8147369f8b")
          expect(task_id).to eq "53292490-6a89-4de2-bfce-2f3ab3fc7bde"
        end
      end
    end

    context "#discard_suspend_state_vapp" do
      it "should discard an existing suspended state" do
        VCR.use_cassette('vapps/discard_suspend_state_vapp') do
          connection.login
          task_id = connection.discard_suspend_state_vapp("65b4dbc9-b0b1-46e4-a420-8f8147369f8b")
          expect(task_id).to eq "68de94c8-9e2e-42f8-90d4-f5a4f625bd2a"
        end
      end
    end

    context "#reset_vapp" do
      it "should reset a given vapp" do
        VCR.use_cassette('vapps/reset_vapp') do
          connection.login
          task_id = connection.reset_vapp("65b4dbc9-b0b1-46e4-a420-8f8147369f8b")
          expect(task_id).to eq "10bf4eec-8d39-4dc0-9c55-61072197f35e"
        end
      end

      it "should raise an error when reset a vapp without running VMs" do
        VCR.use_cassette('vapps/reset_vapp_not_running') do
          connection.login

          expect {
            task_id = connection.reset_vapp("65b4dbc9-b0b1-46e4-a420-8f8147369f8b")
          }.to raise_error VCloudClient::UnhandledError,
            "BadRequest - unhandled error: The requested operation could not be executed since vApp \"Test_vapp1\" does not have any powered on VMs..\n" \
            "Please report this issue."
        end
      end
    end

    context "#clone_vapp" do
      it "should be able to clone a given vapp" do
        VCR.use_cassette('vapps/clone_vapp') do
          connection.login
          result = connection.clone_vapp(
                        "69aaefa5-b18b-40d3-ac0b-7a536707a2a1",
                        "65b4dbc9-b0b1-46e4-a420-8f8147369f8b",
                        "Test_vapp1")

          expect(result).to eq({
                :vapp_id => "891add70-b262-4b81-a9ac-186d6fd33e50",
                :task_id => "1a66be3e-030a-473a-a33c-5a4e005e53b6"
              })
        end
      end
    end

    context "#create_vapp_from_template" do
      it "should create a new vapp" do
        VCR.use_cassette('vapps/create_vapp_from_template') do
          connection.login
          vapp_created = connection.create_vapp_from_template(
                      "69aaefa5-b18b-40d3-ac0b-7a536707a2a1",
                      "Test_vapp_temp",
                      "VApp from template",
                      "89e33fd7-04a7-4b5f-830b-2423c41089e3")

          expect(vapp_created).to eq({
            :vapp_id => "a1e67d35-6275-42af-b81e-9dc3832cff74",
            :task_id => "8023ca3c-a31d-4834-b539-c369b3162830"})
        end
      end

      it "should detect when an existing vapp already exists" do
        VCR.use_cassette('vapps/create_vapp_from_template_existing') do
          connection.login

          expect {
            connection.create_vapp_from_template(
                        "69aaefa5-b18b-40d3-ac0b-7a536707a2a1",
                        "Test_vapp_temp",
                        "VApp from template",
                        "89e33fd7-04a7-4b5f-830b-2423c41089e3")
            }.to raise_error VCloudClient::UnhandledError, "BadRequest - unhandled error: The VCD entity Test_vapp_temp already exists..\nPlease report this issue."
        end
      end

      it "should detect when there isn't enough space" do
        VCR.use_cassette('vapps/create_vapp_from_template_space') do
          connection.login

          expect {
            connection.create_vapp_from_template(
                      "69aaefa5-b18b-40d3-ac0b-7a536707a2a1",
                      "Test_vapp_temp_space",
                      "VApp from template without space",
                      "89e33fd7-04a7-4b5f-830b-2423c41089e3")
          }.to raise_error VCloudClient::UnhandledError, "BadRequest - unhandled error: The requested operation will exceed the VDC's storage quota..\nPlease report this issue."
        end
      end
    end

    context "#delete_vapp" do
      it "should not delete a given vapp if running" do
        VCR.use_cassette('vapps/delete_vapp_running') do
          connection.login

          expect {
            connection.delete_vapp("765892e3-0644-4883-ab13-84db7dd658b8")
          }.to raise_error VCloudClient::InvalidStateError, "Invalid request because vApp is running. Stop vApp 'Test_vapp' and try again."
        end
      end

      it "should delete a given vapp if stopped" do
        VCR.use_cassette('vapps/delete_vapp') do
          connection.login

          task_id = connection.delete_vapp("765892e3-0644-4883-ab13-84db7dd658b8")

          expect(task_id).to eq "129bd950-9151-49a1-97ff-aad35f687802"
        end
      end
    end

    describe "VApp network management" do
      context "#add_org_network_to_vapp" do
        it "should be able to add an org network" do
          VCR.use_cassette('vapps/networks/add_org_network_to_vapp') do
            connection.login
            task_id = connection.add_org_network_to_vapp(
                          "65b4dbc9-b0b1-46e4-a420-8f8147369f8b",
                          {:name => "Test_network1",
                           :id => '163b1865-6176-4498-9048-be056aaa6e5e'},
                          {:parent_network => {
                                :name => "Test_network1",
                                :id => '163b1865-6176-4498-9048-be056aaa6e5e'
                              },
                           :fence_mode => 'bridged'
                          })
            expect(task_id).to eq "8200f876-865b-4012-8a26-3d04c7b2c91f"
          end
        end

        it "should be able to add a second org network" do
          VCR.use_cassette('vapps/networks/add_second_org_network_to_vapp') do
            connection.login
            task_id = connection.add_org_network_to_vapp(
                          "65b4dbc9-b0b1-46e4-a420-8f8147369f8b",
                          {:name => "Test_network2",
                           :id => '163b1865-6176-4498-9048-be056aaa6e5e'},
                          {:parent_network => {
                                :name => "Test_network2",
                                :id => '163b1865-6176-4498-9048-be056aaa6e5e'
                              },
                           :fence_mode => 'bridged'
                          })
            expect(task_id).to eq "e9de32be-3831-44ab-80b2-2d4c00d6dc9a"
          end
        end
      end

      context "#add_internal_network_to_vapp" do
        it "should be able to add an internal network" do
          VCR.use_cassette('vapps/networks/add_internal_network_to_vapp') do
            connection.login
            task_id = connection.add_internal_network_to_vapp("65b4dbc9-b0b1-46e4-a420-8f8147369f8b",
                              {:name => "test-network"},
                              {:gateway => '192.168.0.1',
                               :netmask => '255.255.255.0',
                               :dns1 => '10.101.0.10',
                               :dns2 => '10.101.0.105',
                               :dns_suffix => 'testdns.example.local',
                               :start_address => '192.168.0.2',
                               :end_address => '192.168.0.200'})
            expect(task_id).to eq "1218cd52-e1ae-4d95-8dd8-b7bb7107b261"
          end
        end
      end

      context "#delete_vapp_network" do
        it "should be able to delete a network" do
          VCR.use_cassette('vapps/networks/delete_network_from_vapp') do
            connection.login
            task_id = connection.delete_vapp_network(
                          "65b4dbc9-b0b1-46e4-a420-8f8147369f8b",
                          {:name => "Test_network1"}
                          )
            expect(task_id).to eq "b8c267b0-4cda-47d8-af98-362ffc06cb16"
          end
        end
      end

      context "#set_vapp_network_config" do
        it "should not be able to add a parent network for 'isolated' fence mode" do
          VCR.use_cassette('vapps/networks/add_parent_to_isolated_vapp_network') do
            connection.login

            expect {
              connection.set_vapp_network_config(
                        "65b4dbc9-b0b1-46e4-a420-8f8147369f8b",
                        {:name => "test-network",
                         :id => "c7fe25c4-b15c-4939-a670-82edf57f87e5"},
                        {:parent_network => {
                          :name => "Test_network1",
                          :id => 'fdfcd4d4-9d3d-43bb-86fd-867d6a89259c'}
                        })
            }.to raise_error VCloudClient::UnhandledError,
                "BadRequest - unhandled error: Network with fenced mode \"isolated\" cannot have a parent network..\n" \
                "Please report this issue."
          end
        end
      end
    end
  end

  describe "Task management" do
    context "#get_tasks_list" do
      it "should be able to retrieve information about a given task" do
        VCR.use_cassette('tasks/get_tasks_list') do
          connection.login
          task_list = connection.get_tasks_list("562f56be-fa9f-48bd-a5fe-a0f9b0acceae")

          expect(task_list.count).to eq 34
          expect(task_list.first).to eq({
              :id => "0357f2d7-5e1d-4ccb-810f-de90dc1599cc",
              :operation => "jobUndeploy",
              :status => "success",
              :error => nil,
              :start_time => "2014-05-22T16:06:49.457+02:00",
              :end_time => "2014-05-22T16:06:49.687+02:00",
              :user_canceled => false})
        end
      end
    end

    context "#get_task" do
      it "should be able to retrieve information about a given task" do
        VCR.use_cassette('tasks/get_task') do
          connection.login
          result = connection.get_task("1a66be3e-030a-473a-a33c-5a4e005e53b6")

          expect(result[:status]).to eq "success"
        end
      end
    end
  end

  describe "Network management" do
    context "#get_network" do
      it "should retrieve information about a given network" do
        VCR.use_cassette('networks/get_network') do
          connection.login
          result = connection.get_network("3782a2eb-e408-4764-8986-1ae5fc033363")

          expect(result).to eq({
            :description => "Example Test Network",
            :end_address => "10.202.4.65",
            :fence_mode => "bridged",
            :gateway => "10.202.4.1",
            :id => "3782a2eb-e408-4764-8986-1ae5fc033363",
            :name => "Test_network1",
            :netmask => "255.255.254.0",
            :start_address => "10.202.4.2"})
        end
      end
    end

    context "#get_network_by_name" do
      it "should retrieve information about a given network" do
        VCR.use_cassette('networks/get_network_by_name') do
          connection.login

          org_details = connection.get_organization_by_name("Test")
          result = connection.get_network_by_name(org_details, "Test_network1")

          expect(result).to eq({
            :description => "Example Test Network",
            :end_address => "10.202.4.65",
            :fence_mode => "bridged",
            :gateway => "10.202.4.1",
            :id => "163b1865-6176-4498-9048-be056aaa6e5e",
            :name => "Test_network1",
            :netmask => "255.255.254.0",
            :start_address => "10.202.4.2"})
        end
      end
    end
  end

  describe "VM management" do
    context "#get_vm" do
      it "should show VM's details" do
        VCR.use_cassette('vms/get_vm') do
          connection.login
          result = connection.get_vm("9bb33684-8642-4279-8af2-24eed5f129a6")

          expect(result).to eq(
            {:id => "9bb33684-8642-4279-8af2-24eed5f129a6",
             :vm_name => "Test_vm1",
             :os_desc => "VM Description",
             :networks =>
              {"Test_network1_0" =>
                {:index => "0",
                 :ip => "10.202.4.3",
                 :external_ip => nil,
                 :is_connected => "true",
                 :mac_address => "00:50:56:02:04:ce",
                 :ip_allocation_mode => "POOL"}},
             :guest_customizations =>
              {:enabled => "true",
               :admin_passwd_enabled => "false",
               :admin_passwd_auto => "false",
               :admin_passwd => "example_password",
               :reset_passwd_required => "false",
               :computer_name => "test-computer"},
             :status => "running"})
        end
      end
    end

    context "#add_vm_network" do
      it "should add a network to a VM" do
        VCR.use_cassette('vms/add_vm_network') do
          connection.login

          task_id = connection.add_vm_network(
                      "9bb33684-8642-4279-8af2-24eed5f129a6",
                      {:name => "Test_network1"}
                    )

          expect(task_id).to eq("ced03b97-2253-4909-939e-94502a748119")
        end
      end
    end

    context "#poweroff_vm" do
      it "should power off a given VM" do
        VCR.use_cassette('vms/poweroff_vm') do
          connection.login
          task_id = connection.poweroff_vm("9bb33684-8642-4279-8af2-24eed5f129a6")

          expect(task_id).to eq("5455d8c0-1368-4f8d-aa03-7260b8927ce4")
        end
      end
    end

    context "#rename_vm" do
      it "should rename a given VM" do
        VCR.use_cassette('vms/rename_vm') do
          connection.login
          task_id = connection.rename_vm(
                        "9bb33684-8642-4279-8af2-24eed5f129a6",
                        "Test_vm1")

          expect(task_id).to eq("1a5d5766-b3e0-4707-9658-89d7a26f9a84")
        end
      end
    end

    context "#poweron_vm" do
      it "should reboot a given VM" do
        VCR.use_cassette('vms/poweron_vm') do
          connection.login
          task_id = connection.poweron_vm(
                        "9bb33684-8642-4279-8af2-24eed5f129a6")

          expect(task_id).to eq("7815f98e-98dd-425e-a4d5-9d45bde0692e")
        end
      end
    end

    context "#reboot_vm" do
      it "should reboot a given VM" do
        VCR.use_cassette('vms/reboot_vm') do
          connection.login
          task_id = connection.reboot_vm(
                        "9bb33684-8642-4279-8af2-24eed5f129a6")

          expect(task_id).to eq("0e28cfa8-17c2-4164-af45-90f7132fd9fe")
        end
      end
    end

    context "#suspend_vm" do
      it "should suspend a given VM" do
        VCR.use_cassette('vms/suspend_vm') do
          connection.login
          task_id = connection.suspend_vm(
                        "9bb33684-8642-4279-8af2-24eed5f129a6")

          expect(task_id).to eq("b02ff85d-8e58-48f3-a49a-043a48841797")
        end
      end
    end

    context "#discard_suspend_state_vm" do
      it "should discard a suspend state for a given VM" do
        VCR.use_cassette('vms/discard_suspend_state_vm') do
          connection.login
          task_id = connection.discard_suspend_state_vm(
                        "9bb33684-8642-4279-8af2-24eed5f129a6")

          expect(task_id).to eq("8f36ecb1-48ac-46b4-bdde-02d1931b25e3")
        end
      end
    end

    context "#reset_vm" do
      it "should reset a given VM" do
        VCR.use_cassette('vms/reset_vm') do
          connection.login
          task_id = connection.reset_vm(
                        "9bb33684-8642-4279-8af2-24eed5f129a6")

          expect(task_id).to eq("761ffeb0-cfdb-4628-94ff-fcd7f9350728")
        end
      end
    end

    context "#create_vm_snapshot" do
      it "should create a snapshot for a given VM" do
        VCR.use_cassette('vms/create_vm_snapshot') do
          connection.login
          task_id = connection.create_vm_snapshot(
                        "9bb33684-8642-4279-8af2-24eed5f129a6",
                        "Test Snapshot")

          expect(task_id).to eq("e139c0fd-3e89-4bac-a5f6-1c624b83ad63")
        end
      end
    end

    context "#revert_vm_snapshot" do
      it "should revert an existing snapshot for a given VM" do
        VCR.use_cassette('vms/revert_vm_snapshot') do
          connection.login
          task_id = connection.revert_vm_snapshot(
                        "9bb33684-8642-4279-8af2-24eed5f129a6")

          expect(task_id).to eq("ac3b6345-5b20-4ca9-8aec-4600aa62cd13")
        end
      end
    end

    context "#discard_vm_snapshot" do
      it "should discard an existing snapshot for a given VM" do
        VCR.use_cassette('vms/discard_vm_snapshot') do
          connection.login
          task_id = connection.discard_vm_snapshot(
                        "9bb33684-8642-4279-8af2-24eed5f129a6")

          expect(task_id).to eq("373c293a-aef2-4aea-b9c0-96962369abb1")
        end
      end
    end

    context "#set_vm_ram" do
      it "should set the RAM available for a given VM" do
        VCR.use_cassette('vms/set_vm_ram') do
          connection.login
          task_id = connection.set_vm_ram(
                        "9bb33684-8642-4279-8af2-24eed5f129a6",
                        "4096")

          expect(task_id).to eq("e889e15c-632f-4d6b-978b-92245aa7672f")
        end
      end
    end

    context "#get_vm_disk_info" do
      it "should retrieve disks information for a given VM" do
        VCR.use_cassette('vms/get_vm_disk_info') do
          connection.login
          result = connection.get_vm_disk_info(
                        "1781ed02-7bb5-4e5d-b502-ca8ff110b6f3")

          expect(result).to eq([{:name=>"Hard disk 1", :capacity=>"16384 MB"},
                                {:name=>"Hard disk 2", :capacity=>"2048 MB"}])
        end
      end
    end

    context "#set_vm_disk_info" do
      it "should add a disk for a given VM" do
        VCR.use_cassette('vms/set_vm_disk_info') do
          disk_info={ :add => true,
                      :delete => false,
                      :disk_size => '1000',
                      :disk_name => 'test_disk01'
                    }
          connection.login
          task_id = connection.set_vm_disk_info(
                        "1781ed02-7bb5-4e5d-b502-ca8ff110b6f3",
                        disk_info)

          expect(task_id).to eq("04283c37-d3af-424f-86e4-724835a8758b")
        end
      end
    end

    context "#acquire_ticket_vm" do
      it "should retrieve the screen ticket for a given VM" do
        VCR.use_cassette('vms/acquire_ticket_vm') do
          connection.login
          result = connection.acquire_ticket_vm(
                        "1781ed02-7bb5-4e5d-b502-ca8ff110b6f3")

          expect(result).to eq({:host=>"testurlvmrc.local",
                                :moid=>"vm-302",
                                :token=>"cst-SPMtdoiMV116/8d6WxvRVItG/XdO2N+aKvztP+ixBwFQpzIQjUshSOS7QAsUwCOlcnWvC9NL3EKk1fvRi0fAKc/r7LFgXIAVAttYHUe8GMp1W7yYGhE2+rB9NzDV/R9mVbmJlpqC9kzRtBzDbReApMJzLBxyeOGhgqW3Cg+41bpw7RVIbf+aVm/reHkB4BAWHuKsPCoK37qnHee5H5cAzPH8RDOueng0iyH+DMe9X6wjTYgGsJi09syoBsqDzNHginYaQw/HWKPtcmfCFm7Uty6QuMghSKnNd0UJS/cHAgHW4/Nw/iNZixQEE3ecJjaGfE7QU0A3CGRTdkW5SIUTDKS/c44emaxUUsmZYWTXU5fM54PwILTmFNh7hdyPAQ53-F6jtmgpvJ/GsbGPiUyaJj1WIkuN07yzcPVWeBQ==--tp-1D:87:78:67:7B:D3:C7:E2:87:54:15:4D:B6:AE:CA:30:09:25:0B:20--"})
        end
      end
    end
  end

  describe "Disk management" do
    context "#create_disk" do
      it "should create an independent disk" do
        VCR.use_cassette('disks/create_disk') do
          connection.login
          result = connection.create_disk(
                      "ExampleDisk",
                      1024,
                      "69aaefa5-b18b-40d3-ac0b-7a536707a2a1",
                      "Example Disk Description")

          expect(result).to eq({
              :disk_id => "4da8d986-2715-4664-88be-9e569e53b551",
              :task_id => "e70a0502-67c0-42b3-b5e5-53ade0996d44"})
        end
      end
    end

    context "#get_disk" do
      it "should get information about an independent disk" do
        VCR.use_cassette('disks/get_disk') do
          connection.login
          result = connection.get_disk("4da8d986-2715-4664-88be-9e569e53b551")

          expect(result).to eq({
                  :id => "4da8d986-2715-4664-88be-9e569e53b551",
                  :name => "ExampleDisk",
                  :size => "1024",
                  :description => "Example Disk Description",
                  :storage_profile => "Silver",
                  :owner => "disk_owner"})
        end
      end
    end

    context "#attach_disk_to_vm" do
      it "should attach an independent disk to a VM" do
        VCR.use_cassette('disks/attach_disk_to_vm') do
          connection.login
          task_id = connection.attach_disk_to_vm(
                        "4da8d986-2715-4664-88be-9e569e53b551",
                        "9bb33684-8642-4279-8af2-24eed5f129a6")

          expect(task_id).to eq("accce753-1c48-431c-ad05-1dd4d221ac8a")
        end
      end
    end

    context "#detach_disk_from_vm" do
      it "should detach an independent disk to a VM" do
        VCR.use_cassette('disks/detach_disk_from_vm') do
          connection.login
          task_id = connection.detach_disk_from_vm(
                        "4da8d986-2715-4664-88be-9e569e53b551",
                        "9bb33684-8642-4279-8af2-24eed5f129a6")

          expect(task_id).to eq("99c57e2c-6661-4504-98ef-3c857b92f16d")
        end
      end
    end

    context "#delete_disk" do
      it "should delete an independent disk" do
        VCR.use_cassette('disks/delete_disk') do
          connection.login
          task_id = connection.delete_disk(
                        "4da8d986-2715-4664-88be-9e569e53b551")

          expect(task_id).to eq("37124965-b91d-4474-917e-b10167e64acd")
        end
      end
    end
  end

  describe "compose vapp from vm" do
    before { @url = "https://#{auth_string}@#{base_url}/api/vdc/vdc_id/action/composeVApp" }

    it "should send the correct content-type and payload" do
      # TODO: this test seems to fail under 1.8.7
      stub_request(:post, @url).
        with(:body => "<?xml version=\"1.0\"?>\n<ComposeVAppParams xmlns=\"http://www.vmware.com/vcloud/v1.5\" xmlns:ovf=\"http://schemas.dmtf.org/ovf/envelope/1\" name=\"vapp_name\">\n  <Description>vapp_desc</Description>\n  <InstantiationParams>\n    <NetworkConfigSection>\n      <ovf:Info>Configuration parameters for logical networks</ovf:Info>\n      <NetworkConfig networkName=\"vapp_net\">\n        <Configuration>\n          <IpScopes>\n            <IpScope>\n              <IsInherited>false</IsInherited>\n              <Gateway>10.250.254.253</Gateway>\n              <Netmask>255.255.255.0</Netmask>\n              <IpRanges>\n                <IpRange>\n                  <StartAddress>10.250.254.1</StartAddress>\n                  <EndAddress>10.250.254.100</EndAddress>\n                </IpRange>\n              </IpRanges>\n            </IpScope>\n          </IpScopes>\n          <ParentNetwork href=\"https://#{base_url}/api/network/guid\"/>\n          <FenceMode>natRouted</FenceMode>\n          <Features>\n            <FirewallService>\n              <IsEnabled>false</IsEnabled>\n            </FirewallService>\n          </Features>\n        </Configuration>\n      </NetworkConfig>\n    </NetworkConfigSection>\n  </InstantiationParams>\n  <SourcedItem>\n    <Source href=\"https://#{base_url}/api/vAppTemplate/vm-vm_id\" name=\"vm_name\"/>\n    <InstantiationParams>\n      <NetworkConnectionSection type=\"application/vnd.vmware.vcloud.networkConnectionSection+xml\" href=\"https://#{base_url}/api/vAppTemplate/vm-vm_id/networkConnectionSection/\">\n        <ovf:Info>Network config for sourced item</ovf:Info>\n        <PrimaryNetworkConnectionIndex>0</PrimaryNetworkConnectionIndex>\n        <NetworkConnection network=\"vapp_net\">\n          <NetworkConnectionIndex>0</NetworkConnectionIndex>\n          <IsConnected>true</IsConnected>\n          <IpAddressAllocationMode>POOL</IpAddressAllocationMode>\n        </NetworkConnection>\n      </NetworkConnectionSection>\n    </InstantiationParams>\n    <NetworkAssignment containerNetwork=\"vapp_net\" innerNetwork=\"vapp_net\"/>\n  </SourcedItem>\n  <AllEULAsAccepted>true</AllEULAsAccepted>\n</ComposeVAppParams>\n",
       :headers => {'Accept'=>'application/*+xml;version=5.1', 'Accept-Encoding'=>'gzip, deflate', 'Content-Type'=>'application/vnd.vmware.vcloud.composeVAppParams+xml'}).
        to_return(:status => 200, :headers => {:location => "#{connection.api_url}/vApp/vapp-vapp_created"},
          :body => "<VApp><Task operationName=\"vdcComposeVapp\" href=\"#{connection.api_url}/task/test-task_id\"></VApp>")


      ## vapp_created = connection.compose_vapp_from_vm("vdc_id",   "vapp_name", "vapp_desc", "templ_id")
      vapp_created = connection.compose_vapp_from_vm("vdc_id", "vapp_name", "vapp_desc", { "vm_name" => "vm_id" }, { :name => "vapp_net", :gateway => "10.250.254.253", :netmask => "255.255.255.0", :start_address => "10.250.254.1", :end_address => "10.250.254.100", :fence_mode => "natRouted", :ip_allocation_mode => "POOL", :parent_network =>  "guid", :enable_firewall => "false" })
      expect(vapp_created[:vapp_id]).to eq "vapp_created"
      expect(vapp_created[:task_id]).to eq "test-task_id"
    end
  end

  describe "add a vm to a vapp" do
    before { @url = "https://#{auth_string}@#{base_url}/api/vApp/vapp-vapp_id/action/recomposeVApp" }

    it "add_vm_to_vapp should send the correct content-type and payload" do
      stub_request(:post, @url).
        with(:body => "<?xml version=\"1.0\"?>\n<RecomposeVAppParams xmlns=\"http://www.vmware.com/vcloud/v1.5\" xmlns:ovf=\"http://schemas.dmtf.org/ovf/envelope/1\" name=\"vapp_name\">\n  <SourcedItem>\n    <Source href=\"https://#{base_url}/api/vAppTemplate/vm-template_id\" name=\"vm_name\"/>\n    <InstantiationParams>\n      <NetworkConnectionSection type=\"application/vnd.vmware.vcloud.networkConnectionSection+xml\" href=\"https://#{base_url}/api/vAppTemplate/vm-template_id/networkConnectionSection/\">\n        <ovf:Info>Network config for sourced item</ovf:Info>\n        <PrimaryNetworkConnectionIndex>0</PrimaryNetworkConnectionIndex>\n        <NetworkConnection network=\"vm_net\">\n          <NetworkConnectionIndex>0</NetworkConnectionIndex>\n          <IsConnected>true</IsConnected>\n          <IpAddressAllocationMode>POOL</IpAddressAllocationMode>\n        </NetworkConnection>\n      </NetworkConnectionSection>\n    </InstantiationParams>\n    <NetworkAssignment containerNetwork=\"vm_net\" innerNetwork=\"vm_net\"/>\n  </SourcedItem>\n  <AllEULAsAccepted>true</AllEULAsAccepted>\n</RecomposeVAppParams>\n",
          :headers => {'Accept'=>'application/*+xml;version=5.1', 'Accept-Encoding'=>'gzip, deflate', 'Content-Type'=>'application/vnd.vmware.vcloud.recomposeVAppParams+xml'}).
        to_return(:status => 200, :headers => {},
          :body => "<VApp><Task operationName=\"vdcRecomposeVapp\" href=\"#{connection.api_url}/task/test-task_id\"></VApp>")

      task_id = connection.add_vm_to_vapp({ :id => "vapp_id", :name => "vapp_name" }, { :template_id => "template_id", :vm_name => "vm_name" }, { :name => "vm_net", :ip_allocation_mode => "POOL" })
      expect(task_id).to eq "test-task_id"
    end
  end

  describe "vapp network config" do
    before { @url = "https://#{auth_string}@#{base_url}/api/vApp/vapp-test-vapp/networkConfigSection" }

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

        edge_id = connection.get_vapp_edge_public_ip("test-vapp")
        expect(edge_id).to eq "10.0.0.1"
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

        expect {
          edge_id = connection.get_vapp_edge_public_ip("test-vapp")
        }.to raise_error VCloudClient::InvalidStateError
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

        expect {
          edge_id = connection.get_vapp_edge_public_ip("test-vapp")
        }.to raise_error VCloudClient::InvalidStateError
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

        natrules = connection.get_vapp_port_forwarding_rules("test-vapp")
        expect(natrules.count).to eq 1
        expect(natrules.first).to eq ["1", {:ExternalIpAddress=>"10.0.0.1", :ExternalPort=>"80", :VAppScopedVmId=>"11111111-1111-1111-1111-111111111111", :VmNicId=>"0", :InternalPort=>"80", :Protocol=>"TCP"}]
      end
    end
  end

  describe "vm guest customization" do
    before { @url = "https://#{auth_string}@#{base_url}/api/vApp/vm-test-vm/guestCustomizationSection" }

    it "should send the correct content-type and payload" do
      stub_request(:put, @url).
      with(:body => "<?xml version=\"1.0\"?>\n<GuestCustomizationSection xmlns=\"http://www.vmware.com/vcloud/v1.5\" xmlns:ovf=\"http://schemas.dmtf.org/ovf/envelope/1\">\n  <ovf:Info>VM Guest Customization configuration</ovf:Info>\n  <ComputerName>test-name</ComputerName>\n</GuestCustomizationSection>\n",
             :headers => {'Content-Type'=>'application/vnd.vmware.vcloud.guestCustomizationSection+xml'}).
        to_return(:status => 200,
             :headers => {:location => "#{connection.api_url}/task/test-vm_guest_task"})

      task_id = connection.set_vm_guest_customization("test-vm", "test-name")
      expect(task_id).to eq "test-vm_guest_task"
    end
  end

  describe "show vm details" do
    before { @url = "https://#{auth_string}@#{base_url}/api/vApp/vm-test-vm" }

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

      vm_get = connection.get_vm("test-vm")
      expect(vm_get[:os_desc]).to eq "Test OS"
      expect(vm_get[:guest_customizations]).not_to be_nil
    end
  end

  describe "show vm details" do
    before { @url = "https://#{auth_string}@#{base_url}/api/vApp/vm-test-vm/virtualHardwareSection" }

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
                <ovf:Item vcloud:href=\"https://#{base_url}/api/vApp/vm-test-vm/virtualHardwareSection/cpu\" vcloud:type=\"application/vnd.vmware.vcloud.rasdItem+xml\">
                    <rasd:AllocationUnits>hertz * 10^6</rasd:AllocationUnits>
                    <rasd:Description>Number of Virtual CPUs</rasd:Description>
                    <rasd:ElementName>1 virtual CPU(s)</rasd:ElementName>
                    <rasd:InstanceID>4</rasd:InstanceID>
                    <rasd:Reservation>0</rasd:Reservation>
                    <rasd:ResourceType>3</rasd:ResourceType>
                    <rasd:VirtualQuantity>1</rasd:VirtualQuantity>
                    <rasd:Weight>0</rasd:Weight>
                    <Link rel=\"edit\" type=\"application/vnd.vmware.vcloud.rasdItem+xml\" href=\"https://#{base_url}/api/vApp/vm-test-vm/virtualHardwareSection/cpu\"/>
                </ovf:Item>
                <ovf:Item vcloud:href=\"https://#{base_url}/api/vApp/vm-test-vm/virtualHardwareSection/memory\" vcloud:type=\"application/vnd.vmware.vcloud.rasdItem+xml\">
                    <rasd:AllocationUnits>byte * 2^20</rasd:AllocationUnits>
                    <rasd:Description>Memory Size</rasd:Description>
                    <rasd:ElementName>2048 MB of memory</rasd:ElementName>
                    <rasd:InstanceID>5</rasd:InstanceID>
                    <rasd:Reservation>0</rasd:Reservation>
                    <rasd:ResourceType>4</rasd:ResourceType>
                    <rasd:VirtualQuantity>2048</rasd:VirtualQuantity>
                    <rasd:Weight>0</rasd:Weight>
                    <Link rel=\"edit\" type=\"application/vnd.vmware.vcloud.rasdItem+xml\" href=\"https://#{base_url}/api/vApp/vm-test-vm/virtualHardwareSection/memory\"/>
                </ovf:VirtualHardwareSection>
                </VApp>")
      vm_get = connection.get_vm_info("test-vm")

      expect(vm_get["cpu"][:name]).to eq "1 virtual CPU(s)"
      expect(vm_get["memory"][:name]).to eq "2048 MB of memory"
    end
  end

  describe "poweron vm" do
    before { @url = "https://#{auth_string}@#{base_url}/api/vApp/vm-test-vm/power/action/powerOn" }

    it "should send the correct request" do
      stub_request(:post, @url).
        to_return(:status => 200,
            :headers => {:location => "#{connection.api_url}/task/test-startup_task"})

      task_id = connection.poweron_vm("test-vm")
      expect(task_id).to eq "test-startup_task"
    end
  end


   describe "snapshot vapp" do
    before { @url = "https://#{auth_string}@#{base_url}/api/vApp/vapp-test-vapp/action/createSnapshot" }

    it "should send the correct request" do
      stub_request(:post, @url).
        to_return(:status => 200,
            :headers => {:location => "#{connection.api_url}/task/test-vapp-snapshot_task"})

      task_id = connection.create_vapp_snapshot("test-vapp", :vm)
      expect(task_id).to eq "test-vapp-snapshot_task"
    end
  end


   describe "snapshot vapp - Deprecated mehtod" do
    before { @url = "https://#{auth_string}@#{base_url}/api/vApp/vapp-test-vapp/action/createSnapshot" }

    it "should send the correct request" do
      stub_request(:post, @url).
        to_return(:status => 200,
            :headers => {:location => "#{connection.api_url}/task/test-vapp-snapshot_deprecated_task"})

      task_id = connection.create_snapshot("test-vapp")
      expect(task_id).to eq "test-vapp-snapshot_deprecated_task"
    end
  end

  describe "private API #convert_vapp_status" do
    it "should return correct status for existing codes" do
      expect(connection.send(:convert_vapp_status, 8)).to eq "stopped"
    end

    it "should return a default for unexisting codes" do
      expect(connection.send(:convert_vapp_status, 999)).to eq "Unknown 999"
    end
  end
end
