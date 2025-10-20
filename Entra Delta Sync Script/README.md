# Entra ID Delta Synchronisation Tool

This PowerShell script compares user attributes between two Microsoft Entra ID (Azure AD)
tenants and lets an operator merge the changes interactively. It is intended to fill the
gap when a tenant-to-tenant migration tool does not offer delta synchronisation.

## Features

- Connects to both source and destination tenants via Microsoft Graph (client
  credentials flow).
- Matches users by the local part of the user principal name (e.g.
  `john.smith@sourcetenant.com` ↔ `john.smith@destinationtenant.com`).
- Compares a configurable list of user attributes such as department, job title, and
  employee type.
- Presents differences for each matched user and offers four actions:
  - **Merge to destination** – push the source values to the destination tenant.
  - **Merge to source** – push the destination values back to the source tenant.
  - **Skip** – leave both tenants unchanged.
  - **Flag** – mark the user for follow-up without making changes.
- Exports flagged users to a CSV file that can be opened in Excel for escalation or
  additional review.

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
