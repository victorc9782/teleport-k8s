# sudo ssh -N \
#   -L 127.0.0.1:443:<teleport-cluster-svc-ip>:443 \
#   ubuntu@<control-plane-ip>

sudo ssh -N \
  -L 127.0.0.1:443:10.105.78.190:443 \
  ubuntu@192.168.64.2 \
  -i ~/.ssh/id_rsa