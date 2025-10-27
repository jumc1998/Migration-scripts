<#
.SYNOPSIS
    Automated setup script for Entra ID Delta Sync App Registration.

.DESCRIPTION
    This script automates the creation of Azure AD app registrations needed for the
    Entra ID delta synchronization tool. It creates app registrations in both source
    and destination tenants (or a single multi-tenant app), configures the required
    Microsoft Graph permissions, creates client secrets, and securely stores the
    configuration for later use.

.PARAMETER SetupMode
    Choose between 'MultiTenant' (single app for both tenants) or 'SeparateApps'
    (one app per tenant). Default is 'MultiTenant'.

.PARAMETER AppName
    The display name for the app registration(s). Default is 'Entra Delta Sync Tool'.

.PARAMETER SecretExpirationMonths
    Number of months until the client secret expires. Default is 12 months.

.PARAMETER ConfigOutputPath
    Path where the configuration file will be saved. Default is './entra-sync-config.json'.

.PARAMETER EncryptConfig
    If specified, encrypts the configuration file using Windows DPAPI (Windows only).

.EXAMPLE
    .\Setup-EntraSyncApp.ps1 -SetupMode MultiTenant

.EXAMPLE
    .\Setup-EntraSyncApp.ps1 -SetupMode SeparateApps -EncryptConfig

.NOTES
    Requires Microsoft.Graph PowerShell module to be installed.
    Run: Install-Module Microsoft.Graph -Scope CurrentUser
#>

[CmdletBinding()]
param(
    [Parameter()]
    [ValidateSet('MultiTenant', 'SeparateApps')]
    [string]$SetupMode = 'MultiTenant',

    [Parameter()]
    [string]$AppName = 'Entra Delta Sync Tool',

    [Parameter()]
    [ValidateRange(1, 24)]
    [int]$SecretExpirationMonths = 12,

    [Parameter()]
    [string]$ConfigOutputPath = './entra-sync-config.json',

    [Parameter()]
    [switch]$EncryptConfig
)

#Requires -Modules @{ ModuleName='Microsoft.Graph.Authentication'; ModuleVersion='2.0.0' }
#Requires -Modules @{ ModuleName='Microsoft.Graph.Applications'; ModuleVersion='2.0.0' }

$ErrorActionPreference = 'Stop'

# Required Graph API permissions
$requiredPermissions = @(
    @{
        ResourceAppId = "00000003-0000-0000-c000-000000000000"  # Microsoft Graph
        Permissions = @(
            @{ Id = "df021288-bdef-4463-88db-98f22de89214"; Type = "Role"; Name = "User.Read.All" }
            @{ Id = "741f803b-c850-494e-b5df-cde7c675a1ca"; Type = "Role"; Name = "User.ReadWrite.All" }
        )
    }
)

function Write-ColorOutput {
    param(
        [string]$Message,
        [ConsoleColor]$ForegroundColor = [ConsoleColor]::White
    )
    Write-Host $Message -ForegroundColor $ForegroundColor
}

function Test-GraphModule {
    Write-ColorOutput "`nChecking for Microsoft.Graph PowerShell modules..." -ForegroundColor Cyan

    $requiredModules = @('Microsoft.Graph.Authentication', 'Microsoft.Graph.Applications')
    $missingModules = @()

    foreach ($module in $requiredModules) {
        if (-not (Get-Module -ListAvailable -Name $module)) {
            $missingModules += $module
        }
    }

    if ($missingModules.Count -gt 0) {
        Write-ColorOutput "Missing required modules: $($missingModules -join ', ')" -ForegroundColor Red
        Write-ColorOutput "`nPlease install the required modules by running:" -ForegroundColor Yellow
        Write-ColorOutput "Install-Module Microsoft.Graph -Scope CurrentUser" -ForegroundColor White
        throw "Required modules not installed."
    }

    Write-ColorOutput "All required modules are installed." -ForegroundColor Green
}

function New-AppRegistration {
    param(
        [string]$DisplayName,
        [bool]$IsMultiTenant,
        [string]$TenantContext
    )

    Write-ColorOutput "`nCreating app registration: $DisplayName" -ForegroundColor Cyan

    # Determine sign-in audience
    $signInAudience = if ($IsMultiTenant) {
        "AzureADMultipleOrgs"
    } else {
        "AzureADMyOrg"
    }

    # Create the app registration
    $app = New-MgApplication -DisplayName $DisplayName -SignInAudience $signInAudience

    Write-ColorOutput "App created successfully!" -ForegroundColor Green
    Write-ColorOutput "  Application (client) ID: $($app.AppId)" -ForegroundColor White
    Write-ColorOutput "  Object ID: $($app.Id)" -ForegroundColor White

    return $app
}

