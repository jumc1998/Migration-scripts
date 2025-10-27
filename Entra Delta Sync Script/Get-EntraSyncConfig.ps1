<#
.SYNOPSIS
    View and manage saved Entra Delta Sync configurations.

.DESCRIPTION
    This utility script allows you to view, validate, and manage configurations
    created by Setup-EntraSyncApp.ps1. It can display configuration details
    (without revealing secrets), check secret expiration, and export configuration
    for use in other scripts.

.PARAMETER ConfigPath
    Path to the configuration file. Default is './entra-sync-config.json'.

.PARAMETER ShowSecrets
    If specified, displays the client secrets (use with caution).

.PARAMETER CheckExpiration
    Only check and display secret expiration information.

.PARAMETER ExportForScript
    Exports configuration in a format suitable for direct script consumption.

.EXAMPLE
    .\Get-EntraSyncConfig.ps1

.EXAMPLE
    .\Get-EntraSyncConfig.ps1 -ConfigPath "./my-config.json" -ShowSecrets

.EXAMPLE
    .\Get-EntraSyncConfig.ps1 -CheckExpiration

.NOTES
    Part of the Entra ID Delta Sync toolset.
#>

[CmdletBinding()]
param(
    [Parameter()]
    [string]$ConfigPath = './entra-sync-config.json',

    [Parameter()]
    [switch]$ShowSecrets,

    [Parameter()]
    [switch]$CheckExpiration,

    [Parameter()]
    [switch]$ExportForScript
)

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
        throw "Configuration file not found: $Path"
    }

    $rawContent = Get-Content -Path $Path -Raw | ConvertFrom-Json

    # Check if encrypted
    if ($rawContent.Encrypted -eq $true) {
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
            throw "Failed to decrypt configuration."
        }
    }
    else {
        return $rawContent
    }
}

