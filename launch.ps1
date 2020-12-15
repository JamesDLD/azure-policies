## Variable
$AzureRmSubscriptionName = "mvp-sub1"

## Connectivity
# Login first with Connect-AzAccount if not using Cloud Shell
$AzureRmContext = Get-AzSubscription -SubscriptionName $AzureRmSubscriptionName | Set-AzContext -ErrorAction Stop
Select-AzSubscription -Name $AzureRmSubscriptionName -Context $AzureRmContext -Force -ErrorAction Stop

## Create the Policy Definition
#Method 1 : with PowerShell
$parameters = (Get-Content -Path ".\policies\Deploy_Diagnostic_Settings_for_Databricks_to_Log_Analytics_workspace\policy.parameters.json") | ConvertFrom-Json
$policy = (Get-Content -Path ".\policies\Deploy_Diagnostic_Settings_for_Databricks_to_Log_Analytics_workspace\policy.json") | ConvertFrom-Json

$azurePolicy = New-AzPolicyDefinition -Name $policy.name `
    -DisplayName $policy.displayName `
    -Policy ($policy | ConvertTo-Json -Depth 20) `
    -Parameter ($parameters | ConvertTo-Json -Depth 20) `
    -Metadata '{"category":"Log Monitor"}' `
    -Mode Indexed


#Method 2 : with GitHub Action
<#
1. Add the policy path under on the file ./.github/workflows/manage-azure-policy.yml
 - Sample : 
    - name: Create or Update Azure Policies
      uses: azure/manage-azure-policy@v0
      with:
        paths: |
          policies/Deploy_Diagnostic_Settings_for_Databricks_to_Log_Analytics_workspace/**
#>

  