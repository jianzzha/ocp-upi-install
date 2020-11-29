#!/usr/bin/env bash

set -euo pipefail

SCRIPTPATH="$( cd "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )"

if [ ! -f setup.conf.yaml ]; then
    echo "setup.conf.yaml not found!"
    exit 1
fi

function detect_os {
    source /etc/os-release
}

function add_pxe_files {
    mkdir -p tmp_syslinux
    sudo mkdir -p /var/lib/tftpboot
    curl -s -o tmp_syslinux/syslinux.zip https://mirrors.edge.kernel.org/pub/linux/utils/boot/syslinux/syslinux-6.03.zip
    pushd tmp_syslinux && unzip syslinux.zip && popd
    sudo /bin/cp -f tmp_syslinux/bios/core/lpxelinux.0 /var/lib/tftpboot
    sudo /bin/cp -f tmp_syslinux/bios/com32/elflink/ldlinux/ldlinux.c32 /var/lib/tftpboot 
    /bin/rm -rf tmp_syslinux 
}

function install_docker {
    echo "install docker"
    sudo yum install -y yum-utils device-mapper-persistent-data lvm2
    sudo yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
    sudo yum install -y containerd.io-1.2.13 docker-ce-19.03.8 docker-ce-cli-19.03.8
    start_docker_daemon
}


function install_runtime {
    detect_os
    if [[ "${ID}" == "rhel" ]]; then
        if [[ "${VERSION_ID}" =~ ^7 ]]; then
            if [[ "${container_runtime}" == "podman" ]]; then
                local my_subscription_status=$(sudo subscription-manager status | sed -n -r 's/Overall Status: (\w+)/\1/p') 
                if [[ "${my_subscription_status}" != "Current" ]]; then
                    echo "please register this system before proceed!"
                    exit 1
                fi
                sudo subscription-manager repos --enable rhel-7-server-extras-rpms                 
                sudo yum install -y podman
            elif [[ "${container_runtime}" == "docker" ]]; then
                install_docker
            else
                echo "For rhel7, only docker or podman is supported!"
                exit 1
            fi
        elif [[ "${VERSION_ID}" =~ ^8 ]]; then
            if [[ "${container_runtime}" == "podman" ]]; then
                sudo yum install -y podman 
            else 
                echo "For rhel8, only podman is supported!"
                 exit 1
            fi
        else
            echo "for rhel, only 7 or 8 is supported"
            exit 1
        fi
    elif [[ "${ID}" = "centos" ]]; then
        if [[ "${container_runtime}" == "podman" ]]; then
            sudo yum install -y podman
        elif [[ "${container_runtime}" == "docker" ]]; then
            install_docker
        else
            echo "only podman or docker supported!"
            exit 1
       fi
    else
        echo "only rhel or centos supported!"
        exit 1
    fi
}

function disable_interface {
# $1: node name; $2 interface name
cat << EOF > fix-ign-$1/etc/sysconfig/network-scripts/ifcfg-$2
DEVICE=$2
BOOTPROTO=none
ONBOOT=no
EOF
}

function start_docker_daemon {
mkdir -p /etc/docker
cat > /etc/docker/daemon.json <<EOF
{
  "iptables": false,
  "exec-opts": ["native.cgroupdriver=systemd"],
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "100m"
  },
  "storage-driver": "overlay2",
  "storage-opts": [
    "overlay2.override_kernel_check=true"
  ]
}
EOF
mkdir -p /etc/systemd/system/docker.service.d
systemctl daemon-reload
systemctl enable --now docker
}

if ! command -v wget >/dev/null 2>&1; then
    sudo yum -y install wget
fi

if ! command -v yq >/dev/null 2>&1; then
    echo "install python3 and tools"
    yum -y install jq python3 python3-pip 
    if ! command -v jq >/dev/null 2>&1; then
	#yum failed to install jq, due to repo issue
	sudo wget -O /usr/local/bin/jq https://github.com/stedolan/jq/releases/download/jq-1.6/jq-linux64
	sudo chmod 0755 /usr/local/bin/jq
    fi
    pip3 install yq
fi

container_runtime=$(yq -r '.container_runtime' setup.conf.yaml)
container_runtime=${container_runtime:-podman}
if ! command -v ${container_runtime} >/dev/null 2>&1; then
    install_runtime
fi

