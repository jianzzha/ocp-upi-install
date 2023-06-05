# How to use the containerized SNO installer

## Build the container image

An existing sno-installer container image is available to download from `quay.io/jianzzha/sno-installer`.

If the user is interested to build a local image,
```
podman build -t sno-installer
```

## Create config artifacts 

First create a `config` directory,

```
mkdir config
```

Add `setup.conf.yaml` in the `config` directory. A sample example of `setup.conf.yaml`:

```
# OCP image settings
client_base_url: 'https://mirror.openshift.com/pub/openshift-v4/clients/ocp'
coreos_image_base_url: "https://mirror.openshift.com/pub/openshift-v4/x86_64/dependencies/rhcos"
client_version: 4.12.0
# rhcos_version is only necessary if the coreos version is different than the ocp version
rhcos_version: 4.12.10

# provision host settings
baremetal_phy_int: ens3f0
baremetal_vlan: 99
http_port: 10080

# installation settings
network_type: OVNKubernetes
disk: /dev/sda
#disk: /dev/nvme0n1
#http_proxy: "http://<your_proxy_ip>:<your_proxy_port>
# OCP has a default no_proxy list which normally works, this no_proxy setting is an extra list
i#no_proxy: "192.168.222.0/24"

# ipxe settings
first_ipxe_interface: net4

# dnsmasq settings
pxe_mac: "f0:b2:b9:04:9b:60"
sno_name: dut
base_domain: myocp4.com

# idrac setting
uefi: false
ipmi_addr:
ipmi_user: 
ipmi_password:

pull_secret: 'pull secret aquired from https://console.redhat.com/openshift/install/pull-secret'
```

Run the container image to generate artifacts,

```
podman run --privileged --net=host -v $PWD/config:/home/config --rm -it sno-installer
```

## Intsall SNO

From the `config` directory, execute the generated script `setup.sh`, e.g.,

```
cd config
./setup.sh
```

To install on a virtual machine on the local host in stead,
```
./setup.sh vm
```

On RHEL, running virtual machine requires the following yum packages pre-installed,
```
sudo dnf group install 'Virtualization Hypervisor' 
sudo dnf install virt-install
sudo systemctl enable libvirtd --now
```

To wipe out all disks on the target server before install,
```
./setup.sh wipe-first
```

To wipe out `sda` on the target server before install,
```
./setup.sh wipe-first sda
```

To debug coreos image install problem, prepare the live boot enviroment (then followed by manual booting the target and ssh -i ssh/id_rsa core@<targeti ip>),
```
./setup.sh live
```

## Cleanup

Use `clean` sub-command to remove what's installed by the `setup.sh` script,

```
./setup.sh clean
```

Use `help` to see other available sub-commands.