function Add-GraphPermissions {
    param(
        [string]$AppObjectId,
        [array]$Permissions
    )

    Write-ColorOutput "`nAdding Microsoft Graph API permissions..." -ForegroundColor Cyan

    $graphServicePrincipal = Get-MgServicePrincipal -Filter "appId eq '00000003-0000-0000-c000-000000000000'"

    $requiredResourceAccess = @{
        ResourceAppId = "00000003-0000-0000-c000-000000000000"
        ResourceAccess = @()
    }

    foreach ($permission in $Permissions[0].Permissions) {
        $requiredResourceAccess.ResourceAccess += @{
            Id = $permission.Id
            Type = $permission.Type
        }
        Write-ColorOutput "  Added: $($permission.Name) ($($permission.Type))" -ForegroundColor White
    }

    Update-MgApplication -ApplicationId $AppObjectId -RequiredResourceAccess @($requiredResourceAccess)

    Write-ColorOutput "Permissions added successfully!" -ForegroundColor Green
}

function New-AppSecret {
    param(
        [string]$AppObjectId,
        [int]$ExpirationMonths
    )

    Write-ColorOutput "`nCreating client secret..." -ForegroundColor Cyan

    $endDate = (Get-Date).AddMonths($ExpirationMonths)

    $passwordCred = @{
        DisplayName = "Auto-generated by Setup-EntraSyncApp - $(Get-Date -Format 'yyyy-MM-dd')"
        EndDateTime = $endDate
    }

    $secret = Add-MgApplicationPassword -ApplicationId $AppObjectId -PasswordCredential $passwordCred

    Write-ColorOutput "Client secret created successfully!" -ForegroundColor Green
    Write-ColorOutput "  Secret ID: $($secret.KeyId)" -ForegroundColor White
    Write-ColorOutput "  Expires: $($endDate.ToString('yyyy-MM-dd'))" -ForegroundColor White
    Write-ColorOutput "`n  ⚠️  IMPORTANT: Copy the secret value now - it won't be shown again!" -ForegroundColor Yellow

    return $secret
}

function Save-Configuration {
    param(
        [hashtable]$Config,
        [string]$OutputPath,
        [bool]$Encrypt
    )

    Write-ColorOutput "`nSaving configuration..." -ForegroundColor Cyan

    $jsonConfig = $Config | ConvertTo-Json -Depth 10

    if ($Encrypt -and $IsWindows) {
        # Use DPAPI encryption on Windows
        $secureString = ConvertTo-SecureString -String $jsonConfig -AsPlainText -Force
        $encryptedData = ConvertFrom-SecureString -SecureString $secureString

        $encryptedConfig = @{
            Encrypted = $true
            Data = $encryptedData
            CreatedAt = (Get-Date).ToString('o')
            CreatedBy = $env:USERNAME
            Computer = $env:COMPUTERNAME
        } | ConvertTo-Json

        Set-Content -Path $OutputPath -Value $encryptedConfig
        Write-ColorOutput "Configuration saved (encrypted) to: $OutputPath" -ForegroundColor Green
        Write-ColorOutput "  ⚠️  This file can only be decrypted on this computer by this user." -ForegroundColor Yellow
    }
    else {
        if ($Encrypt -and -not $IsWindows) {
            Write-ColorOutput "  ⚠️  Encryption is only supported on Windows. Saving unencrypted." -ForegroundColor Yellow
        }

        # Save as plain JSON
        $configWithMetadata = $Config.Clone()
        $configWithMetadata.Add('CreatedAt', (Get-Date).ToString('o'))
        $configWithMetadata.Add('CreatedBy', $env:USER ?? $env:USERNAME)

        $configWithMetadata | ConvertTo-Json -Depth 10 | Set-Content -Path $OutputPath
        Write-ColorOutput "Configuration saved to: $OutputPath" -ForegroundColor Green
        Write-ColorOutput "  ⚠️  This file contains sensitive information. Protect it accordingly!" -ForegroundColor Yellow
    }
}

