#!/usr/bin/bash

set -euo pipefail
shopt -s expand_aliases
source alias.source

if [ ! -f setup.conf.yaml ]; then
    echo "setup.conf.yaml not found!"
    exit 1
fi

function install_openshift_client() {
    version=$1
    mkdir -p tmp
    wget -N -P tmp ${client_base_url}/${version}/openshift-client-linux.tar.gz
    wget -N -P tmp ${client_base_url}/${version}/openshift-install-linux.tar.gz
    /bin/rm -rf /usr/local/bin/{kubectl,oc,openshift*}
    tar -C /usr/local/bin -xzf tmp/openshift-client-linux.tar.gz
    tar -C /usr/local/bin -xzf tmp/openshift-install-linux.tar.gz
}

function get_default_route_interface() {
    oif=$(ip route | sed -n -r '0,/default/s/.* dev (\w+).*/\1/p')
    echo $oif
}

function set_iptable_service() {
    # do nothing if an MASQUERADE entry exists
    if iptables -t nat -L POSTROUTING | egrep "MASQUERADE.*anywhere.*anywhere"; then
       echo "MASQUERADE entry already exists!"
       return
    fi
    export default_route_interface=`get_default_route_interface`
    envsubst < ocp-iptables.tmpl > /usr/local/bin/ocp-iptables.sh
    chmod u+x /usr/local/bin/ocp-iptables.sh 
    envsubst < iptables.service.tmpl > /usr/local/lib/systemd/system/ocp-iptables.service
    iptables -t nat -A POSTROUTING -s 192.168.222.0/24 ! -d 192.168.222.0/24 -o ${default_route_interface} -j MASQUERADE
}

function setup_baremetal_interface() {
    systemctl enable NetworkManager --now
    nmcli con down baremetal || true
    nmcli con del baremetal || true
    nmcli con add type bridge ifname baremetal con-name baremetal ipv4.method manual ipv4.addr 192.168.222.1/24 ipv4.dns 192.168.222.1 ipv4.dns-priority 10 autoconnect yes bridge.stp no
    nmcli con reload baremetal
    nmcli con up baremetal
    BM_IF=$(run yq -r .baremetal_phy_int setup.conf.yaml)
    BM_VLAN=$(run yq -r .baremetal_vlan setup.conf.yaml)
    if [[ -n "${BM_IF}" && "${BM_IF}" != "null" ]]; then
        if [[ -n "${BM_VLAN}" && "${BM_VLAN}" != "null" ]]; then
            nmcli con down $BM_IF.$BM_VLAN || true
            nmcli con del $BM_IF.$BM_VLAN || true
            nmcli con add type vlan autoconnect yes con-name $BM_IF.$BM_VLAN ifname $BM_IF.$BM_VLAN dev $BM_IF id $BM_VLAN master baremetal slave-type bridge
            nmcli con reload $BM_IF.$BM_VLAN
            nmcli con up $BM_IF.$BM_VLAN
        else
            nmcli con down $BM_IF || true
            nmcli con del $BM_IF || true
            nmcli con add type bridge-slave autoconnect yes con-name $BM_IF ifname $BM_IF master baremetal
            nmcli con reload $BM_IF
            nmcli con up $BM_IF
        fi
    else
        echo "baremetal_phy_int not specified!"
        exit 1
    fi
}

function setup_firewall() {
    if firewall-cmd --state; then
        firewall-cmd --permanent --add-service=dhcp --add-service=dns || true
        firewall-cmd --permanent --add-port=${http_port}/tcp || true
    fi
}

function start_pxe_boot() {
    uefi=$(yq .uefi setup.conf.yaml)
    pxe_opt=""
    if [[ "${uefi}" == "true" ]]; then
        pxe_opt="options=efiboot"
    fi
    ipmi_addr=$(run yq -r .ipmi_addr setup.conf.yaml)
    ipmi_user=$(run yq -r .ipmi_user setup.conf.yaml)
    ipmi_password=$(run yq -r .ipmi_password setup.conf.yaml)
    run ipmitool -I lanplus -H ${ipmi_addr} -U ${ipmi_user} -P ${ipmi_password} chassis bootdev pxe ${pxe_opt}
    run ipmitool -I lanplus -H ${ipmi_addr} -U ${ipmi_user} -P ${ipmi_password} chassis power cycle
}