if ! command -v filetranspile >/dev/null 2>&1; then
    echo "download filetranspile"
    sudo curl -o /usr/local/bin/filetranspile https://raw.githubusercontent.com/ashcrow/filetranspiler/18/filetranspile
    sudo chmod u+x /usr/local/bin/filetranspile
    echo "pip install modules for filetranspile"
    pip3 install PyYAML
fi

services_in_container=$(yq -r .services_in_container setup.conf.yaml)
services_in_container=${services_in_container:-true}
if [[ "${services_in_container}" == "true" ]]; then
    dir_httpd=${SCRIPTPATH}/www
    dir_tftpboot=${SCRIPTPATH}
else
    dir_httpd=/var/www/html
    dir_tftpboot=/var/lib/tftpboot
fi

skip_first_time_only_setup=$(yq -r '.skip_first_time_only_setup' setup.conf.yaml)

if ! iptables -t nat -S POSTROUTING | egrep -- 'POSTROUTING -s 192.168.222.0.*-j MASQUERADE'; then
    echo "MASQUERADE not set on installation host, will run through first time setup"
    skip_first_time_only_setup="false"
fi

for cmd in virsh virt-install ipmitool tmux; do
    command -v $cmd >/dev/null 2>&1 || { skip_first_time_only_setup="false"; break; }
done

if [ ! -f install-config.yaml ]; then
    echo "install-config.yaml not found, will run through first time setup"
    skip_first_time_only_setup="false"
fi

rhcos_major_rel=$(yq -r '.rhcos_major_rel' setup.conf.yaml)
 
