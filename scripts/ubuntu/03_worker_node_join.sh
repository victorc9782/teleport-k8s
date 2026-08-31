# run this if lost the join command on master node
kubeadm token create --print-join-command

# Example for current cluster
sudo kubeadm join <master-node-ip>:6443 --token <token> \
	--discovery-token-ca-cert-hash sha256:<hash> 
