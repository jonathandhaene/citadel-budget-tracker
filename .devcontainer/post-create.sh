#!/bin/bash
set -e

echo "🏰 Setting up Citadel Budgets development environment..."

# Install Azure Functions Core Tools
echo "📦 Installing Azure Functions Core Tools..."
wget -q https://packages.microsoft.com/config/ubuntu/22.04/packages-microsoft-prod.deb
sudo dpkg -i packages-microsoft-prod.deb
sudo apt-get update
sudo apt-get install -y azure-functions-core-tools-4

# Install Bicep CLI
echo "📦 Installing Bicep CLI..."
curl -Lo bicep https://github.com/Azure/bicep/releases/latest/download/bicep-linux-x64
chmod +x ./bicep
sudo mv ./bicep /usr/local/bin/bicep

# Install Python dependencies for validation notebooks
echo "🐍 Installing Python dependencies..."
pip install --user jupyter nbconvert requests python-dotenv azure-identity azure-cosmos

# Install TypeScript dependencies for tier-sync function
echo "📦 Installing tier-sync Function dependencies..."
cd src/tier-sync-function
npm install
cd ../..

# Create local settings template if it doesn't exist
if [ ! -f src/tier-sync-function/local.settings.json ]; then
  echo "📝 Creating local.settings.json template..."
  cat > src/tier-sync-function/local.settings.json <<EOF
{
  "IsEncrypted": false,
  "Values": {
    "AzureWebJobsStorage": "UseDevelopmentStorage=true",
    "FUNCTIONS_WORKER_RUNTIME": "node",
    "COSMOS_ACCOUNT_NAME": "<your-cosmos-account-name>",
    "TIER_GROUP_OID_BRONZE": "<bronze-tier-group-oid>",
    "TIER_GROUP_OID_SILVER": "<silver-tier-group-oid>",
    "TIER_GROUP_OID_GOLD": "<gold-tier-group-oid>"
  }
}
EOF
fi

echo "✅ Citadel Budgets development environment ready!"
echo ""
echo "Next steps:"
echo "  1. Configure Azure CLI: az login"
echo "  2. Update src/tier-sync-function/local.settings.json with your values"
echo "  3. Run validation notebooks: jupyter notebook validation/"
echo "  4. Start tier-sync Function locally: cd src/tier-sync-function && func start"