if [[ "${skip_first_time_only_setup}" == "false" ]]; then
    echo "entering first time setup" 
    [ -f ~/clean-interfaces.sh ] && ~/clean-interfaces.sh --nuke
    yum -y groupinstall 'Virtualization Host'
    yum -y install ipmitool wget virt-install vim-enhanced git tmux
    systemctl enable --now libvirtd

    if [[ "${services_in_container}" == "false" ]]; then
        yum install -y httpd haproxy dnsmasq
    fi

    /bin/cp -f install-config.yaml.tmpl install-config.yaml
    networkType=$(yq -r '.networkType' setup.conf.yaml)
    networkType=${networkType:-OVNKubernetes}
    sed -i s/%%networkType%%/${networkType}/ install-config.yaml
    echo "${networkType} inserted into install-config.yaml"

    echo "setup dnsmasq config file"
    mkdir -p dnsmasq
    /bin/cp -f dnsmasq.conf.tmpl dnsmasq/dnsmasq.conf

    echo "set up pxe files"
    PXEDIR="${dir_tftpboot}/pxelinux.cfg"
    mkdir -p ${PXEDIR}
    /bin/cp -f pxelinux-cfg.tmpl ${PXEDIR}/worker
    if [[ "${rhcos_major_rel}" == "4.6" || "${rhcos_major_rel}" == "4.7" ]]; then
        /bin/cp -f pxelinux-cfg-4.6.tmpl ${PXEDIR}/worker
    fi
    /bin/cp -f ${PXEDIR}/worker ${PXEDIR}/default
    /bin/cp -f ${PXEDIR}/worker ${PXEDIR}/bootstrap
    # bootstrap is a VM with hardcode mac address
    sed -i s/worker.ign/bootstrap.ign/ ${PXEDIR}/bootstrap
    /bin/cp -f ${PXEDIR}/bootstrap ${PXEDIR}/01-52-54-00-f9-8e-41
    /bin/cp -f ${PXEDIR}/worker ${PXEDIR}/master
    sed -i s/worker.ign/master.ign/ ${PXEDIR}/master
    masters=$(yq -r '.master | length' setup.conf.yaml)
    sed -i s/%%master-replicas%%/${masters}/ install-config.yaml
    lastentry=bootstrap
    for i in $(seq 0 $((masters-1))); do
	mac=$(yq -r .master[$i].mac setup.conf.yaml | tr '[:upper:]' '[:lower:]')
        sed -i "/dhcp-host=.*,${lastentry}/a dhcp-host=${mac},192.168.222.2${i},master$i" dnsmasq/dnsmasq.conf 
        lastentry=master$i
        m=$(echo $mac | sed s/\:/-/g | tr '[:upper:]' '[:lower:]')
        disable_ifs=$(yq -r ".master[$i].disable_int | length" setup.conf.yaml)
        if ((disable_ifs == 0)); then
            /bin/cp -f ${PXEDIR}/master ${PXEDIR}/01-${m}
        else
            /bin/cp -f ${PXEDIR}/master ${PXEDIR}/master${i}
            ### setup individual ign file
            sed -i s/master.ign/master${i}.ign/ ${PXEDIR}/master${i}
            /bin/cp -f ${PXEDIR}/master${i} ${PXEDIR}/01-${m}
            mkdir -p fix-ign-master${i}/etc/sysconfig/network-scripts/
            for j in $(seq 0 $((disable_ifs-1))); do
                ifname=$(yq -r .master[$i].disable_int[$j] setup.conf.yaml)
                disable_interface master${i} ${ifname}
            done
        fi
    done
    workers=$(yq -r '.worker | length' setup.conf.yaml)
    sed -i s/%%worker-replicas%%/${workers}/ install-config.yaml
    for i in $(seq 0 $((workers-1))); do
        mac=$(yq -r .worker[$i].mac setup.conf.yaml | tr '[:upper:]' '[:lower:]')
        sed -i "/dhcp-host=.*,${lastentry}/a dhcp-host=${mac},192.168.222.$((30+i)),worker$i" dnsmasq/dnsmasq.conf
        lastentry=worker$i
        m=$(echo $mac | sed s/\:/-/g | tr '[:upper:]' '[:lower:]')
        disable_ifs=$(yq -r ".worker[$i].disable_int | length" setup.conf.yaml)
        if ((disable_ifs == 0)); then
            /bin/cp -f ${PXEDIR}/worker ${PXEDIR}/01-${m}
        else
            /bin/cp -f ${PXEDIR}/worker ${PXEDIR}/worker${i} 
            ### setup individual ign file
            sed -i s/worker.ign/worker${i}.ign/ ${PXEDIR}/worker${i} 
            /bin/cp -f ${PXEDIR}/worker${i} ${PXEDIR}/01-${m}
            mkdir -p fix-ign-worker${i}/etc/sysconfig/network-scripts/
            for j in $(seq 0 $((disable_ifs-1))); do
                ifname=$(yq -r .worker[$i].disable_int[$j] setup.conf.yaml)
                disable_interface worker${i} ${ifname}
            done
        fi
    done

    sudo systemctl enable NetworkManager --now
    sudo nmcli con down baremetal || true
    sudo nmcli con del baremetal || true
    sudo nmcli con add type bridge ifname baremetal con-name baremetal ipv4.method manual ipv4.addr 192.168.222.1/24 ipv4.dns 192.168.222.1 ipv4.dns-priority 10 autoconnect yes bridge.stp no
    sudo nmcli con reload baremetal
    sudo nmcli con up baremetal

    BM_IF=$(yq -r .baremetal_phy_int setup.conf.yaml)
    if [ -n "${BM_IF}" ]; then
        sudo nmcli con down $BM_IF || true
        sudo nmcli con del $BM_IF || true
        sudo nmcli con add type bridge-slave autoconnect yes con-name $BM_IF ifname $BM_IF master baremetal
        sudo nmcli con reload $BM_IF
        sudo nmcli con up $BM_IF
    fi
   
    disable_firewalld=$(yq -r .disable_firewalld setup.conf.yaml)
    if [[ "${disable_firewalld}" == "true" ]]; then
        echo "disable firewalld and selinux"
        sudo systemctl disable --now firewalld
        echo "after disable firewalld, restart libvirt"
        sudo systemctl restart libvirtd
    fi

    disable_selinux=$(yq -r .disable_selinux setup.conf.yaml)
    if [[ "${disable_selinux}" == "true" ]]; then
        echo "disable selinux"
        sudo setenforce 0 || true
        sudo sed -i --follow-symlinks 's/SELINUX=enforcing/SELINUX=disabled/g' /etc/sysconfig/selinux
        echo "selinux disabled"
    fi 
    
    echo "disable libvirt default network"
    if virsh net-list | grep default; then
        sudo virsh net-destroy default
        sudo virsh net-undefine default
        echo "virsh default network destroyed"
    fi
    
    echo "setup libvirt network ocp4-upi"
    if ! virsh net-list | grep ocp4-upi; then
        virsh net-define ocp4-upi-net.xml
        virsh net-autostart ocp4-upi
        virsh net-start ocp4-upi
        echo "virsh network ocp4-upi started"
    fi
   
    reset_iptables=$(yq -r .reset_iptables setup.conf.yaml)  
    if [[ "${reset_iptables}" == "true" ]]; then
        echo "reset iptables"
        sudo iptables -F
        sudo iptables -X
        sudo iptables -F -t nat
        sudo iptables -X -t nat
        echo "iptables flushed"
    fi

    if ! iptables -t nat -L POSTROUTING | egrep "MASQUERADE.*anywhere.*anywhere"; then
        oif=$(ip route | sed -n -r '0,/default/s/.* dev (\w+).*/\1/p')
        sudo iptables -t nat -A POSTROUTING -s 192.168.222.0/24 ! -d 192.168.222.0/24 -o $oif -j MASQUERADE
        sed -i "/^except-interface=lo/a except-interface=${oif}" dnsmasq/dnsmasq.conf 
        echo "MASQUERADE set on bastion"
    fi
    sudo echo 1 > /proc/sys/net/ipv4/ip_forward
    
    echo "set up /etc/resolv.conf"
    sed -i 's/^search.*/search test.myocp4.com/' /etc/resolv.conf
    if ! grep 192.168.222.1 /etc/resolv.conf; then
        sed -i '/^search/a nameserver\ 192.168.222.1' /etc/resolv.conf
        echo "bastion /etc/resolv.conf updated"
    fi

    mkdir -p ${dir_httpd}
    if [[ ${services_in_container} == "false" ]]; then
         sudo cp haproxy/haproxy.cfg /etc/haproxy/haproxy.cfg
         sudo cp dnsmasq/dnsmasq.conf /etc/dnsmasq.conf
         add_pxe_files
         sed -i s/Listen\ 80/Listen\ 81/ /etc/httpd/conf/httpd.conf
         sudo systemctl enable haproxy httpd dnsmasq
         sudo systemctl restart haproxy httpd dnsmasq 
         echo "haproxy httpd dnsmasq started on bastion as systemd service"
    else
         sh services.sh
         echo "service runs in containers"
    fi

    if ! [[ -f ~/.ssh/id_rsa ]]; then
        ssh-keygen -f ~/.ssh/id_rsa -q -N ""
        echo "ssh key generated on bastion"
    fi
    pub_key_content=`cat ~/.ssh/id_rsa.pub`
    sed -i -r -e "s|sshKey:.*|sshKey: ${pub_key_content}|" install-config.yaml
    echo "bastion ssh key inserted into install-config.yaml"
