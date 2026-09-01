# Technical Document for Kubernetes Installation and Application Deployment

## 1. Executive Summary


This project implements a three-node Kubernetes cluster using `kubeadm`, running on Ubuntu 24.04 virtual machines hosted on a MacBook Air M2 using UTM virtualisation. The cluster consists of one control-plane node and two worker nodes.

The solution follows a GitOps-based deployment approach using Argo CD to manage Kubernetes application, infrastructure, and networking configurations declaratively from Git. A static Nginx application is deployed to a default namespace and is accessible from a web browser over HTTPS.

Kubernetes user authentication is implemented using X.509 client certificates issued through the Kubernetes `CertificateSigningRequest` (CSR) API. A non-administrative application user is granted least-privilege, namespace-scoped permissions through Kubernetes Role-Based Access Control (RBAC), allowing the user to deploy, access, and monitor the Nginx application without granting access to unrelated cluster resources.

A separate administrative identity also uses certificate-based authentication but is authorised through a `ClusterRoleBinding` to the built-in `cluster-admin` role for cluster administration. This separation demonstrates the distinction between authentication, which establishes user identity, and authorisation, which determines the resources and operations available to that identity.

Another additional requirement is to deploy Teleport cluster for exploration purposes. The related documentation and installation details are also maintained in the same repository.

## 2. Architecture Overview

### Kubernetes Infrastructure
Kubernetes Cluster - `kubeadm`

- 1 control plane node
- 2 worker nodes
- Ubuntu 24.04 on MacOS Host with UTM virtualisation

### Native Kubernetes administrator/user access
```
User private key
      ↓
Kubernetes CSR
      ↓
CSR approval
      ↓
X.509 client certificate
      ↓
kubeconfig
      ↓
Kubernetes API
      ↓
RBAC RoleBinding
      ↓
Application namespace (e.g. default)
```

### GitOps - Argo CD
```
Kubernetes Admin
   ↓
Install Argo Application
```
```
Developer
   ↓
Git commit (Infrastructure/Application/Networking)
   ↓
GitHub
   ↓
Argo CD
   ↓
Kubernetes
```
### Nginx
```
macOS Host
    ↓
Browser
    ↓
HTTPS / 30443 | SSH Port-forwarding / 443
    ↓
Gateway with SSL termination
    ↓
NGINX Gateway Fabric
    ↓
HTTPRoute
    ↓
nginx-demo Service
    ↓
nginx-pod - port 80
```

### Teleport
```
macOS Host
    ↓
Browser
    ↓
SSH Port-forwarding / 443
    ↓
Gateway - TLS Passthrough
    ↓
NGINX Gateway Fabric
    ↓
HTTPRoute
    ↓
Teleport Service
    ↓
Teleport pod - port 443
```

## 3. Environment and Technology Choices
| Component       | Choice                      | Reason                                       |
| --------------- | --------------------------- | -------------------------------------------- |
| Host            | macOS                       | Local development environment                |
| Virtualisation  | UTM                         | Allows multiple Linux VMs without cloud cost |
| Guest OS        | Ubuntu 24.04                | Supported general-purpose Linux              |
| Kubernetes      | kubeadm                     | Challenge requirement                        |
| Runtime         | containerd                  | Kubernetes-compatible container runtime      |
| Nodes           | 1 control plane + 2 workers | Challenge requirement                        |
| CNI             | Calico                      | Pod networking and NetworkPolicy capability  |
| GitOps          | Argo CD                     | Declarative application deployment           |
| Gateway         | NGINX Gateway Fabric        | Gateway API based application exposure       |
| TLS             | cert-manager                | Required automated certificate management    |
| Access          | X.509 + Kubernetes RBAC     | Required native access model                 |
| Advanced access | Teleport                    | Advanced objective                           |

### Installed versions
| Component       | Version                     | Source                                       |
| --------------- | --------------------------- | -------------------------------------------- |
| Kubernetes      | 1.34.11                     | Official kubeadm                             |
| Containerd      | 2.2.1                       | Official containerd                          |
| Calico          | 3.32.1                      | Official Calico                              |
| Argo CD         | 3.5.2                       | Official Argo CD                             |
| NGINX Gateway   | 2.6.7                       | Official NGINX Gateway Fabric                |
| cert-manager    | 1.21.1                      | Official cert-manager                        |
| Teleport        | 18.11.0                     | Official Teleport                            |

