<#
.SYNOPSIS
    Interactive Entra ID delta synchronisation helper for tenant-to-tenant migrations.

.DESCRIPTION
    Authenticates against source and destination Entra ID tenants using the same Azure AD application
    (client credentials flow) and compares key user attributes. For each user with differences the
    operator can choose to merge the source values into the destination tenant, merge the destination
    values back to source, skip the user, or flag the user for later review. Flagged users can be
    exported to a CSV file that can be opened in Excel.

.NOTES
    Requires Microsoft Graph application permissions such as User.Read.All and User.ReadWrite.All
    granted to the application (client id / secret). The application must be configured as multi-tenant
    if the tenants differ.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$SourceTenantId,

    [Parameter(Mandatory = $true)]
    [string]$DestinationTenantId,

    [Parameter(Mandatory = $true)]
    [string]$ClientId,

    [Parameter(Mandatory = $true)]
    [string]$SourceUserDomain,

    [Parameter(Mandatory = $true)]
    [string]$DestinationUserDomain,

    [Parameter()]
    [System.Security.SecureString]$ClientSecret,

    [Parameter()]
    [string[]]$AttributesToCompare = @(
        'displayName',
        'mail',
        'department',
        'jobTitle',
        'employeeType',
        'mobilePhone',
        'officeLocation'
    ),

    [Parameter()]
    [string]$GraphBaseUri = 'https://graph.microsoft.com/v1.0'
)

function Get-SecureStringPlainText {
    param(
        [System.Security.SecureString]$SecureString
    )

    $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecureString)
    try {
        return [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
    }
    finally {
        if ($bstr -ne [IntPtr]::Zero) {
            [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
        }
    }
}

function Get-GraphToken {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$TenantId,
        [Parameter(Mandatory = $true)][string]$ClientId,
        [Parameter(Mandatory = $true)][System.Security.SecureString]$ClientSecret,
        [Parameter()][string]$Scope = 'https://graph.microsoft.com/.default'
    )

    $tokenEndpoint = "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token"
    $body = [ordered]@{
        client_id     = $ClientId
        scope         = $Scope
        client_secret = Get-SecureStringPlainText -SecureString $ClientSecret
        grant_type    = 'client_credentials'
    }

    try {
        $response = Invoke-RestMethod -Method Post -Uri $tokenEndpoint -Body $body -ContentType 'application/x-www-form-urlencoded'
        return $response.access_token
    }
    catch {
        throw "Failed to acquire Microsoft Graph token for tenant $TenantId. $_"
    }
}

function Invoke-GraphRequest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Method,
        [Parameter(Mandatory = $true)][string]$Uri,
        [Parameter(Mandatory = $true)][string]$AccessToken,
        [Parameter()][object]$Body,
        [Parameter()][hashtable]$AdditionalHeaders
    )

    $headers = @{ Authorization = "Bearer $AccessToken" }
    if ($AdditionalHeaders) {
        foreach ($key in $AdditionalHeaders.Keys) {
            $headers[$key] = $AdditionalHeaders[$key]
        }
    }

    $params = @{ Method = $Method; Uri = $Uri; Headers = $headers }
    if ($Body) {
        $json = if ($Body -is [string]) { $Body } else { $Body | ConvertTo-Json -Depth 10 }
        $params['Body'] = $json
        $params['ContentType'] = 'application/json'
    }

    Invoke-RestMethod @params
}

function Get-GraphPagedResults {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Uri,
        [Parameter(Mandatory = $true)][string]$AccessToken
    )

    $results = @()
    $nextLink = $Uri
    while ($nextLink) {
        $response = Invoke-GraphRequest -Method Get -Uri $nextLink -AccessToken $AccessToken
        if ($response.value) {
            $results += $response.value
        }
        $nextLink = $response.'@odata.nextLink'
    }

    return $results
}

function Get-LocalPart {
    param([string]$Upn)
    if ([string]::IsNullOrWhiteSpace($Upn)) { return $null }
    if ($Upn -notmatch '^(?<alias>[^@]+)@.+$') { return $null }
    return $Matches['alias'].ToLowerInvariant()
}

function Format-AttributeValue {
    param([object]$Value)
    if ($null -eq $Value) { return '' }
    if ($Value -is [System.Array]) {
        return ($Value -join '; ')
    }
    return [string]$Value
}

