# Entra Delta Sync - Automated Setup Guide

This guide walks you through the automated setup process for the Entra ID Delta Sync tool.

## Overview

The automated setup includes three main scripts:

1. **Setup-EntraSyncApp.ps1** - Creates and configures app registrations
2. **Invoke-EntraDeltaSync.ps1** - Runs the sync using saved configuration
3. **Get-EntraSyncConfig.ps1** - Views and manages saved configurations

## Quick Start

### Step 1: Install Prerequisites

```powershell
# Install Microsoft Graph PowerShell modules
Install-Module Microsoft.Graph -Scope CurrentUser -Force
```

### Step 2: Run the Setup Script

Choose between two setup modes:

#### Option A: Multi-Tenant App (Recommended)

Single app registration used for both tenants:

```powershell
.\Setup-EntraSyncApp.ps1 -SetupMode MultiTenant
```

**Advantages:**
- Single app to manage
- One client secret to track
- Simpler configuration

**Requirements:**
- Admin access to both tenants
- App must be multi-tenant capable

#### Option B: Separate Apps

Different app registration in each tenant:

```powershell
.\Setup-EntraSyncApp.ps1 -SetupMode SeparateApps
```

**Advantages:**
- Each tenant maintains full control
- Better for strict compliance requirements
- Tenant isolation

**Requirements:**
- Admin access to both tenants
- Two separate app registrations to manage

### Step 3: Grant Admin Consent

After the setup script completes, you'll receive URLs to grant admin consent:

1. Click the provided URL or paste it into your browser
2. Sign in with a Global Administrator account
3. Review the requested permissions
4. Click "Accept" to grant consent

**Required Permissions:**
- `User.Read.All` - Read all users' profiles
- `User.ReadWrite.All` - Read and write all users' profiles

### Step 4: Run the Sync

```powershell
.\Invoke-EntraDeltaSync.ps1 `
    -SourceUserDomain "sourcetenant.com" `
    -DestinationUserDomain "destinationtenant.com" `
    -LogFilePath "./sync-$(Get-Date -Format 'yyyyMMdd-HHmmss').log" `
    -CheckpointFilePath "./checkpoint.json"
```

## Setup Script Options

### Setup-EntraSyncApp.ps1 Parameters

| Parameter | Description | Default | Required |
|-----------|-------------|---------|----------|
| `SetupMode` | 'MultiTenant' or 'SeparateApps' | MultiTenant | No |
| `AppName` | Display name for the app(s) | Entra Delta Sync Tool | No |
| `SecretExpirationMonths` | How long secret is valid (1-24) | 12 | No |
| `ConfigOutputPath` | Where to save configuration | ./entra-sync-config.json | No |
| `EncryptConfig` | Encrypt config file (Windows only) | False | No |

### Examples

**Create app with custom name and 6-month secret:**
```powershell
.\Setup-EntraSyncApp.ps1 `
    -SetupMode MultiTenant `
    -AppName "My Company Migration Tool" `
    -SecretExpirationMonths 6
```

**Create encrypted configuration (Windows only):**
```powershell
.\Setup-EntraSyncApp.ps1 `
    -SetupMode MultiTenant `
    -EncryptConfig
```

**Save configuration to custom location:**
```powershell
.\Setup-EntraSyncApp.ps1 `
    -SetupMode SeparateApps `
    -ConfigOutputPath "C:\SecureConfigs\entra-sync.json"
```

## Configuration Management

### View Your Configuration

```powershell
# View configuration (secrets hidden)
.\Get-EntraSyncConfig.ps1

# View with secrets visible (use caution!)
.\Get-EntraSyncConfig.ps1 -ShowSecrets

