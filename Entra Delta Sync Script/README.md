# Entra ID Delta Synchronisation Tool

This PowerShell script compares user attributes between two Microsoft Entra ID (Azure AD)
tenants and lets an operator merge the changes interactively. It is intended to fill the
gap when a tenant-to-tenant migration tool does not offer delta synchronisation.

## Features

- **Multi-tenant Authentication**: Connects to both source and destination tenants via Microsoft Graph (client credentials flow) with automatic token refresh for long-running sessions.
- **User Matching**: Matches users by the local part of the user principal name (e.g. `john.smith@sourcetenant.com` ↔ `john.smith@destinationtenant.com`).
- **Attribute Comparison**: Compares a configurable list of user attributes such as department, job title, and employee type.
- **Interactive Actions**: Presents differences for each matched user and offers four actions:
  - **Merge to destination** – push the source values to the destination tenant.
  - **Merge to source** – push the destination values back to the source tenant.
  - **Skip** – leave both tenants unchanged.
  - **Flag** – mark the user for follow-up without making changes.
- **CSV Export**: Exports flagged users to a CSV file that can be opened in Excel for escalation or additional review.
- **Progress Tracking**: Displays real-time progress indicators when processing large numbers of users.
- **Detailed Logging**: Optional file-based logging with timestamps and severity levels for audit trails.
- **Resume Capability**: Checkpoint-based resumption allows you to continue from where you left off if the script is interrupted.
- **Cross-Platform Support**: Compatible with both Windows PowerShell 5.1 and PowerShell 7+ (Linux/macOS).
- **Input Validation**: Validates tenant IDs, client IDs, and domains to prevent configuration errors.
- **Error Handling**: Comprehensive error handling with detailed error messages and error counts in the summary.

## Prerequisites

1. Register a multi-tenant application in Microsoft Entra ID that has the following
   Microsoft Graph **application** permissions (or broader as required by your
   environment):
   - `User.Read.All`
   - `User.ReadWrite.All`
2. Grant admin consent for the permissions in both the source and destination tenants.
3. Record the **Directory (tenant) IDs** for the source and destination tenants as well
   as the application **Client ID** and **Client Secret**.
4. Run the script with PowerShell 7+ (`pwsh`) or Windows PowerShell 5.1.

## Usage

The script is located at `entra_id_delta_sync.ps1`. It accepts tenant details, the
application ID, and the source/destination user domains as parameters. If the client
secret is not supplied as a parameter you will be prompted to enter it securely.

```powershell
pwsh .\entra_id_delta_sync.ps1 \`
    -SourceTenantId <source-tenant-id> \`
    -DestinationTenantId <destination-tenant-id> \`
    -ClientId <application-id> \`
    -SourceUserDomain "sourcetenant.com" \`
    -DestinationUserDomain "destinationtenant.com"
```

### Optional parameters

- `-AttributesToCompare` – Provide a custom list of user attributes to compare.
  Defaults to `displayName`, `mail`, `department`, `jobTitle`, `employeeType`,
  `mobilePhone`, and `officeLocation`.
- `-GraphBaseUri` – Override the Microsoft Graph endpoint (defaults to
  `https://graph.microsoft.com/v1.0`).
- `-LogFilePath` – Path to a log file for detailed operation logging. If specified,
  all operations will be logged with timestamps and severity levels.
  Example: `-LogFilePath "C:\Logs\sync-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"`
- `-CheckpointFilePath` – Path to a checkpoint file for resume capability. If the
  script is interrupted, it can resume from the last checkpoint.
  Example: `-CheckpointFilePath "C:\Temp\sync-checkpoint.json"`

## Workflow

During execution the script:

1. Authenticates to Microsoft Graph for both tenants with the provided application
   credentials.
2. Retrieves all users from each tenant (limited to the requested attributes).
3. Matches users by the local part of the user principal name and compares the selected
   attributes.
4. Displays the differences for each matched user and prompts you to choose an action:
   merge towards the destination, merge towards the source, skip, or flag the user.
