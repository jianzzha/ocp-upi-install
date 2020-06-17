#/usr/bin/bash
set -euo pipefail

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
 

