
# User Account Update Script

This PowerShell script allows you to update user accounts in Microsoft 365 using a CSV file. It provides options to export planned changes, apply changes, and rollback changes if necessary.

## Prerequisites

1. Install the Microsoft Graph PowerShell module:
   ```powershell
   Install-Module Microsoft.Graph -Scope CurrentUser
   ```

2. Ensure you have the necessary permissions to manage user accounts in Microsoft 365.

## CSV File Format

The CSV file can contain any of the following columns. Only the values you supply will be applied:

```plaintext
UserPrincipalName,NewUserPrincipalName,Department,JobTitle,CompanyName,PrimaryEmail,Alias
```

Example rows:

```csv
UserPrincipalName,NewUserPrincipalName,Department,CompanyName
john.doe@oldcompany.com,john.doe@newcompany.com,Sales,NewCompany
jane.smith@oldcompany.com,,,NewCompany
```

## How to Use

1. **Prepare the CSV File**: The CSV may contain any subset of the supported columns. Only supplied values are updated.

2. **Run the Script**: Execute the script in PowerShell. You will be presented with a menu to select from:

   - `Export planned changes`: This option will read the CSV file, display the planned changes, and ask for confirmation. If confirmed, it will save the changes to a specified CSV file.
   - `Apply changes`: This option will read the changes from a specified CSV file and apply them to the user accounts, while also generating a rollback file.
   - `Rollback changes`: This option will read the rollback data from a specified CSV file and revert the user accounts to their original state.
   - `Exit`: Exit the script.

3. **Log File**: The script will log all activities to `ScriptLog.txt`.

4. **Rollback File**: The script will generate a rollback data file when applying changes, which can be used to undo changes if needed.

5. **Alias Updates**: If the CSV includes an `Alias` and `PrimaryEmail`, the script will attempt to add the alias using `Set-Mailbox`.

## Example

To run the script, simply open PowerShell, navigate to the directory containing the script, and execute it:

```powershell
.\UserAccountUpdateScript.ps1
```

Follow the on-screen instructions to select the desired option and proceed accordingly.
