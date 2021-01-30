#!/usr/bin/env bash

set -euo pipefail

SCRIPTPATH="$( cd "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )"

if [ ! -f setup.conf.yaml ]; then
    echo "setup.conf.yaml not found!"
    exit 1
fi

function build_badfish_image {
    pushd ${SCRIPTPATH}
    git clone https://github.com/redhat-performance/badfish.git
    cp -f alias_idrac_interfaces.yml badfishi/config/idrac_interfaces.yml
    cd badfish
    podman build -t quay.io/jianzzha/alias .
    popd
}

lab_name=$(yq -r '.lab_name' setup.conf.yaml)
lab_name=${lab_name:-""}

# if badfish image not exists, then build it with local change
if [[ "${lab_name}" == "alias" ]]; then
    if ! podman image pull quay.io/jianzzha/alias; then
        build_badfish_image
    fi
fi

masters=$(yq -r '.master | length' setup.conf.yaml)
for i in $(seq 0 $((masters-1))); do
    type=$(yq -r .worker[$i].type setup.conf.yaml)
    if [[ "${type}" != "virtual" ]]; then
        ipmi_addr=$(yq -r .master[$i].ipmi_addr setup.conf.yaml)
        ipmi_user=$(yq -r .master[$i].ipmi_user setup.conf.yaml)
        ipmi_password=$(yq -r .master[$i].ipmi_password setup.conf.yaml)
        if [[ "${lab_name}" == "alias" ]]; then
            echo "change alias lab boot order"
            podman run -it --rm  quay.io/jianzzha/alias -H ${ipmi_addr} -u ${ipmi_user} -p ${ipmi_password} -i config/idrac_interfaces.yml -t upi
        fi
    fi
done

workers=$(yq -r '.worker | length' setup.conf.yaml)
for i in $(seq 0 $((workers-1))); do
    type=$(yq -r .worker[$i].type setup.conf.yaml)
    if [[ "${type}" != "virtual" ]]; then
        ipmi_addr=$(yq -r .worker[$i].ipmi_addr setup.conf.yaml)
        ipmi_user=$(yq -r .worker[$i].ipmi_user setup.conf.yaml)
        ipmi_password=$(yq -r .worker[$i].ipmi_password setup.conf.yaml)
        if [[ "${lab_name}" == "alias" ]]; then
            echo "change alias lab boot order"
            podman run -it --rm  quay.io/jianzzha/alias -H ${ipmi_addr} -u ${ipmi_user} -p ${ipmi_password} -i config/idrac_interfaces.yml -t upi
        fi
    fi
done

