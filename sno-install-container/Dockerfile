FROM docker.io/fedora:29
RUN dnf install -y --nodocs jq gettext ipmitool python3 python3-devel iproute openssh \
    && dnf clean all && rm -rf /var/cache/yum
RUN python3 -m pip install --no-cache-dir --upgrade pip \
       && python3 -m pip install --no-cache-dir yq
ADD installer /home/installer
WORKDIR /home/installer
ENTRYPOINT ["./sno-install.sh"]
