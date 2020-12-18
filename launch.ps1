## Variable
$AzureRmSubscriptionName = "mvp-sub1"

## Connectivity
# Login first with Connect-AzAccount if not using Cloud Shell
$AzureRmContext = Get-AzSubscription -SubscriptionName $AzureRmSubscriptionName | Set-AzContext -ErrorAction Stop
Select-AzSubscription -Name $AzureRmSubscriptionName -Context $AzureRmContext -Force -ErrorAction Stop

## Create or Update Azure Policies Definition and Azure Policies Initiative Definition
#Method 1 : with PowerShell
foreach ($item in Get-Item .\policies\*\policy.parameters.json) {
  $policy = (Get-Content -Path $($item.FullName -replace "policy.parameters.json", "policy.json")) | ConvertFrom-Json
  $parameters = (Get-Content -Path $item.FullName) | ConvertFrom-Json
  
  Write-Output "Deploying the Azure Policy : $($policy.properties.displayName)"
  New-AzPolicyDefinition -Name $policy.name `
    -DisplayName $policy.properties.displayName `
    -Policy ($policy.properties | ConvertTo-Json -Depth 20) `
    -Parameter ($parameters | ConvertTo-Json -Depth 20) `
    -Metadata ($policy.properties.metadata | ConvertTo-Json) `
    -Mode Indexed
}

foreach ($item in Get-Item .\initiatives\*\policy.parameters.json) {
  $policy = (Get-Content -Path $($item.FullName -replace "policy.parameters.json", "policyset.json")) | ConvertFrom-Json
  $parameters = (Get-Content -Path $item.FullName) | ConvertFrom-Json
  
  Write-Output "Deploying the Azure Policy Initiative : $($policy.properties.displayName)"
  $initiativePolicy = New-AzPolicySetDefinition -Name $policy.name `
    -DisplayName $policy.properties.displayName `
    -PolicyDefinition ($policy.properties.policyDefinitions | ConvertTo-Json -Depth 5) `
    -Parameter ($parameters | ConvertTo-Json) `
    -Metadata  ($policy.properties.metadata | ConvertTo-Json)


  foreach ($item_assign in Get-Item "$($item.Directory.FullName)\assign.*.json") {
    $assign = (Get-Content -Path $item_assign.FullName) | ConvertFrom-Json

    ## Assign the Initiative Policy
    $PolicyAssignment = New-AzPolicyAssignment -Name $assign.name `
      -DisplayName $assign.properties.displayName `
      -PolicySetDefinition $initiativePolicy `
      -Scope $assign.properties.scope `
      -AssignIdentity `
      -Location $assign.location `
      -PolicyParameter ($assign.properties.parameters | ConvertTo-Json)

    ## Extract the ObjectID of the Policy Assignment Managed Identity
    $objectID = [GUID]($PolicyAssignment.Identity.principalId) #[GUID]($assign.identity.principalId) #

    ## Create a role assignment from the role definition ids available in each policies initiatives
    $roleDefinitionIds = $initiativePolicy.Properties.PolicyDefinitions.policyDefinitionId | ForEach-Object { (Get-AzPolicyDefinition -Id $_).Properties.policyRule.then.details.roleDefinitionIds } | Select-Object -Unique
    foreach ($roleDefinitionId in $roleDefinitionIds) {
      
      New-AzRoleAssignment -Scope "$($assign.properties.scope)" -ObjectId $objectID -RoleDefinitionId "$($roleDefinitionId.Split("/")[-1])"

      ## Debug because I have locally the error described here : https://stackoverflow.com/questions/63598486/azure-new-azroleassignment-input-string-was-not-in-a-correct-format-error-wit
      Write-Host "New-AzRoleAssignment -Scope $($assign.properties.scope) -ObjectId $objectID -RoleDefinitionId $($roleDefinitionId.Split("/")[-1])"
    }

  }

}

# $Test = Get-AzPolicyAssignment -Scope "/subscriptions/6094e15e-3e04-47b5-9b3b-aa8ae3cf1e52/resourceGroups/dld-corp-mvp-dataplatform"
# $Test = $Test[1]
# $Test.name
# $Test.Properties.DisplayName
# $Test.Properties.Scope
# #Method 2 : with GitHub Action
# <#
# 1. Use Azure GiHub Action with azure/manage-azure-policy@v0, see file ./.github/workflows/manage-azure-policy.yml
#  - Sample to create or update all policies : 
#     - name: Create or Update Azure Policies
#       uses: azure/manage-azure-policy@v0
#       with:
#         paths: |
#           policies/**
#           initiatives/**
# #>
  
# # Policy Assignment
# # # Variable
# # $scope = Get-AzResourceGroup -Name "dld-corp-mvp-dataplatform" #Replace it with your target scope
# # $logAnalytics = Get-AzOperationalInsightsWorkspace -Name "mvp-hub-logaw1" -ResourceGroupName "infr-hub-prd-rg1" #Replace it with your target Log Analytics Workspace
# # $initiativePolicy = Get-AzPolicySetDefinition -Name 'Windows Virtual Desktop Resources Diagnostic Settings' 
# # $params = @{'logAnalytics' = ($logAnalytics.ResourceId) }

# ## Assign the Initiative Policy
# New-AzPolicyAssignment -Name 'WVD to Log Analytics Demo' `
#   -DisplayName 'WVD to Log Analytics Demo' `
#   -PolicySetDefinition $initiativePolicy `
#   -Scope $scope.ResourceId `
#   -AssignIdentity `
#   -Location 'westeurope' `
#   -PolicyParameterObject $params

# ## Get the newly created policy assignment object
# $PolicyAssignment = Get-AzPolicyAssignment -Name 'WVD to Log Analytics Demo' -Scope $scope.ResourceId

# ## Extract the ObjectID of the Policy Assignment Managed Identity
# $objectID = [GUID]($PolicyAssignment.Identity.principalId)

# ## Create a role assignment from the previous information
# $roleDefinitionId = (Get-AzRoleDefinition -Name "Contributor").Id #For the Demo we will assing the "Contributor" privilege to our Policy Assignment Managed Identity
# New-AzRoleAssignment -Scope $scope.ResourceId -ObjectId $objectID -RoleDefinitionId $roleDefinitionId