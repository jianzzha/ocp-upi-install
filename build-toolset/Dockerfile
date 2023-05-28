FROM docker.io/alpine:3.12
RUN apk --no-cache add gettext py3-pip jq ipmitool curl libmagic
RUN pip3 install yq python-magic && \
    curl -o /usr/local/bin/filetranspile https://raw.githubusercontent.com/ashcrow/filetranspiler/master/filetranspile && \
    chmod +x /usr/local/bin/filetranspile
CMD ["/usr/bin/sh"]
