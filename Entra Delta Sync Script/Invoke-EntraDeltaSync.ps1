<#
.SYNOPSIS
    Wrapper script to invoke the Entra ID delta sync using saved configuration.

.DESCRIPTION
    This script loads the configuration created by Setup-EntraSyncApp.ps1 and invokes
    the entra_id_delta_sync.ps1 script with the appropriate parameters. It handles
    both multi-tenant and separate app configurations.

.PARAMETER ConfigPath
    Path to the configuration file created by Setup-EntraSyncApp.ps1.
    Default is './entra-sync-config.json'.

.PARAMETER SourceUserDomain
    The domain suffix for source tenant users (e.g., 'sourcetenant.com').

.PARAMETER DestinationUserDomain
    The domain suffix for destination tenant users (e.g., 'destinationtenant.com').

.PARAMETER AttributesToCompare
    Optional array of attributes to compare. If not specified, uses script defaults.

.PARAMETER LogFilePath
    Optional path for detailed logging.

.PARAMETER CheckpointFilePath
    Optional path for checkpoint file to enable resume capability.

.EXAMPLE
    .\Invoke-EntraDeltaSync.ps1 -SourceUserDomain "source.com" -DestinationUserDomain "dest.com"

.EXAMPLE
    .\Invoke-EntraDeltaSync.ps1 -ConfigPath "./my-config.json" -SourceUserDomain "source.com" -DestinationUserDomain "dest.com" -LogFilePath "./sync.log"

.NOTES
    Requires the configuration file created by Setup-EntraSyncApp.ps1
#>

[CmdletBinding()]
param(
    [Parameter()]
    [string]$ConfigPath = './entra-sync-config.json',

    [Parameter(Mandatory = $true)]
    [string]$SourceUserDomain,

    [Parameter(Mandatory = $true)]
    [string]$DestinationUserDomain,

    [Parameter()]
    [string[]]$AttributesToCompare,

    [Parameter()]
    [string]$LogFilePath,

    [Parameter()]
    [string]$CheckpointFilePath
)

$ErrorActionPreference = 'Stop'

function Write-ColorOutput {
    param(
        [string]$Message,
        [ConsoleColor]$ForegroundColor = [ConsoleColor]::White
    )
    Write-Host $Message -ForegroundColor $ForegroundColor
}

function Get-SavedConfiguration {
    param([string]$Path)

    if (-not (Test-Path $Path)) {
        throw "Configuration file not found: $Path. Please run Setup-EntraSyncApp.ps1 first."
    }

    Write-ColorOutput "Loading configuration from: $Path" -ForegroundColor Cyan

    $rawContent = Get-Content -Path $Path -Raw | ConvertFrom-Json

    # Check if encrypted
    if ($rawContent.Encrypted -eq $true) {
        Write-ColorOutput "Decrypting configuration..." -ForegroundColor Yellow

        if (-not $IsWindows) {
            throw "Encrypted configurations can only be decrypted on Windows."
        }

        try {
            $secureString = ConvertTo-SecureString -String $rawContent.Data
            $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureString)
            try {
                $decryptedJson = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
                $config = $decryptedJson | ConvertFrom-Json
                return $config
            }
            finally {
                [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
            }
        }
        catch {
            throw "Failed to decrypt configuration. This file may have been encrypted on a different computer or by a different user."
        }
    }
    else {
        return $rawContent
    }
}

# Main execution
Write-ColorOutput @"

╔═══════════════════════════════════════════════════════════╗
║                                                           ║
║        Entra ID Delta Sync - Automated Execution          ║
║                                                           ║
╚═══════════════════════════════════════════════════════════╝

"@ -ForegroundColor Cyan