if ! command -v envsubst >/dev/null 2>&1; then
    echo "Please run yum install gettext frist"
    exit 1
fi

setup_baremetal_interface

/bin/rm -rf tmp && mkdir tmp

client_base_url=$(run yq -r .client_base_url setup.conf.yaml)
if [[ -z "${client_base_url}" ]]; then
    client_base_url="https://mirror.openshift.com/pub/openshift-v4/clients/ocp"
fi

client_version=$(run yq -r .client_version setup.conf.yaml)
install_openshift_client ${client_version}

rhcos_major_rel=$(run yq -r '.rhcos_major_rel' setup.conf.yaml)
rhcos_minor_rel=$(run yq -r '.rhcos_minor_rel' setup.conf.yaml)

coreos_image_base_url=$(run yq -r '.coreos_image_base_url' setup.conf.yaml)
if [[ -z "${coreos_image_base_url}" ]]; then
    coreos_image_base_url="https://mirror.openshift.com/pub/openshift-v4/x86_64/dependencies/rhcos"
fi
RHCOS_IMAGES_BASE_URI="${coreos_image_base_url}/${rhcos_major_rel}/${rhcos_minor_rel}"
echo "downloading $RHCOS_IMAGES_BASE_URI/rhcos-live.x86_64.iso"
curl -L -o tmp/rhcos-live.x86_64.iso "$RHCOS_IMAGES_BASE_URI/rhcos-live.x86_64.iso"

export http_port=$(run yq -r '.http_port' setup.conf.yaml)
if [[ -z "${http_port}" || "${http_port}" == "null" ]]; then
    export http_port=8080
fi

/bin/rm -rf htdocs && mkdir htdocs
if podman  container exists httpd; then
    podman stop httpd && podman rm httpd
fi
podman run -dit --name httpd -p ${http_port}:80 -v "$PWD/htdocs":/usr/local/apache2/htdocs/ docker.io/httpd:2.4

/bin/rm -rf dnsmasq && mkdir dnsmasq

# set up dnsmasq service in container
export default_route_interface=`get_default_route_interface`
echo "exclude ${default_route_interface} from dnsmasq.conf"

export pxe_mac=$(run yq -r '.pxe_mac' setup.conf.yaml)
export sno_name=$(run yq -r '.sno_name' setup.conf.yaml)
envsubst < dnsmasq.tmpl > dnsmasq/dnsmasq.conf

if podman  container exists ocp-dnsmasq; then
    podman stop ocp-dnsmasq && podman rm ocp-dnsmasq
fi
podman run -dit --name ocp-dnsmasq -v $PWD/dnsmasq:/etc/dnsmasq.d --cap-add=NET_ADMIN --net=host quay.io/jianzzha/dnsmasq -d -q --conf-file=/etc/dnsmasq.d/dnsmasq.conf --enable-tftp --tftp-root=/var/lib/tftpboot --log-queries --log-dhcp

setup_firewall

if ! [[ -f ~/.ssh/id_rsa ]]; then
    ssh-keygen -f ~/.ssh/id_rsa -q -N ""
fi
export pub_key_content=`cat ~/.ssh/id_rsa.pub`

export pull_secret=\'$(run yq -r '.pull_secret' setup.conf.yaml)\'
#sed -r -e "s/pullSecret: (.*)/pullSecret: \'${pull_secret}\'/" install-config.tmpl > tmp/install-config.yaml

export network_type=$(run yq -r '.network_type' setup.conf.yaml)

export disk=$(run yq -r '.disk' setup.conf.yaml)

envsubst < install-config.tmpl > tmp/install-config.yaml

/bin/rm -rf ocp && mkdir ocp
cp tmp/install-config.yaml ocp/

openshift-install --dir=ocp create single-node-ignition-config

coreos-installer iso ignition embed -i ocp/bootstrap-in-place-for-live-iso.ign tmp/rhcos-live.x86_64.iso -o htdocs/rhcos-live.x86_64.iso

envsubst < bootstrap.ipxe.tmpl > htdocs/bootstrap.ipxe 

chmod 0644 htdocs/rhcos-live.x86_64.iso
chmod 0644 htdocs/bootstrap.ipxe

start_pxe_boot

openshift-install --dir=ocp wait-for install-complete
 
