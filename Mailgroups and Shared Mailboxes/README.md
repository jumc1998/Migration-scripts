# Mailgroup and Shared Mailbox Update Script

This PowerShell script updates distribution groups and shared mailboxes in Exchange Online using data from a CSV file. It follows the same export/apply/rollback workflow as the user management script.

## Prerequisites

1. Install the Exchange Online PowerShell module:
   ```powershell
   Install-Module ExchangeOnlineManagement -Scope CurrentUser
   ```
2. Ensure you have sufficient permissions to modify distribution groups and shared mailboxes.

## CSV File Format

The input CSV should contain the following columns:

```plaintext
ObjectType,Identity,NewDisplayName,NewPrimarySmtpAddress,NewAlias
```

- `ObjectType` must be either `Group` or `SharedMailbox`.
- `Identity` is the existing alias or email address of the group or mailbox.
- `NewDisplayName`, `NewPrimarySmtpAddress`, and `NewAlias` specify the desired updates.

## Usage

1. **Export planned changes**
   - Choose option `1` in the script menu.
   - Provide the path to the CSV file described above and a path to save the planned changes file.
   - The script will show the proposed modifications and ask for confirmation before exporting them.

2. **Apply changes**
   - Choose option `2`.
   - Specify the planned changes CSV from the previous step and a path for the rollback file.
   - Updates are applied to the groups/mailboxes and a rollback file is generated.

3. **Rollback changes**
   - Choose option `3` and supply the rollback CSV produced earlier. The script will revert the objects to their original values.

All actions are logged to `ScriptLog.txt` in the working directory.

## Example

```powershell
# Connect and start the menu
./Update-MailObjects.ps1
```

Follow the prompts to export, apply, or rollback changes as needed.
