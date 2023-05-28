#!/usr/bin/bash

set -euo pipefail

if [ ! -f ../config/setup.conf.yaml ]; then
    echo "setup.conf.yaml not found!"
    exit 1
fi

ln -sfT ../config/setup.conf.yaml setup.conf.yaml

function get_default_route_interface() {
    oif=$(ip route | sed -n -r '0,/default/s/.* dev (\w+).*/\1/p')
    echo $oif
}

function start_pxe_boot() {
    uefi=$(yq -r .uefi setup.conf.yaml)
    pxe_opt=""
    if [[ "${uefi}" == "true" ]]; then
        pxe_opt="options=efiboot"
    fi
    ipmi_addr=$(yq -r .ipmi_addr setup.conf.yaml)
    ipmi_user=$(yq -r .ipmi_user setup.conf.yaml)
    ipmi_password=$(yq -r .ipmi_password setup.conf.yaml)
    ipmitool -I lanplus -H ${ipmi_addr} -U ${ipmi_user} -P ${ipmi_password} chassis bootdev pxe ${pxe_opt}
    ipmitool -I lanplus -H ${ipmi_addr} -U ${ipmi_user} -P ${ipmi_password} chassis power cycle
}

if [[ "${1:-none}" == "pxe" ]]; then
    start_pxe_boot
    exit 0
fi

# use DOLLAR to escape vars from envsubst 
export DOLLAR='$'
export BM_IF=$(yq -r .baremetal_phy_int setup.conf.yaml)
export BM_VLAN=$(yq -r .baremetal_vlan setup.conf.yaml)
export http_port=$(yq -r '.http_port' setup.conf.yaml)
if [[ -z "${http_port}" || "${http_port}" == "null" ]]; then
    export http_port=8080
fi
export default_route_interface=`get_default_route_interface`
export pxe_mac=$(yq -r '.pxe_mac' setup.conf.yaml)
export sno_name=$(yq -r '.sno_name' setup.conf.yaml)
export sno_ip=$(yq -r '.sno_ip' setup.conf.yaml)
if [[ -z "${sno_ip}" || "${sno_ip}" == "null" ]]; then
    export sno_ip="192.168.222.30"
fi
export dhcp_low=$(yq -r '.dhcp_low' setup.conf.yaml)
if [[ -z "${dhcp_low}" || "${dhcp_low}" == "null" ]]; then
    export dhcp_low="192.168.222.20"
fi
export dhcp_high=$(yq -r '.dhcp_high' setup.conf.yaml)
if [[ -z "${dhcp_high}" || "${dhcp_high}" == "null" ]]; then
    export dhcp_high="192.168.222.100"
fi

/bin/rm -rf ../config/dnsmasq && mkdir ../config/dnsmasq
envsubst < dnsmasq.tmpl > ../config/dnsmasq/dnsmasq.conf
envsubst < ocp-iptables.tmpl > ../config/ocp-iptables.sh
envsubst < iptables.service.tmpl > ../config/ocp-iptables.service 
envsubst < host_file.tmpl > ../config/hosts

export client_base_url=$(yq -r .client_base_url setup.conf.yaml)
if [[ -z "${client_base_url}" || "${client_base_url}" == "null" ]]; then
    export client_base_url="https://mirror.openshift.com/pub/openshift-v4/clients/ocp"
fi

export client_version=$(yq -r .client_version setup.conf.yaml)

rhcos_major_rel=$(yq -r '.rhcos_major_rel' setup.conf.yaml)
rhcos_minor_rel=$(yq -r '.rhcos_minor_rel' setup.conf.yaml)

coreos_image_base_url=$(yq -r '.coreos_image_base_url' setup.conf.yaml)
if [[ -z "${coreos_image_base_url}" ]]; then
    coreos_image_base_url="https://mirror.openshift.com/pub/openshift-v4/x86_64/dependencies/rhcos"
fi
export rcos_iso_url="${coreos_image_base_url}/${rhcos_major_rel}/${rhcos_minor_rel}"

# generate install-config.yaml
/bin/rm -rf ../config/ssh && mkdir ../config/ssh
ssh-keygen -f ../config/ssh/id_rsa -q -N ""
export pub_key_content=`cat ../config/ssh/id_rsa.pub`
export pull_secret=\'$(yq -r '.pull_secret' setup.conf.yaml)\'
export network_type=$(yq -r '.network_type' setup.conf.yaml)
export disk=$(yq -r '.disk' setup.conf.yaml)
envsubst < install-config.tmpl > install-config.yaml

# create sno ignition
/bin/rm -rf ../config/ocp && mkdir ../config/ocp
cp install-config.yaml ../config/ocp/

# generate ipxe file
export first_ipxe_interface=$(yq -r '.first_ipxe_interface' setup.conf.yaml)
if [[ -z "${first_ipxe_interface}" || "${first_ipxe_interface}" == "null" ]]; then
    export first_ipxe_interface="net0"
fi
/bin/rm -rf ../config/htdocs && mkdir ../config/htdocs
envsubst < bootstrap.ipxe.tmpl > ../config/htdocs/bootstrap.ipxe 

# impi
uefi=$(yq -r .uefi setup.conf.yaml)
export pxe_opt=""
if [[ "${uefi}" == "true" ]]; then
    export pxe_opt="options=efiboot"
fi
export ipmi_addr=$(yq -r .ipmi_addr setup.conf.yaml)
export ipmi_user=$(yq -r .ipmi_user setup.conf.yaml)
export ipmi_password=$(yq -r .ipmi_password setup.conf.yaml)

# generate host setup script
envsubst < setup.tmpl > ../config/setup.sh

# check the syntax
bash -n ../config/setup.sh 
chmod u+x ../config/setup.sh

