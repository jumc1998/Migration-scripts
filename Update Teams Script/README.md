# Teams Name and Description Update Script

## Overview

This script connects to Microsoft Teams and prepares name and description changes for existing teams. It can export all planned updates to a CSV file and later apply them once approved.

## Prerequisites

- PowerShell 5.1 or later
- Microsoft Teams PowerShell module
- Permissions to modify Teams

Install the module if it is not already available:

```powershell
Install-Module MicrosoftTeams -Scope CurrentUser
```

## Usage

1. Run the script and sign in when prompted:

   ```powershell
   .\Update-Teams.ps1
   ```

2. Export proposed changes by specifying text to replace and the output CSV path:

   ```powershell
   Export-TeamChanges -oldValue "OldName" -newValue "NewName" -exportFilePath "TeamChanges.csv"
   ```

   Review `TeamChanges.csv` to verify the new names and descriptions.

3. After approval, apply the updates:

   ```powershell
   Apply-TeamChanges -importFilePath "TeamChanges.csv"
   ```

The script uses `Get-Team` to read existing teams and `Set-Team` to apply the changes.
