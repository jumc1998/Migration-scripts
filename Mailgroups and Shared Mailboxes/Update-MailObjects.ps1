# Path to the log file
$logFilePath = "ScriptLog.txt"

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

# Function to display planned changes and get confirmation
function Confirm-Changes {
    param (
        [array]$changes
    )
    Write-Host "The following changes will be made:" -ForegroundColor Yellow
    foreach ($change in $changes) {
        Write-Host $change
    }
    $confirmation = Read-Host "Do you want to proceed with these changes? (yes/no)"
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
        Write-Host "Rollback file not found." -ForegroundColor Red
        return
    }

    $rollbackData = Import-Csv -Path $rollbackFilePath

    foreach ($item in $rollbackData) {
        try {
            if ($item.ObjectType -eq 'Group') {
                Set-DistributionGroup -Identity $item.Identity -DisplayName $item.DisplayName -PrimarySmtpAddress $item.PrimarySmtpAddress -Alias $item.Alias
            } else {
                Set-Mailbox -Identity $item.Identity -DisplayName $item.DisplayName -PrimarySmtpAddress $item.PrimarySmtpAddress -Alias $item.Alias
            }
            Log-Message "Rolled back changes for $($item.Identity)"
        } catch {
            Log-Message "Error rolling back changes for $($item.Identity): $_" "ERROR"
        }
    }
}

# Export planned changes to CSV
function Export-MailObjectChanges {
    param (
        [string]$csvFilePath,
        [string]$plannedChangesFilePath
    )

    if (-not (Test-Path -Path $csvFilePath)) {
        Write-Host "CSV file not found." -ForegroundColor Red
        return
    }

    $data = Import-Csv -Path $csvFilePath
    $plannedChanges = @()
    $changes = @()

    foreach ($item in $data) {
        if ($item.ObjectType -eq 'Group') {
            $obj = Get-DistributionGroup -Identity $item.Identity -ErrorAction SilentlyContinue
        } else {
            $obj = Get-Mailbox -Identity $item.Identity -ErrorAction SilentlyContinue
        }
        if ($null -ne $obj) {
            $plannedChanges += [PSCustomObject]@{
                ObjectType            = $item.ObjectType
                Identity              = $item.Identity
                DisplayName           = $obj.DisplayName
                PrimarySmtpAddress    = $obj.PrimarySmtpAddress
                Alias                 = $obj.Alias
                NewDisplayName        = $item.NewDisplayName
                NewPrimarySmtpAddress = $item.NewPrimarySmtpAddress
                NewAlias              = $item.NewAlias
            }
            if ($obj.DisplayName -ne $item.NewDisplayName) {
                $changes += "Update display name for $($item.Identity) to $($item.NewDisplayName)"
            }
            if ($obj.PrimarySmtpAddress -ne $item.NewPrimarySmtpAddress) {
                $changes += "Update primary address for $($item.Identity) to $($item.NewPrimarySmtpAddress)"
            }
            if ($obj.Alias -ne $item.NewAlias) {
                $changes += "Update alias for $($item.Identity) to $($item.NewAlias)"
            }
        } else {
            Log-Message "$($item.Identity) not found" "ERROR"
        }
    }

    if (Confirm-Changes -changes $changes) {
        $plannedChanges | Export-Csv -Path $plannedChangesFilePath -NoTypeInformation
        Write-Host "Planned changes exported to $plannedChangesFilePath"
        Log-Message "Planned changes exported to $plannedChangesFilePath"
    } else {
        Write-Host "Operation cancelled." -ForegroundColor Red
    }
}

# Apply changes from CSV
function Apply-MailObjectChanges {
    param (
        [Parameter(Mandatory=$true)][string]$plannedChangesFilePath,
        [Parameter(Mandatory=$true)][string]$rollbackFilePath
    )

    if (-not (Test-Path -Path $plannedChangesFilePath)) {
        Write-Host "CSV file not found." -ForegroundColor Red
        return
    }

    $data = Import-Csv -Path $plannedChangesFilePath
    $rollbackData = @()

    foreach ($item in $data) {
        if ($item.ObjectType -eq 'Group') {
            $obj = Get-DistributionGroup -Identity $item.Identity -ErrorAction SilentlyContinue
            if ($null -ne $obj) {
                $rollbackData += [PSCustomObject]@{
                    ObjectType         = 'Group'
                    Identity           = $item.Identity
                    DisplayName        = $obj.DisplayName
                    PrimarySmtpAddress = $obj.PrimarySmtpAddress
                    Alias              = $obj.Alias
                }
                try {
                    Set-DistributionGroup -Identity $item.Identity -DisplayName $item.NewDisplayName -PrimarySmtpAddress $item.NewPrimarySmtpAddress -Alias $item.NewAlias
                    Log-Message "Updated group $($item.Identity)"
                } catch {
                    Log-Message "Error updating group $($item.Identity): $_" "ERROR"
                }
            } else {
                Log-Message "Group $($item.Identity) not found" "ERROR"
            }
        } else {
            $obj = Get-Mailbox -Identity $item.Identity -ErrorAction SilentlyContinue
            if ($null -ne $obj) {
                $rollbackData += [PSCustomObject]@{
                    ObjectType         = 'SharedMailbox'
                    Identity           = $item.Identity
                    DisplayName        = $obj.DisplayName
                    PrimarySmtpAddress = $obj.PrimarySmtpAddress
                    Alias              = $obj.Alias
                }
                try {
                    Set-Mailbox -Identity $item.Identity -DisplayName $item.NewDisplayName -PrimarySmtpAddress $item.NewPrimarySmtpAddress -Alias $item.NewAlias
                    Log-Message "Updated mailbox $($item.Identity)"
                } catch {
                    Log-Message "Error updating mailbox $($item.Identity): $_" "ERROR"
                }
            } else {
                Log-Message "Mailbox $($item.Identity) not found" "ERROR"
            }
        }
    }

    $rollbackData | Export-Csv -Path $rollbackFilePath -NoTypeInformation
    Write-Host "Rollback data exported to $rollbackFilePath"
    Log-Message "Rollback data exported to $rollbackFilePath"
}

# Display menu
function Display-Menu {
    Write-Host "Select an option:" -ForegroundColor Green
    Write-Host "1. Export planned changes"
    Write-Host "2. Apply changes"
    Write-Host "3. Rollback changes"
    Write-Host "4. Exit"

    $selection = Read-Host "Enter your choice (1/2/3/4)"

    switch ($selection) {
        1 {
            $csvFilePath = Read-Host "Enter the path to the CSV file with objects"
            $plannedChangesFilePath = Read-Host "Enter the path to save the planned changes CSV file"
            Export-MailObjectChanges -csvFilePath $csvFilePath -plannedChangesFilePath $plannedChangesFilePath
        }
        2 {
            $plannedChangesFilePath = Read-Host "Enter the path to the CSV file with planned changes"
            $rollbackFilePath = Read-Host "Enter the path to save the rollback data CSV file"
            Apply-MailObjectChanges -plannedChangesFilePath $plannedChangesFilePath -rollbackFilePath $rollbackFilePath
        }
        3 {
            $rollbackFilePath = Read-Host "Enter the path to the CSV file with rollback data"
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

# Main
try {
    Connect-ExchangeOnline
    Display-Menu
} finally {
    Disconnect-ExchangeOnline -Confirm:$false
}