try {
    # Load configuration
    $config = Get-SavedConfiguration -Path $ConfigPath

    Write-ColorOutput "`nConfiguration loaded successfully!" -ForegroundColor Green
    Write-ColorOutput "  Setup Mode: $($config.SetupMode)" -ForegroundColor White
    Write-ColorOutput "  Setup Date: $($config.SetupDate)" -ForegroundColor White

    # Check secret expiration
    $expiryDate = [DateTime]::Parse($config.SecretExpiresAt)
    $daysUntilExpiry = ($expiryDate - (Get-Date)).Days

    if ($daysUntilExpiry -lt 0) {
        Write-ColorOutput "`n⚠️  WARNING: Client secret has EXPIRED!" -ForegroundColor Red
        Write-ColorOutput "Please run Setup-EntraSyncApp.ps1 again to create a new secret." -ForegroundColor Yellow
        throw "Client secret expired."
    }
    elseif ($daysUntilExpiry -lt 30) {
        Write-ColorOutput "`n⚠️  WARNING: Client secret expires in $daysUntilExpiry days!" -ForegroundColor Yellow
    }

    # Determine script path
    $syncScriptPath = Join-Path $PSScriptRoot "entra_id_delta_sync.ps1"

    if (-not (Test-Path $syncScriptPath)) {
        throw "Sync script not found: $syncScriptPath"
    }

    # Build parameters based on setup mode
    $syncParams = @{
        SourceUserDomain = $SourceUserDomain
        DestinationUserDomain = $DestinationUserDomain
    }

    if ($config.SetupMode -eq 'MultiTenant') {
        Write-ColorOutput "`nUsing MULTI-TENANT configuration" -ForegroundColor Cyan

        # For multi-tenant, we need both tenant IDs
        $sourceTenantId = Read-Host "Enter SOURCE Tenant ID"
        $destinationTenantId = Read-Host "Enter DESTINATION Tenant ID"

        $syncParams.Add('SourceTenantId', $sourceTenantId)
        $syncParams.Add('DestinationTenantId', $destinationTenantId)
        $syncParams.Add('ClientId', $config.AppRegistration.ClientId)
        $syncParams.Add('ClientSecret', (ConvertTo-SecureString -String $config.AppRegistration.ClientSecret -AsPlainText -Force))
    }
    else {
        Write-ColorOutput "`nUsing SEPARATE APPS configuration" -ForegroundColor Cyan

        $syncParams.Add('SourceTenantId', $config.SourceApp.TenantId)
        $syncParams.Add('DestinationTenantId', $config.DestinationApp.TenantId)

        # Note: The sync script needs to be modified to accept separate credentials
        # For now, we'll use the source app credentials (assuming same secret for demo)
        $syncParams.Add('ClientId', $config.SourceApp.ClientId)
        $syncParams.Add('ClientSecret', (ConvertTo-SecureString -String $config.SourceApp.ClientSecret -AsPlainText -Force))

        Write-ColorOutput "`n⚠️  Note: Using source app credentials. The sync script currently doesn't support separate app credentials per tenant." -ForegroundColor Yellow
    }

    # Add optional parameters
    if ($AttributesToCompare) {
        $syncParams.Add('AttributesToCompare', $AttributesToCompare)
    }

    if ($LogFilePath) {
        $syncParams.Add('LogFilePath', $LogFilePath)
    }

    if ($CheckpointFilePath) {
        $syncParams.Add('CheckpointFilePath', $CheckpointFilePath)
    }

    # Display parameters (excluding secret)
    Write-ColorOutput "`nSync Parameters:" -ForegroundColor Cyan
    foreach ($key in $syncParams.Keys) {
        if ($key -ne 'ClientSecret') {
            $value = if ($syncParams[$key] -is [array]) { $syncParams[$key] -join ', ' } else { $syncParams[$key] }
            Write-ColorOutput "  $key: $value" -ForegroundColor White
        }
    }

    Write-ColorOutput "`n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
    Write-ColorOutput "Starting Entra ID Delta Sync..." -ForegroundColor Cyan
    Write-ColorOutput "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━`n" -ForegroundColor Cyan

    # Invoke the sync script
    & $syncScriptPath @syncParams

    Write-ColorOutput "`n╔═══════════════════════════════════════════════════════════╗" -ForegroundColor Green
    Write-ColorOutput "║              SYNC EXECUTION COMPLETED                     ║" -ForegroundColor Green
    Write-ColorOutput "╚═══════════════════════════════════════════════════════════╝" -ForegroundColor Green
}
catch {
    Write-ColorOutput "`n✗ Execution failed: $_" -ForegroundColor Red
    Write-ColorOutput $_.ScriptStackTrace -ForegroundColor Red
    exit 1
}