fi

update_installer=$(yq -r '.update_installer' setup.conf.yaml)
if ! command -v oc >/dev/null 2>&1; then
    update_installer=true
fi
if ! command -v openshift-install >/dev/null 2>&1; then
    update_installer=true
fi

if [[ "${update_installer:-false}" == "true" ]]; then
    echo "download openshift images"

    build=$(yq -r .build setup.conf.yaml)
    build=${build:-ga}
    version=$(yq -r .version setup.conf.yaml)

    if [[ "${build}" == "dev" ]]; then
        release_url="https://mirror.openshift.com/pub/openshift-v4/clients/ocp-dev-preview"
    else
        release_url="https://mirror.openshift.com/pub/openshift-v4/clients/ocp"
    fi
    curl -L -o release.txt ${release_url}/${version}/release.txt
    release_version=$(sed -n -r 's/.*Version:\s*(.*)/\1/p' release.txt)
    release_image=$(sed -n -r 's/.*Pull From:\s*(.*)/\1/p' release.txt)
    /bin/rm -rf release.txt
    mkdir -p tmp
    wget -N -P tmp ${release_url}/${version}/openshift-client-linux-${release_version}.tar.gz 
    wget -N -P tmp ${release_url}/${version}/openshift-install-linux-${release_version}.tar.gz

    sudo /bin/rm -rf /usr/local/bin/{kubectl,oc,openshift*}
    sudo tar -C /usr/local/bin -xzf tmp/openshift-client-linux-${release_version}.tar.gz 
    sudo tar -C /usr/local/bin -xzf tmp/openshift-install-linux-${release_version}.tar.gz
    /bin/rm -rf tmp
fi

update_rhcos=$(yq -r '.update_rhcos' setup.conf.yaml)
if [[ "${services_in_container}" == "true" && ! -f www/metal ]]; then
    update_rhcos=true
fi
if [[ "${services_in_container}" == "false" && ! -f /var/www/html/metal ]]; then
    update_rhcos=true
fi

