# Migration Scripts

This repository contains a collection of PowerShell scripts for migrating and updating various Microsoft 365 components.

## General structure

```
Migration-scripts/
│
├─ Dynamic Group Script/
│   ├─ README.md
│   └─ Update-Dyanmic-group.ps1
├─ Endpoint/
│   ├─ Endpoint_update.ps1
│   └─ Execute.cmd
├─ Mailgroups and Shared Mailboxes/
│   ├─ README.md
│   └─ Update-MailObjects.ps1
├─ Update Sharepoint Script/
│   └─ Update-Sharepoint.ps1
├─ Update Teams Script/
│   └─ Update-Teams.ps1
└─ User Management Script/
    ├─ README.md
    ├─ update.ps1
    └─ CombinedUserData.csv
```

The root `README.md` provides an overview, while each subdirectory contains its own README and PowerShell script with detailed usage information.

## Important features

- **Dynamic Group Script**
  - Updates Azure AD dynamic group rules with logging and rollback support.
  - Provides export/apply/rollback menu options.
  - Requires Microsoft Graph permissions. The README outlines prerequisites and usage details.

- **Endpoint**
  - Windows endpoint script to adjust Outlook/OneDrive settings and notify the user before shutting down the device.
  - Handles registry updates and displays messages to users.

- **Update SharePoint Script**
  - Uses Microsoft Graph to update site display names with an export/apply/rollback workflow.
  - Interactive menu with options similar to the dynamic group script.

- **Update Teams Script**
  - Connects to Microsoft Teams, exports planned team name/description changes, and can later apply those changes from a CSV file.

- **Mailgroups and Shared Mailboxes**
  - Updates distribution groups and shared mailboxes using Exchange Online.
  - Offers export, apply, and rollback options similar to the user management script.

- **User Management Script**
  - Reads user details from a CSV, prepares or applies updates via Microsoft Graph, and can roll back changes.
  - The accompanying README explains the optional CSV columns and how the script only updates values you supply.

## Pointers for learning more

1. **PowerShell basics** – Each script uses functions, parameters, and standard I/O operations. Familiarity with PowerShell scripting is key.
2. **Microsoft Graph and Microsoft Teams modules** – Scripts rely on these modules to interact with Azure AD, SharePoint, Teams, and user accounts.
3. **CSV-driven workflows** – Several scripts export planned changes to CSV, then allow you to review and apply them later, providing rollback support.
4. **Automation and permissions** – Ensure you have the necessary permissions (e.g., `Group.ReadWrite.All`, `Sites.ReadWrite.All`, `User.ReadWrite.All`) when running these scripts.

To get started, read the README in each directory for setup details and examine the script files for usage patterns and customization points. Once comfortable with these, you can extend or combine the scripts for broader migration tasks within Microsoft 365.

