FROM registry.fedoraproject.org/fedora-minimal:latest AS builder

RUN microdnf install --quiet --assumeyes nmap-ncat fish curl jq mosquitto
ADD monitor.fish /monitor.fish
CMD ["/usr/bin/fish", "monitor.fish"]
