# simpletimeservice

A minimal Python microservice that returns the current timestamp and visitor IP address,
containerised with Docker, and deployed to AWS ECS Fargate via Terraform — all driven
from a Linux server.

---

## Table of Contents

- [Project Overview](#project-overview)
- [Repository Structure](#repository-structure)
- [Architecture & Why ECS Fargate](#architecture--why-ecs-fargate)
- [Step 0 — Create Your AWS EC2 Server](#step-0--create-your-aws-ec2-server)
  - [Prerequisites — AWS Account](#prerequisites--aws-account)
  - [A. Create a Key Pair (for SSH access)](#a-create-a-key-pair-for-ssh-access)
  - [B. Launch the EC2 Instance](#b-launch-the-ec2-instance)
  - [C. Connect to the Server via SSH](#c-connect-to-the-server-via-ssh)
- [Server Setup — Install Required Tools](#server-setup--install-required-tools)
  - [1. Update the System](#1-update-the-system)
  - [2. Install Git](#2-install-git)
  - [3. Install Python 3.11+](#3-install-python-311)
  - [4. Install Docker](#4-install-docker)
  - [5. Install Terraform](#5-install-terraform)
  - [6. Install AWS CLI](#6-install-aws-cli)
- [Clone the Repository](#clone-the-repository)
- [Part 1 — Build and Test the App on the Server](#part-1--build-and-test-the-app-on-the-server)
  - [Run with Python](#run-with-python)
  - [Build and Run with Docker](#build-and-run-with-docker)
  - [Push the Image to DockerHub](#push-the-image-to-dockerhub)
- [Part 2 — Deploy to AWS with Terraform](#part-2--deploy-to-aws-with-terraform)
  - [Authenticate to AWS](#authenticate-to-aws)
  - [Configure Terraform Variables](#configure-terraform-variables)
  - [Deploy](#deploy)
  - [Access the Application](#access-the-application)
  - [Destroy Infrastructure](#destroy-infrastructure)
- [Infrastructure Details](#infrastructure-details)
- [Security Notes](#security-notes)
- [Troubleshooting](#troubleshooting)

---

## Project Overview

`SimpleTimeService` is an HTTP microservice with a single endpoint:

**`GET /`**

```json
{
  "timestamp": "2024-11-15T10:30:00.123456",
  "ip": "203.0.113.42"
}
```

It is built with Python (Flask), packaged into a minimal Docker image, and deployed to AWS
using ECS Fargate behind an Application Load Balancer (ALB).

---

## Repository Structure

```
.
├── app/
│   ├── app.py              # Flask application
│   ├── requirements.txt    # Python dependencies
│   └── Dockerfile          # Container build instructions
└── terraform/
    ├── main.tf             # Root module — wires everything together
    ├── variables.tf        # Input variable declarations
    ├── outputs.tf          # Output values (e.g. load balancer URL)
    ├── terraform.tfvars    # Your variable values (edit this before deploying)
    ├── vpc.tf              # VPC, subnets, IGW, NAT Gateway
    ├── ecs.tf              # ECS cluster, task definition, service
    └── alb.tf              # Application Load Balancer, target group
```

---

## Architecture & Why ECS Fargate

**Choice: AWS ECS Fargate + Application Load Balancer**

| Concern | Decision |
|---|---|
| Compute | ECS Fargate — serverless containers, no EC2 instances to manage |
| Networking | Custom VPC with public and private subnets across 2 Availability Zones |
| Ingress | Application Load Balancer in public subnets, port 80 |
| App placement | ECS tasks run in **private subnets only** — no public IPs |
| Outbound internet (image pulls) | NAT Gateway in public subnet |

**Why not EKS or plain EC2?**

- EKS adds significant overhead (control plane, node groups, kubectl) for a single stateless service.
- Plain EC2 requires OS patching, Docker daemon management, and instance lifecycle work.
- ECS Fargate is container-native, scales automatically, and needs zero server management.

**Traffic flow:**

```
Internet
   │
   ▼
Application Load Balancer   ← public subnets, port 80
   │
   ▼
ECS Fargate Tasks           ← private subnets, port 8080
   │
   ▼
NAT Gateway                 ← outbound only (image pulls, AWS API calls)
```

---

## Step 0 — Create Your AWS EC2 Server

This section walks you through creating a fresh Ubuntu server on AWS EC2 from scratch —
the machine from which you will build, push, and deploy everything.

> If you already have a server, skip to [Server Setup — Install Required Tools](#server-setup--install-required-tools).

### Prerequisites — AWS Account

You need an AWS account. If you don't have one:

1. Go to https://aws.amazon.com and click **Create an AWS Account**.
2. Enter your email, set a root password, and provide billing information.
3. Choose the **Free Tier** plan.
4. Once logged in, go to the **AWS Console** at https://console.aws.amazon.com.

> **Important:** Do not use your root account for day-to-day work. After signing in as
> root, go to **IAM → Users → Create User**, give it `AdministratorAccess`, and use
> that user for everything below.

---

### A. Create a Key Pair (for SSH access)

A key pair lets you securely SSH into your EC2 instance. You create it once and reuse it.

1. In the AWS Console, use the search bar at the top to search for **EC2** and open it.
2. In the left sidebar, scroll down to **Network & Security → Key Pairs**.
3. Click **Create key pair**.
4. Fill in the form:
   - **Name:** `simpletimeservice-key`
   - **Key pair type:** RSA
   - **Private key file format:**
     - Choose `.pem` if you are on Linux/macOS
     - Choose `.ppk` if you are on Windows and using PuTTY
5. Click **Create key pair**.

Your browser will automatically download the private key file (e.g. `simpletimeservice-key.pem`).

**Move and protect the key file on your local machine:**

```bash
# Move it to your SSH directory
mv ~/Downloads/simpletimeservice-key.pem ~/.ssh/

# Set strict permissions — SSH will refuse to use the key without this
chmod 400 ~/.ssh/simpletimeservice-key.pem
```

> Never share this file. Never commit it to Git.

---

### B. Launch the EC2 Instance

1. In the EC2 Console, click **Instances** in the left sidebar, then **Launch instances**.

2. **Name:** `simpletimeservice-server`

3. **Application and OS Image (AMI):**
   - Click **Browse more AMIs** if needed
   - Search for `Ubuntu Server 22.04 LTS`
   - Select the one labelled **Free tier eligible**
   - Architecture: `64-bit (x86)`

4. **Instance type:**
   - For development/testing: `t2.micro` (Free Tier eligible)
   - For heavier workloads (building large images): `t3.small` or `t3.medium`

5. **Key pair:** Select `simpletimeservice-key` from the dropdown.

6. **Network settings** — click **Edit**:
   - **VPC:** Leave as default (we are only creating the *deployment server* here; the
     app's VPC is created by Terraform later)
   - **Subnet:** Choose any public subnet (or leave as default)
   - **Auto-assign public IP:** Enable
   - **Firewall (security groups):** Select **Create security group**
     - Security group name: `simpletimeservice-server-sg`
     - Add the following inbound rules:

     | Type | Protocol | Port | Source | Why |
     |---|---|---|---|---|
     | SSH | TCP | 22 | My IP | Lets you SSH in from your machine only |

     > Using "My IP" is more secure than `0.0.0.0/0`. If your IP changes later,
     > update this rule: EC2 → Security Groups → Edit inbound rules.

7. **Configure storage:**
   - Size: `20 GiB` (default 8 GiB is too small for Docker images)
   - Volume type: `gp3`

8. Click **Launch instance**.

9. Click **View all instances**. Wait until the **Instance state** column shows
   `Running` and the **Status check** column shows `2/2 checks passed`
   (usually takes 1–2 minutes).

10. Click on your instance and copy the **Public IPv4 address** — you will need it to SSH in.

---

### C. Connect to the Server via SSH

**From Linux or macOS (Terminal):**

```bash
ssh -i ~/.ssh/simpletimeservice-key.pem ubuntu@<your-ec2-public-ip>
```

Replace `<your-ec2-public-ip>` with the IP address you copied (e.g. `54.172.45.130`).

When prompted `Are you sure you want to continue connecting?` — type `yes` and press Enter.

You should see a welcome banner and a prompt like:

```
ubuntu@ip-172-31-45-23:~$
```

You are now inside the server. Continue to the next section.

## Server Setup — Install Required Tools

> Run all commands as a user with `sudo` access.
> These instructions are written for **Ubuntu 22.04 / Debian 12**.
> If you are on Amazon Linux 2023, replace `apt` with `dnf` where noted.

### 1. Update the System

```bash
sudo apt update && sudo apt upgrade -y
```

### 2. Install Git

```bash
sudo apt install -y git
git --version
```

### 3. Install Python 3.11+

```bash
sudo apt install -y python3 python3-pip python3-venv
python3 --version
```

Expected output: `Python 3.11.x` or higher.

### 4. Install Docker

```bash
# Install dependencies
sudo apt install -y ca-certificates curl gnupg

# Add Docker's GPG key
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
  | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg

# Add the Docker repository
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
  | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# Install Docker
sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io

# Allow your user to run Docker without sudo
sudo usermod -aG docker $USER
newgrp docker

# Verify
docker --version
```

Test Docker works without sudo:

```bash
docker run hello-world
```

### 5. Install Terraform

```bash
# Add HashiCorp GPG key and repository
sudo apt install -y gnupg software-properties-common
wget -O- https://apt.releases.hashicorp.com/gpg \
  | gpg --dearmor \
  | sudo tee /usr/share/keyrings/hashicorp-archive-keyring.gpg > /dev/null

echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] \
  https://apt.releases.hashicorp.com $(lsb_release -cs) main" \
  | sudo tee /etc/apt/sources.list.d/hashicorp.list

sudo apt update
sudo apt install -y terraform

# Verify
terraform -version
```

Expected output: `Terraform v1.6.x` or higher.

### 6. Install AWS CLI

```bash
# Download and install AWS CLI v2
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
sudo apt install -y unzip
unzip awscliv2.zip
sudo ./aws/install

# Verify
aws --version

# Clean up installer files
rm -rf awscliv2.zip aws/
```

---

## Clone the Repository

```bash
git clone https://github.com/<your-username>/simpletimeservice.git
cd simpletimeservice
```

Replace `<your-username>` with your actual GitHub username.

---

## Part 1 — Build and Test the App on the Server

### Run with Python

```bash
cd app
pip install -r requirements.txt
python3 -m uvicorn main:app --reload
```

The server starts on port `8080`. Open a second terminal and test:

```bash
curl http://localhost:8080/
```

Expected response:

```json
{
  "timestamp": "2024-11-15T10:30:00.123456",
  "ip": "127.0.0.1"
}
```

Press `Ctrl+C` to stop the server.

### Build and Run with Docker

```bash
cd app

# Build the image
docker build -t simpletimeservice:latest .

# Run in the background
docker run -d -p 8080:8080 --name simpletimeservice simpletimeservice:latest

# Test it
curl http://localhost:8080/

# Confirm it runs as a non-root user
docker exec simpletimeservice whoami
# Expected output: appuser

# Stop and remove the container when done
docker stop simpletimeservice && docker rm simpletimeservice
```

### Push the Image to DockerHub

Terraform pulls the image from a public registry. You need a free DockerHub account:
https://hub.docker.com/signup

```bash
# Log in — enter your DockerHub username and password when prompted
docker login 

# Tag the image with your DockerHub username
docker tag simpletimeservice:latest <your-dockerhub-username>/simpletimeservice:latest

# Push it
docker push <your-dockerhub-username>/simpletimeservice:latest
```

Replace `<your-dockerhub-username>` with your actual username (e.g. `johndoe`).

After pushing, go to https://hub.docker.com, open the repository, and confirm its
visibility is **Public**. Terraform cannot pull a private image without credentials.

---

## Part 2 — Deploy to AWS with Terraform

> **Cost warning:** Deploying this infrastructure creates billable AWS resources
> (ALB, NAT Gateway, ECS tasks). Estimated cost: ~$1–3 per day while running.
> Always run `terraform destroy` when you are done.

### Authenticate to AWS

Your server needs AWS credentials to create infrastructure. Use one of these two methods:

---

**Method A — IAM Instance Profile (best if your server is an EC2 instance)**

No keys are stored on disk. The EC2 instance authenticates using an attached IAM Role.

1. In the AWS Console, go to **IAM → Roles → Create Role**.
2. Select trusted entity type: **AWS Service → EC2**.
3. Attach the `AmazonEC2FullAccess,AmazonECS_FullAccess,AutoScalingFullAccess,CloudWatchFullAccess,ElasticLoadBalancingFullAccess,IAMFullAccess` policy
4. Name the role (e.g. `ec2-terraform-role`) and create it.
5. Go to **EC2 → Instances**, select your server instance.
6. Click **Actions → Security → Modify IAM Role**, select the role, and save.

Verify the server can reach AWS:

```bash
aws sts get-caller-identity
```

You should see your AWS account ID and the attached role name. No further setup needed.

---

**Method B — AWS Access Keys (works on any server, including non-EC2)**

1. In the AWS Console, go to **IAM → Users → <your-user> → Security credentials**.
2. Click **Create access key** → select **Command Line Interface (CLI)** → create.
3. Copy the **Access Key ID** and **Secret Access Key**. You only see the secret once.

Configure the AWS CLI on your server:

```bash
cd
aws configure
```

Enter the values when prompted:

```
AWS Access Key ID [None]:     AKIAIOSFODNN7EXAMPLE
AWS Secret Access Key [None]: wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY
Default region name [None]:   us-east-1
Default output format [None]: json
```

Credentials are saved to `~/.aws/credentials`. Terraform reads them automatically.

Verify it works:

```bash
aws sts get-caller-identity
```

> **Security reminder:** Never paste credentials into any Terraform file or commit them
> to Git. `~/.aws/credentials` is the correct and safe location.

---

### Configure Terraform Variables

Open the variables file:

```bash
cd simpletimeservice/terraform
nano terraform.tfvars
```

Edit the values to match your setup:

```hcl
aws_region = "us-east-1"

# Container
container_image = "<dockerhub-username>/simpletimeservice:latest"
container_port  = 8080

# Task sizing
task_cpu    = 256
task_memory = 512

# Service capacity
desired_count = 2
min_capacity  = 2
max_capacity  = 10

# Scale out when average CPU across the service exceeds 60%.
scale_out_cpu_threshold = 60
# Scale in when average CPU drops below 20% (saves cost).
scale_in_cpu_threshold  = 20

# Networking
vpc_cidr             = "10.0.0.0/16"
public_subnet_cidrs  = ["10.0.1.0/24", "10.0.2.0/24"]
private_subnet_cidrs = ["10.0.11.0/24", "10.0.12.0/24"]

# Tags
project_name = "SimpleTimeService"
environment  = "dev"
```

Save and exit: `Ctrl+X` → `Y` → `Enter`.

---

### Deploy

All Terraform commands run from the `terraform/` directory.

**Step 1 — Initialise** (downloads providers and modules; run once):

```bash
terraform init
```

Expected: `Terraform has been successfully initialized!`

**Step 2 — Preview** (shows what will be created; no changes made yet):

```bash
terraform plan
```

Read through the plan. You should see ~25–30 resources planned: VPC, subnets, route
tables, NAT Gateway, ALB, target group, ECS cluster, task definition, and service.

**Step 3 — Apply** (creates all infrastructure):

```bash
terraform apply
```

Type `yes` when prompted. This takes approximately 3–5 minutes.

When complete you will see:

```
Apply complete! Resources: 28 added, 0 changed, 0 destroyed.

Outputs:

alb_dns_name = "http://simpletimeservice-alb-1234567890.us-east-1.elb.amazonaws.com"
```

---

### Access the Application

Wait about 60 seconds after apply finishes for ECS tasks to start and pass health checks.
Then test from the server:

```bash
curl http://simpletimeservice-alb-1234567890.us-east-1.elb.amazonaws.com/
```

Use the exact URL printed in your Terraform output. Expected response:

```json
{
  "timestamp": "2024-11-15T10:30:00.123456",
  "ip": "203.0.113.42"
}
```

To check the Health checks:

```bash
curl http://simpletimeservice-dev-alb-1234567890.us-east-1.elb.amazonaws.com 
```

```json
{"status":"ok"}
```

You can also paste the URL into a browser from any machine.

---

### Destroy Infrastructure

When you are done, tear everything down to stop AWS charges:

```bash
cd terraform
terraform destroy
```

Type `yes` when prompted. After it completes, verify in the AWS Console
(EC2 → Load Balancers, ECS → Clusters) that no resources remain.

---

## Infrastructure Details

| Resource | Details |
|---|---|
| VPC | Single VPC, `/16` CIDR |
| Subnets | 2 public + 2 private subnets across 2 Availability Zones |
| Internet Gateway | Attached to VPC; enables public subnets to reach the internet |
| NAT Gateway | 1 instance in a public subnet; gives private subnets outbound-only access |
| ALB | Internet-facing, in public subnets, port 80 |
| ECS Cluster | Fargate launch type — no EC2 instances |
| ECS Task | 256 CPU units, 512 MB memory; runs as non-root user `appuser` |
| ECS Service | Configured desired count; automatically replaces failed tasks |
| Security Group — ALB | Inbound: port 80 from `0.0.0.0/0` |
| Security Group — ECS | Inbound: port 8080 from ALB security group only |
| IAM Task Execution Role | Allows ECS to pull images and write to CloudWatch Logs |
| CloudWatch Logs | Log group `/ecs/simpletimeservice`, retained for 7 days |

---

## Security Notes

- **Non-root container:** The app runs as `appuser` (UID 1001). Root access is dropped
  in the Dockerfile before `CMD`.
- **Private subnets only:** ECS tasks have no public IPs and cannot be reached directly
  from the internet.
- **Least-privilege security groups:** ECS tasks accept traffic only from the ALB
  security group, not from the open internet.
- **No secrets in code:** AWS credentials never appear in Terraform files or Git history.
  Use `~/.aws/credentials` (Method B) or an EC2 instance profile (Method A).
- **Minimal base image:** `python:3.11-slim` keeps the image small and reduces the
  attack surface.

---
