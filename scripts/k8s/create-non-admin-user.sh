mkdir -p .kube-certs/victor

openssl genrsa -out .kube-certs/victor/victor.key 4096

openssl req -new \
  -key .kube-certs/victor/victor.key \
  -out .kube-certs/victor/victor.csr \
  -subj "/CN=victor/O=k8s-api-users"

# create CSR manifest as shown in docs/kubeadm-non-admin-user-cert.md
cat > .kube-certs/victor/victor-csr.yaml <<EOF
apiVersion: certificates.k8s.io/v1
kind: CertificateSigningRequest
metadata:
  name: victor-k8s-api-access
spec:
  request: $(base64 < .kube-certs/victor/victor.csr | tr -d '\n')
  signerName: kubernetes.io/kube-apiserver-client
  expirationSeconds: 86400
  usages:
    - client auth
EOF

kubectl apply -f .kube-certs/victor/victor-csr.yaml
kubectl certificate approve victor-k8s-api-access

kubectl get csr victor-k8s-api-access \
  -o jsonpath='{.status.certificate}' \
  | base64 --decode > .kube-certs/victor/victor.crt

# Build the Non-Admin Kubeconfig
CURRENT_CONTEXT="$(kubectl config current-context)"
CLUSTER_NAME="$(kubectl config view -o jsonpath="{.contexts[?(@.name==\"${CURRENT_CONTEXT}\")].context.cluster}")"
API_SERVER="$(kubectl config view --raw -o jsonpath="{.clusters[?(@.name==\"${CLUSTER_NAME}\")].cluster.server}")"

kubectl config view --raw \
  -o jsonpath="{.clusters[?(@.name==\"${CLUSTER_NAME}\")].cluster.certificate-authority-data}" \
  | base64 --decode > .kube-certs/victor/ca.crt

kubectl config --kubeconfig=.kube-certs/victor/kubeconfig set-cluster "${CLUSTER_NAME}" \
  --server="${API_SERVER}" \
  --certificate-authority=.kube-certs/victor/ca.crt \
  --embed-certs=true

kubectl config --kubeconfig=.kube-certs/victor/kubeconfig set-credentials victor \
  --client-certificate=.kube-certs/victor/victor.crt \
  --client-key=.kube-certs/victor/victor.key \
  --embed-certs=true

kubectl config --kubeconfig=.kube-certs/victor/kubeconfig set-context victor@"${CLUSTER_NAME}" \
  --cluster="${CLUSTER_NAME}" \
  --user=victor \
  --namespace=default

kubectl config --kubeconfig=.kube-certs/victor/kubeconfig use-context victor@"${CLUSTER_NAME}"