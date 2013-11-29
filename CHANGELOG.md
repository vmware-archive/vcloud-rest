Changes
==
2013-11-29 (1.0.0)
--

This is the first release that leaves beta status.
It's actively used in production by at least one company and thus it's important
to offer a more stable interface.

FEATURES:

* General
    * Add proper logging
        (set env vars *VCLOUD_REST_DEBUG_LEVEL* and *VCLOUD_REST_LOG_FILE*)
    * Various entities can be searched by name
* vApp
    * Add methods to create/revert snapshots
    * Add method to clone a vApp
    * Add support to force vApp's Guest Customization
    * get_vapp: retrieve network information
    * get_vapp: retrieve vApp snapshot info
    * Add method to remove a network from a vApp
    * Add method to add an external (from vDC) network to a vApp
    * retrieve vApp's RetainNetInfoAcrossDeployments setting
* VM
    * Add external ip address to ```get_vm```
    * Add method to retrieve VM info (cpu & RAM)
    * Add method to set VM's CPUs info
    * Add method to set VM's RAM info
    * Add method to retrieve VM's disks info
    * Add method to manage VM's disks (add, delete, resize)
    * Add support to upload a customization script
    * Add support to force VM's Guest Customization
    * Add support to manage VM's status (start/stop...)
    * retrieve VM's status in get_vm
    * Add method to rename VMs
* OVF
    * Add a :send_manifest option to ```upload_ovf```
* Network
    * Add method to show network details
* Tasks
    * Add methods to list/cancel Tasks

CHANGES:

* vApp clone returns an hash to provide also the new vApp's ID
* retrieve VM's name directly instead of using the GuestCustomization section
* Do not track Gemfile.lock anymore
* Relax nokogiri version to >= 1.5.10
* set_vapp_network_config requires different parameters

FIXES:

* Reset auth token when a session is destroyed
* Fix wait_task_completion
* Uniform output for get_catalog_item and get_catalog_item_by_name
* ParentNetwork is optional
* Fix ID retrievals using regexps
* set_vapp_network_config to ensure existing configs are not lost
* Better error handling for upload OVF

2013-07-25 (0.3.0)
--

FEATURES:

* Add ```compose_vapp_from_vm``` to compose a vapp using VMs in a catalog
* Add ```get_vapp_template``` to get information on VMs inside a vapp template
* Add ```set_vapp_port_forwarding_rules``` to set NAT port forwarding rules in an existing vapp
* ```set_vapp_network_config```: add parent network specification
* ```get_vapp```: ```vms_hash``` now contains also ```vapp_scoped_local_id```
* Add ```get_vapp_edge_public_ip``` to fetch the public IP of a vApp (vShield Edge)
* Add ```get_vapp_port_forwarding_rules``` to return vApp portforwarding rules
* Add ``reboot_vapp/suspend_vapp/reset_vapp``
* Add ```upload_ovf``` to upload an OVF Package

CHANGES:

* ```RetainNetInfoAcrossDeployments``` now defaults to false (fenced deployments)

FIXES:

* Better handling of 500 errors

REMARKS:
A big thanks to Fabio Rapposelli and Timo Sugliani for the great work done!

2013-05-13 (0.2.2)
--

FIXES:

* Fix retrieving of 'ipAddress' attribute of VMs inside VAPP

VARIOUS:

* Add license field to gemspec
* Bump nokogiri dependency to 1.5.9

2012-12-27 (0.2.1)
--

FIXES:

* Fix VM's admin password retrieval

2012-12-21 (0.2.0)
--

FEATURES:

* Allow Task tracking for vApp startup & shutdown
* Improve error message for operations on vApp not running
* Improve error message for access forbidden
* Extend vApp status codes handling
* Add method to show VM's details
* Basic vApp network configuration
* Basic VM network configuration
* Basic Guest Customization configuration

FIXES:

* Show catalog item: fix ID parsing

2012-12-19 (0.1.1)
--

FIXES:

* Fix gemspec URL

2012-12-19 (0.1.0)
--

FEATURES:

* Add support for main operations:
 * login/logout
 * organization _list/show_
 * vdc _show_
 * catalog _show_
 * catalog item _show_
 * vapp _create/delete/startup/shutdown_

2012-12-14 (0.0.1)
--

* Initial release