## 4. Detailed Design and Implementation
### 4.1 Kubernetes Cluster Infrastructure
#### Node topology:
k8s-master-node:
- 3GB RAM, 3 vCPU, 10GiB Disk, Ubuntu 24.04
- Ubuntu 24.04
- Hosts the Kubernetes control-plane components
- Setup required environment on Ubuntu with scripts/ubuntu/01_common_setup.sh

The control-plane node was initially provisioned with 2 GB RAM and 2 vCPUs. These resources were increased to 3 GB RAM and 3 vCPUs after the operating system experienced memory pressure while additional components were deployed to the cluster.

k8s-worker-node1 / k8s-worker-node2
- 2GB RAM, 2 vCPU , 10GiB Disk each, Ubuntu 24.04
- Ubuntu 24.04
- Hosts the Kubernetes worker components and applications
- Setup required environment on Ubuntu with scripts/ubuntu/01_common_setup.sh

Network:  
The virtual machines use the UTM shared network for communication between the macOS host and Kubernetes nodes.

This approach keeps the Kubernetes environment local to the laptop and avoids dependencies on external cloud infrastructure. Each Kubernetes node receives an IP address on the UTM shared network, while Kubernetes pod networking is provided separately by Calico.


#### kubeadm:
kubeadm is used to bootstrap a standard Kubernetes cluster without abstracting the underlying control-plane components. This provides direct exposure to Kubernetes cluster configuration and administration while satisfying the requirement to use a standard Kubernetes installation rather than a development-oriented distribution such as Minikube or Kind.
- Setup control-plane node on Ubuntu with `scripts/ubuntu/02_control_plane.sh`
- Join as worker nodes on Ubuntu with `scripts/ubuntu/03_worker_node_join.sh`

#### containerd:
containerd is used as the container runtime for the Kubernetes cluster.

Its responsibilities include pulling and managing container images, creating and running containers, and managing the container lifecycle. Kubernetes pod networking is handled separately through the Container Network Interface (CNI).

- Setup containerd on Ubuntu with `scripts/ubuntu/01_common_setup.sh`

#### Calico:
Calico is used as the Kubernetes Container Network Interface (CNI) implementation. It provides pod-to-pod networking across the cluster and supports Kubernetes NetworkPolicy for controlling network communication between workloads.

The cluster uses `10.244.0.0/16` as pod CIDR. This range was selected instead of Calico's commonly used `192.168.0.0/16` range to avoid potential address overlap with the UTM shared network used by the virtual machines.

- Setup Calico on Ubuntu with `scripts/ubuntu/02_control_plane.sh`

### 4.2 Kubernetes Authentication and RBAC
#### User certificate lifecycle
1. Generate user private key
2. Create CSR with user group
    - signerName: kubernetes.io/kube-apiserver-client
    - usages: client auth
    - CN = [NAME]
    - O  = [GROUP]
3. Create Kubernetes CertificateSigningRequest 
4. Administrator approves CSR
5. Kubernetes issues client certificate
6. Create kubeconfig with certificate + private key
7. kubectl authenticates against kube-apiserver
8. Access cluster using kubectl

The actions is done with `scripts/k8s/create-admin-user.sh` and `scripts/k8s/create-non-admin-user.sh`

#### RBAC
To implement least-privilege access control, the following RBAC resources has been created:

ClusterRole:
- cluster-admin
- view
- edit

RoleBinding:
- k8s-api-admins - cluster-admin in all namespaces
- k8s-api-users - view and edit in default namespace

### 4.3 Argo CD
By following GitOps model, Argo CD is used to deploy Kubernetes resources including infrastructure and applications to the cluster.

#### Infrastructure:
- cert-manager # Automated certificate management
- gateway-api # Gateway API implementation for Kubernetes
- k8s-api-access # RBAC for user access
- local-path-provisioner # Local storage provisioner
- nginx-gateway-fabric # NGINX Gateway Fabric
- nginx-routing # NGINX routing

#### Applications:
- nginx-demo # Demo NGINX application with HTTP and HTTPS access
- teleport # Demo Teleport application

Argo CD was installed in the cluster with following command:
```sh
kubectl create namespace argocd
kubectl apply -n argocd --server-side --force-conflicts -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl patch svc argocd-server -n argocd -p '{"spec": {"type": "LoadBalancer"}}'
```

To initialise the Argo CD admin password, use the following command:
```sh
argocd admin initial-password -n argocd
```

The Argo CD application configuration is stored in https://github.com/victorc9782/teleport-k8s.
Argo CD in the cluster will monitor this repo and deploy the resources to the cluster.

