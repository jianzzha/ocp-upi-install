# ocp-upi-install

Verified installation host: rhel7.7; rhel 8 should work as well but not verified.

Verified services (httpd/haproxy/dnsmasq) running on the installation host. The script also support running these services
using podman or docker, but they are not verified and may have issue.

To run the install, on the installtion host, as a root user, git clone this repo, then run ./setup.sh

The install options are set in setup.conf.yaml, please follow the comment line in the setup.conf.yaml to make adjust.

### prerequisites

**BIOS boot order on the baremetal hosts: 1. hard disk 2. PXE on the baremetal NIC.** 

If BIOS boot order is not setup this way, manual intervention for baremetal hosts is required. For example, 
currently Alias lab does not have  the hard disk as the first boot device, so alias lab requires manual intervention. 

Here is how to do the manual intervention:

1. open console connection to the baremetal machine
1. boot to hard disk
   * ipmitool -I lanplus -H ${ipmi_addr} -U ${ipmi_user} -P ${ipmi_password} chassis bootdev pxe
   * ipmitool -I lanplus -H ${ipmi_addr} -U ${ipmi_user} -P ${ipmi_password} chassis power cycle
1. Once the baremetal boots up and completes image download, it will reboot itself; once reboot happens,
   * ipmitool -I lanplus -H ${ipmi_addr} -U ${ipmi_user} -P ${ipmi_password} chassis bootdev disk
   * ipmitool -I lanplus -H ${ipmi_addr} -U ${ipmi_user} -P ${ipmi_password} chassis power cycle
1. the baremetal machine will boot into hard disk and do some self provision and reboot again, once the reboot happens,
   * ipmitool -I lanplus -H ${ipmi_addr} -U ${ipmi_user} -P ${ipmi_password} chassis bootdev disk
   * ipmitool -I lanplus -H ${ipmi_addr} -U ${ipmi_user} -P ${ipmi_password} chassis power cycle





