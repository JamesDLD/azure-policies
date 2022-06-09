![manage-azure-policy-mvp](https://github.com/JamesDLD/azure-policies/workflows/manage-azure-policy-mvp/badge.svg)

# Content
With this policy: any resource that has the tag key *LockLevel* with the value *CanNotDelete* means authorized users can read and modify the resource, but they can’t delete it.

Before implementing Azure Locks make sure you have read the following documentation [Considerations before applying your locks](https://docs.microsoft.com/en-us/azure/azure-resource-manager/management/lock-resources?tabs=json&WT.mc_id=AZ-MVP-5003548#considerations-before-applying-your-locks).

Published in the Blog post [Compliance and delegation of Azure Locks through Azure Policy](https://medium.com/microsoftazure/compliance-and-delegation-of-azure-locks-through-azure-policy-9f464d40faee).


# Disclaimer

The sample scripts are not supported under any Microsoft standard support program or service. The sample scripts are provided AS IS without warranty of any kind. Microsoft further disclaims all implied warranties including, without limitation, any implied warranties of merchantability or of fitness for a particular purpose. The entire risk arising out of the use or performance of the sample scripts and documentation remains with you. In no event shall Microsoft, its authors, or anyone else involved in the creation, production, or delivery of the scripts be liable for any damages whatsoever (including, without limitation, damages for loss of business profits, business interruption, loss of business information, or other pecuniary loss) arising out of the use of or inability to use the sample scripts or documentation, even if Microsoft has been advised of the possibility of such damages.