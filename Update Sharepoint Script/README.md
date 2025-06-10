# SharePoint Site Display Name Update Script

## Overview

This PowerShell script updates the `DisplayName` property of SharePoint Online sites using the Microsoft Graph PowerShell module. It supports exporting planned changes, applying them later, and rolling back if needed. All operations are logged to `ScriptLog.txt`.

## Prerequisites

- PowerShell 5.1 or later
- Microsoft Graph PowerShell module
- Permission to manage SharePoint sites (`Sites.ReadWrite.All`)

Install the Microsoft Graph module if required:

```powershell
Install-Module Microsoft.Graph -Scope CurrentUser
```

## Usage

1. Run the script in PowerShell:

   ```powershell
   .\Update-Sharepoint.ps1
   ```

2. Choose one of the menu options:

   - **Export planned changes** – Provide the old value to replace, the new value, and a path to save the CSV. The script exports matching sites with their proposed new names.
   - **Apply changes** – Supply a CSV previously exported by the script. The script updates each site and creates `RollbackData.csv` for potential rollback.
   - **Rollback changes** – Use a CSV created by the apply step to restore the original site names.
   - **Exit** – Quit the script.

3. The script connects to Microsoft Graph when it starts and disconnects when finished.

## Notes

Update the `$logFilePath` and `$rollbackFilePath` variables in the script if you want to store the log or rollback files in a different location.