# Check only expiration status
.\Get-EntraSyncConfig.ps1 -CheckExpiration
```

### Configuration File Structure

#### Multi-Tenant Configuration
```json
{
  "SetupMode": "MultiTenant",
  "SetupDate": "2024-01-15T10:30:00Z",
  "SecretExpiresAt": "2025-01-15T10:30:00Z",
  "AppRegistration": {
    "Type": "MultiTenant",
    "TenantId": "primary-tenant-guid",
    "ClientId": "app-client-guid",
    "ClientSecret": "secret-value",
    "ApplicationObjectId": "object-guid",
    "SecretKeyId": "key-guid",
    "SecondaryTenantId": "secondary-tenant-guid"
  }
}
```

#### Separate Apps Configuration
```json
{
  "SetupMode": "SeparateApps",
  "SetupDate": "2024-01-15T10:30:00Z",
  "SecretExpiresAt": "2025-01-15T10:30:00Z",
  "SourceApp": {
    "TenantId": "source-tenant-guid",
    "ClientId": "source-app-guid",
    "ClientSecret": "source-secret",
    "ApplicationObjectId": "source-object-guid",
    "SecretKeyId": "source-key-guid"
  },
  "DestinationApp": {
    "TenantId": "dest-tenant-guid",
    "ClientId": "dest-app-guid",
    "ClientSecret": "dest-secret",
    "ApplicationObjectId": "dest-object-guid",
    "SecretKeyId": "dest-key-guid"
  }
}
```

## Running Syncs

### Basic Sync
```powershell
.\Invoke-EntraDeltaSync.ps1 `
    -SourceUserDomain "source.com" `
    -DestinationUserDomain "destination.com"
```

### Sync with Logging
```powershell
.\Invoke-EntraDeltaSync.ps1 `
    -SourceUserDomain "source.com" `
    -DestinationUserDomain "destination.com" `
    -LogFilePath "./logs/sync-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"
```

### Sync with Checkpoints (Resume Capability)
```powershell
.\Invoke-EntraDeltaSync.ps1 `
    -SourceUserDomain "source.com" `
    -DestinationUserDomain "destination.com" `
    -CheckpointFilePath "./checkpoint.json"
```

### Sync with Custom Attributes
```powershell
.\Invoke-EntraDeltaSync.ps1 `
    -SourceUserDomain "source.com" `
    -DestinationUserDomain "destination.com" `
    -AttributesToCompare @('displayName', 'mail', 'department', 'jobTitle', 'manager')
```

### Full Featured Sync
```powershell
.\Invoke-EntraDeltaSync.ps1 `
    -ConfigPath "./entra-sync-config.json" `
    -SourceUserDomain "source.com" `
    -DestinationUserDomain "destination.com" `
    -AttributesToCompare @('displayName', 'mail', 'department', 'jobTitle') `
    -LogFilePath "./logs/sync-$(Get-Date -Format 'yyyyMMdd-HHmmss').log" `
    -CheckpointFilePath "./checkpoints/sync-checkpoint.json"
```

## Security Best Practices

### Configuration File Security

1. **Protect Configuration Files**
   ```powershell
   # Windows: Use encryption
   .\Setup-EntraSyncApp.ps1 -EncryptConfig

   # Linux/Mac: Set restrictive permissions
   chmod 600 entra-sync-config.json
   ```

2. **Store in Secure Locations**
   - Windows: Use folders with NTFS permissions
   - Linux/Mac: Use home directory with 600 permissions
   - Consider using Azure Key Vault for production

3. **Use Environment-Specific Configs**
   ```powershell
   # Development
   .\Setup-EntraSyncApp.ps1 -ConfigOutputPath "./configs/dev-config.json"

   # Production
   .\Setup-EntraSyncApp.ps1 -ConfigOutputPath "./configs/prod-config.json"
   ```

### Secret Rotation

Monitor secret expiration and rotate regularly:

```powershell
# Check expiration
.\Get-EntraSyncConfig.ps1 -CheckExpiration

# If expiring soon, run setup again
.\Setup-EntraSyncApp.ps1 -SetupMode MultiTenant
```

Set up automated reminders:

```powershell
# Windows Task Scheduler: Create task to run monthly
$action = New-ScheduledTaskAction -Execute 'pwsh' `
    -Argument '-File "C:\Scripts\Get-EntraSyncConfig.ps1" -CheckExpiration'

$trigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Monday -At 9am

Register-ScheduledTask -TaskName "Check Entra Sync Secret" `
    -Action $action -Trigger $trigger
```

## Troubleshooting

### "Required modules not installed"

**Solution:**
```powershell
Install-Module Microsoft.Graph -Scope CurrentUser -Force
Import-Module Microsoft.Graph.Authentication
Import-Module Microsoft.Graph.Applications
```

### "Failed to acquire Microsoft Graph token"

**Possible causes:**
- Incorrect tenant ID
- User doesn't have permissions
- Network connectivity issues

**Solution:**
```powershell
# Test connection manually
Connect-MgGraph -TenantId "your-tenant-id" -Scopes "Application.ReadWrite.All"
Get-MgContext  # Should show connection details
```

