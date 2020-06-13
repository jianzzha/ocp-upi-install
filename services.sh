#/usr/bin/bash
set -euo pipefail

echo start haproxy service
[ -f haproxy/haproxy.cfg ] || { echo "haproxy/haproxy.cfg not found!"; exit 1; } 
podman rm ocp-haproxy || true
count=$(sudo podman ps --filter name=ocp-haproxy --format {{.Names}} | wc -l)
if [[ $count -eq 0 ]]; then
    sudo podman run -d --name ocp-haproxy  --cap-add=NET_ADMIN --net=host -v "$PWD/haproxy":/usr/local/etc/haproxy:ro haproxy:1.7
else
    # let haproxy reload haproxy.cfg
    sudo podman kill -s HUP ocp-haproxy 
fi

echo start httpd service 
[ -d www ] || { echo "directory www not found!"; exit 1; }
podman rm ocp-httpd || true
count=$(sudo podman ps --filter name=ocp-httpd --format {{.Names}} | wc -l)
if [[ $count -eq 0 ]]; then
    sudo podman run -dit --name ocp-httpd -p 81:80 -v "$PWD/www":/usr/local/apache2/htdocs/ httpd:2.4
else
    sudo podman kill -s HUP ocp-httpd
fi

echo "start dnsmasq service"
[ -f dnsmasq/dnsmasq.conf ] || { echo "dnsmasq/dnsmasq.conf not found!"; exit 1; }
podman rm ocp-dnsmasq || true
count=$(sudo podman ps --filter name=ocp-dnsmasq --format {{.Names}} | wc -l)
if [[ $count -eq 0 ]]; then
    sudo podman run -dit --name ocp-dnsmasq -v dnsmasq:/etc/dnsmasq.d -v pxelinux.cfg:/var/lib/tftpboot/pxelinux.cfg --cap-add=NET_ADMIN --net=host quay.io/jianzzha/dnsmasq -d -q --conf-dir=/etc/dnsmasq.d
else
    sudo podman kill -s HUP ocp-dnsmasq
fi
