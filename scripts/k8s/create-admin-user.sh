set -euo pipefail

mkdir -p .kube-certs/victor-admin

openssl genrsa -out .kube-certs/victor-admin/victor.key 4096

openssl req -new \
  -key .kube-certs/victor-admin/victor.key \
  -out .kube-certs/victor-admin/victor.csr \
  -subj "/CN=victor-admin/O=k8s-api-admins"

# create CSR manifest as shown in docs/kubeadm-non-admin-user-cert.md
cat > .kube-certs/victor-admin/victor-csr.yaml <<EOF
apiVersion: certificates.k8s.io/v1
kind: CertificateSigningRequest
metadata:
  name: victor-admin-k8s-api-access
spec:
  request: $(base64 < .kube-certs/victor-admin/victor.csr | tr -d '\n')
  signerName: kubernetes.io/kube-apiserver-client
  expirationSeconds: 86400
  usages:
    - client auth
EOF

kubectl delete csr victor-admin-k8s-api-access --ignore-not-found
kubectl apply -f .kube-certs/victor-admin/victor-csr.yaml
kubectl certificate approve victor-admin-k8s-api-access

kubectl get csr victor-admin-k8s-api-access \
  -o jsonpath='{.status.certificate}' \
  | base64 --decode > .kube-certs/victor-admin/victor.crt

if [ "$(openssl x509 -noout -modulus -in .kube-certs/victor-admin/victor.crt | openssl md5)" != "$(openssl rsa -noout -modulus -in .kube-certs/victor-admin/victor.key | openssl md5)" ]; then
  echo "Generated certificate does not match private key" >&2
  exit 1
fi

# Build the Admin Kubeconfig
CURRENT_CONTEXT="$(kubectl config current-context)"
CLUSTER_NAME="$(kubectl config view -o jsonpath="{.contexts[?(@.name==\"${CURRENT_CONTEXT}\")].context.cluster}")"
API_SERVER="$(kubectl config view --raw -o jsonpath="{.clusters[?(@.name==\"${CLUSTER_NAME}\")].cluster.server}")"

kubectl config view --raw \
  -o jsonpath="{.clusters[?(@.name==\"${CLUSTER_NAME}\")].cluster.certificate-authority-data}" \
  | base64 --decode > .kube-certs/victor-admin/ca.crt

kubectl config --kubeconfig=.kube-certs/victor-admin/kubeconfig set-cluster "${CLUSTER_NAME}" \
  --server="${API_SERVER}" \
  --certificate-authority=.kube-certs/victor-admin/ca.crt \
  --embed-certs=true

kubectl config --kubeconfig=.kube-certs/victor-admin/kubeconfig set-credentials victor-admin \
  --client-certificate=.kube-certs/victor-admin/victor.crt \
  --client-key=.kube-certs/victor-admin/victor.key \
  --embed-certs=true

kubectl config --kubeconfig=.kube-certs/victor-admin/kubeconfig set-context victor-admin@"${CLUSTER_NAME}" \
  --cluster="${CLUSTER_NAME}" \
  --user=victor-admin \
  --namespace=default

kubectl config --kubeconfig=.kube-certs/victor-admin/kubeconfig use-context victor-admin@"${CLUSTER_NAME}"