if [[ "${update_rhcos}" == "true" ]]; then
    OPENSHIFT_RHCOS_MINOR_REL="$(curl -sS https://mirror.openshift.com/pub/openshift-v4/dependencies/rhcos/$rhcos_major_rel/latest/ | grep rhcos-$rhcos_major_rel | head -1 | cut -d '-' -f 2)"
    RHCOS_IMAGES_BASE_URI="https://mirror.openshift.com/pub/openshift-v4/dependencies/rhcos/$rhcos_major_rel/latest/"
    SHA256=$(curl -sS "$RHCOS_IMAGES_BASE_URI"sha256sum.txt)
    declare -A images
    if [[ "${rhcos_major_rel}" == "4.6" || "${rhcos_major_rel}" == "4.7" ]]; then
        images[ramdisk]=$(echo "$SHA256" | grep live-initramfs | rev | cut -d ' ' -f 1 | rev | head -n 1)
        images[kernel]=$(echo "$SHA256" | grep live-kernel | rev | cut -d ' ' -f 1 | rev | head -n 1)
        images[metal]=$(echo "$SHA256" | grep live-rootfs | rev | cut -d ' ' -f 1 | rev | head -n 1)
    else
        images[ramdisk]=$(echo "$SHA256" | grep installer-initramfs | rev | cut -d ' ' -f 1 | rev | head -n 1)
        images[kernel]=$(echo "$SHA256" | grep installer-kernel | rev | cut -d ' ' -f 1 | rev | head -n 1)
        images[metal]=$(echo "$SHA256" | grep x86_64-metal | rev | cut -d ' ' -f 1 | rev | head -n 1)
    fi
    mkdir -p ${dir_httpd} && chmod a+rx ${dir_httpd} 
    for image in ramdisk kernel metal; do
        if [ -f ${dir_httpd}/${image} ]; then
            expected=$(echo "$SHA256" | grep ${images[$image]} | cut -d ' ' -f 1)
            existing=$(sha256sum ${dir_httpd}/${image} | awk '{print $1}')
            if [[ "${existing}" == "${expected}" ]]; then
                printf "%s already present with correct sha256sum..skipping...\n" "$image"
                continue
            else
                /bin/rm -rf ${dir_httpd}/${image}
            fi
        fi
        curl -L -o ${dir_httpd}/${image} "$RHCOS_IMAGES_BASE_URI/${images[$image]}"
    done
fi

echo "remove exisiting install directory"
[ -d ~/ocp4-upi-install-1 ] && rm -rf  ~/ocp4-upi-install-1

echo "recreate install directory"
mkdir ~/ocp4-upi-install-1
cp install-config.yaml ~/ocp4-upi-install-1

pushd ~/ocp4-upi-install-1
openshift-install create manifests
# disable pod schedule on master nodes
sed -i s/mastersSchedulable.*/mastersSchedulable:\ False/ manifests/cluster-scheduler-02-config.yml

