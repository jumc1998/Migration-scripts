# Path to the log file
$logFilePath = "ScriptLog.txt"

# Path to the rollback file
$rollbackFilePath = "RollbackData.csv"

# Function to log messages
function Log-Message {
    param (
        [string]$message,
        [string]$type = "INFO"
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "$timestamp - [$type] - $message"
    Write-Host $logMessage
    Add-Content -Path $logFilePath -Value $logMessage
}

# Function to display the menu and get user confirmation
function Confirm-Changes {
    param (
        [array]$changes
    )

    Write-Host "The following changes will be made:" -ForegroundColor Yellow
    foreach ($change in $changes) {
        Write-Host $change
    }

    $confirmation = Read-Host "Did you get a response and want to export this to CSV? (yes/no)"
    return $confirmation -eq 'yes'
}

# Function to rollback changes
function Rollback-Changes {
        param (
            [Parameter(Mandatory=$true)][string]$rollbackFilePath
        )
    $confirmation = Read-Host "Are you sure you want to rollback changes? This action cannot be undone. (yes/no)"
    if ($confirmation -ne 'yes') {
        Write-Host "Rollback cancelled." -ForegroundColor Red
        return
    }



        if (-not (Test-Path -Path $rollbackFilePath)) {
            Write-Host "File not found." -ForegroundColor Red
            return
        }

        $rollbackData = Import-Csv -Path $rollbackFilePath

        foreach ($group in $rollbackData) {
            try {
                Update-MgGroup -GroupId $group.GroupId -MembershipRule $group.OldRule
                Log-Message "Rolled back changes for group $($group.DisplayName)"
            } catch {
                Log-Message "Error rolling back changes for group $($group.DisplayName): $_" "ERROR"
            }
        }
}

# Export planned changes to CSV
function Export-DynamicGroupChanges {
    param (
        [string]$oldValue,
        [string]$newValue,
        [string]$exportFilePath,
        [switch]$AppendNewValue
    )

    # Get all dynamic groups
    $groups = Get-MgGroup -Filter "groupTypes/any(c:c eq 'DynamicMembership')" -All | Select Id,DisplayName,Description,CreatedDateTime,MembershipRule
    $exportData = @()
    $rollbackData = @()
    $changes = @()

    foreach ($group in $groups) {
        $oldRule = $group.MembershipRule
        if ($AppendNewValue) {
            $newRule = $oldRule -replace [regex]::Escape($oldValue), "$oldValue`", `"$newValue"
        } else {
            $newRule = $oldRule -replace [regex]::Escape($oldValue), $newValue
        }

        if ($oldRule -ne $newRule) {
            $exportData += [PSCustomObject]@{
                GroupId     = $group.Id
                DisplayName = $group.DisplayName
                OldRule     = $oldRule
                NewRule     = $newRule
            }
            $changes += "Update membership rule for group $($group.DisplayName) from '$oldRule' to '$newRule'"
        }
    }

    if (Confirm-Changes -changes $changes) {
        $exportData | Export-Csv -Path $exportFilePath -NoTypeInformation
        Write-Host "Exported dynamic group changes to $exportFilePath"
        Log-Message "Exported dynamic group changes to $exportFilePath"
    } else {
        Write-Host "Operation cancelled." -ForegroundColor Red
    }
}

# Apply changes from CSV
function Apply-DynamicGroupChanges {
    param (
        [string]$importFilePath
    )

    if (-not (Test-Path -Path $importFilePath)) {
        Write-Host "Import file not found." -ForegroundColor Red
        return
    }

    $importData = Import-Csv -Path $importFilePath

    foreach ($item in $importData) {
        try {
            Update-MgGroup -GroupId $item.GroupId -MembershipRule $item.NewRule
            Log-Message "Updated dynamic group rule for group $($item.DisplayName)"
        } catch {
            Log-Message "Error updating dynamic group rule for group $($item.DisplayName): $_" "ERROR"
        }
    }
}

# Display menu and execute selected option
function Display-Menu {
    Write-Host "Select an option:" -ForegroundColor Green
    Write-Host "1. Export planned changes"
    Write-Host "2. Apply changes"
    Write-Host "3. Rollback changes"
    Write-Host "4. Exit"

    $selection = Read-Host "Enter your choice (1/2/3/4)"

    switch ($selection) {
        1 {
            $oldValue = Read-Host "Enter the old value to replace"
            $newValue = Read-Host "Enter the new value"
            $exportFilePath = Read-Host "Enter the path to export the CSV file"
            $appendNewValue = Read-Host "Do you want to append the new value after the old value? (yes/no)"
            $shouldAppend = $appendNewValue -eq 'yes'
            Export-DynamicGroupChanges -oldValue $oldValue -newValue $newValue -exportFilePath $exportFilePath -AppendNewValue:$shouldAppend
        }
        2 {
            $importFilePath = Read-Host "Enter the path to the CSV file with changes"
            Apply-DynamicGroupChanges -importFilePath $importFilePath
        }
        3 {
            $rollbackFilePath = Read-Host "Enter the path to the CSV file with changes you want to rollback"
            Rollback-Changes -rollbackFilePath $rollbackFilePath
        }
        4 {
            Write-Host "Exiting..." -ForegroundColor Red
            return
        }
        default {
            Write-Host "Invalid selection. Please try again." -ForegroundColor Yellow
            Display-Menu
        }
    }
}

# Main script execution
try {
    # Connect to Microsoft Graph
    Connect-MgGraph -Scopes "Group.ReadWrite.All"
    Display-Menu
} finally {
    # Disconnect from Microsoft Graph
    Disconnect-MgGraph
}