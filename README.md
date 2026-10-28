tofu output -raw sample_url
# first-tofu EKS Gitless GitOps

This playground runs one EKS cluster in `us-east-1`, with `dev` and `prod` namespaces. The D2 fleet, infrastructure, and apps layers live in this repository as `fleet/`, `infra/`, and `apps/`; Flux reconciles signed OCI artifacts from ECR and does not clone Git.

The cluster uses a dedicated two-AZ VPC, one `m6a.large` worker in one AZ (maximum two), EBS CSI with encrypted `gp3`, and an ALB restricted to the workstation's current public IPv4 `/32`. Infrastructure, GitHub OIDC publishing, ECR, Pod Identity, and storage are managed by OpenTofu.

## Deploy

The OpenTofu state and plans use enforced KMS-backed encryption. Initialize and inspect plans before applying changes:

```sh
tofu init
tofu validate
tofu plan
tofu apply
```

After the repository exists at `https://github.com/ilkomiliev/eks-flux-d2` and GitHub Actions has published the `main` artifacts, install Flux without Helm:

```sh
aws eks update-kubeconfig --region us-east-1 --name first-tofu-eks
kubectl apply --server-side --field-manager=kustomize-controller -k fleet/flux-operator
kubectl rollout status deployment/flux-operator -n flux-system
kubectl apply --server-side --field-manager=kustomize-controller -k fleet/bootstrap
kubectl wait fluxinstance/flux -n flux-system --for=condition=Ready --timeout=5m
kubectl apply --server-side --field-manager=kustomize-controller -f fleet/bootstrap/fleet-source.yaml
```

The first bootstrap is intentionally separate from Git. The operator creates its Flux distribution and CRDs before `fleet-source.yaml` is applied. Flux then reconciles cert-manager, namespaces, and the remaining controllers in dependency order. To install the controller layer before the first fleet artifact is available, use:

```sh
kubectl apply --server-side --force-conflicts --field-manager=kustomize-controller -k infra/cert-manager
kubectl rollout status deployment/cert-manager -n cert-manager
kubectl apply --server-side --force-conflicts --field-manager=kustomize-controller -k infra/controllers
```

The built-in Flux Web UI is exposed at the ALB DNS name on the `flux-web` Ingress. It uses HTTPS, the existing ACM certificate, and the ALB security group restricted to the current workstation `/32`. The UI uses its default anonymous, read-only view; update the ALB allowlist if your public IP changes.

The cluster's Flux service accounts use IAM roles; GitHub Actions uses OIDC. No PAT or AWS key is committed or required in GitHub secrets. The OCI source reports `MANIFEST_UNKNOWN` until the repository's first `main` workflow run publishes its signed fleet artifact.

## Delivery

On pushes to `main`, CI validates the Kustomize builds, builds the Superset image with the PostgreSQL driver, publishes the fleet and infrastructure artifacts plus the dev application artifact to ECR, and signs the artifacts and image using GitHub OIDC keyless Cosign. Superset images are referenced by immutable commit or release tags.

After a version tag such as `v1.2.3` has passed CI and been verified in `dev`, run **Promote verified release to prod** from GitHub Actions and enter that tag. The workflow copies the exact signed app artifact and Superset image to the `prod` tags; Flux then reconciles the `prod` namespace. The workflow uses the GitHub `prod` environment as an optional approval gate.

Before enabling workflows, configure the GitHub repository's default branch as `main`, enable Actions, and create a protected `prod` environment if an approval gate is desired. The local workspace has no Git remote configured; these files have not been pushed.

## Workloads And Secrets

The operators are installed from release-pinned raw Kustomize manifests, not Helm charts: Apache Superset Operator `v0.3.0`, Zalando Postgres Operator `v2.0.3`, Valkey Operator `v0.8.0`, and AWS Load Balancer Controller `v2.13.4`. Superset uses PostgreSQL for metadata and Valkey for caches. Valkey is intentionally configured as one primary with database 0 and hash-tagged cache prefixes to fit its Cluster-mode-only API and Superset's Redis client.

The Superset and Valkey operator APIs are alpha; Valkey's operator has no backup/restore and is not production-ready. `prod` is a promotion test namespace, not a production deployment. Each namespace has a single Postgres instance and single Valkey primary on `gp3`; persistent data is deleted when its PVCs are removed.

Superset credentials are SOPS-encrypted with the dedicated `alias/first-tofu-gitops-secrets` KMS key. Flux's Kustomize controller has decrypt-only access to that key. Do not replace these files with plaintext or print decrypted output. To rotate the initial development admin password, change it through Superset or update it with SOPS and trigger a reconciliation.

## Cleanup And Cost

Destroy the OpenTofu infrastructure root to remove EKS, the cluster workloads, ECR repositories, and IAM roles. The OpenTofu state key, legacy add-ons key, and GitOps SOPS key/alias are intentionally retained. The encrypted OpenTofu state and plans still require the state key; the SOPS key must remain while encrypted app manifests need decryption.

The earlier continuous-cost estimate was about $167/month before ALB LCU and data transfer. The GitOps KMS key adds roughly $1/month. Actual charges vary by region, usage, and pricing changes; delete the cluster when the playground is idle.