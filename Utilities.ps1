Import-Module "$PSScriptRoot\newtonsoft.json.psm1"

function Get-SitecoreAzureToolkit{
   return Resolve-Path "$PSScriptRoot\packages\SitecoreAzureToolkit*\"
}
function Get-SitecoreLicense{
     return Resolve-Path "$PSScriptRoot\packages\License*\license.xml"
}
function Get-JsonTemplates{
    param(
        $StorageAccountName,
        $StorageAccountAccessKey,
        [string]$Name
    )
    $Name = $Name.ToLower() -replace '[^a-zA-Z]', ""
    $context = New-AzureStorageContext -StorageAccountName $StorageAccountName -StorageAccountKey $StorageAccountAccessKey
    $container = New-AzureStorageContainer -Name $Name -Context $context -Permission Container
    $ret = @{}
    $root = Set-AzureStorageBlobContent -File "$PSScriptRoot\azuredeploy.json" -Context $context -Container $container.Name -Force
    $ret["root"] = $root.ICloudBlob.Uri.AbsoluteUri
    Get-ChildItem "$PSScriptRoot\nested" -File | ForEach-Object{
        $tmp = Set-AzureStorageBlobContent -File $_.FullName -Context $context -Container $container.Name -Force
        $ret[(Split-Path $_.FullName -leaf)] = $tmp.ICloudBlob.Uri.AbsoluteUri;
    }
    return $ret
}
function Clear-JsonTemplates{
    param(
        $StorageAccountName,
        $StorageAccountAccessKey,
        [string]$Name
    )
    $Name = $Name.ToLower() -replace '[^a-zA-Z]', ""
    New-AzureStorageContext -StorageAccountName $StorageAccountName -StorageAccountKey $StorageAccountAccessKey | Remove-AzureStorageContainer -Name $Name -Force
}
function Get-PfxCertificate{
    param(
        $Name,
        $Password
    )
    return "$PSScriptRoot\sitecore.pfx"
    # $thumbprint = (New-SelfSignedCertificate `
    # -Subject "CN=$env:COMPUTERNAME @ Sitecore, Inc." `
    # -Type SSLServerAuthentication `
    # -FriendlyName $Name).Thumbprint

    # $certificateFilePath = "$PSScriptRoot\sitecore.pfx"
    # Export-PfxCertificate `
    #     -cert cert:\LocalMachine\MY\$thumbprint `
    #     -FilePath $certificateFilePath `
    #     -Password (ConvertTo-SecureString $Password -AsPlainText -Force) | Out-Null
    # return $certificateFilePath
}
function Clear-PfxCertificate{
    if (Test-Path "$PSScriptRoot\sitecore.pfx"){
        Remove-Item "$PSScriptRoot\sitecore.pfx"
    }
}

