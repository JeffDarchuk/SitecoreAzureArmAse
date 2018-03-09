param(
    [string]$ResourceGroupName,
    [string]$SubscriptionId,
    [string]$Location = "EAST US",
    [string]$TenantId,
    [string]$ServicePrincipalId,
    [string]$ServicePrincipalKey
)
$mainsw =  [system.diagnostics.stopwatch]::StartNew()
#$PSVersionTable.PSVersion
#Install-Module -Name AzureRM -Scope CurrentUser -Force
. "$PSScriptRoot\Utilities.ps1"

#populate this variable with a hashtable of the web accessable arm template json files, in the stock Sitecore setup these were hosted out of github
$SCTemplates= $null
#populate this variable with the path to your sitecore license XML
$LicenseFile = $null
#populate this variable with the path to the certificate pfx you're using as your client cert
$CertificateFile = $null
#populate this variable with the path to a parameters file, default Sitecore templates use one named azuredeploy.parameters.json
$ParamFile = $null
#populate this hashtable with any parameters set at runtime
$Parameters = @{
    location                    = $Location
}
# Read and Set the license.xml
$licenseXml = Get-Content $LicenseFile -Raw -Encoding UTF8
$Parameters.Add("licenseXml", $licenseXml)
# Import-Module "$SCSDK\Sitecore.Cloud.Cmdlets.psm1"
$Credential = New-Object -TypeName PSCredential($ServicePrincipalID, (ConvertTo-SecureString -String $ServicePrincipalKey -AsPlainText -Force))
$connectParameters = @{
    Credential              = $Credential
    TenantId                = $TenantId
    SubscriptionId          = $SubscriptionId
    authCertificateBlob     = [System.Convert]::ToBase64String([System.IO.File]::ReadAllBytes($CertificateFile))
}
#load all default parameters from a parameters.json file
$paramJson = Get-Content $ParamFile -Raw | ConvertFrom-Json
$paramJson.parameters | Select-Object -Property * | ForEach-Object {$_.PSObject.Properties} | ForEach-Object {
    if (-not $Parameters.ContainsKey($_.Name)){
        $Parameters[$_.Name] = $_.Value.value
    }
}
$validParameters = Get-ValidParameters
Add-AzureRmAccount @connectParameters -ServicePrincipal
Set-AzureRMContext -SubscriptionId $SubscriptionId
#this first run is simply to gather parameters defined in the previous main ARM entry point
$output = Start-SitecoreAzureDeployment -Name $ResourceGroupName -Location $Location -ArmTemplateUrl "$($SCTemplates["root"])" -SetKeyValue $Parameters

#TmpParameters will now contain the parameters needed for the next deployment, as well as loading in all outputs and parameters from the last ARM template execution for future use, these are loaded in the Parameters variable
$TmpParameters = Get-Parameters -ArmOutput $output -AllParameters $Parameters -ValidParameters $validParameters["nested-infrastructure.json"]
write-host "INFRASTRUCTURE"
$timer =  [system.diagnostics.stopwatch]::StartNew()
$output = Start-SitecoreAzureDeployment -Name $ResourceGroupName -Location $Location -ArmTemplateUrl "$($SCTemplates["nested-infrastructure.json"])" -SetKeyValue $TmpParameters
write-host "Completed in $($timer.Elapsed.Minutes) minutes $($timer.Elapsed.Seconds) seconds."

$TmpParameters = Get-Parameters -ArmOutput $output -AllParameters $Parameters -ValidParameters $validParameters["nested-infrastructure-xconnect.json"]
write-host "INFRASTRUCTURE XCONNECT"
$timer =  [system.diagnostics.stopwatch]::StartNew()
$output = Start-SitecoreAzureDeployment -Name $ResourceGroupName -Location $Location -ArmTemplateUrl "$($SCTemplates["nested-infrastructure-xconnect.json"])" -SetKeyValue $TmpParameters
write-host "Completed in $($timer.Elapsed.Minutes) minutes $($timer.Elapsed.Seconds) seconds."

$TmpParameters = Get-Parameters -ArmOutput $output -AllParameters $Parameters -ValidParameters $validParameters["nested-infrastructure-ma.json"]
write-host "INFRASTRUCTURE MA"
$timer =  [system.diagnostics.stopwatch]::StartNew()
$output = Start-SitecoreAzureDeployment -Name $ResourceGroupName -Location $Location -ArmTemplateUrl "$($SCTemplates["nested-infrastructure-ma.json"])" -SetKeyValue $TmpParameters
write-host "Completed in $($timer.Elapsed.Minutes) minutes $($timer.Elapsed.Seconds) seconds."

$TmpParameters = Get-Parameters -ArmOutput $output -AllParameters $Parameters -ValidParameters $validParameters["nested-infrastructure-exm.json"]
write-host "INFRASTRUCTURE-EXM"
$timer =  [system.diagnostics.stopwatch]::StartNew()
$output = Start-SitecoreAzureDeployment -Name $ResourceGroupName -Location $Location -ArmTemplateUrl "$($SCTemplates["nested-infrastructure-exm.json"])" -SetKeyValue $TmpParameters
write-host "Completed in $($timer.Elapsed.Minutes) minutes $($timer.Elapsed.Seconds) seconds."

