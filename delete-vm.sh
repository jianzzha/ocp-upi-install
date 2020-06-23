#/usr/bin/env bash

echo "delete VM"
for vm in $(virsh list | egrep -o "ocp4-upi\S*"); do
    virsh destroy $vm
    virsh undefine $vm
done

for vm in $(virsh list --all | egrep -o "ocp4-upi\S*"); do
    virsh undefine $vm
done

echo "delete VM image"
for vol in $(virsh vol-list default | awk '/ocp4-upi/ {print $1}'); do
    virsh vol-delete $vol --pool default
done