To add an application to Argo CD, use the following command with cluster-admin role:
```sh
kubectl apply -f argocd/<argocd-application-name>.yaml -n argocd
```

Argo CD URL: https://argocd.local:31996.  
Remarks: `argocd.local` is added to Macbook `/etc/hosts`

### 4.4 Nginx Application Deployment
#### 4.4.1 Nginx Demo Application
nginx-demo is a simple Nginx-based web application deployed to the Kubernetes cluster. It serves the static web content required for the challenge, including the peach cheesecake recipe.

The application is packaged as a Helm chart and deployed through Argo CD using a GitOps workflow.

The Helm chart is stored at:

https://github.com/victorc9782/teleport-k8s/application/nginx-demo

The corresponding Argo CD Application resource is defined at:

https://github.com/victorc9782/teleport-k8s/argocd/nginx-demo.yaml

Argo CD syncs the related resources in Git repository and deploys them to the Kubernetes cluster.

#### 4.4.2 Nginx Gateway Fabric and Routing
The app support both HTTP and HTTPS access with Gateway API and Nginx Gateway Fabric.
The related components are installed with Argo CD in the cluster:
- gateway-api - provides the Kubernetes Gateway API CRDs
- nginx-gateway-fabric - Gateway API controller and processes the Gateway API resources
- nginx-routing - ArgoCD application defines the Gateway and HTTPRoute resources used to expose the Nginx demo application

The local kubeadm environment does not provide a cloud load-balancer implementation. Therefore, a Kubernetes LoadBalancer Service cannot automatically provision an externally reachable load balancer as it would in a managed cloud environment.

To make the application accessible from the macOS host, the NGINX Gateway Fabric Service is exposed using NodePort.

The request flow is:
```
MacBook Browser
       |
       | nginx-demo.local
       v
Kubernetes Node IP
       |
       | NodePort
       v
NGINX Gateway Fabric
       |
       v
    Gateway
  ┌────┴─────┐
  │          │
HTTP       HTTPS
:80         :443
  │          │
  │       TLS termination
  │          │
  └────┬─────┘
       |
       v
   HTTPRoute
       |
       v
nginx-demo Service :80
       |
       v
   Nginx Pod :80
```
The Gateway defines HTTP and HTTPS listeners for the hostname nginx-demo.local.

For HTTPS traffic, the Gateway references a TLS certificate managed by cert-manager. TLS is terminated at the NGINX Gateway Fabric layer, after which the request is routed internally as HTTP.

The HTTPRoute matches requests for nginx-demo.local and forwards them to the nginx-demo Kubernetes Service on port 80. The Service then load-balances the request to the available Nginx application pods.

Because nginx-demo.local is a private hostname and is not registered in public DNS, a static entry is added to the macOS `/etc/hosts file to resolve the hostname to a reachable Kubernetes node IP.

This allows the application to be accessed from the local browser using:

http://nginx-demo.local

https://nginx-demo.local

### 4.5 cert-manager
cert-manager is used to automate the issuance and lifecycle management of TLS certificates within the Kubernetes cluster. It is installed and managed declaratively through Argo CD.

For the Nginx demo application, cert-manager creates a self-signed TLS certificate for nginx-demo.local. The corresponding Certificate resource and generated Kubernetes TLS Secret are stored in the default namespace, where they can be referenced by the HTTPS listener configured on the Gateway.

The certificate is used by NGINX Gateway Fabric to terminate HTTPS traffic at the Gateway layer before forwarding the request to the application over HTTP.

Because the Kubernetes cluster runs on a private UTM network and nginx-demo.local is not publicly resolvable or reachable, a public ACME certificate authority such as Let's Encrypt cannot be used directly for this local homelab. A cert-manager SelfSigned Issuer is therefore used instead.

In a production environment, the same declarative Certificate workflow could be integrated with an organisation's internal PKI or a public ACME certificate authority, depending on the application's DNS configuration and accessibility.

### 4.6 Teleport
Teleport Community Edition is deployed to the Kubernetes cluster through Argo CD using the Teleport Helm chart version 18.11.0.

The corresponding Argo CD Application resource is defined at:

https://github.com/victorc9782/teleport-k8s/argocd/teleport.yaml

Referred document: https://goteleport.com/docs/installation/self-hosted/helm-deployments/kubernetes-cluster/

#### 4.6.1 PersistentVolume
The Teleport Auth Service requires persistent storage to maintain cluster state. While Kubernetes supports PersistentVolume (PV) and PersistentVolumeClaim (PVC) resources, the local kubeadm cluster running on UTM does not provide a default dynamic storage provisioner or StorageClass such as those commonly available in managed cloud Kubernetes services.

To provide persistent storage in the local environment, local-path-provisioner is deployed to the cluster. It dynamically provisions local persistent volumes using storage attached to the Kubernetes nodes.

local-path-provisioner was selected for the homelab because it is lightweight, simple to operate, requires no additional external storage infrastructure, and is suitable for a small local lab environment.

However, the provisioned storage is tied to an individual Kubernetes node and therefore does not provide the high availability, replication, or resilience expected from a production storage platform.

In a production environment, Teleport persistent storage would normally use an appropriate highly available storage solution, such as cloud-provider block storage, a Container Storage Interface (CSI) based storage platform, or another organisational storage service. Backup, recovery, replication, and availability requirements would also need to be considered as part of the storage design.

#### 4.6.2 Teleport Network Access
Teleport differs from the Nginx demo application because the Teleport Proxy Service is designed to receive TLS traffic directly and uses port 443 as its primary external entry point.

The Teleport Proxy multiplexes multiple Teleport protocols over the TLS connection. Therefore, TLS is passed through the NGINX Gateway Fabric layer rather than being terminated by the Gateway.

The external hostname used for the Teleport service is:

teleport.victor.local

```
The traffic flow is:

