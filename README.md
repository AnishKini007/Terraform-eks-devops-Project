# DevOps Portfolio Project — Terraform + EKS + RDS + CI/CD + Monitoring

A self-contained cloud infrastructure project: Terraform provisions a VPC, an
EKS cluster, and an RDS database on AWS; a small Flask app gets built,
containerized, and deployed onto the cluster through a CI/CD pipeline; and
Prometheus/Grafana monitor it. Built to demonstrate hands-on cloud
infrastructure skills alongside existing CI/CD and DevSecOps experience.

## Architecture

```
                         ┌───────────────────────────────────────────┐
                         │                  VPC (10.20.0.0/16)         │
                         │                                             │
   Internet ──► NAT ──►  │  Public subnets          Private subnets    │
                         │  (NAT GW, ALB/NLB)   ┌──────────────────┐   │
                         │                      │   EKS Node Group  │   │
                         │                      │  ┌────────────┐  │   │
                         │                      │  │ App Pod x2 │  │   │
                         │                      │  └─────┬──────┘  │   │
                         │                      └────────┼─────────┘   │
                         │                               │             │
                         │                      ┌────────▼─────────┐   │
                         │                      │   RDS (Postgres)  │   │
                         │                      │  private subnet   │   │
                         │                      └───────────────────┘   │
                         └───────────────────────────────────────────┘
```

- **VPC**: 2 public + 2 private subnets across 2 AZs, single NAT gateway (cost-optimized for a portfolio project — a real prod setup would use one NAT per AZ for HA).
- **EKS**: managed control plane + a managed node group of `t3.medium` nodes in private subnets.
- **RDS**: Postgres, private-only, reachable exclusively from the EKS node security group.
- **App**: Flask service with `/health` (liveness/readiness) and `/metrics` (Prometheus scrape target).
- **CI/CD**: GitHub Actions builds the Docker image, pushes to ECR, updates kubeconfig, and applies the K8s manifests. (You already know GitLab CI cold — porting this pipeline to a `.gitlab-ci.yml` with `docker build/push` + `kubectl apply` stages is a straightforward exercise if you'd rather keep everything in GitLab.)
- **Monitoring**: kube-prometheus-stack via Helm (steps below), scraping the app's `/metrics` endpoint automatically via the pod annotations already in `k8s/deployment.yaml`.

## Prerequisites

- AWS account with billing alerts set up (see Cost Warning below)
- AWS CLI configured (`aws configure`)
- Terraform >= 1.6
- kubectl
- Helm 3
- Docker

## Setup steps

### 1. Provision the infrastructure

```bash
cp terraform.tfvars.example terraform.tfvars
# edit terraform.tfvars — at minimum set a real db_password

terraform init
terraform plan   # review what will be created before applying
terraform apply
```

This takes 12-15 minutes — EKS cluster creation is slow. That's normal.

### 2. Point kubectl at the new cluster

```bash
terraform output configure_kubectl
# copy-paste and run the command it prints, something like:
aws eks update-kubeconfig --region ap-south-1 --name devops-portfolio-dev

kubectl get nodes   # confirm nodes show up as Ready
```

### 3. Create an ECR repo and push the app image (first time, manually)

```bash
aws ecr create-repository --repository-name devops-portfolio-app --region ap-south-1

aws ecr get-login-password --region ap-south-1 | docker login --username AWS \
  --password-stdin <account_id>.dkr.ecr.ap-south-1.amazonaws.com

docker build -t devops-portfolio-app ./app
docker tag devops-portfolio-app:latest <account_id>.dkr.ecr.ap-south-1.amazonaws.com/devops-portfolio-app:latest
docker push <account_id>.dkr.ecr.ap-south-1.amazonaws.com/devops-portfolio-app:latest
```

### 4. Deploy the app

```bash
sed -i "s|<ECR_REPO_URL>|<account_id>.dkr.ecr.ap-south-1.amazonaws.com/devops-portfolio-app|" k8s/deployment.yaml
kubectl apply -f k8s/deployment.yaml
kubectl apply -f k8s/service.yaml
kubectl get svc devops-portfolio-app   # wait for EXTERNAL-IP, then curl it
```

### 5. Wire up the CI/CD pipeline

Add these as GitHub repo secrets: `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`
(ideally for an IAM user scoped only to ECR push + `eks:DescribeCluster` +
the ability to deploy — not your root/admin credentials). After that, any
push to `main` touching `app/` or `k8s/` rebuilds and redeploys automatically.

### 6. Install monitoring

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
helm install monitoring prometheus-community/kube-prometheus-stack \
  --namespace monitoring --create-namespace

kubectl port-forward -n monitoring svc/monitoring-grafana 3000:80
# open http://localhost:3000 (default login: admin / prom-operator)
# add a dashboard/panel querying app_requests_total to see your app's traffic
```

## ⚠️ Cost warning — read before running `terraform apply`

This is NOT free tier. Rough running costs if left up:

| Resource | Approx. cost |
|---|---|
| EKS control plane | $0.10/hr (~$73/month) |
| 2x t3.medium nodes | ~$0.083/hr total (~$60/month) |
| NAT Gateway | ~$0.045/hr + data (~$33/month) |
| RDS db.t3.micro | ~$0.017/hr (~$12/month) |

**Run `terraform destroy` the same day you're done experimenting.** Set a
billing alarm in AWS Budgets for $10-20 as a safety net before you start.

```bash
kubectl delete -f k8s/   # delete the LoadBalancer service FIRST — Terraform
                          # doesn't know about the NLB it created and will
                          # leave it orphaned (and billing) otherwise
terraform destroy
```

## What this project demonstrates (for interviews / resume)

- Provisioning cloud infrastructure as code, not clicking through a console
- Understanding of network segmentation (public vs. private subnets, security groups as the only path between tiers)
- Container image build → registry → orchestrator deployment pipeline
- Kubernetes fundamentals: deployments, services, resource limits, health probes
- Observability: metrics instrumentation in the app itself, not just infra-level monitoring
- Awareness of cost tradeoffs (single NAT gateway, small instance sizes) — a real interview signal, since "I know how to keep AWS bills sane" matters to hiring managers

## Likely interview questions this project prepares you to answer

- "Walk me through what happens when you push code to main." (→ CI/CD pipeline flow)
- "How does your app reach the database, and how is that secured?" (→ security groups, private subnets)
- "Why single NAT gateway instead of one per AZ?" (→ cost vs. HA tradeoff — you can discuss both sides)
- "What would you change to make this production-ready?" (→ multi-AZ RDS, private-only EKS API endpoint, Terraform remote state + locking, secrets via AWS Secrets Manager instead of a tfvars file, HPA/cluster autoscaler)
