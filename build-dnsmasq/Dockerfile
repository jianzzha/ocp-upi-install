FROM docker.io/alpine:3.12
RUN apk -U add dnsmasq curl
COPY tftpboot /var/lib/tftpboot
EXPOSE 53 67 69
ENTRYPOINT ["/usr/sbin/dnsmasq"]
