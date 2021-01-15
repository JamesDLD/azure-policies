################################################################################
#                                 Variable
################################################################################
Set-StrictMode -Version 2
$ErrorActionPreference = "Stop"
$complianceJobs = @()
$AzRoleDefinitions = @()

################################################################################
#                                 Connectivity
################################################################################
# Login first with Connect-AzAccount if not using Cloud Shell

################################################################################
#                                 Action
################################################################################
## Create or ensure that the needed custom roles exist
foreach ($item in Get-Item .\roles\*.json) {
  $roles = (Get-Content -Path $item.FullName) | ConvertFrom-Json
  foreach ($role in $roles) {
    $AzRoleDefinition = Get-AzRoleDefinition -Name $role.Name
    if (!$AzRoleDefinition ) {
      Write-Output "Creating the custom role $($role.Name)"
      $AzRoleDefinitions += New-AzRoleDefinition -InputFile $item.FullName
    }
    else { $AzRoleDefinitions += $AzRoleDefinition }
  }
}
$deploymentScriptMinimumPrivilege = $AzRoleDefinitions | Where-Object { $_.Name -like "Deployment script minimum privilege for deployment principal" }

## Create or Update Azure Policies Definition and Azure Policies Initiative Definition
foreach ($item in Get-Item .\policies\*\policy.parameters.json) {
  $policy = (Get-Content -Path $($item.FullName -replace "policy.parameters.json", "policy.json")) | ConvertFrom-Json
  $parameters = (Get-Content -Path $item.FullName) | ConvertFrom-Json
  
  if ($policy.properties.policyType -ne "BuiltIn") {
    Write-Output "Deploying the Azure Policy : $($policy.properties.displayName)"
    New-AzPolicyDefinition -Name $policy.name `
      -DisplayName $policy.properties.displayName `
      -Policy ($policy.properties | ConvertTo-Json -Depth 20) `
      -Parameter ($parameters | ConvertTo-Json -Depth 20) `
      -Metadata ($policy.properties.metadata | ConvertTo-Json) `
      -ManagementGroupName $policy.id.Split("/")[4] `
      -Mode Indexed
  }
}

foreach ($item in Get-Item .\initiatives\*\policy.parameters.json) {
  $policy = (Get-Content -Path $($item.FullName -replace "policy.parameters.json", "policyset.json")) | ConvertFrom-Json
  $parameters = (Get-Content -Path $item.FullName) | ConvertFrom-Json
  
  Write-Output "Deploying the Azure Policy Initiative : $($policy.properties.displayName)"
  $initiativePolicy = New-AzPolicySetDefinition -Name $policy.name `
    -DisplayName $policy.properties.displayName `
    -PolicyDefinition ($policy.properties.policyDefinitions | ConvertTo-Json -Depth 5) `
    -Parameter ($parameters | ConvertTo-Json) `
    -ManagementGroupName $policy.id.Split("/")[4] `
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
    # Role assignment is done on the Policy assignment Identity and on the User Managed Identity used for the deployment script on ARM Template (used for remediation)
    $roleDefinitionIds = @()
    $initiativePolicy.Properties.PolicyDefinitions.policyDefinitionId | ForEach-Object { 
      $AzPolicyDefinition = Get-AzPolicyDefinition -Id $_
      $then = $AzPolicyDefinition.Properties.PolicyRule.then
      if ($then | Get-Member | Where-Object { $_.Name -like "details" }) {
        if ($then.details | Get-Member | Where-Object { $_.Name -like "roleDefinitionIds" } ) {
          $roleDefinitionIds += $then.details.roleDefinitionIds 
        }
      }
    }
    $roleDefinitionIds = $roleDefinitionIds | Select-Object -Unique

    foreach ($roleDefinitionId in $roleDefinitionIds) {
      
      $AzRoleAssignment = Get-AzRoleAssignment -Scope "$($assign.properties.scope)" -ObjectId $objectID -RoleDefinitionId "$($roleDefinitionId.Split("/")[-1])" -ErrorVariable notPresent -ErrorAction SilentlyContinue
      if (!$AzRoleAssignment) {
        New-AzRoleAssignment -Scope "$($assign.properties.scope)" -ObjectId $objectID -RoleDefinitionId "$($roleDefinitionId.Split("/")[-1])"
      }
    }

    ## User Managed Identity used for the deployment script on ARM Template (used for remediation)
    if ($assign.properties.parameters | Get-Member | Where-Object { $_.Name -like "identityId" } ) {
      $AzUserAssignedIdentity = Get-AzUserAssignedIdentity -ResourceGroupName $assign.properties.parameters.identityId.value.split("/")[-5] -Name $assign.properties.parameters.identityId.value.split("/")[-1]

      $AzRoleAssignment = Get-AzRoleAssignment -Scope "$($assign.properties.scope)" -ObjectId $AzUserAssignedIdentity.PrincipalId -RoleDefinitionId $deploymentScriptMinimumPrivilege.Id -ErrorAction SilentlyContinue
      if (!$AzRoleAssignment) {
        New-AzRoleAssignment -Scope "$($assign.properties.scope)" -ObjectId $AzUserAssignedIdentity.PrincipalId -RoleDefinitionId $deploymentScriptMinimumPrivilege.Id
      }

      foreach ($roleDefinitionId in $roleDefinitionIds) {
      
        $AzRoleAssignment = Get-AzRoleAssignment -Scope "$($assign.properties.scope)" -ObjectId $AzUserAssignedIdentity.PrincipalId -RoleDefinitionId "$($roleDefinitionId.Split("/")[-1])" -ErrorVariable notPresent -ErrorAction SilentlyContinue
        if (!$AzRoleAssignment) {
          New-AzRoleAssignment -Scope "$($assign.properties.scope)" -ObjectId $AzUserAssignedIdentity.PrincipalId -RoleDefinitionId "$($roleDefinitionId.Split("/")[-1])"
        }
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
    $complianceJobs | Select-Object Id, State, PSBeginTime
    #>
    
  }
}