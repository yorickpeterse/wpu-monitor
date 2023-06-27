FROM alpine:3

RUN apk add --update nmap-ncat fish curl jq
ADD monitor.fish /monitor.fish
CMD ["/usr/bin/fish", "monitor.fish"]
