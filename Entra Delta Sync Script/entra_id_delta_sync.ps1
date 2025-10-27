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
    [string]$GraphBaseUri = 'https://graph.microsoft.com/v1.0',

    [Parameter()]
    [string]$LogFilePath,

    [Parameter()]
    [string]$CheckpointFilePath
)

#region Input Validation
Write-Verbose 'Validating input parameters...'

# Validate Tenant IDs are GUIDs
$guidPattern = '^[{]?[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}[}]?$'
if ($SourceTenantId -notmatch $guidPattern) {
    throw "SourceTenantId '$SourceTenantId' is not a valid GUID."
}
if ($DestinationTenantId -notmatch $guidPattern) {
    throw "DestinationTenantId '$DestinationTenantId' is not a valid GUID."
}
if ($ClientId -notmatch $guidPattern) {
    throw "ClientId '$ClientId' is not a valid GUID."
}

# Validate domains
if ([string]::IsNullOrWhiteSpace($SourceUserDomain)) {
    throw 'SourceUserDomain cannot be empty.'
}
if ([string]::IsNullOrWhiteSpace($DestinationUserDomain)) {
    throw 'DestinationUserDomain cannot be empty.'
}

Write-Verbose 'Input validation completed successfully.'
#endregion

function Write-Log {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [Parameter()]
        [ValidateSet('Info', 'Warning', 'Error', 'Success')]
        [string]$Level = 'Info'
    )

    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $logMessage = "[$timestamp] [$Level] $Message"

    if ($LogFilePath) {
        Add-Content -Path $LogFilePath -Value $logMessage
    }

    switch ($Level) {
        'Info'    { Write-Host $Message -ForegroundColor Cyan }
        'Warning' { Write-Host $Message -ForegroundColor Yellow }
        'Error'   { Write-Host $Message -ForegroundColor Red }
        'Success' { Write-Host $Message -ForegroundColor Green }
    }
}

function Save-Checkpoint {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Data
    )

    if ($CheckpointFilePath) {
        try {
            $Data | ConvertTo-Json -Depth 10 | Set-Content -Path $CheckpointFilePath
            Write-Verbose "Checkpoint saved to $CheckpointFilePath"
        }
        catch {
            Write-Log "Failed to save checkpoint: $_" -Level Warning
        }
    }
}

function Get-Checkpoint {
    if ($CheckpointFilePath -and (Test-Path $CheckpointFilePath)) {
        try {
            $checkpoint = Get-Content -Path $CheckpointFilePath -Raw | ConvertFrom-Json
            Write-Log "Resuming from checkpoint: $CheckpointFilePath" -Level Info
            return $checkpoint
        }
        catch {
            Write-Log "Failed to load checkpoint: $_" -Level Warning
            return $null
        }
    }
    return $null
}

function Get-SecureStringPlainText {
    param(
        [System.Security.SecureString]$SecureString
    )

    $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecureString)
    try {
        # Use PtrToStringAuto for cross-platform compatibility (PowerShell 7+)
        if ($PSVersionTable.PSVersion.Major -ge 6) {
            return [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
        }
        else {
            return [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
        }
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

function Test-TokenExpiry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][DateTime]$ExpiryTime,
        [Parameter()][int]$BufferMinutes = 5
    )

    return (Get-Date) -gt $ExpiryTime.AddMinutes(-$BufferMinutes)
}

