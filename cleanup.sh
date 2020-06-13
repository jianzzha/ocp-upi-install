#/usr/bin/bash
set -euo pipefail

./delete-vm.sh

container_runtime=$(yq -r '.container_runtime' setup.conf.yaml)

echo "stop container haproxy dnsmasq httpd services"

for c in ocp-haproxy ocp-httpd ocp-dnsmasq; do
    ${container_runtime} stop $c || true
    ${container_runtime} rm $c || true
done

echo "stop bastion haproxy dnsmasq httpd services"
for s in haproxy dnsmasq httpd; do
    sudo systemctl disable --now $s || true
done

echo "clean up working directory"
/bin/rm -rf pxelinux.cfg
/bin/rm -rf dnsmasq
/bin/rm -rf *.ign
/bin/rm -rf www
/bin/rm -rf fix-ign-*
/bin/rm -rf install-config.yaml
 