MacBook Client / Browser / tsh
          |
          | HTTPS / TLS :443 port fowarding to <KUBERNETES_NODE_IP> 
          | teleport.victor.local
          v
Kubernetes Node
          |
          | NodePort
          v
Teleport Cluster Service
```

Because teleport.victor.local is a private hostname, a corresponding entry is configured in the macOS `/etc/hosts` file so that the hostname resolves to a reachable Kubernetes node.

#### 4.6.3 Teleport Configruation
To grant access to user for validation,  local user is created based on the official instructions.

```
# Create member.yaml
kind: role
version: v7
metadata:
  name: member
spec:
  allow:
    kubernetes_groups: ["system:masters"]
    kubernetes_labels:
      '*': '*'
    kubernetes_resources:
      - kind: '*'
        namespace: '*'
        name: '*'
        verbs: ['*']
```

Execute below commands with `kubeconfig` of admin to create the role:
```
kubectl exec -i deployment/teleport-cluster-auth -- tctl create -f < member.yaml
```

## 5. Testing and Validation
Cluster Access:
```sh
Non-admin access:
export KUBECONFIG=non-admin.kubeconfig 
kubectl auth can-i create deployments -n default # expect yes
kubectl auth can-i create deployments -n kube-system # expect no
```

Admin access:
```sh
export KUBECONFIG=admin.kubeconfig 
kubectl auth can-i create deployments -n default # expect yes
kubectl auth can-i create deployments -n kube-system # expect yes
```

Argo CD: Access with browser https://argocd.local:31996/

Nginx demo: Access with browser https://nginx-demo.local:30443

Teleport: Access with browser https://teleport.victor.local (With port-forwarding as Teleport has error with non-443 port)

## 6. Design Trade-offs and Limitations
The architecture and configuration used in this project are designed for a local homelab environment. Several decisions prioritise simplicity, reproducibility, and minimal infrastructure requirements over the high availability, scalability, and operational controls expected in a production environment.

### 6.1 Single control plane
The Kubernetes cluster uses a single control-plane node.

Benefit: 
- Simple to deploy and maintain.
- Requires fewer compute resources.
- Appropriate for a local homelab environment

Limitation: 
- The control-plane node represents a single point of failure.
- Failure of the node would make the Kubernetes API and control-plane services unavailable until the node is recovered.
- The design does not provide control-plane or etcd high availability.

Production consideration:

A production cluster would normally use multiple control-plane nodes, commonly three or more, with an appropriate load-balancing mechanism in front of the Kubernetes API server. This provides redundancy for the Kubernetes control plane and etcd.

### 6.2 Local UTM environment
The kubeadm cluster is hosted locally using Ubuntu virtual machines running on UTM.

Benefit:
- No external cloud infrastructure or associated cloud costs are required.
- The complete environment can be created and tested locally.
- Provides direct access to the Kubernetes nodes and underlying operating system for administration and troubleshooting.

Limitation:
- No cloud-provider integration is available for automatically provisioning external load balancers.
- Networking differs from a managed Kubernetes environment.
- External application access requires additional mechanisms such as NodePort and local hostname resolution.
- Compute, memory, storage, and network capacity are limited by the host laptop.
- The environment does not provide infrastructure-level high availability.

Production consideration:

A production deployment would normally use dedicated infrastructure or a cloud platform with managed Kubernetes service, load-balancing, storage, monitoring, and high-availability capabilities.

### 6.3 Kubernetes RBAC and kubeconfig Access
Kubernetes users in this homelab are authenticated using X.509 client certificates, with their permissions controlled through Kubernetes RBAC. User kubeconfig files containing the required cluster and client certificate information are generated and distributed manually.

Benefits:
- Uses native Kubernetes authentication and authorisation mechanisms.
- No additional identity-management platform is required.
- Provides granular access control through Role, RoleBinding, ClusterRole, and ClusterRoleBinding resources.
- Demonstrates namespace-scoped least-privilege access for application users.

Limitations:
- User certificate issuance and kubeconfig distribution require administrative intervention.
- Certificate renewal and rotation must be managed separately.
- Revoking user access requires appropriate certificate and RBAC lifecycle management.
- Manual kubeconfig distribution becomes increasingly difficult to manage as the number of users and clusters increases.
- Secure storage and distribution of private keys must be carefully controlled.

Production consideration:
In a production environment, user identity and Kubernetes access would typically be integrated with a secure and automated identity-management process. 
Short-lived credentials, centralised identity providers, automated credential issuance, and auditable access workflows can reduce the operational risks associated with manually distributed kubeconfig files.

### 6.4 Nginx application deployment
For simplicity, the Nginx demonstration resources in this homelab are deployed to the Kubernetes default namespace with fixed resource and replica.

Benefits:
- Reduces the amount of configuration required for a small demonstration environment.
- Keeps the focus of the homelab on Kubernetes authentication, RBAC, networking, and application deployment.

Limitations:
- The default namespace provides limited logical separation between workloads.
- Namespace-scoped security and resource-management controls are more difficult to apply independently when multiple applications share the same namespace.
The approach does not represent the stronger workload isolation normally expected in a larger Kubernetes environment.
- Resource and replica are fixed, not scalable.

Production consideration:

Production workloads would typically be organised into dedicated namespaces based on application, team, environment, or another organisational boundary. Appropriate namespace-scoped controls could then be applied, including:

- Kubernetes RBAC
- NetworkPolicy
- ResourceQuota
- Pod security controls
- HPA

The exact namespace model should be selected according to the organisation's tenancy, security, and operational requirements.

### 6.5 Local path provisioner for PV
The local environment uses local-path-provisioner to provide dynamically provisioned persistent storage for the Teleport Auth Service.

Benefits:
- Lightweight and simple to deploy.
- Does not require additional external storage infrastructure.
- Supports dynamic provisioning of Kubernetes PersistentVolumes.
- Suitable for a local lab or homelab environment.

Limitations:
- Persistent data is tied to the storage of an individual Kubernetes node.
- Storage is not replicated between nodes.
- Failure or loss of the underlying node or disk can make the stored data unavailable.
- The solution does not provide the high availability or resilience expected from production storage.

Production consideration:

A production deployment should use an appropriate highly available storage solution, such as cloud-provider block storage, a CSI-based storage platform, or an organisational storage service.

The production storage design should also consider:
- Backup and restoration
- Data replication
- Disaster recovery
- Storage availability
- Performance requirements
- Capacity planning
- Encryption at rest

### 6.6 Teleport Configuration
Teleport's built-in ACME configuration is disabled for this homelab because the cluster is hosted on a private UTM network and the teleport.victor.local hostname is not publicly resolvable or reachable by a public ACME certificate authority.

Benefits:
- Avoids unnecessary external dependencies in the local environment.
- Allows Teleport to operate using certificates appropriate for the private homelab environment.

Limitations:
- Locally generated or privately issued certificates are not automatically trusted by external clients.
- The configuration does not demonstrate automated certificate issuance from a publicly trusted certificate authority.

Production consideration:
A production Teleport deployment should use a certificate-management approach appropriate to the organisation's infrastructure and security requirements. This may include Teleport's ACME integration with a public certificate authority such as Let's Encrypt, an organisational PKI, or certificates provisioned through another certificate-management platform.

If ACME is used, a publicly resolvable hostname and appropriate ACME account configuration, including a valid administrative email address, should be provided.
