#!/bin/bash
# ------------------------------------------------------------------
#         Enable resource logs in Virtual Machine Scale Sets
# 1 = Name of the Virtual Machine Set 
# 1 = Resource Group name of the Virtual Machine Set 
# 3 = Storage Account Id where the log will be sent
# ------------------------------------------------------------------

# Variable
echo START
before=$(az vmss show --name $1 --resource-group $2 -o json)
osType=$(az vmss show --name $1 --resource-group $2 --query virtualMachineProfile.storageProfile.osDisk.osType -o tsv)

if [ "$osType" = "Linux" ]; then
    echo "Getting diagnostic configuration for Linux ..."
    az vmss diagnostics get-default-config > config.json
elif [ "$osType" = "Windows" ]; then
    echo "Getting diagnostic configuration for Linux ..."
    az vmss diagnostics get-default-config --is-windows-os > config.json
else
    exit 1
fi

saname=$(az storage account show --ids $3 --query name -o tsv)
echo "Preparing the config.json file to point to the SA [ ${saname} ] ..."
vmsssId=$(az vmss show --name $1 --resource-group $2 --query id -o tsv)
sed -i "s/__DIAGNOSTIC_STORAGE_ACCOUNT__/$saname/g" ./config.json
sed -i "s/__VM_OR_VMSS_RESOURCE_ID__/$vmsssId/g" ./config.json
echo "Getting Access Key of SA [ ${saname} ] ..."
saKey=$(az storage account keys list --account-name $saname --query "[?keyName=='key1'].value" -o tsv)
end=$4
echo "Getting SAS Token Key for SA [ ${saname} ] with the end date [ ${end} ] ..."
saSasToken=$(az storage account generate-sas --account-key $saKey --account-name $saname --permissions cdlruwap --services bfqt --resource-types sco --expiry $end -o tsv)
protected_settings='{"storageAccountName":"'"$saname"'","storageAccountSasToken":"'"$saSasToken"'"}'
echo $protected_settings > protected_settings.json

# Action
echo "Enabling resource log on VM Scale Set [ ${1} ] located in Resource Group [ ${2} ] ..."
result=$(az vmss diagnostics set --protected-settings protected_settings.json --vmss-name $1 --resource-group $2 --settings config.json)

# Log
after=$(az vmss show --name $1 --resource-group $2 -o json);
echo "{ "before_after": [ ${before},${after},${result} ] }" > $AZ_SCRIPTS_OUTPUT_PATH;
echo END