function Compare-UserAttributes {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$SourceUser,
        [Parameter(Mandatory = $true)]$DestinationUser,
        [Parameter(Mandatory = $true)][string[]]$Attributes
    )

    $differences = @()
    foreach ($attribute in $Attributes) {
        $sourceValue = $SourceUser.$attribute
        $destinationValue = $DestinationUser.$attribute

        $sourceSerialized = if ($sourceValue -is [System.Array]) { $sourceValue -join '|' } else { [string]$sourceValue }
        $destinationSerialized = if ($destinationValue -is [System.Array]) { $destinationValue -join '|' } else { [string]$destinationValue }

        if ($sourceSerialized -ne $destinationSerialized) {
            $differences += [PSCustomObject]@{
                Attribute       = $attribute
                SourceValue     = Format-AttributeValue -Value $sourceValue
                DestinationValue= Format-AttributeValue -Value $destinationValue
            }
        }
    }

    return $differences
}

function Show-Differences {
    param(
        [string]$SourceUpn,
        [string]$DestinationUpn,
        [System.Collections.IEnumerable]$Differences
    )

    Write-Host '=============================================================' -ForegroundColor Cyan
    Write-Host "Source:      $SourceUpn" -ForegroundColor Yellow
    Write-Host "Destination: $DestinationUpn" -ForegroundColor Yellow
    Write-Host 'Attribute differences:' -ForegroundColor Cyan
    $table = $Differences | Format-Table -AutoSize | Out-String
    Write-Host $table
}

function Get-ActionSelection {
    param([string[]]$ValidChoices)
    $validMap = @{}
    foreach ($choice in $ValidChoices) {
        $validMap[$choice.ToLowerInvariant()] = $choice
    }

    while ($true) {
        $response = Read-Host "Choose action [$($ValidChoices -join '/')]"
        $normalized = $response.Trim().ToLowerInvariant()
        if ($validMap.ContainsKey($normalized)) {
            return $validMap[$normalized]
        }
        Write-Host "Invalid choice '$response'. Valid options: $($ValidChoices -join ', ')." -ForegroundColor Red
    }
}

function Update-UserAttributes {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$SourceUser,
        [Parameter(Mandatory = $true)]$DestinationUser,
        [Parameter(Mandatory = $true)][System.Collections.IEnumerable]$Differences,
        [Parameter(Mandatory = $true)][string]$Direction,
        [Parameter(Mandatory = $true)][string]$SourceToken,
        [Parameter(Mandatory = $true)][string]$DestinationToken,
        [Parameter(Mandatory = $true)][string]$GraphBaseUri
    )

    $payload = @{}
    foreach ($diff in $Differences) {
        $attribute = $diff.Attribute
        switch ($Direction) {
            'SourceToDestination' {
                $payload[$attribute] = $SourceUser.$attribute
            }
            'DestinationToSource' {
                $payload[$attribute] = $DestinationUser.$attribute
            }
        }
    }

    if ($payload.Keys.Count -eq 0) {
        Write-Host 'No attributes to update.' -ForegroundColor DarkYellow
        return
    }

    switch ($Direction) {
        'SourceToDestination' {
            $uri = "$GraphBaseUri/users/$($DestinationUser.id)"
            Invoke-GraphRequest -Method Patch -Uri $uri -AccessToken $DestinationToken -Body $payload | Out-Null
        }
        'DestinationToSource' {
            $uri = "$GraphBaseUri/users/$($SourceUser.id)"
            Invoke-GraphRequest -Method Patch -Uri $uri -AccessToken $SourceToken -Body $payload | Out-Null
        }
        default {
            throw "Unsupported update direction '$Direction'"
        }
    }
}

if (-not $PSBoundParameters.ContainsKey('ClientSecret') -or $null -eq $ClientSecret) {
    $ClientSecret = Read-Host -Prompt 'Enter client secret for the application' -AsSecureString
}

Write-Host 'Authenticating to Microsoft Graph...' -ForegroundColor Cyan
$sourceToken = Get-GraphToken -TenantId $SourceTenantId -ClientId $ClientId -ClientSecret $ClientSecret
$destinationToken = Get-GraphToken -TenantId $DestinationTenantId -ClientId $ClientId -ClientSecret $ClientSecret

$selectQuery = ($AttributesToCompare + 'id' + 'userPrincipalName') | Select-Object -Unique | ForEach-Object { $_ }
$selectString = '$select=' + ($selectQuery -join ',')

Write-Host 'Retrieving users from source tenant...' -ForegroundColor Cyan
$sourceUsers = Get-GraphPagedResults -Uri "$GraphBaseUri/users?$selectString" -AccessToken $sourceToken
Write-Host "Retrieved $($sourceUsers.Count) users from source tenant." -ForegroundColor Green

