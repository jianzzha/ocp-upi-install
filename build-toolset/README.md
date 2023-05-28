# How to use

First setup an alias for the convenience,
```
alias tool='podman run --rm --privileged --pull always \
        -v /dev:/dev -v `pwd`:/data \
        -w /data quay.io/jianzzha/toolset'
```

Then use the embeded tools inside using the alias, for example, to use filetranspile,
```
tool filetranspile -i ocp/bootstrap-in-place-for-live-iso.ign -f fakeroot -o tmp/bootstrap.ign
```

Tools available:
* filetranspile
* ipmitool
* jq
* yq
* envsubst

The tool list will keep growing.

