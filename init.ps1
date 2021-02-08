
<#
This script prepare the polcicy to fit with your environment.
#>

$OldCompanyName = "MVP"
$NewCompanyName = "SPACEX"
$OldManagementGroupId = "/providers/Microsoft.Management/managementGroups/core"
$NewManagementGroupId = "/providers/Microsoft.Management/managementGroups/xxxxxxxxxxx"

#Rename multiple files 
$items = Get-ChildItem -Path *.json -Recurse -File 
foreach ($item in $items) {
    $content = Get-Content -Path $item.FullName
    if ($content -like "*$OldCompanyName*") {
        Write-Host "Modifying file : $($item.FullName)"
        $content -replace $OldCompanyName, $NewCompanyName > $item.FullName
    }

    if ($content -like "*$OldManagementGroupId*") {
        Write-Host "Modifying file : $($item.FullName)"
        $content -replace $OldManagementGroupId, $NewManagementGroupId > $item.FullName
    }
    
}

#Rename multiple folders
$items = Get-ChildItem -Path ./ -Recurse -Directory
foreach ($item in $items) {
    if ($item.Name -like "*$OldCompanyName*") {
        Write-Host "Renaming folder : $($item.FullName)"
        Move-Item -Path $item.FullName $item.FullName.Replace($OldCompanyName, $NewCompanyName)
    }
}