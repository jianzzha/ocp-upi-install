# Single Node Cluster Install

For single node cluster install, user should use the containerized installer [a relative link](sno-install-container/README.md)

# ocp-upi-install

Verified installation host: rhel7.7; rhel 8 should work as well but not verified.

Verified services (httpd/haproxy/dnsmasq) running on the installation host. The script also support running these services
using podman or docker, but they are not verified and may have issue.

To run the install, on the installtion host, as a root user, git clone this repo, then run ./setup.sh

The install options are set in setup.conf.yaml, please follow the comment line in the setup.conf.yaml to make adjust.

The following settings in setup.conf.yaml most likely need to change to fit your enviroment,
* "version", OCP version
* "rhcos_major_rel", rhcos version
* "ipmi_addr", if you use baremetal worker, its ipmi address
* "ipmi_user", if you use baremetal worker, its ipmi user name
* "ipmi_password", if you use baremetal worker, its ipmi password
* "disable_int", if you use baremetal worker, list the interfaces that should be disabled (to prevent multi home dhcp issue)
* "baremetal_phy_int", this is the control node (or bastion) interface that is used to connect the baremetal workers
* "baremetal_vlan", if vlan is used on "baremetal_phy_int" to connect the baremetal workers, put down the vlan id; otherwise remove
* "ntp_server", ntp server in your network

### topology

<img src="https://docs.google.com/drawings/d/e/2PACX-1vSCLG6HLcMAYDSXD76n6C0NaVaFA0gdXjna-BZ_lJyDkDRZ9XV_Z3HfkRQVFaHvbH7W35H82EoznpZr/pub?w=960&amp;h=720">

### prerequisites

Before running the setup.sh script, use `yum update -y` to update RHEL.

**BIOS boot order on the baremetal hosts: 1. hard disk 2. PXE on the baremetal NIC.** 

If BIOS boot order is not setup this way, manual intervention for baremetal hosts is required. For example, 
currently Alias lab does not have  the hard disk as the first boot device, so alias lab requires manual intervention. 

Here is how to do the manual intervention:

1. open console connection to the baremetal machine
1. pxe boot on baremetal network
   * ipmitool -I lanplus -H ${ipmi_addr} -U ${ipmi_user} -P ${ipmi_password} chassis bootdev pxe
   * ipmitool -I lanplus -H ${ipmi_addr} -U ${ipmi_user} -P ${ipmi_password} chassis power cycle
1. Once the baremetal boots up and completes image download, it will reboot itself; once reboot happens,
   * ipmitool -I lanplus -H ${ipmi_addr} -U ${ipmi_user} -P ${ipmi_password} chassis bootdev disk
   * ipmitool -I lanplus -H ${ipmi_addr} -U ${ipmi_user} -P ${ipmi_password} chassis power cycle
1. the baremetal machine will boot into hard disk and do some self provision and reboot again, once the reboot happens,
   * ipmitool -I lanplus -H ${ipmi_addr} -U ${ipmi_user} -P ${ipmi_password} chassis bootdev disk
   * ipmitool -I lanplus -H ${ipmi_addr} -U ${ipmi_user} -P ${ipmi_password} chassis power cycle