Write-Host 'Retrieving users from destination tenant...' -ForegroundColor Cyan
$destinationUsers = Get-GraphPagedResults -Uri "$GraphBaseUri/users?$selectString" -AccessToken $destinationToken
Write-Host "Retrieved $($destinationUsers.Count) users from destination tenant." -ForegroundColor Green

$destinationLookup = @{}
foreach ($destUser in $destinationUsers) {
    $localPart = Get-LocalPart -Upn $destUser.userPrincipalName
    if (-not $localPart) { continue }
    $destinationLookup[$localPart] = $destUser
}

$flaggedUsers = @()
$processedUsers = 0
$updatedSourceCount = 0
$updatedDestinationCount = 0
$skippedCount = 0
$missingMatches = 0

foreach ($sourceUser in $sourceUsers) {
    $processedUsers++
    $localPart = Get-LocalPart -Upn $sourceUser.userPrincipalName
    if (-not $localPart) { continue }

    $destinationUser = $null
    if ($destinationLookup.ContainsKey($localPart)) {
        $destinationUser = $destinationLookup[$localPart]
    }
    else {
        $fallbackUpn = "$localPart@$DestinationUserDomain"
        $destinationUser = $destinationUsers | Where-Object { $_.userPrincipalName -eq $fallbackUpn } | Select-Object -First 1
    }

    if (-not $destinationUser) {
        $missingMatches++
        Write-Host "No destination match for $($sourceUser.userPrincipalName)" -ForegroundColor DarkYellow
        continue
    }

    $differences = Compare-UserAttributes -SourceUser $sourceUser -DestinationUser $destinationUser -Attributes $AttributesToCompare
    if ($differences.Count -eq 0) {
        continue
    }

    Show-Differences -SourceUpn $sourceUser.userPrincipalName -DestinationUpn $destinationUser.userPrincipalName -Differences $differences

    $choice = Get-ActionSelection -ValidChoices @('Merge to destination', 'Merge to source', 'Skip', 'Flag')

    switch ($choice) {
        'Merge to destination' {
            try {
                Update-UserAttributes -SourceUser $sourceUser -DestinationUser $destinationUser -Differences $differences -Direction 'SourceToDestination' -SourceToken $sourceToken -DestinationToken $destinationToken -GraphBaseUri $GraphBaseUri
                Write-Host 'Destination updated successfully.' -ForegroundColor Green
                $updatedDestinationCount++
            }
            catch {
                Write-Host "Failed to update destination: $_" -ForegroundColor Red
            }
        }
        'Merge to source' {
            try {
                Update-UserAttributes -SourceUser $sourceUser -DestinationUser $destinationUser -Differences $differences -Direction 'DestinationToSource' -SourceToken $sourceToken -DestinationToken $destinationToken -GraphBaseUri $GraphBaseUri
                Write-Host 'Source updated successfully.' -ForegroundColor Green
                $updatedSourceCount++
            }
            catch {
                Write-Host "Failed to update source: $_" -ForegroundColor Red
            }
        }
        'Skip' {
            $skippedCount++
            Write-Host 'Skipped.' -ForegroundColor DarkYellow
        }
        'Flag' {
            $note = Read-Host 'Optional note for flagged user (press enter to leave blank)'
            $flaggedUsers += [PSCustomObject]@{
                SourceUserPrincipalName      = $sourceUser.userPrincipalName
                DestinationUserPrincipalName = $destinationUser.userPrincipalName
                Differences                  = ($differences | ConvertTo-Json -Depth 5)
                Note                         = $note
            }
            Write-Host 'User flagged for review.' -ForegroundColor DarkYellow
        }
    }
}

Write-Host "Processed $processedUsers users." -ForegroundColor Cyan
Write-Host "Updated destination users: $updatedDestinationCount" -ForegroundColor Green
Write-Host "Updated source users:      $updatedSourceCount" -ForegroundColor Green
Write-Host "Skipped users:             $skippedCount" -ForegroundColor Yellow
Write-Host "Users without destination match: $missingMatches" -ForegroundColor Yellow

if ($flaggedUsers.Count -gt 0) {
    Write-Host "Flagged users: $($flaggedUsers.Count)" -ForegroundColor Yellow
    $exportPath = Read-Host 'Enter path to export flagged users to CSV (leave blank to skip)'
    if (-not [string]::IsNullOrWhiteSpace($exportPath)) {
        try {
            $flaggedUsers | Export-Csv -Path $exportPath -NoTypeInformation -Encoding UTF8
            Write-Host "Flagged users exported to $exportPath" -ForegroundColor Green
        }
        catch {
            Write-Host "Failed to export flagged users: $_" -ForegroundColor Red
        }
    }
}
else {
    Write-Host 'No users were flagged during this session.' -ForegroundColor Cyan
}
