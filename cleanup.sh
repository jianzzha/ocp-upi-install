#/usr/bin/bash
set -euo pipefail

parse_args() {
   USAGE="Usage: $0 [options]
Options:
   -e  erase dnsmasq completely

This script cleans upi setup.
"
    while getopts ":eh" opt
    do
        case ${opt} in
            e) erase_dnsmasq=true ;;
            h) echo "$USAGE"; exit 0 ;;
            *) echo $USAGE; exit 1 ;;
        esac
    done
}

parse_args $@

./delete-vm.sh

container_runtime=$(yq -r '.container_runtime' setup.conf.yaml)

echo "stop container haproxy dnsmasq httpd services"

for c in ocp-haproxy ocp-httpd ocp-dnsmasq; do
    ${container_runtime} stop $c 2>/dev/null || true
    ${container_runtime} rm $c 2>/dev/null || true
done

echo "stop bastion haproxy dnsmasq httpd services"
for s in haproxy dnsmasq httpd; do
    sudo systemctl disable --now $s || true
done

echo "clean up tftpboot directory on bastion"
sudo /bin/rm -rf /var/lib/tftpboot/pxelinux.cfg

echo "clean up www directory on bastion"
sudo /bin/rm -rf /var/www/html/*ign

echo "clean up working directory, except images"
/bin/rm -rf pxelinux.cfg
/bin/rm -rf dnsmasq
/bin/rm -rf *.ign
/bin/rm -rf www/*.ign
/bin/rm -rf fix-ign-*
/bin/rm -rf install-config.yaml
 
echo "delete VM network"
if virsh net-list | grep ocp4-upi; then
    virsh net-destroy ocp4-upi
    virsh net-undefine ocp4-upi
fi

echo "delete baremetal bridge"
while intf=$(nmcli -f GENERAL.DEVICE,BRIDGE.SLAVES device show baremetal 2>/dev/null | sed -n -r 's/BRIDGE.SLAVES.*\s+(en\S+).*/\1/p'); do
    if [[ -z "${intf}" ]]; then
        break
    fi
    echo "delete ${intf}"
    nmcli con del ${intf} || true
done
nmcli con del baremetal 2>/dev/null || true

echo "flush iptables"
iptables -F
iptables -X
iptables -F -t nat
iptables -X -t nat
systemctl disable ocp-iptables || true

if [[ "${erase_dnsmasq:-false}" == "true" ]]; then
    echo "clean up dnsmasq config"
    /bin/rm -rf /etc/dnsmasq.d
    if [[ -e /etc/dnsmasq.conf.bak ]]; then
        echo "restore dnsmasq config"
        /bin/cp -f /etc/dnsmasq.conf.bak /etc/dnsmasq.conf
    else
        /bin/rm -rf /etc/dnsmasq.conf || true
        yum remove -y dnsmasq 2>/dev/null || true
    fi
fi

if [[ -e /mnt/efiboot ]]; then
    umount -l /mnt/efiboot 2>/dev/null || true
fi

if [[ -e /mnt/iso ]]; then
    umount -l /mnt/iso 2>/dev/null || true
fi
