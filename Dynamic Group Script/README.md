
# Dynamic Group Rule Update Script

## Overview

This PowerShell script is designed to update the membership rules of dynamic groups in Azure AD using the Microsoft Graph module. The script includes features for exporting planned changes, confirming changes with the user, applying the changes, and rolling them back if necessary.

## Prerequisites

- PowerShell 5.1 or later
- Microsoft Graph PowerShell module
- Appropriate permissions to read and write group settings in Azure AD

## Installation

1. Install the Microsoft Graph PowerShell module if you haven't already:

    ```powershell
    Install-Module Microsoft.Graph -Scope CurrentUser
    ```

2. Clone this repository to your local machine.

## Configuration

1. Open the script file and update the file paths for the log file and rollback file:

    ```powershell
    # Path to the log file
    $logFilePath = "C:\Path\To\ScriptLog.txt"

    # Path to the rollback file
    $rollbackFilePath = "C:\Path\To\RollbackData.csv"
    ```

2. Ensure you have the necessary permissions to run the script:

    - `Group.ReadWrite.All`

## Usage

### Export Planned Changes

To export planned changes to a CSV file, uncomment the following line in the script:

```powershell
Export-DynamicGroupChanges -oldValue "CPX" -newValue "Panelclaw EU" -exportFilePath "DynamicGroupChanges.csv"
```

This command will:

- Retrieve all dynamic groups with "CPX" in their membership rule.
- Prepare a list of changes by replacing "CPX" with "Panelclaw EU" in the membership rules.
- Ask for user confirmation before exporting the changes to `DynamicGroupChanges.csv`.
- Log the planned changes and save rollback data to `RollbackData.csv`.

### Apply Changes

After reviewing and approving the changes, uncomment the following line in the script:

```powershell
Apply-DynamicGroupChanges -importFilePath "DynamicGroupChanges.csv"
```

This command will:

- Read the changes from the CSV file.
- Apply the new membership rules to the respective groups.
- Log the changes.

### Rollback Changes

In case you need to rollback the changes, uncomment the following line in the script:

```powershell
Rollback-Changes
```

This command will:

- Read the rollback data from `RollbackData.csv`.
- Restore the original membership rules for the respective groups.
- Log the rollback operations.

### Disconnect from Microsoft Graph

After completing your operations, disconnect from Microsoft Graph:

```powershell
Disconnect-MgGraph
```

## Error Handling

The script includes error handling and logging for both the change application and rollback processes. All operations and errors are logged to the specified log file.

## Contributing

Please feel free to submit issues or pull requests if you have any improvements or bug fixes.

---

*Note: Ensure to update file paths and other configurations based on your environment and requirements.*