# copy extra manifest files
if [[ -d $SCRIPTPATH/manifests ]]; then
    for f in $(ls $SCRIPTPATH/manifests/*.yaml 2>/dev/null); do
        /bin/cp -f $f manifests/
    done
fi
 
echo "create ignition files"
openshift-install create ignition-configs
/usr/bin/cp -f *.ign ${dir_httpd} 
popd

echo "copy kubeconfig file"
[ -d ~/.kube ] || mkdir -p ~/.kube
[ -L ~/.kube/config ] && /bin/rm -rf ~/.kube/config
[ -e ~/.kube/config ] && /bin/mv -f ~/.kube/config ~/.kube/config.bak
/bin/cp -f ~/ocp4-upi-install-1/auth/kubeconfig ~/.kube/config

for d in $(ls -d fix-ign-master*); do
    node=$(echo $d | sed -r 's/fix-ign-(master.*)/\1/')
    /usr/bin/cp -f ~/ocp4-upi-install-1/master.ign ./ 
    filetranspile -i master.ign -f $d -o ${node}.ign
    /usr/bin/cp -f ${node}.ign ${dir_httpd} 
done

for d in $(ls -d fix-ign-worker*); do
    node=$(echo $d | sed -r 's/fix-ign-(worker.*)/\1/')
    /usr/bin/cp -f ~/ocp4-upi-install-1/worker.ign ./
    filetranspile -i worker.ign -f $d -o ${node}.ign
    /usr/bin/cp -f ${node}.ign ${dir_httpd}    
done

chmod a+rx ${dir_httpd}/*

./delete-vm.sh

echo "start bootstrap VM ..."
virt-install -n ocp4-upi-bootstrap --pxe --os-type=Linux --os-variant=rhel8.0 --ram=8192 --vcpus=4 --network network=ocp4-upi,mac=52:54:00:f9:8e:41 --disk size=60,bus=scsi,sparse=yes --check disk_size=off --noautoconsole
while true; do
    sleep 3
    if virsh list --state-shutoff | grep ocp4-upi-bootstrap; then
       virsh start ocp4-upi-bootstrap 
       break
    fi
done       

echo "start master ..."
vmcount=0
masters=$(yq -r '.master | length' setup.conf.yaml)
for i in $(seq 0 $((masters-1))); do
    type=$(yq -r .master[$i].type setup.conf.yaml)
    if [[ ${type} == "virtual" ]]; then
        vmcount=$((vmcount+1))
        mac=$(yq -r .master[$i].mac setup.conf.yaml)
        virt-install -n ocp4-upi-master${i} --pxe --os-type=Linux --os-variant=rhel8.0 --ram=12288 --vcpus=4 --network network=ocp4-upi,mac=${mac} --disk size=120,bus=scsi,sparse=yes --check disk_size=off --noautoconsole;
    else
        ipmi_addr=$(yq -r .master[$i].ipmi_addr setup.conf.yaml)
        ipmi_user=$(yq -r .master[$i].ipmi_user setup.conf.yaml)
        ipmi_password=$(yq -r .master[$i].ipmi_password setup.conf.yaml)
        ipmitool -I lanplus -H ${ipmi_addr} -U ${ipmi_user} -P ${ipmi_password} chassis bootdev pxe
        ipmitool -I lanplus -H ${ipmi_addr} -U ${ipmi_user} -P ${ipmi_password} chassis power cycle
    fi
done

while [[ ${vmcount} -gt 0 ]]; do
        sleep 3
        if virsh list --all | grep 'shut off'; then
            vm=$(virsh list --state-shutoff | awk '/shut off/{print $2; exit;}')
            virsh start ${vm}
            vmcount=$((vmcount-1)) 
        fi
done

openshift-install --dir ~/ocp4-upi-install-1 wait-for bootstrap-complete

echo "delete bootstrap server ..."
virsh destroy ocp4-upi-bootstrap
virsh undefine ocp4-upi-bootstrap

echo "start worker ..."
vmcount=0
workers=$(yq -r '.worker | length' setup.conf.yaml)
for i in $(seq 0 $((workers-1))); do
    type=$(yq -r .worker[$i].type setup.conf.yaml)
    if [[ ${type} == "virtual" ]]; then
        vmcount=$((vmcount+1))
        mac=$(yq -r .worker[$i].mac setup.conf.yaml)
        virt-install -n ocp4-upi-worker${i} --pxe --os-type=Linux --os-variant=rhel8.0 --ram=12288 --vcpus=4 --network network=ocp4-upi,mac=${mac} --disk size=120,bus=scsi,sparse=yes --check disk_size=off --noautoconsole
    else
        ipmi_addr=$(yq -r .worker[$i].ipmi_addr setup.conf.yaml)
        ipmi_user=$(yq -r .worker[$i].ipmi_user setup.conf.yaml)
        ipmi_password=$(yq -r .worker[$i].ipmi_password setup.conf.yaml)
        ipmitool -I lanplus -H ${ipmi_addr} -U ${ipmi_user} -P ${ipmi_password} chassis bootdev pxe
        ipmitool -I lanplus -H ${ipmi_addr} -U ${ipmi_user} -P ${ipmi_password} chassis power cycle
    fi
done

while [[ ${vmcount} -gt 0 ]]; do
        sleep 3
        if virsh list --all | grep 'shut off'; then
            vm=$(virsh list --state-shutoff | awk '/shut off/{print $2; exit;}')
            virsh start ${vm}
            vmcount=$((vmcount-1)) 
        fi
done

tmux kill-session -t csr 2>/dev/null || true
cmd="count=$((workers*2)); \
     while ((count > 0)); do \
         echo 'waiting for Pending csr'; \
         if oc get csr | grep Pending; then \
             csr=\$(oc get csr | awk '/Pending/ {print\$1; exit;}'); \
             oc adm certificate approve \$csr; \
             ((count--)); \
         fi; \
         sleep 5; \
     done; \
     > /root/.ssh/known_hosts"
tmux new-session -s csr -d "${cmd}"

echo "The baremetal machine should reboot twice; If the baremetal machine keep doing PXE boot then the BIOS boot order is incorrect. The hard drive should be the first boot device."
echo "watch oc get clusterversion to get progress status"
 
