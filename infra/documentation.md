# Terraform: EKS cluster for PayTrack

This folder creates an Amazon EKS cluster and one managed node group inside a VPC that already exists. It was validated offline only. Nothing was applied, as the assessment requires.

## What it creates

| Resource | Purpose |
|---|---|
| `aws_iam_role.cluster` + 1 policy attachment | Role used by the EKS control plane (`AmazonEKSClusterPolicy`) |
| `aws_eks_cluster.this` | The cluster, in the existing private subnets, with a private-only API endpoint |
| `aws_iam_role.node` + 3 policy attachments | Role used by the worker nodes |
| `aws_eks_node_group.this` | Managed node group in the same private subnets |

Everything is written as plain resources, without a module, so the cluster, node group, IAM and networking settings are all visible in `main.tf`.

| File | Content |
|---|---|
| `versions.tf` | Terraform and AWS provider versions |
| `variables.tf` | Inputs |
| `main.tf` | Provider, IAM roles, cluster, node group |
| `outputs.tf` | Cluster name, endpoint, security group ID, node role ARN |
| `terraform.tfvars.example` | Example inputs with placeholders, no credentials |

## Versions

- AWS provider `~> 6.0`: any 6.x release, never a new major version. The lock file pins the tested version, 6.72.0.
- Terraform `>= 1.5.0`. Tested with 1.17.1 only.
- Kubernetes `1.36` in the example file. On 11 November 2026 it was in EKS standard support until 2 August 2027, and it was not the newest release.

## Assumptions

### Networking

- The VPC and the private subnets already exist and are managed by the platform team. This code does not create or change them.
- `private_subnet_ids` holds at least two subnets in different Availability Zones. EKS requires this.
- The subnets have enough free IP addresses. Every pod gets its own address from the subnet.
- The private subnets have a way out to AWS services, through a NAT gateway or VPC endpoints. Nodes need this to join the cluster and pull images. Without it the node group fails to create.
- No subnet tags are needed by this code. If an internal load balancer is added later, the subnets need the tag `kubernetes.io/role/internal-elb = 1`.
- `vpc_id` is an input but no resource uses it. EKS works out the VPC from the subnet IDs. It is kept because the provided example file includes it.

### Cluster access

- The Kubernetes API endpoint is private only. This fits an internal API. To use `kubectl`, a person must be inside the VPC, through a VPN or a bastion host, and the cluster security group must allow port 443 from that source. The security group ID is an output for this reason.
- GitHub-hosted runners cannot reach a private endpoint. The CI workflow therefore validates only and does not deploy.
- Authentication mode is `API`. The IAM identity that creates the cluster becomes its administrator. Nobody else has access until they receive an EKS access entry. No access entries are created here.
- AWS credentials come from the environment of whoever runs Terraform. No keys are in these files.

### Node access

- Nodes run in private subnets and are not reachable from the internet.
- SSH to the nodes is not opened. The node group has no `remote_access` block.

### IAM

- Both roles use AWS-managed policies only. No custom or administrator policy is attached.
- The node role uses `AmazonEC2ContainerRegistryPullOnly`, which is narrower than the older `ReadOnly` policy.
- `AmazonEKS_CNI_Policy` is attached to the node role because it is the simplest working setup. AWS recommends a separate role for the network plugin. See "Not included".

## Validation without creating cloud resources

Run from this folder:

```bash
terraform init -backend=false
terraform fmt && terraform fmt -check -recursive && terraform validate
```

| Command | What it checks |
|---|---|
| `fmt -check` | Formatting. Prints nothing when correct. |
| `init -backend=false` | Downloads the provider. Skips state storage, so it needs no AWS account. |
| `validate` | Syntax, references and argument names. It does not contact AWS. |

All three pass. `terraform plan` was not run because it needs AWS credentials. This means the configuration is proven to be valid, but it is not proven to apply successfully in a real account.

## Not included

These are recommendations, not implemented, to keep the solution small:

- A remote state backend, such as S3. It is needed before real use.
- Control plane logging and secret encryption with a customer-managed KMS key.
- A separate IAM role for the network plugin, so the CNI policy can leave the node role.
- Access entries for the platform team.