function Show-AdminConsentInstructions {
    param(
        [string]$TenantId,
        [string]$ClientId,
        [string]$TenantType
    )

    $consentUrl = "https://login.microsoftonline.com/$TenantId/adminconsent?client_id=$ClientId"

    Write-ColorOutput "`n═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
    Write-ColorOutput "ADMIN CONSENT REQUIRED - $TenantType Tenant" -ForegroundColor Yellow
    Write-ColorOutput "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
    Write-ColorOutput "`nTo grant admin consent, visit this URL:" -ForegroundColor White
    Write-ColorOutput $consentUrl -ForegroundColor Green
    Write-ColorOutput "`nOr manually grant consent in the Azure Portal:" -ForegroundColor White
    Write-ColorOutput "1. Go to Azure Portal > Azure Active Directory > App registrations" -ForegroundColor White
    Write-ColorOutput "2. Find app: $($ClientId)" -ForegroundColor White
    Write-ColorOutput "3. Go to 'API permissions'" -ForegroundColor White
    Write-ColorOutput "4. Click 'Grant admin consent for [tenant name]'" -ForegroundColor White
    Write-ColorOutput "═══════════════════════════════════════════════════════════════`n" -ForegroundColor Cyan
}

# Main execution
Write-ColorOutput @"

╔═══════════════════════════════════════════════════════════╗
║                                                           ║
║     Entra ID Delta Sync - App Registration Setup         ║
║                                                           ║
╚═══════════════════════════════════════════════════════════╝

"@ -ForegroundColor Cyan

# Check prerequisites
Test-GraphModule

# Get setup parameters
Write-ColorOutput "Setup Mode: $SetupMode" -ForegroundColor White
Write-ColorOutput "App Name: $AppName" -ForegroundColor White
Write-ColorOutput "Secret Expiration: $SecretExpirationMonths months" -ForegroundColor White

# Configuration object
$configuration = @{
    SetupMode = $SetupMode
    SetupDate = (Get-Date).ToString('o')
    SecretExpiresAt = (Get-Date).AddMonths($SecretExpirationMonths).ToString('o')
}

