# CLI commands reference

Replace placeholders:

- `YOUR_ORG` / `YOUR_REPO` – your GitHub org and repo (e.g. `myorg` / `self-hosted-azure-github-runners`)
- `YOUR_SUBSCRIPTION_ID` – Azure subscription ID (from `az account show`)
- `github-runners-oidc` – display name for the Azure app (change if you like)

---

## 1. Azure login

```bash
az login
az account set --subscription "YOUR_SUBSCRIPTION_ID"
```

---

## 2. One-time Azure OIDC setup (for GitHub Actions workflow)

### Option A: Single Cloud Shell script (copy-paste all)

Ready to use for your repository `T0S1N0/self-hosted-azure-github-runners`.

```bash
#!/bin/bash
# Azure OIDC setup for GitHub Actions - copy-paste into Azure Cloud Shell
set -e

# === CONFIGURATION ===
GITHUB_REPO="T0S1N0/self-hosted-azure-github-runners"
APP_DISPLAY_NAME="github-runners-oidc"
GITHUB_BRANCH="main"

# === SETUP ===
echo "🔧 Setting up Azure OIDC for GitHub Actions..."
echo "Repository: $GITHUB_REPO"
echo "Branch: $GITHUB_BRANCH"
echo ""

# Get current subscription and tenant
SUBSCRIPTION_ID=$(az account show --query id -o tsv)
TENANT_ID=$(az account show --query tenantId -o tsv)
echo "✅ Subscription: $SUBSCRIPTION_ID"
echo "✅ Tenant: $TENANT_ID"
echo ""

# Create app registration
echo "📝 Creating app registration: $APP_DISPLAY_NAME"
CLIENT_ID=$(az ad app create --display-name "$APP_DISPLAY_NAME" --query appId -o tsv)
echo "✅ App created - Client ID: $CLIENT_ID"
echo ""

# Create service principal
echo "🔑 Creating service principal..."
az ad sp create --id "$CLIENT_ID" > /dev/null
echo "✅ Service principal created"
echo ""

# Assign Contributor role at subscription level
echo "👤 Assigning Contributor role..."
az role assignment create \
  --assignee "$CLIENT_ID" \
  --role "Contributor" \
  --scope "/subscriptions/$SUBSCRIPTION_ID" \
  > /dev/null
echo "✅ Contributor role assigned"
echo ""

# Create federated credential for GitHub Actions
echo "🔐 Creating federated credential for GitHub..."
az ad app federated-credential create \
  --id "$CLIENT_ID" \
  --parameters "{
    \"name\": \"github-actions-$GITHUB_BRANCH\",
    \"issuer\": \"https://token.actions.githubusercontent.com\",
    \"subject\": \"repo:$GITHUB_REPO:ref:refs/heads/$GITHUB_BRANCH\",
    \"description\": \"GitHub Actions OIDC for $GITHUB_BRANCH branch\",
    \"audiences\": [\"api://AzureADTokenExchange\"]
  }" \
  > /dev/null
echo "✅ Federated credential created"
echo ""

# Display GitHub secrets
echo "================================================"
echo "🎉 Setup complete! Add these secrets to GitHub:"
echo "================================================"
echo ""
echo "Repository: Settings → Secrets and variables → Actions → New repository secret"
echo ""
echo "AZURE_CLIENT_ID=$CLIENT_ID"
echo "AZURE_TENANT_ID=$TENANT_ID"
echo "AZURE_SUBSCRIPTION_ID=$SUBSCRIPTION_ID"
echo ""
echo "================================================"
```

### Option B: Step-by-step commands

Run from any directory. These create the app registration, service principal, role assignment, and federated credential for GitHub OIDC.

```bash
# App registration (no client secret)
AZURE_APP=$(az ad app create --display-name "github-runners-oidc" --query appId -o tsv)
echo "AZURE_CLIENT_ID=$AZURE_APP"

# Service principal
az ad sp create --id "$AZURE_APP"

# Contributor on the subscription (narrow scope in production, e.g. --scope /subscriptions/.../resourceGroups/my-rg)
az role assignment create \
  --assignee "$AZURE_APP" \
  --role "Contributor" \
  --scope "/subscriptions/$(az account show --query id -o tsv)"

# Federated credential for GitHub (subject = this repo, main branch)
az ad app federated-credential create \
  --id "$AZURE_APP" \
  --parameters '{
    "name": "github-actions-main",
    "issuer": "https://token.actions.githubusercontent.com",
    "subject": "repo:T0S1N0/self-hosted-azure-github-runners:ref:refs/heads/main",
    "description": "GitHub Actions OIDC for main branch",
    "audiences": ["api://AzureADTokenExchange"]
  }'
```

Get IDs for GitHub secrets:

```bash
echo "AZURE_CLIENT_ID=$AZURE_APP"
echo "AZURE_TENANT_ID=$(az account show --query tenantId -o tsv)"
echo "AZURE_SUBSCRIPTION_ID=$(az account show --query id -o tsv)"
```

---

## 3. Set GitHub repository secrets (for workflow)

Requires [GitHub CLI](https://cli.github.com/) (`gh`) and `gh auth login`.

```bash
cd /path/to/self-hosted-azure-github-runners

# Azure secrets
gh secret set AZURE_CLIENT_ID        --body "$AZURE_APP"
gh secret set AZURE_TENANT_ID        --body "$(az account show --query tenantId -o tsv)"
gh secret set AZURE_SUBSCRIPTION_ID  --body "$(az account show --query id -o tsv)"

# GitHub PAT for runner registration (create at https://github.com/settings/tokens/new with 'repo' scope)
gh secret set GH_PAT  # paste your PAT when prompted
```

---

## 4. Trigger the deploy workflow (optional)

```bash
gh workflow run "Deploy self-hosted runners"
# Or with ref
gh workflow run "Deploy self-hosted runners" --ref main
```

---

## 5. Manual path: Terraform + Ansible (no workflow)

From the **repository root**.

### 5.1 Terraform

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars if needed (location, runner_count, etc.)

terraform init
terraform plan
terraform apply

# Save private key if Terraform generated SSH key
terraform output -raw generated_ssh_private_key_pem > ../runner_key.pem
chmod 600 ../runner_key.pem
```

### 5.2 Generate Ansible inventory

```bash
cd ..
chmod +x scripts/generate-inventory.sh
./scripts/generate-inventory.sh
# Or: ./scripts/generate-inventory.sh azureuser
```

### 5.3 Get a runner registration token

In the repo: **Settings → Actions → Runners → Add new runner** and copy the token. Then:

```bash
export GITHUB_RUNNER_REGISTRATION_TOKEN="paste_token_here"
```

### 5.4 Set repo URL and run Ansible

Edit `ansible/group_vars/runners.yml` and set `github_repo_url` to your repo (e.g. `https://github.com/YOUR_ORG/YOUR_REPO`). Then:

```bash
cd ansible
ansible-playbook configure_runners.yml
```

If you're using the Terraform-generated key:

```bash
ansible-playbook configure_runners.yml \
  -e "ansible_ssh_private_key_file=$PWD/../runner_key.pem"
```

---

## 6. Cleanup (manual path)

```bash
cd terraform
terraform destroy
```

Remove runners in GitHub: **Settings → Actions → Runners** → remove each runner.
