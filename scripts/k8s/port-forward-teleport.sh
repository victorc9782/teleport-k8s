# sudo ssh -N \
#   -L 127.0.0.1:443:<teleport-cluster-svc-ip>:443 \
#   ubuntu@<control-plane-ip>

sudo ssh -N \
  -L 127.0.0.1:443:10.111.205.66:443 \
  ubuntu@192.168.64.2