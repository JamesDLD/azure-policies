![manage-azure-policy-mvp](https://github.com/JamesDLD/azure-policies/workflows/manage-azure-policy-mvp/badge.svg)

# Content
Share Azure Policies with the community.

# Reference
- [Using GitHub for Azure Policy as Code](https://techcommunity.microsoft.com/t5/azure-governance-and-management/using-github-for-azure-policy-as-code/ba-p/1886464?WT.mc_id=DOP-MVP-5003548)
- [Tutorial: Implement Azure Policy as Code with GitHub](https://docs.microsoft.com/en-us/azure/governance/policy/tutorials/policy-as-code-github?WT.mc_id=DOP-MVP-5003548)
- [Design Azure Policy as Code workflows](https://docs.microsoft.com/en-us/azure/governance/policy/concepts/policy-as-code?WT.mc_id=DOP-MVP-5003548)
- [Azure Policy initiative definition structure](https://docs.microsoft.com/en-us/azure/governance/policy/concepts/initiative-definition-structure?WT.mc_id=DOP-MVP-5003548)

# Policies
## Guidelines for Monitoring
- [Diagnostic logging in Azure Databricks](https://docs.microsoft.com/en-us/azure/databricks/administration-guide/account-settings/azure-diagnostic-logs?WT.mc_id=DOP-MVP-5003548)
- [Workspace-based Application Insights](https://docs.microsoft.com/en-us/azure/azure-monitor/app/convert-classic-resource?WT.mc_id=DOP-MVP-5003548)
- [Diagnostic Settings for Azure Windows Virtual Desktop](https://medium.com/faun/diagnostic-settings-for-azure-windows-virtual-desktop-resources-part-2-4bfb9ce8d1be)

# How to

## Create or Update Azure Policies Definition and Azure Policies Initiative Definition
### Method 1 : with PowerShell 
Excecute the script [launch.ps1](launch.ps1)
* Note : this script launches also a compliance scan on each scope where you have assigned your policy.

### Method 2 : with GitHub Action

1. Set up Secrets in GitHub Action workflows
Some detail are explained [here](https://github.com/Azure/actions-workflow-samples/blob/master/assets/create-secrets-for-GitHub-workflows.md), in addition you can assign the privilege [Resource Policy Contributor](https://docs.microsoft.com/en-us/azure/role-based-access-control/built-in-roles?WT.mc_id=DP-MVP-5003548#resource-policy-contributor) to the service principal you have just created for GitHub Action.

2. Use Azure GiHub Action with azure/manage-azure-policy@v0, see file ./.github/workflows/manage-azure-policy.yml
 - Sample to create or update all policies : 
    - name: Create or Update Azure Policies
      uses: azure/manage-azure-policy@v0
      with:
        paths: |
          policies/**
          initiatives/**

*Important note* : if you want to proceed assignment of policies that use make sure to fill in the App Registration detail into the following brackets on the assign.<Policy>.json file
```
"identity": {
  "principalId": "The Identity principalId",
  "tenantId": "Your Tenant Id",
  "type": "SystemAssigned"
}
```
