################################################################################
#                                 Variable
################################################################################
Set-StrictMode -Version 2
$ErrorActionPreference = "Stop"
$AzureRmSubscriptionName = "mvp-sub1"
$complianceJobs = @()

################################################################################
#                                 Connectivity
################################################################################
# Login first with Connect-AzAccount if not using Cloud Shell
$AzureRmContext = Get-AzSubscription -SubscriptionName $AzureRmSubscriptionName | Set-AzContext -ErrorAction Stop
Select-AzSubscription -Name $AzureRmSubscriptionName -Context $AzureRmContext -Force -ErrorAction Stop

################################################################################
#                                 Action
################################################################################
## Create or Update Azure Policies Definition and Azure Policies Initiative Definition

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
    $roleDefinitionIds = @()
    $initiativePolicy.Properties.PolicyDefinitions.policyDefinitionId | ForEach-Object { 
      $AzPolicyDefinition = Get-AzPolicyDefinition -Id $_
      $details = $AzPolicyDefinition.Properties.PolicyRule.then
      if ($AzPolicyDefinition.Properties.PolicyRule.then | Get-Member | Where-Object { $_.Name -like "details" }) {
        $details | Get-Member | Where-Object { $_.Name -like "roleDefinitionIds" }
        $roleDefinitionIds += $AzPolicyDefinition.Properties.PolicyRule.then.details.roleDefinitionIds 
      }
    }
    $roleDefinitionIds = $roleDefinitionIds | Select-Object -Unique

    foreach ($roleDefinitionId in $roleDefinitionIds) {
      
      $AzRoleAssignment = Get-AzRoleAssignment -Scope "$($assign.properties.scope)" -ObjectId $objectID -RoleDefinitionId "$($roleDefinitionId.Split("/")[-1])" -ErrorVariable notPresent -ErrorAction SilentlyContinue
      if (!$AzRoleAssignment) {
        New-AzRoleAssignment -Scope "$($assign.properties.scope)" -ObjectId $objectID -RoleDefinitionId "$($roleDefinitionId.Split("/")[-1])"
        ## Debug because I have locally the error described here : https://stackoverflow.com/questions/63598486/azure-new-azroleassignment-input-string-was-not-in-a-correct-format-error-wit
        Write-Host "New-AzRoleAssignment -Scope $($assign.properties.scope) -ObjectId $objectID -RoleDefinitionId $($roleDefinitionId.Split("/")[-1])"
      }
    }

    ## Start a compliance scan
    if ($assign.properties.scope -like "*resourceGroups*") {
      $complianceJobs += Start-AzPolicyComplianceScan -ResourceGroupName $($assign.properties.scope).Split("/")[-1] -AsJob
    }
    else {
      $complianceJobs += Start-AzPolicyComplianceScan -AsJob
    }
    <#
    Memo to get the job info --> 
    $complianceJobs[0]
    $complianceJobs[0].PSBeginTime
    #>
    
  }
}