function Show-ConfigurationSummary {
    param($Config, [bool]$IncludeSecrets)

    Write-ColorOutput "`n╔═══════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-ColorOutput "║           Entra Delta Sync Configuration                 ║" -ForegroundColor Cyan
    Write-ColorOutput "╚═══════════════════════════════════════════════════════════╝`n" -ForegroundColor Cyan

    Write-ColorOutput "Setup Information:" -ForegroundColor Yellow
    Write-ColorOutput "  Mode: $($Config.SetupMode)" -ForegroundColor White
    Write-ColorOutput "  Created: $($Config.SetupDate)" -ForegroundColor White
    if ($Config.CreatedBy) {
        Write-ColorOutput "  Created By: $($Config.CreatedBy)" -ForegroundColor White
    }

    $expiryDate = [DateTime]::Parse($Config.SecretExpiresAt)
    $daysUntilExpiry = ($expiryDate - (Get-Date)).Days

    Write-ColorOutput "`nSecret Expiration:" -ForegroundColor Yellow
    Write-ColorOutput "  Expires: $($expiryDate.ToString('yyyy-MM-dd HH:mm'))" -ForegroundColor White

    if ($daysUntilExpiry -lt 0) {
        Write-ColorOutput "  Status: EXPIRED ❌" -ForegroundColor Red
        Write-ColorOutput "  Action Required: Run Setup-EntraSyncApp.ps1 to create new secret" -ForegroundColor Red
    }
    elseif ($daysUntilExpiry -lt 30) {
        Write-ColorOutput "  Status: Expiring Soon ⚠️  ($daysUntilExpiry days remaining)" -ForegroundColor Yellow
    }
    else {
        Write-ColorOutput "  Status: Valid ✓ ($daysUntilExpiry days remaining)" -ForegroundColor Green
    }

    if ($Config.SetupMode -eq 'MultiTenant') {
        Write-ColorOutput "`nMulti-Tenant App Registration:" -ForegroundColor Yellow
        Write-ColorOutput "  Primary Tenant ID: $($Config.AppRegistration.TenantId)" -ForegroundColor White
        Write-ColorOutput "  Client ID: $($Config.AppRegistration.ClientId)" -ForegroundColor White
        Write-ColorOutput "  Application Object ID: $($Config.AppRegistration.ApplicationObjectId)" -ForegroundColor White

        if ($IncludeSecrets) {
            Write-ColorOutput "  Client Secret: $($Config.AppRegistration.ClientSecret)" -ForegroundColor Red
        }
        else {
            Write-ColorOutput "  Client Secret: ******** (hidden)" -ForegroundColor DarkGray
        }

        if ($Config.AppRegistration.SecondaryTenantId) {
            Write-ColorOutput "  Secondary Tenant ID: $($Config.AppRegistration.SecondaryTenantId)" -ForegroundColor White
        }
    }
    else {
        Write-ColorOutput "`nSource Tenant App:" -ForegroundColor Yellow
        Write-ColorOutput "  Tenant ID: $($Config.SourceApp.TenantId)" -ForegroundColor White
        Write-ColorOutput "  Client ID: $($Config.SourceApp.ClientId)" -ForegroundColor White
        Write-ColorOutput "  Application Object ID: $($Config.SourceApp.ApplicationObjectId)" -ForegroundColor White

        if ($IncludeSecrets) {
            Write-ColorOutput "  Client Secret: $($Config.SourceApp.ClientSecret)" -ForegroundColor Red
        }
        else {
            Write-ColorOutput "  Client Secret: ******** (hidden)" -ForegroundColor DarkGray
        }

        Write-ColorOutput "`nDestination Tenant App:" -ForegroundColor Yellow
        Write-ColorOutput "  Tenant ID: $($Config.DestinationApp.TenantId)" -ForegroundColor White
        Write-ColorOutput "  Client ID: $($Config.DestinationApp.ClientId)" -ForegroundColor White
        Write-ColorOutput "  Application Object ID: $($Config.DestinationApp.ApplicationObjectId)" -ForegroundColor White

        if ($IncludeSecrets) {
            Write-ColorOutput "  Client Secret: $($Config.DestinationApp.ClientSecret)" -ForegroundColor Red
        }
        else {
            Write-ColorOutput "  Client Secret: ******** (hidden)" -ForegroundColor DarkGray
        }
    }

    Write-ColorOutput "" -ForegroundColor White
}

# Main execution
try {
    Write-ColorOutput "Loading configuration from: $ConfigPath" -ForegroundColor Cyan
    $config = Get-SavedConfiguration -Path $ConfigPath
    Write-ColorOutput "Configuration loaded successfully!`n" -ForegroundColor Green

    if ($CheckExpiration) {
        # Only show expiration info
        $expiryDate = [DateTime]::Parse($config.SecretExpiresAt)
        $daysUntilExpiry = ($expiryDate - (Get-Date)).Days

        if ($daysUntilExpiry -lt 0) {
            Write-ColorOutput "Secret Status: EXPIRED" -ForegroundColor Red
            exit 1
        }
        elseif ($daysUntilExpiry -lt 30) {
            Write-ColorOutput "Secret Status: Expiring in $daysUntilExpiry days" -ForegroundColor Yellow
            exit 0
        }
        else {
            Write-ColorOutput "Secret Status: Valid ($daysUntilExpiry days remaining)" -ForegroundColor Green
            exit 0
        }
    }
    elseif ($ExportForScript) {
        # Export for script consumption
        $config | ConvertTo-Json -Depth 10
    }
    else {
        # Show full summary
        Show-ConfigurationSummary -Config $config -IncludeSecrets $ShowSecrets.IsPresent

        if ($ShowSecrets) {
            Write-ColorOutput "⚠️  WARNING: Secrets are visible above. Ensure no one else can see your screen!" -ForegroundColor Red
        }
    }
}
catch {
    Write-ColorOutput "Error: $_" -ForegroundColor Red
    exit 1
}
