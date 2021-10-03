#/usr/bin/bash
set -euo pipefail

./delete-vm.sh || true

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

echo "clean up www directory on bastion"
sudo /bin/rm -rf /var/www/html/ign || true
sudo /bin/rm -rf /var/www/html/boot.ipxe || true

echo "clean up working directory, except images"
/bin/rm -rf pxelinux.cfg || true
/bin/rm -rf dnsmasq || true
/bin/rm -rf *.ign || true
/bin/rm -rf www/*.ign || true
/bin/rm -rf fix-ign-* || true
/bin/rm -rf install-config.yaml || true
 

