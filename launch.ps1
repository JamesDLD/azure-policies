<#
.SYNOPSIS
  Deploy Azure Policies.
.DESCRIPTION
  REQUIRED : Internet access & Already connected to an Azure tenant
  REQUIRED : PowerShell modules, see variables
.PARAMETER env
   Mandatory
   Environment where to deploy Azure Policies
.NOTES
   AUTHOR: James Dumont le Douarec
.LINK
    https://medium.com/microsoftazure/an-azure-policy-journey-7bb53b41c43d
    https://github.com/JamesDLD/azure-policies
.EXAMPLE
   ./launch.ps1
#>

################################################################################
#                                 Variable
################################################################################
Set-StrictMode -Version 2
$ErrorActionPreference = "Stop"
$complianceJobs = @()
$AzRoleDefinitions = @()
$Scopes = @()
$PowerShellModules = @(
  @{ 
    Name           = "Az.ManagedServiceIdentity"
    MinimumVersion = "0.7.3"
  },
  @{ 
    Name           = "Az.Accounts"
    MinimumVersion = "2.7.0"
  },
  @{ 
    Name           = "Az.Resources"
    MinimumVersion = "5.1.0"
  }
  @{ 
    Name           = "Az.PolicyInsights"
    MinimumVersion = "1.4.1"
  }
)

################################################################################
#                                 Pre-requisite
################################################################################

ForEach ($PowerShellModule in $PowerShellModules) {
  Write-host "Importing Module $($PowerShellModule.Name) with MinimumVersion $($PowerShellModule.MinimumVersion)"
  Import-Module -Name $($PowerShellModule.Name) -MinimumVersion $($PowerShellModule.MinimumVersion) -ErrorAction Stop
}

################################################################################
#                                 Connectivity
################################################################################
# Login first with Connect-AzAccount if not using Cloud Shell

################################################################################
#                                 Action
################################################################################
# $SubscriptionId = "<Your Subscription Id>"
# Select-AzSubscription -SubscriptionId $SubscriptionId -ErrorAction Stop

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
      -Mode $policy.properties.mode
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
    if ($assign.properties.notScopes) {
      $PolicyAssignment = New-AzPolicyAssignment -Name $assign.name `
        -DisplayName $assign.properties.displayName `
        -PolicySetDefinition $initiativePolicy `
        -Scope $assign.properties.scope `
        -NotScope $assign.properties.notScopes `
        -AssignIdentity `
        -Location $assign.location `
        -PolicyParameter ($assign.properties.parameters | ConvertTo-Json) 
    }
    else {
      $PolicyAssignment = New-AzPolicyAssignment -Name $assign.name `
        -DisplayName $assign.properties.displayName `
        -PolicySetDefinition $initiativePolicy `
        -Scope $assign.properties.scope `
        -AssignIdentity `
        -Location $assign.location `
        -PolicyParameter ($assign.properties.parameters | ConvertTo-Json)
    }


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

    $AzRoleAssignment = Get-AzRoleAssignment -Scope "$($assign.properties.scope)" -ObjectId $objectID -RoleDefinitionId $deploymentScriptMinimumPrivilege.Id -ErrorAction SilentlyContinue
    if (!$AzRoleAssignment) {
      New-AzRoleAssignment -Scope "$($assign.properties.scope)" -ObjectId $objectID.Guid -RoleDefinitionId $deploymentScriptMinimumPrivilege.Id
    }

    foreach ($roleDefinitionId in $roleDefinitionIds) {
      
      $AzRoleAssignment = Get-AzRoleAssignment -Scope "$($assign.properties.scope)" -ObjectId $objectID -RoleDefinitionId "$($roleDefinitionId.Split("/")[-1])" -ErrorVariable notPresent -ErrorAction SilentlyContinue
      if (!$AzRoleAssignment) {
        New-AzRoleAssignment -Scope "$($assign.properties.scope)" -ObjectId $objectID.Guid -RoleDefinitionId "$($roleDefinitionId.Split("/")[-1])"
      }
    }

    ## User Managed Identity used for the deployment script on ARM Template (used for remediation)
    if ($assign.properties.parameters | Get-Member | Where-Object { $_.Name -like "identityId" } ) {
      $AzureRmContext = Get-AzSubscription -SubscriptionId $assign.properties.parameters.identityId.value.split("/")[2] | Set-AzContext -ErrorAction Stop
      Select-AzSubscription -Name $AzureRmContext.Subscription.Name -Context $AzureRmContext -Force -ErrorAction Stop | Out-Null
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

    ## Prepare the compliance scan
    $Scopes += $assign.properties.scope
    
  }
}

# Start a compliance scan
$Scopes = $Scopes | Select-Object -Unique
foreach ($Scope in $Scopes) {
  if ($Scope -like "*resourceGroups*") {
    $complianceJobs += Start-AzPolicyComplianceScan -ResourceGroupName $Scope.Split("/")[-1] -AsJob
  }
  else {
    $complianceJobs += Start-AzPolicyComplianceScan -AsJob
  }
}

<#
Memo to get the job info --> 
$complianceJobs | Select-Object Id, State, PSBeginTime
#>