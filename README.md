# Self-Hosted GitHub Actions Runners on Azure

Automate the deployment and configuration of self-hosted GitHub Actions runners on Azure using **Terraform** for infrastructure and **Ansible** for VM setup.

## Overview

1. **Terraform** provisions Azure resources: resource group, virtual network, subnet, and Linux VMs with public IPs.
2. **Ansible** installs the GitHub Actions runner on each VM, registers it with your repository, and runs it as a service.
3. Runners appear in your repo under **Settings → Actions → Runners** and are ready for workflows.

You can run the process **manually** (Steps 1–4 below) or **automatically** via the GitHub Actions workflow (see [Automated deployment](#automated-deployment-github-actions)).

**CLI commands:** See [docs/CLI-COMMANDS.md](docs/CLI-COMMANDS.md) for copy-paste Azure, GitHub, Terraform, and Ansible commands (OIDC setup, secrets, manual deploy, cleanup).

---

## Automated deployment (GitHub Actions)

A workflow (`.github/workflows/deploy-runners.yml`) automates the full pipeline: Terraform apply → generate inventory → Ansible configure. It runs on **workflow_dispatch** (manual) or on **push to `main`** when Terraform/Ansible files change.

### One-time Azure setup (OIDC)

The workflow uses **Azure OIDC** (no long-lived client secrets). Configure once:

1. **App registration** in Azure AD (Entra ID): create an app, note **Application (client) ID**.
2. **Federated credential** for GitHub:
   - Credential type: **GitHub Actions**
   - Issuer: `https://token.actions.githubusercontent.com`
   - Audience: `api://AzureADTokenExchange`
   - Subject: `repo:<your-org>/<your-repo>:ref:refs/heads/main` (or `environment:production` if you use an environment)
3. **Grant the app** “Contributor” (or equivalent) on the subscription or a resource group.

### Repository secrets

In the repo: **Settings → Secrets and variables → Actions**, add:

| Secret | Description |
|--------|-------------|
| `AZURE_CLIENT_ID` | Application (client) ID of the app registration |
| `AZURE_TENANT_ID` | Azure AD (tenant) ID |
| `AZURE_SUBSCRIPTION_ID` | Azure subscription ID |

No GitHub PAT is needed: the workflow uses the built-in `GITHUB_TOKEN` to create a runner registration token via the API.

### Terraform state

The workflow uses **local** Terraform state (in the runner workspace). Each run sees the state from that run only. For **repeated or production use**, configure a [remote backend](https://developer.hashicorp.com/terraform/language/settings/backend) (e.g. `azurerm`) and pass backend config via environment or a backend block in Terraform.

### Run the workflow

- **Manual:** Actions → **Deploy self-hosted runners** → **Run workflow**.
- **Automatic:** Push to `main` that changes files under `terraform/`, `ansible/`, or the workflow file.

---

## Step 1: Prerequisites and Initial Setup (manual)

### Accounts and permissions

- **Azure subscription** with permissions to create resource groups, networks, and VMs.
- **GitHub repository** where you have admin rights (to add runners).

### Install tools

- [Terraform](https://www.terraform.io/downloads) (≥ 1.0)
- [Ansible](https://docs.ansible.com/ansible/latest/installation_guide/index.html)
- [Azure CLI](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli)

### Authenticate with Azure

```bash
az login
```

### GitHub registration token

You need a **Personal Access Token (PAT)** or the one-time **registration token** from GitHub:

- **Option A (recommended):** In your repo go to **Settings → Actions → Runners → Add new runner**. Copy the registration token shown there (short-lived; use it right after provisioning).
- **Option B:** Create a [GitHub PAT](https://github.com/settings/tokens) with the `repo` scope if you use it for registration.

Store the token securely. It will be passed to Ansible via environment variable (never committed).

---

## Step 2: Provision Cloud Infrastructure with Terraform

### Configure variables

From the repository root:

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars: location, runner_count, admin_username, etc.
```

Optional: set `ssh_public_key_path` to your public key (e.g. `~/.ssh/id_rsa.pub`). If unset, Terraform generates an SSH key; the private key is in the apply output (sensitive).

### Deploy infrastructure

```bash
terraform init
terraform plan   # optional: review the plan
terraform apply  # confirm with 'yes'
```

### Save outputs

After apply, note the runner IPs:

```bash
terraform output runner_public_ips_list
```

If Terraform generated the SSH key, save the private key for Ansible:

```bash
terraform output -raw generated_ssh_private_key_pem > runner_key.pem
chmod 600 runner_key.pem
```

---

## Step 3: Configure the Virtual Machines with Ansible

### Generate inventory from Terraform

From the **repository root**:

```bash
chmod +x scripts/generate-inventory.sh
./scripts/generate-inventory.sh
# Optional: ./scripts/generate-inventory.sh azureuser  # if your admin user is different
```

This creates `ansible/hosts` with the VM IPs from Terraform. Alternatively, copy `ansible/hosts.example` to `ansible/hosts` and fill in the IPs manually.

### Set repository and token

1. Edit `ansible/group_vars/runners.yml` and set `github_repo_url` to your repo (e.g. `https://github.com/your-org/your-repo`).
2. Export the registration token (from **Settings → Actions → Runners → Add new runner**):

   ```bash
   export GITHUB_RUNNER_REGISTRATION_TOKEN=your_token_here
   ```

### SSH key for Ansible

- If you used your own key in Terraform, ensure that key is used by SSH/Ansible (e.g. `ssh-add` or set `ansible_ssh_private_key_file` in `ansible/hosts`).
- If Terraform generated the key, set in `ansible/hosts` under `[runners:vars]`:

   ```ini
   ansible_ssh_private_key_file=/path/to/runner_key.pem
   ```

### Run the playbook

From the **repository root**:

```bash
cd ansible
ansible-playbook configure_runners.yml
```

Or from repo root with explicit paths:

```bash
ansible-playbook -i ansible/hosts ansible/configure_runners.yml
```

The playbook will:

- Install dependencies (curl, git, jq, unzip, libicu-dev)
- Download and extract the GitHub Actions runner
- Register each VM as a runner for your repo (using the token)
- Install and start the runner as a systemd service

---

## Step 4: Verify the Self-Hosted Runners

1. Open your repository on GitHub.
2. Go to **Settings → Actions → Runners**.
3. Under **Self-hosted runners** you should see your new runners with a green dot and **Idle** status.

They are ready to be used in workflows with `runs-on: self-hosted` (or a label you assign).

---

## Project layout

```
.
├── .github/workflows/
│   └── deploy-runners.yml     # Automated Terraform + Ansible run
├── terraform/
│   ├── versions.tf            # Provider requirements
│   ├── variables.tf           # Input variables
│   ├── main.tf                # Azure resources (RG, VNet, VMs, etc.)
│   ├── outputs.tf             # Runner IPs, resource group name
│   └── terraform.tfvars.example
├── ansible/
│   ├── ansible.cfg
│   ├── configure_runners.yml  # Main playbook
│   ├── hosts.example
│   ├── hosts                  # Generated; contains VM IPs
│   └── group_vars/
│       └── runners.yml        # github_repo_url, token from env
├── scripts/
│   └── generate-inventory.sh  # Build ansible/hosts from Terraform output
├── docs/
│   └── CLI-COMMANDS.md        # Copy-paste CLI commands (Azure, gh, Terraform, Ansible)
└── README.md
```

---

## Customization

- **Terraform:** Adjust `terraform/variables.tf` and `terraform.tfvars` (e.g. `runner_count`, `vm_size`, `location`, `vnet_address_space`).
- **Ansible:** Runner version is in `configure_runners.yml` (`runner_version`). Repository URL and runner names are in `group_vars/runners.yml` and inventory.

---

## Cleanup

Destroy the Azure infrastructure:

```bash
cd terraform
terraform destroy
```

Remove runners from GitHub (**Settings → Actions → Runners**) before or after destroying the VMs.
