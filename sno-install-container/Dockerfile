FROM ubi8-minimal
RUN microdnf install --nodocs jq gettext ipmitool python3 python3-devel iproute openssh tar \
    && microdnf -y clean all
RUN python3 -m pip install --no-cache-dir --upgrade pip \
       && python3 -m pip install --no-cache-dir yq
ADD installer /home/installer
WORKDIR /home/installer
ENTRYPOINT ["./sno-install.sh"]
