# Deployment Log — 2026-07-12

Record of the first end-to-end deployment of this project: infra provisioning, the
issues hit along the way, and how each was resolved. Kept alongside `README.md` as
a reference for future re-deploys and as evidence of real troubleshooting for
interviews.

## 1. Initial `terraform apply` failed — stale AWS versions

```
Error: creating RDS DB Instance: InvalidParameterCombination: Cannot find version 15.4 for postgres
Error: creating EKS Cluster: InvalidParameterException: unsupported Kubernetes version 1.28
```

Both defaults in `variables.tf` had aged out of AWS support (Postgres 15.4 and EKS
1.28 are no longer offered for new resources in `ap-south-1`).

**Fix** — queried the account directly instead of guessing, since these lists drift
over time:

```bash
aws rds describe-db-engine-versions --engine postgres --region ap-south-1
aws eks describe-cluster-versions --region ap-south-1
```

Updated the two defaults:

| Variable | File | Old | New |
|---|---|---|---|
| `cluster_version` | `variables.tf:34` | `1.28` | `1.33` (stable STANDARD_SUPPORT, not the bleeding-edge 1.36) |
| `db_engine_version` | `variables.tf:67` | `15.4` | `15.18` (latest available patch on major version 15) |

Verified with `terraform plan` (clean, 12 resources to add) before re-running
`terraform apply`, which completed successfully — EKS cluster, node group, and RDS
instance all created.

## 2. Connected kubectl to the new cluster

```bash
aws eks update-kubeconfig --region ap-south-1 --name devops-portfolio-dev
kubectl get nodes   # 2 nodes, Ready
```

## 3. `docker login` to ECR failed — PowerShell pipe corruption

```
Error response from daemon: login attempt to ...amazonaws.com/v2/ failed with status: 400 Bad Request
```

`aws ecr get-login-password | docker login --password-stdin ...` piped through
PowerShell corrupts the token (encoding/newline handling on the native-process
stdin pipe), even though the token itself checked out fine in isolation (1812
chars, correct account ID via `aws sts get-caller-identity`).

**Fix** — route the token through `cmd.exe` instead of PowerShell's native pipe:

```powershell
$token = aws ecr get-login-password --region ap-south-1
[System.IO.File]::WriteAllText("$env:TEMP\ecr_token.txt", $token)
cmd /c "type `"$env:TEMP\ecr_token.txt`" | docker login --username AWS --password-stdin 975050192962.dkr.ecr.ap-south-1.amazonaws.com"
```

Also: the README's `<account_id>` placeholder can't be typed literally in
PowerShell — `<` is a reserved redirection operator there. Replaced with the real
account ID (`975050192962`, from `aws sts get-caller-identity`).

## 4. `docker build` failed — OneDrive Files-On-Demand vs. Docker Desktop WSL2

```
ERROR: failed to solve: failed to read dockerfile: invalid file request Dockerfile
```

The project lives under `OneDrive\Desktop\...`. `app/Dockerfile` and `app/app.py`
had the `ReparsePoint` Windows file attribute (OneDrive cloud-placeholder marker).
Docker Desktop's WSL2 file-sync (9P protocol) can't reliably read files with that
attribute, regardless of whether the file is actually hydrated locally — forcing a
read via `Get-Content -Raw` didn't clear the flag or fix the build.

**Fix** — copy the `app/` directory to a plain local path outside OneDrive (used
the session scratch directory) and build from there:

```powershell
Copy-Item -Path "app\*" -Destination $buildDir -Recurse -Force
docker build -t devops-portfolio-app $buildDir
```

Build succeeded immediately once run outside OneDrive.

**Takeaway for future builds from this repo:** always build from a non-OneDrive
copy, or move the whole project out of OneDrive / disable Files-On-Demand for this
folder.

## 5. Tagged and pushed the image

```bash
docker tag devops-portfolio-app:latest 975050192962.dkr.ecr.ap-south-1.amazonaws.com/devops-portfolio-app:latest
docker push 975050192962.dkr.ecr.ap-south-1.amazonaws.com/devops-portfolio-app:latest
```

(ECR repo `devops-portfolio-app` already existed in the account.)

## 6. Deployed to the cluster

Updated `k8s/deployment.yaml` to point at the real image instead of the
`<ECR_REPO_URL>` placeholder:

```
image: 975050192962.dkr.ecr.ap-south-1.amazonaws.com/devops-portfolio-app:latest
```

```bash
kubectl apply -f k8s/deployment.yaml
kubectl apply -f k8s/service.yaml
```

## 7. Verified end-to-end

- `kubectl get pods` — both replicas `Running`.
- Internal check via `kubectl port-forward` → `/` and `/health` both responded correctly.
- External check — NLB provisioned by the `LoadBalancer` service came up at
  `a3b4c675108c84953a5b8ebe9484de9c-436863131.ap-south-1.elb.amazonaws.com`; took
  a couple of minutes for cross-AZ target health checks to pass, then served
  traffic correctly:
  ```json
  {"message":"Hello from EKS!","pod":"devops-portfolio-app-59f688b5b4-2vbhm"}
  ```

## Remaining / optional steps (not yet done)

- **CI/CD**: add `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` as GitHub repo
  secrets so pushes to `main` touching `app/` or `k8s/` auto-build and redeploy.
- **Monitoring**: install `kube-prometheus-stack` via Helm and wire up a Grafana
  panel on `app_requests_total`.

## Cost reminder

Live infra now running: EKS control plane + 2× t3.medium nodes + NAT Gateway + RDS
db.t3.micro (~$180/month if left up indefinitely). To tear down:

```bash
kubectl delete -f k8s/   # delete the LoadBalancer service first, or Terraform
                          # will orphan the NLB
terraform destroy
```
