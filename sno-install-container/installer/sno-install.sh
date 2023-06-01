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

function install_openshift_installer() {
    mkdir -p ../config/tmp
    update="true"
    if [[ -f ../config/tmp/openshift-install-linux.tar.gz ]]; then
        expected_checksum=`curl -sS ${client_base_url}/${client_version}/sha256sum.txt | grep -e openshift-install-linux-${client_version}.tar.gz | cut -d ' ' -f 1`
        if echo "${expected_checksum} ../config/tmp/openshift-install-linux.tar.gz" | sha256sum --check --status; then
            update="false"
        fi
    fi
    if [[ "${update}" == "true" ]]; then
        curl -L -o ../config/tmp/openshift-install-linux.tar.gz ${client_base_url}/${client_version}/openshift-install-linux.tar.gz
    fi
    tar -C /usr/bin -xzf ../config/tmp/openshift-install-linux.tar.gz && chmod u+x /usr/bin/openshift-install
}

function download_openshift_client() {
    mkdir -p ../config/tmp
    if [[ -f ../config/tmp/openshift-client-linux.tar.gz ]]; then
        expected_checksum=`curl -sS ${client_base_url}/${client_version}/sha256sum.txt | grep -e openshift-client-linux-${client_version}.tar.gz | cut -d ' ' -f 1`
        if echo "${expected_checksum} ../config/tmp/openshift-client-linux.tar.gz" | sha256sum --check --status; then
            return
        fi
    fi
    curl -L -o ../config/tmp/openshift-client-linux.tar.gz ${client_base_url}/${client_version}/openshift-client-linux.tar.gz
}

function download_rhcos_iso_via_openshift_install() {
    mkdir -p ../config/tmp
    expected_checksum=`/usr/bin/openshift-install coreos print-stream-json | jq -r '.architectures.x86_64.artifacts.metal.formats.iso.disk.sha256'`
    if [[ -f ../config/tmp/rhcos-live.x86_64.iso ]]; then
        if echo "${expected_checksum} ../config/tmp/rhcos-live.x86_64.iso" | sha256sum --check --status; then
            return
        fi
    fi
    url=`/usr/bin/openshift-install coreos print-stream-json | jq -r '.architectures.x86_64.artifacts.metal.formats.iso.disk.location'`
    curl -L -o ../config/tmp/rhcos-live.x86_64.iso ${url}
}

function download_rhcos_iso() {
    mkdir -p ../config/tmp
    if [[ -f ../config/tmp/rhcos-live.x86_64.iso ]]; then
        expected_checksum=`curl -sS ${rcos_iso_url}/sha256sum.txt | grep rhcos-live.x86_64.iso | cut -d ' ' -f 1`
        if echo "${expected_checksum} ../config/tmp/rhcos-live.x86_64.iso" | sha256sum --check --status; then
            return
        fi
    fi
    curl -L -o ../config/tmp/rhcos-live.x86_64.iso "${rcos_iso_url}/rhcos-live.x86_64.iso"
}

if [[ "${1:-none}" == "pxe" ]]; then
    start_pxe_boot
    exit 0
fi

# use DOLLAR to escape vars from envsubst 
export DOLLAR='$'
export POUND='#'
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
export base_domain=$(yq -r '.base_domain' setup.conf.yaml)
if [[ -z "${base_domain}" || "${base_domain}" == "null" ]]; then
    export base_domain="myocp4.com"
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

install_openshift_installer
download_openshift_client

rhcos_version=$(yq -r '.rhcos_version' setup.conf.yaml)
if [[ -z ${rhcos_version} || "${rhcos_version}" == "null" ]]; then
    download_rhcos_iso_via_openshift_install
else
    rhcos_major_rel=`echo ${rhcos_version} | awk -F. '{print $1"."$2}'`
    rhcos_minor_rel=${rhcos_version}
    coreos_image_base_url=$(yq -r '.coreos_image_base_url' setup.conf.yaml)
    if [[ -z "${coreos_image_base_url}" ]]; then
        coreos_image_base_url="https://mirror.openshift.com/pub/openshift-v4/x86_64/dependencies/rhcos"
    fi
    export rcos_iso_url="${coreos_image_base_url}/${rhcos_major_rel}/${rhcos_minor_rel}"
    download_rhcos_iso
fi

# generate install-config.yaml
mkdir -p ../config/ssh
if [[ ! -e ../config/ssh/id_rsa || ! -e ../config/ssh/id_rsa.pub ]]; then
    /bin/rm -rf ../config/ssh/*
    ssh-keygen -f ../config/ssh/id_rsa -q -N ""
fi
export pub_key_content=`cat ../config/ssh/id_rsa.pub`
export pull_secret=\'$(yq -r '.pull_secret' setup.conf.yaml)\'
export network_type=$(yq -r '.network_type' setup.conf.yaml)
export disk=$(yq -r '.disk' setup.conf.yaml)
envsubst < install-config.tmpl > install-config.yaml

# insert http proxy info
http_proxy=$(yq -r '.http_proxy' setup.conf.yaml)
no_proxy_extra=$(yq -r '.no_proxy' setup.conf.yaml)
no_proxy="${sno_name}.${base_domain},127.0.0.1,localhost,${no_proxy_extra}"
if [[ -n "${http_proxy/null/}" ]]; then
    sed -i "/^baseDomain:.*/a proxy:\n  httpProxy: \"${http_proxy}\"\n  httpsProxy: \"${http_proxy}\"\n  noProxy: \"${no_proxy}\"" install-config.yaml
fi

# create sno ignition
/bin/rm -rf ../config/ocp && mkdir ../config/ocp
cp install-config.yaml ../config/ocp/
openshift-install --dir=../config/ocp create single-node-ignition-config

envsubst < ssh.bu.tmpl > ../config/ocp/ssh.bu

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

