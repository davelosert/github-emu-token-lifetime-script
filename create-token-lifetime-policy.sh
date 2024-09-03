#!/bin/bash

## This is a static App ID For the Enterprise App "GitHub Enterprise Managed User (OIDC) as specified in the official GitHub Docs here:
## https://docs.github.com/en/enterprise-cloud@latest/admin/managing-iam/configuring-authentication-for-enterprise-managed-users/finding-the-object-id-for-your-entra-oidc-application#using-microsoft-entra-id-admin-center-to-find-your-object-id
EMU_APP_APP_ID="12f6db80-0741-4a7e-b9c5-b85d737b3a31"

echo "⏳ Searching for the service principal for the App 'GitHub Enterprise Managed User (OIDC)'..."
# Get the Object ID of the service principal using the App ID
SERVICE_PRINCIPAL_OBJECT_ID=$(az ad sp list --filter "appId eq '${EMU_APP_APP_ID}'" --query '[].id' --output tsv)

if [ -z "$SERVICE_PRINCIPAL_OBJECT_ID" ]; then
	echo "Error: No service principal found for App '${EMU_APP_APP_ID}' (GitHub Enterprise Managed User (OIDC)) - are you sure it is installed in this tenant?."
	exit 1
fi

echo "✅ Service Principal found with ObjectID: $SERVICE_PRINCIPAL_OBJECT_ID"
echo ""
read -p "❔ Do you want create a new token lifetime policy and assign it to the Service Principal? (y/n): " confirm
echo ""

if [[ ! "$confirm" =~ ^[Yy](es)?$ ]]; then
	echo "Operation cancelled."
	exit 1
fi

# Step 1: Create a new policy - it defaults to 8 hours. Adjust the 8:00:00 to your desired lifetime if you want to change it.
echo "⏳ Creating a new token lifetime policy with the name 'GitHub Session Token Lifetime Policy'..."
TOKEN_BODY='{
  "definition": [
      "{\"TokenLifetimePolicy\":{\"Version\":1,\"AccessTokenLifetime\":\"8:00:00\"}}"
  ],
  "displayName": "GitHub Session Token Lifetime Policy",
  "isOrganizationDefault": false
}'
CREATE_RESPONSE=$(az rest --method POST --uri 'https://graph.microsoft.com/v1.0/policies/tokenLifetimePolicies' --body "$TOKEN_BODY" --headers "Content-Type=application/json")

# Extract the policy ID from the response
POLICY_ID=$(echo $CREATE_RESPONSE | jq -r '.id')
echo "✅ Policy created with ID: $POLICY_ID"

# Step 2: Assign the Policy to the Service Principal
echo "⏳ Assigning the Policy to the Service Principal with Id $SERVICE_PRINCIPAL_OBJECT_ID..."
az rest --method POST --uri "https://graph.microsoft.com/v1.0/servicePrincipals/$SERVICE_PRINCIPAL_OBJECT_ID/tokenLifetimePolicies/\$ref" --body "{
  \"@odata.id\":\"https://graph.microsoft.com/v1.0/policies/tokenLifetimePolicies/$POLICY_ID\"
}" --headers "Content-Type=application/json"

# Step 3: Check if it worked
echo "✅ Success! The following policy has been assigned to the Service Principal:"
echo "-------------- Response Start --------------"
az rest --method GET --uri "https://graph.microsoft.com/v1.0/servicePrincipals/$SERVICE_PRINCIPAL_OBJECT_ID/tokenLifetimePolicies"
echo "-------------- Response End --------------"

echo ""
echo "📝 Summary:"
echo "  - Service Principal's ObjectID: $SERVICE_PRINCIPAL_OBJECT_ID"
echo "  - Policy's Id: $POLICY_ID"
echo ""

echo "🗑️  To delete the policy, use the following commands:"
echo "  1. Remove the policy assignment from the Service Principal:"
echo "  az rest --method DELETE --uri 'https://graph.microsoft.com/v1.0/servicePrincipals/${SERVICE_PRINCIPAL_OBJECT_ID}/tokenLifetimePolicies/${POLICY_ID}/\$ref'"
echo ""
echo "  2. Delete the policy:"
echo "  az rest --method DELETE --uri 'https://graph.microsoft.com/v1.0/policies/tokenLifetimePolicies/${POLICY_ID}'"