function Update-TokensIfNeeded {
    if (Test-TokenExpiry -ExpiryTime $script:sourceTokenExpiry) {
        Write-Log 'Source token expired, refreshing...' -Level Warning
        $script:sourceToken = Get-GraphToken -TenantId $SourceTenantId -ClientId $ClientId -ClientSecret $ClientSecret
        $script:sourceTokenExpiry = (Get-Date).AddMinutes(55)
        Write-Log 'Source token refreshed.' -Level Success
    }

    if (Test-TokenExpiry -ExpiryTime $script:destinationTokenExpiry) {
        Write-Log 'Destination token expired, refreshing...' -Level Warning
        $script:destinationToken = Get-GraphToken -TenantId $DestinationTenantId -ClientId $ClientId -ClientSecret $ClientSecret
        $script:destinationTokenExpiry = (Get-Date).AddMinutes(55)
        Write-Log 'Destination token refreshed.' -Level Success
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

# Initialize logging
if ($LogFilePath) {
    Write-Log "=== Entra ID Delta Sync Session Started ===" -Level Info
    Write-Log "Source Tenant: $SourceTenantId" -Level Info
    Write-Log "Destination Tenant: $DestinationTenantId" -Level Info
}

Write-Log 'Authenticating to Microsoft Graph...' -Level Info
try {
    $sourceToken = Get-GraphToken -TenantId $SourceTenantId -ClientId $ClientId -ClientSecret $ClientSecret
    $sourceTokenExpiry = (Get-Date).AddMinutes(55)  # Tokens typically valid for 1 hour
    Write-Log 'Source tenant authentication successful.' -Level Success
}
catch {
    Write-Log "Failed to authenticate to source tenant: $_" -Level Error
    throw
}

try {
    $destinationToken = Get-GraphToken -TenantId $DestinationTenantId -ClientId $ClientId -ClientSecret $ClientSecret
    $destinationTokenExpiry = (Get-Date).AddMinutes(55)
    Write-Log 'Destination tenant authentication successful.' -Level Success
}
catch {
    Write-Log "Failed to authenticate to destination tenant: $_" -Level Error
    throw
}

$selectQuery = ($AttributesToCompare + 'id' + 'userPrincipalName') | Select-Object -Unique | ForEach-Object { $_ }
$selectString = '$select=' + ($selectQuery -join ',')

Write-Log 'Retrieving users from source tenant...' -Level Info
try {
    $sourceUsers = Get-GraphPagedResults -Uri "$GraphBaseUri/users?$selectString" -AccessToken $sourceToken
    Write-Log "Retrieved $($sourceUsers.Count) users from source tenant." -Level Success
}
catch {
    Write-Log "Failed to retrieve users from source tenant: $_" -Level Error
    throw
}

Write-Log 'Retrieving users from destination tenant...' -Level Info
try {
    $destinationUsers = Get-GraphPagedResults -Uri "$GraphBaseUri/users?$selectString" -AccessToken $destinationToken
    Write-Log "Retrieved $($destinationUsers.Count) users from destination tenant." -Level Success
}
catch {
    Write-Log "Failed to retrieve users from destination tenant: $_" -Level Error
    throw
}

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
$errorCount = 0

# Load checkpoint if available
$checkpoint = Get-Checkpoint
$processedUpns = if ($checkpoint -and $checkpoint.ProcessedUpns) {
    [System.Collections.Generic.HashSet[string]]::new($checkpoint.ProcessedUpns)
} else {
    [System.Collections.Generic.HashSet[string]]::new()
}

$totalUsers = $sourceUsers.Count
$usersWithDifferences = 0

foreach ($sourceUser in $sourceUsers) {
    $processedUsers++

    # Display progress every 10 users or for the first/last user
    if ($processedUsers -eq 1 -or $processedUsers -eq $totalUsers -or $processedUsers % 10 -eq 0) {
        $percentComplete = [math]::Round(($processedUsers / $totalUsers) * 100, 1)
        Write-Progress -Activity "Processing Users" -Status "User $processedUsers of $totalUsers ($percentComplete%)" -PercentComplete $percentComplete
    }

    # Skip if already processed (from checkpoint)
    if ($processedUpns.Contains($sourceUser.userPrincipalName)) {
        Write-Verbose "Skipping already processed user: $($sourceUser.userPrincipalName)"
        continue
    }

    # Refresh tokens if needed
    Update-TokensIfNeeded

    $localPart = Get-LocalPart -Upn $sourceUser.userPrincipalName
    if (-not $localPart) {
        Write-Log "Invalid UPN format: $($sourceUser.userPrincipalName)" -Level Warning
        continue
    }

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
        Write-Log "No destination match for $($sourceUser.userPrincipalName)" -Level Warning
        $processedUpns.Add($sourceUser.userPrincipalName) | Out-Null
        continue
    }

    $differences = Compare-UserAttributes -SourceUser $sourceUser -DestinationUser $destinationUser -Attributes $AttributesToCompare
    if ($differences.Count -eq 0) {
        $processedUpns.Add($sourceUser.userPrincipalName) | Out-Null
        continue
    }

    $usersWithDifferences++
    Show-Differences -SourceUpn $sourceUser.userPrincipalName -DestinationUpn $destinationUser.userPrincipalName -Differences $differences

    $choice = Get-ActionSelection -ValidChoices @('Merge to destination', 'Merge to source', 'Skip', 'Flag')

    switch ($choice) {
        'Merge to destination' {
            try {
                Update-UserAttributes -SourceUser $sourceUser -DestinationUser $destinationUser -Differences $differences -Direction 'SourceToDestination' -SourceToken $sourceToken -DestinationToken $destinationToken -GraphBaseUri $GraphBaseUri
                Write-Log "Destination updated successfully for $($destinationUser.userPrincipalName)" -Level Success
                $updatedDestinationCount++
            }
            catch {
                Write-Log "Failed to update destination for $($destinationUser.userPrincipalName): $_" -Level Error
                $errorCount++
            }
        }
        'Merge to source' {
            try {
                Update-UserAttributes -SourceUser $sourceUser -DestinationUser $destinationUser -Differences $differences -Direction 'DestinationToSource' -SourceToken $sourceToken -DestinationToken $destinationToken -GraphBaseUri $GraphBaseUri
                Write-Log "Source updated successfully for $($sourceUser.userPrincipalName)" -Level Success
                $updatedSourceCount++
            }
            catch {
                Write-Log "Failed to update source for $($sourceUser.userPrincipalName): $_" -Level Error
                $errorCount++
            }
        }
        'Skip' {
            $skippedCount++
            Write-Log "Skipped $($sourceUser.userPrincipalName)" -Level Warning
        }
        'Flag' {
            $note = Read-Host 'Optional note for flagged user (press enter to leave blank)'
            $flaggedUsers += [PSCustomObject]@{
                SourceUserPrincipalName      = $sourceUser.userPrincipalName
                DestinationUserPrincipalName = $destinationUser.userPrincipalName
                Differences                  = ($differences | ConvertTo-Json -Depth 5)
                Note                         = $note
            }
            Write-Log "User flagged for review: $($sourceUser.userPrincipalName)" -Level Warning
        }
    }

    # Mark as processed and save checkpoint
    $processedUpns.Add($sourceUser.userPrincipalName) | Out-Null

    # Save checkpoint every 5 users
    if ($processedUsers % 5 -eq 0) {
        Save-Checkpoint -Data @{
            ProcessedUpns = @($processedUpns)
            LastProcessedUser = $sourceUser.userPrincipalName
            UpdatedDestinationCount = $updatedDestinationCount
            UpdatedSourceCount = $updatedSourceCount
            SkippedCount = $skippedCount
            ErrorCount = $errorCount
        }
    }
}

Write-Progress -Activity "Processing Users" -Completed

# Final summary
Write-Log "`n========== SYNCHRONIZATION SUMMARY ==========" -Level Info
Write-Log "Total users processed:             $processedUsers" -Level Info
Write-Log "Users with differences found:      $usersWithDifferences" -Level Info
Write-Log "Updated destination users:         $updatedDestinationCount" -Level Success
Write-Log "Updated source users:              $updatedSourceCount" -Level Success
Write-Log "Skipped users:                     $skippedCount" -Level Warning
Write-Log "Users without destination match:   $missingMatches" -Level Warning
Write-Log "Errors encountered:                $errorCount" -Level $(if ($errorCount -gt 0) { 'Error' } else { 'Info' })
Write-Log "Flagged users:                     $($flaggedUsers.Count)" -Level $(if ($flaggedUsers.Count -gt 0) { 'Warning' } else { 'Info' })
Write-Log "=============================================" -Level Info

if ($flaggedUsers.Count -gt 0) {
    Write-Log "`nFlagged users require review." -Level Warning
    $exportPath = Read-Host 'Enter path to export flagged users to CSV (leave blank to skip)'
    if (-not [string]::IsNullOrWhiteSpace($exportPath)) {
        try {
            $flaggedUsers | Export-Csv -Path $exportPath -NoTypeInformation -Encoding UTF8
            Write-Log "Flagged users exported to $exportPath" -Level Success
        }
        catch {
            Write-Log "Failed to export flagged users: $_" -Level Error
        }
    }
}
else {
    Write-Log 'No users were flagged during this session.' -Level Info
}

# Clean up checkpoint file if completed successfully
if ($CheckpointFilePath -and (Test-Path $CheckpointFilePath) -and $errorCount -eq 0) {
    try {
        Remove-Item -Path $CheckpointFilePath -Force
        Write-Log "Checkpoint file removed (session completed successfully)." -Level Info
    }
    catch {
        Write-Log "Failed to remove checkpoint file: $_" -Level Warning
    }
}

if ($LogFilePath) {
    Write-Log "=== Entra ID Delta Sync Session Ended ===" -Level Info
    Write-Host "`nSession log saved to: $LogFilePath" -ForegroundColor Cyan
}