try {
    if ($SetupMode -eq 'MultiTenant') {
        #region Multi-Tenant Setup
        Write-ColorOutput "`n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
        Write-ColorOutput "Setting up MULTI-TENANT app registration" -ForegroundColor Cyan
        Write-ColorOutput "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan

        Write-ColorOutput "`nYou will need to authenticate to the PRIMARY tenant." -ForegroundColor Yellow
        Write-ColorOutput "This app will be used for both source and destination tenants." -ForegroundColor Yellow

        $primaryTenantId = Read-Host "`nEnter PRIMARY Tenant ID (where app will be registered)"

        # Connect to Microsoft Graph
        Write-ColorOutput "`nConnecting to Microsoft Graph..." -ForegroundColor Cyan
        Connect-MgGraph -TenantId $primaryTenantId -Scopes "Application.ReadWrite.All", "Directory.Read.All" -NoWelcome

        $context = Get-MgContext
        Write-ColorOutput "Connected to tenant: $($context.TenantId)" -ForegroundColor Green

        # Create app registration
        $app = New-AppRegistration -DisplayName $AppName -IsMultiTenant $true -TenantContext "Primary"

        # Add permissions
        Add-GraphPermissions -AppObjectId $app.Id -Permissions $requiredPermissions

        # Create secret
        $secret = New-AppSecret -AppObjectId $app.Id -ExpirationMonths $SecretExpirationMonths

        # Build configuration
        $configuration.Add('AppRegistration', @{
            Type = 'MultiTenant'
            TenantId = $context.TenantId
            ClientId = $app.AppId
            ClientSecret = $secret.SecretText
            ApplicationObjectId = $app.Id
            SecretKeyId = $secret.KeyId
        })

        Write-ColorOutput "`n✓ Multi-tenant app registration completed!" -ForegroundColor Green

        # Show admin consent instructions for both tenants
        Show-AdminConsentInstructions -TenantId $context.TenantId -ClientId $app.AppId -TenantType "PRIMARY"

        $secondaryTenantId = Read-Host "Enter SECONDARY (destination) Tenant ID for admin consent instructions"
        if (-not [string]::IsNullOrWhiteSpace($secondaryTenantId)) {
            Show-AdminConsentInstructions -TenantId $secondaryTenantId -ClientId $app.AppId -TenantType "SECONDARY"
            $configuration.AppRegistration.Add('SecondaryTenantId', $secondaryTenantId)
        }
        #endregion
    }
    else {
        #region Separate Apps Setup
        Write-ColorOutput "`n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
        Write-ColorOutput "Setting up SEPARATE app registrations" -ForegroundColor Cyan
        Write-ColorOutput "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan

        Write-ColorOutput "`nYou will need to create apps in both tenants." -ForegroundColor Yellow

        # Source Tenant App
        Write-ColorOutput "`n┌─────────────────────────────────────┐" -ForegroundColor Cyan
        Write-ColorOutput "│  SOURCE TENANT APP REGISTRATION     │" -ForegroundColor Cyan
        Write-ColorOutput "└─────────────────────────────────────┘" -ForegroundColor Cyan

        $sourceTenantId = Read-Host "Enter SOURCE Tenant ID"

        Write-ColorOutput "`nConnecting to SOURCE tenant..." -ForegroundColor Cyan
        Connect-MgGraph -TenantId $sourceTenantId -Scopes "Application.ReadWrite.All", "Directory.Read.All" -NoWelcome

        $sourceContext = Get-MgContext
        Write-ColorOutput "Connected to tenant: $($sourceContext.TenantId)" -ForegroundColor Green

        $sourceApp = New-AppRegistration -DisplayName "$AppName (Source)" -IsMultiTenant $false -TenantContext "Source"
        Add-GraphPermissions -AppObjectId $sourceApp.Id -Permissions $requiredPermissions
        $sourceSecret = New-AppSecret -AppObjectId $sourceApp.Id -ExpirationMonths $SecretExpirationMonths

        Show-AdminConsentInstructions -TenantId $sourceContext.TenantId -ClientId $sourceApp.AppId -TenantType "SOURCE"

        Write-Host "`nPress Enter when you're ready to set up the DESTINATION tenant app..."
        Read-Host

        # Disconnect from source
        Disconnect-MgGraph | Out-Null

        # Destination Tenant App
        Write-ColorOutput "`n┌─────────────────────────────────────┐" -ForegroundColor Cyan
        Write-ColorOutput "│  DESTINATION TENANT APP REGISTRATION│" -ForegroundColor Cyan
        Write-ColorOutput "└─────────────────────────────────────┘" -ForegroundColor Cyan

        $destTenantId = Read-Host "Enter DESTINATION Tenant ID"

        Write-ColorOutput "`nConnecting to DESTINATION tenant..." -ForegroundColor Cyan
        Connect-MgGraph -TenantId $destTenantId -Scopes "Application.ReadWrite.All", "Directory.Read.All" -NoWelcome

        $destContext = Get-MgContext
        Write-ColorOutput "Connected to tenant: $($destContext.TenantId)" -ForegroundColor Green

        $destApp = New-AppRegistration -DisplayName "$AppName (Destination)" -IsMultiTenant $false -TenantContext "Destination"
        Add-GraphPermissions -AppObjectId $destApp.Id -Permissions $requiredPermissions
        $destSecret = New-AppSecret -AppObjectId $destApp.Id -ExpirationMonths $SecretExpirationMonths

        Show-AdminConsentInstructions -TenantId $destContext.TenantId -ClientId $destApp.AppId -TenantType "DESTINATION"

        # Build configuration
        $configuration.Add('SourceApp', @{
            TenantId = $sourceContext.TenantId
            ClientId = $sourceApp.AppId
            ClientSecret = $sourceSecret.SecretText
            ApplicationObjectId = $sourceApp.Id
            SecretKeyId = $sourceSecret.KeyId
        })

        $configuration.Add('DestinationApp', @{
            TenantId = $destContext.TenantId
            ClientId = $destApp.AppId
            ClientSecret = $destSecret.SecretText
            ApplicationObjectId = $destApp.Id
            SecretKeyId = $destSecret.KeyId
        })

        Write-ColorOutput "`n✓ Separate app registrations completed!" -ForegroundColor Green
        #endregion
    }

    # Save configuration
    Save-Configuration -Config $configuration -OutputPath $ConfigOutputPath -Encrypt $EncryptConfig.IsPresent

    # Summary
    Write-ColorOutput "`n╔═══════════════════════════════════════════════════════════╗" -ForegroundColor Green
    Write-ColorOutput "║                 SETUP COMPLETED SUCCESSFULLY              ║" -ForegroundColor Green
    Write-ColorOutput "╚═══════════════════════════════════════════════════════════╝" -ForegroundColor Green

    Write-ColorOutput "`nNext Steps:" -ForegroundColor Cyan
    Write-ColorOutput "1. Grant admin consent using the URLs provided above" -ForegroundColor White
    Write-ColorOutput "2. Verify the configuration file: $ConfigOutputPath" -ForegroundColor White
    Write-ColorOutput "3. Run the sync script using: .\Invoke-EntraDeltaSync.ps1" -ForegroundColor White
    Write-ColorOutput "`nConfiguration has been saved. Keep this file secure!" -ForegroundColor Yellow
}
catch {
    Write-ColorOutput "`n✗ Setup failed: $_" -ForegroundColor Red
    Write-ColorOutput $_.ScriptStackTrace -ForegroundColor Red
    throw
}
finally {
    # Cleanup
    if (Get-MgContext) {
        Disconnect-MgGraph | Out-Null
    }
}