Write-Host "Waiting a minute to allow infrastructure to settle."
Start-Sleep -s 60

$TmpParameters = Get-Parameters -ArmOutput $output -AllParameters $Parameters -ValidParameters $validParameters["nested-application-xconnect.json"]
write-host "APPLICATION-XCONNECT"
$timer =  [system.diagnostics.stopwatch]::StartNew()
$output = Start-SitecoreAzureDeployment -Name $ResourceGroupName -Location $Location -ArmTemplateUrl "$($SCTemplates["nested-application-xconnect.json"])" -SetKeyValue $TmpParameters
write-host "Completed in $($timer.Elapsed.Minutes) minutes $($timer.Elapsed.Seconds) seconds."

$TmpParameters = Get-Parameters -ArmOutput $output -AllParameters $Parameters -ValidParameters $validParameters["nested-application-ma.json"]
write-host "APPLICATION-MA"
$timer =  [system.diagnostics.stopwatch]::StartNew()
$output = Start-SitecoreAzureDeployment -Name $ResourceGroupName -Location $Location -ArmTemplateUrl "$($SCTemplates["nested-application-ma.json"])" -SetKeyValue $TmpParameters
write-host "Completed in $($timer.Elapsed.Minutes) minutes $($timer.Elapsed.Seconds) seconds."

$TmpParameters = Get-Parameters -ArmOutput $output -AllParameters $Parameters -ValidParameters $validParameters["nested-application.1.json"]
write-host "APPLICATION 1"
$timer =  [system.diagnostics.stopwatch]::StartNew()
$output = Start-SitecoreAzureDeployment -Name $ResourceGroupName -Location $Location -ArmTemplateUrl "$($SCTemplates["nested-application.1.json"])" -SetKeyValue $TmpParameters
write-host "Completed in $($timer.Elapsed.Minutes) minutes $($timer.Elapsed.Seconds) seconds."

$TmpParameters = Get-Parameters -ArmOutput $output -AllParameters $Parameters -ValidParameters $validParameters["nested-application.2.json"]
write-host "APPLICATION 2"
$timer =  [system.diagnostics.stopwatch]::StartNew()
$output = Start-SitecoreAzureDeployment -Name $ResourceGroupName -Location $Location -ArmTemplateUrl "$($SCTemplates["nested-application.2.json"])" -SetKeyValue $TmpParameters
write-host "Completed in $($timer.Elapsed.Minutes) minutes $($timer.Elapsed.Seconds) seconds."

$TmpParameters = Get-Parameters -ArmOutput $output -AllParameters $Parameters -ValidParameters $validParameters["nested-application.3.json"]
write-host "APPLICATION 3"
$timer =  [system.diagnostics.stopwatch]::StartNew()
$output = Start-SitecoreAzureDeployment -Name $ResourceGroupName -Location $Location -ArmTemplateUrl "$($SCTemplates["nested-application.3.json"])" -SetKeyValue $TmpParameters
write-host "Completed in $($timer.Elapsed.Minutes) minutes $($timer.Elapsed.Seconds) seconds."

$TmpParameters = Get-Parameters -ArmOutput $output -AllParameters $Parameters -ValidParameters $validParameters["nested-application.4.json"]
write-host "APPLICATION 4"
$timer =  [system.diagnostics.stopwatch]::StartNew()
$output = Start-SitecoreAzureDeployment -Name $ResourceGroupName -Location $Location -ArmTemplateUrl "$($SCTemplates["nested-application.4.json"])" -SetKeyValue $TmpParameters
write-host "Completed in $($timer.Elapsed.Minutes) minutes $($timer.Elapsed.Seconds) seconds."

$TmpParameters = Get-Parameters -ArmOutput $output -AllParameters $Parameters -ValidParameters $validParameters["nested-application-appsettings.json"]
write-host "APPLICATION APP SETTINGS"
$timer =  [system.diagnostics.stopwatch]::StartNew()
$output = Start-SitecoreAzureDeployment -Name $ResourceGroupName -Location $Location -ArmTemplateUrl "$($SCTemplates["nested-application-appsettings.json"])" -SetKeyValue $TmpParameters
write-host "Completed in $($timer.Elapsed.Minutes) minutes $($timer.Elapsed.Seconds) seconds."

$TmpParameters = Get-Parameters -ArmOutput $output -AllParameters $Parameters -ValidParameters $validParameters["nested-application-exm.json"]
write-host "APPLICATION-EXM"
$timer =  [system.diagnostics.stopwatch]::StartNew()
$output = Start-SitecoreAzureDeployment -Name $ResourceGroupName -Location $Location -ArmTemplateUrl "$($SCTemplates["nested-application-exm.json"])" -SetKeyValue $TmpParameters
write-host "Completed in $($timer.Elapsed.Minutes) minutes $($timer.Elapsed.Seconds) seconds."

write-host "Arm template executions completed in $($mainsw.Elapsed.Hours) hours, $($mainsw.Elapsed.Minutes) minutes and $($mainsw.Elapsed.Seconds) seconds."