# How to use the containerized SNO installer

## Build the container image

```
podman build -t quay.io/jianzzha/sno-installer
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
rhcos_major_rel: 4.12
rhcos_minor_rel: 4.12.0

# provision host settings
baremetal_phy_int: ens3f0
baremetal_vlan: 99
http_port: 10080

# installation settings
network_type: OVNKubernetes
disk: /dev/sda
#disk: /dev/nvme0n1

# dnsmasq settings
pxe_mac: "f0:b2:b9:04:9b:60"
sno_name: dut

# idrac setting
uefi: false
ipmi_addr:
ipmi_user: 
ipmi_password:

pull_secret: 'pull secret aquired from https://console.redhat.com/openshift/install/pull-secret'
```

Run the container image to generate artifacts,

```
podman run --privileged --net=host -v $PWD/config:/home/config --rm -it quay.io/jianzzha/sno-installer
```

## Intsall SNO

From the `config` directory, execute the generated script `setup.sh`, e.g.,

```
cd config
./setup.sh
```

## Cleanup

Use `clean` sub-command to remove what's installed by the `setup.sh` script,

```
./setup.sh clean
```

Use `help` to see other available sub-commands.