5. Executes the chosen action immediately via Microsoft Graph and records flagged users.
6. At the end of the run, summarises the results and optionally exports flagged users to
   a CSV file that can be opened in Excel.

> **Tip:** Test the script with a small user subset first to verify that the permissions
> are correct and that the attribute list covers the fields relevant to your migration.

## Advanced Usage Examples

### With logging and checkpoint support

```powershell
pwsh .\entra_id_delta_sync.ps1 `
    -SourceTenantId <source-tenant-id> `
    -DestinationTenantId <destination-tenant-id> `
    -ClientId <application-id> `
    -SourceUserDomain "sourcetenant.com" `
    -DestinationUserDomain "destinationtenant.com" `
    -LogFilePath "C:\Logs\entra-sync-$(Get-Date -Format 'yyyyMMdd-HHmmss').log" `
    -CheckpointFilePath "C:\Temp\entra-sync-checkpoint.json" `
    -Verbose
```

### With custom attributes

```powershell
pwsh .\entra_id_delta_sync.ps1 `
    -SourceTenantId <source-tenant-id> `
    -DestinationTenantId <destination-tenant-id> `
    -ClientId <application-id> `
    -SourceUserDomain "sourcetenant.com" `
    -DestinationUserDomain "destinationtenant.com" `
    -AttributesToCompare @('displayName', 'mail', 'department', 'jobTitle', 'manager', 'employeeId')
```

## Improvements in Latest Version

### Version 2.0 Enhancements

1. **Cross-Platform Compatibility**: Fixed SecureString handling for PowerShell 7+ on Linux/macOS
2. **Input Validation**: Added GUID validation for tenant IDs and client ID
3. **Token Management**: Automatic token refresh for sessions longer than 1 hour
4. **Progress Tracking**: Real-time progress bar showing percentage completion
5. **Logging System**: Optional file-based logging with structured output
6. **Resume Capability**: Checkpoint system allows resuming interrupted sessions
7. **Error Tracking**: Comprehensive error counting and reporting
8. **Enhanced Summary**: Detailed statistics including users with differences, errors, and processing counts

## Best Practices

1. **Start Small**: Run the script with a test group of users first to validate the configuration
2. **Use Logging**: Always enable logging for production migrations using `-LogFilePath`
3. **Enable Checkpoints**: For large migrations (>100 users), use `-CheckpointFilePath` to enable resume capability
4. **Monitor Token Expiry**: The script automatically refreshes tokens, but be aware sessions with very large tenants may take several hours
5. **Backup Strategy**: Consider exporting user data before making bulk changes
6. **Permissions Review**: Ensure the service principal has only the minimum required permissions
7. **Test Connectivity**: Verify network connectivity and firewall rules before starting large migrations
8. **Review Flagged Users**: Always review flagged users before making manual changes

## Troubleshooting

### Common Issues

**Issue**: "SourceTenantId is not a valid GUID"
- **Solution**: Ensure tenant IDs are in GUID format (e.g., `12345678-1234-1234-1234-123456789abc`)

**Issue**: "Failed to acquire Microsoft Graph token"
- **Solution**: Verify the client secret is correct and the app registration has been granted admin consent in both tenants

**Issue**: Script hangs during user processing
- **Solution**: Use Ctrl+C to interrupt, then restart with `-CheckpointFilePath` to resume from where it stopped

**Issue**: "No destination match for user@domain.com"
- **Solution**: Verify the user exists in the destination tenant with the correct UPN format

**Issue**: Token expiration errors in long sessions
- **Solution**: The script now automatically refreshes tokens. If you see this error, it may indicate network connectivity issues

## Security Considerations

- Client secrets are handled securely using `SecureString` and are never logged
- Use Azure Key Vault or secure credential management for storing client secrets
- Regularly rotate client secrets according to your security policy
- Review Graph API permissions regularly and apply principle of least privilege
- Enable audit logging in both tenants to track all changes
- Consider using Conditional Access policies to restrict where the script can be run from

## Support and Feedback

For issues, questions, or feature requests, please refer to the main repository documentation or contact your IT administrator.
