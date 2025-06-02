
# User Account Update Script

This PowerShell script allows you to update user accounts in Microsoft 365 using a CSV file. It provides options to export planned changes, apply changes, and rollback changes if necessary.

## Prerequisites

1. Install the Microsoft Graph PowerShell module:
   ```powershell
   Install-Module Microsoft.Graph -Scope CurrentUser
   ```

2. Ensure you have the necessary permissions to manage user accounts in Microsoft 365.

## CSV File Format

The CSV file used for this script should have the following columns:

```plaintext
UserPrincipalName,NewUserPrincipalName,Department,JobTitle,CompanyName,PrimaryEmail,Alias
```

Here is an example of how the CSV file might look:

```csv
UserPrincipalName,NewUserPrincipalName,Department,JobTitle,CompanyName,PrimaryEmail,Alias
john.doe@oldcompany.com,john.doe@newcompany.com,Sales,Sales Manager,NewCompany,john.doe@newcompany.com,john.d.alias@newcompany.com
jane.smith@oldcompany.com,jane.smith@newcompany.com,HR,HR Director,NewCompany,jane.smith@newcompany.com,jane.s.alias@newcompany.com
```

## How to Use

1. **Prepare the CSV File**: Ensure your CSV file follows the format mentioned above.

2. **Run the Script**: Execute the script in PowerShell. You will be presented with a menu to select from:

   - `Export planned changes`: This option will read the CSV file, display the planned changes, and ask for confirmation. If confirmed, it will save the changes to a specified CSV file.
   - `Apply changes`: This option will read the changes from a specified CSV file and apply them to the user accounts, while also generating a rollback file.
   - `Rollback changes`: This option will read the rollback data from a specified CSV file and revert the user accounts to their original state.
   - `Exit`: Exit the script.

3. **Log File**: The script will log all activities to `ScriptLog.txt`.

4. **Rollback File**: The script will generate a rollback data file when applying changes, which can be used to undo changes if needed.

## Example

To run the script, simply open PowerShell, navigate to the directory containing the script, and execute it:

```powershell
.\UserAccountUpdateScript.ps1
```

Follow the on-screen instructions to select the desired option and proceed accordingly.