Function Start-SitecoreAzureDeployment{
    <#
        .SYNOPSIS
        You can deploy a new Sitecore instance on Azure for a specific SKU

        .DESCRIPTION
        Deploys a new instance of Sitecore on Azure

        .PARAMETER location
        Standard Azure region (e.g.: North Europe)
        .PARAMETER Name
        Name of the deployment
        .PARAMETER ArmTemplateUrl
        Url to the ARM template
        .PARAMETER ArmTemplatePath
        Path to the ARM template
        .PARAMETER ArmParametersPath
        Path to the ARM template parameter
        .PARAMETER LicenseXmlPath
        Path to a valid Sitecore license
        .PARAMETER SetKeyValue
        This is a hash table, use to set the unique values for the deployment parameters in Arm Template Parameters Json

        .EXAMPLE
        Import-Module -Verbose .\Cloud.Services.Provisioning.SDK\tools\Sitecore.Cloud.Cmdlets.psm1
        $SetKeyValue = @{
        "deploymentId"="xP0-QA";
        "Sitecore.admin.password"="!qaz2wsx";
        "sqlserver.login"="xpsqladmin";
        "sqlserver.password"="Password12345";    "analytics.mongodb.connectionstring"="mongodb://17.54.72.145:27017/xP0-QA-analytics";
        "tracking.live.mongodb.connectionstring"="mongodb://17.54.72.145:27017/xP0-QA-tracking_live";
        "tracking.history.mongodb.connectionstring"="mongodb://17.54.72.145:27017/xP0-QA-tracking_history";
        "tracking.contact.mongodb.connectionstring"="mongodb://17.54.72.145:27017/xP0-QA-tracking_contact"
        }
        Start-SitecoreAzureDeployment -Name $SetKeyValue.deploymentId -Region "North Europe" -ArmTemplatePath "C:\dev\azure\xP0.Template.json" -ArmParametersPath "xP0.Template.params.json" -LicenseXmlPath "D:\xp0\license.xml" -SetKeyValue $SetKeyValue
    #>
    [CmdletBinding()]
    param (
        [parameter(Mandatory=$true)]
        [alias("Region")]
        [string]$Location,
        [parameter(Mandatory=$true)]
        [string]$Name,
        [parameter(ParameterSetName="Template URI", Mandatory=$true)]
        [string]$ArmTemplateUrl,
        [parameter(ParameterSetName="Template Path", Mandatory=$true)]
        [string]$ArmTemplatePath,
        [hashtable]$SetKeyValue
    )

    try {
        Write-Host "Deployment Started..."

        if ([string]::IsNullOrEmpty($ArmTemplateUrl) -and [string]::IsNullOrEmpty($ArmTemplatePath)) {
            Write-Host "Either ArmTemplateUrl or ArmTemplatePath is required!"
            Break
        }

        if ($SetKeyValue -eq $null) {
            $SetKeyValue = @{}
        }

        # Set the Parameters in Arm Template Parameters Json
        $paramJson = @{}

        Write-Host "Setting ARM template parameters..."

        if ($paramJson."`$schema") {
            $paramJson = $paramJson.parameters
        }
        $SetKeyValue.Keys | % {
            if ($SetKeyValue[$_] -eq $null){
                write-host "parameter $_ is null"
            }
            if ($SetKeyValue[$_].GetType().Name -eq "JObject"){
                $paramJson.Add($_, @{"value" = (ConvertFrom-JsonNewtonsoft $SetKeyValue[$_].ToString())})
            }else{
                $paramJson.Add($_, @{"value" = $SetKeyValue[$_]})
            }
            }

        # Save to a temporary file
        $paramJsonFile = "temp_$([System.IO.Path]::GetRandomFileName())"
        $fullJson = $paramJson | ConvertTo-JsonNewtonsoft
        $fullJson | Set-Content $paramJsonFile -Encoding UTF8

        Write-Host "ARM template parameters are set!"

        # Deploy Sitecore in given Location
        Write-Host "Deploying Sitecore Instace..."
        $notPresent = Get-AzureRmResourceGroup -Name $Name -ev notPresent -ea 0
        if (!$notPresent) {
            throw "The resource group must already exist"
        }
        else {
            Write-Host "Resource Group Already Exists."
        }
        $retries = 4

        for ($i = 0; $i -lt $retries; $i++){
            try{
                if ([string]::IsNullOrEmpty($ArmTemplateUrl)) {
                    $PSResGrpDeployment = New-AzureRmResourceGroupDeployment -Name $Name -ResourceGroupName $Name -TemplateFile $ArmTemplatePath -TemplateParameterFile $paramJsonFile
                }else{
                    write-host "Using template: $($ArmTemplateUrl -replace ' ', '%20')"
                    write-host "JSON PARAMETERS:\n\n$fullJson"
                    # Replace space character in the url, as it's not being replaced by the cmdlet itself
                    $PSResGrpDeployment = New-AzureRmResourceGroupDeployment -Name $Name -ResourceGroupName $Name -TemplateUri ($ArmTemplateUrl -replace ' ', '%20') -TemplateParameterFile $paramJsonFile
                }
                write-host "Provisioning State: $($PSResGrpDeployment.ProvisioningState)"
                if ($PSResGrpDeployment.ProvisioningState -ne "Failed"){
                    break
                }
            }catch{
                Write-Error $_.Exception.Message       
            }
            if ($retries -gt ($i - 1)){
                write-host "Trying again..."
                Start-Sleep -s 15
            }
        }
        return $PSResGrpDeployment
    }
    catch {
        Write-Error $_.Exception.Message
        Break
    }
    finally {
      if ($paramJsonFile) {
        Remove-Item $paramJsonFile
      }
    }
}
function Get-Parameters{
    param(
        $ArmOutput,
        [hashtable] $AllParameters,
        [hashtable] $ValidParameters
    )
    $ret = @{}
    foreach ($key in $Armoutput.Parameters.Keys){
        if (!$AllParameters.ContainsKey($key)){
            $AllParameters[$key] = $ArmOutput.Parameters[$key].Value
        }
    }
    if ($Armoutput.Outputs -ne $null){
        foreach ($key in $Armoutput.Outputs.Keys){
            if (!$AllParameters.ContainsKey($key)){
                $AllParameters[$key] = $ArmOutput.Outputs[$key].Value
            }
        }
    }
    $ValidParameters.Keys | ForEach-Object{
        if ($_ -ne $null -and $AllParameters.ContainsKey($_) -and $AllParameters[$_] -ne $null){
            $ret[$_] = $AllParameters[$_]
        }
    }
    return $ret
}
function Get-ValidParameters{
    $ret = @{}
    Get-ChildItem "$PSScriptRoot\nested" | ForEach-Object{
        if ($_.FullName.EndsWith(".json")){
            $fileName = Split-Path $_.FullName -Leaf
            $json = Get-Content $_.FullName | ConvertFrom-Json
            $curTable = @{}
            $json.parameters | Select-Object -Property * | ForEach-Object {$_.PSObject.Properties} | ForEach-Object {
                if ($_.Name -ne "resourceSizes" -and $_.Name -ne "skuMap" -and $_.Name -ne $null){
                    $curTable[$_.Name] = $true
                }
            }
            $ret[$fileName] = $curTable
        }
    }
    return $ret
}