### "Admin consent required"

The setup script provides consent URLs. Make sure to:
1. Use a Global Administrator account
2. Grant consent for BOTH tenants (multi-tenant mode)
3. Wait a few minutes for changes to propagate

### "Configuration file not found"

**Solution:**
```powershell
# Check current directory
Get-ChildItem *.json

# Specify full path
.\Invoke-EntraDeltaSync.ps1 -ConfigPath "C:\Full\Path\To\config.json"
```

### "Failed to decrypt configuration"

Encrypted configs can only be decrypted:
- On the same computer where they were created
- By the same user who created them
- On Windows (encryption not supported on Linux/Mac)

**Solution:**
- Recreate config without encryption
- Use the original computer/user
- Copy unencrypted version for other machines

### "Token expiration errors"

The sync script automatically refreshes tokens, but if you see errors:

```powershell
# Check current secret status
.\Get-EntraSyncConfig.ps1 -CheckExpiration

# If expired, create new secret
.\Setup-EntraSyncApp.ps1
```

## Advanced Scenarios

### Using Azure Key Vault

For production environments, store secrets in Azure Key Vault:

```powershell
# After running Setup-EntraSyncApp.ps1, extract and store in Key Vault
$config = Get-Content ./entra-sync-config.json | ConvertFrom-Json

# Store in Key Vault
Set-AzKeyVaultSecret -VaultName "MyVault" `
    -Name "EntraSyncClientSecret" `
    -SecretValue (ConvertTo-SecureString $config.AppRegistration.ClientSecret -AsPlainText -Force)

# Retrieve in sync script
$secret = Get-AzKeyVaultSecret -VaultName "MyVault" -Name "EntraSyncClientSecret" -AsPlainText
```

### Automated Syncs with Task Scheduler

```powershell
# Create scheduled task for weekly sync
$action = New-ScheduledTaskAction -Execute 'pwsh' -Argument @"
-File "C:\Scripts\Invoke-EntraDeltaSync.ps1" `
-SourceUserDomain "source.com" `
-DestinationUserDomain "dest.com" `
-LogFilePath "C:\Logs\sync-$(Get-Date -Format 'yyyyMMdd').log"
"@

$trigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Friday -At 6pm

Register-ScheduledTask -TaskName "Weekly Entra Sync" `
    -Action $action -Trigger $trigger -User "SYSTEM"
```

### Multi-Environment Setup

```powershell
# Development environment
.\Setup-EntraSyncApp.ps1 `
    -AppName "Entra Sync DEV" `
    -ConfigOutputPath "./configs/dev-config.json" `
    -SecretExpirationMonths 6

# Production environment
.\Setup-EntraSyncApp.ps1 `
    -AppName "Entra Sync PROD" `
    -ConfigOutputPath "./configs/prod-config.json" `
    -SecretExpirationMonths 12 `
    -EncryptConfig

# Run dev sync
.\Invoke-EntraDeltaSync.ps1 -ConfigPath "./configs/dev-config.json" -SourceUserDomain "dev.com" -DestinationUserDomain "dev-dest.com"

# Run prod sync
.\Invoke-EntraDeltaSync.ps1 -ConfigPath "./configs/prod-config.json" -SourceUserDomain "prod.com" -DestinationUserDomain "prod-dest.com"
```

## Support

For issues with:
- **Setup scripts**: Check this guide first, then open an issue
- **Sync process**: See main README.md
- **Permissions**: Review Azure AD documentation on app registrations
- **Graph API**: See Microsoft Graph documentation

## Appendix: Manual Setup (Alternative)

If you prefer manual setup or the automated script doesn't work:

1. **Azure Portal** → **Azure Active Directory** → **App registrations** → **New registration**
2. Enter name: "Entra Delta Sync Tool"
3. Select account type: "Accounts in any organizational directory (Multi-tenant)"
4. Register the application
5. Note the **Application (client) ID** and **Directory (tenant) ID**
6. Go to **Certificates & secrets** → **New client secret**
7. Create secret and copy the value immediately
8. Go to **API permissions** → **Add a permission** → **Microsoft Graph** → **Application permissions**
9. Add: `User.Read.All` and `User.ReadWrite.All`
10. Click **Grant admin consent**
11. Manually create the configuration JSON file with the values

This manual process is what the automated script does for you!
