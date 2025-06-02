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

# Function to display the menu and get user confirmation
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

    foreach ($user in $rollbackData) {
        try {
            Update-MgUser -UserId $user.ObjectId -UserPrincipalName $user.OriginalUserPrincipalName -CompanyName $user.OriginalCompanyName
            Log-Message "Rolled back changes for $($user.OriginalUserPrincipalName)"
        } catch {
            Log-Message "Error rolling back changes for $($user.OriginalUserPrincipalName): $_" "ERROR"
        }
    }
}

# Export planned changes to CSV
function Export-UserChanges {
    param (
        [string]$csvFilePath,
        [string]$plannedChangesFilePath
    )

    $userData = Import-Csv -Path $csvFilePath
    $changes = @()
    $plannedChangesData = @()

    foreach ($user in $userData) {
        $currentUser = Get-MgUser -UserId $user.UserPrincipalName
        
        if ($currentUser) {
            $changes += "Update UPN for $($user.UserPrincipalName) to $($user.NewUserPrincipalName)"
            $changes += "Update Department for $($user.UserPrincipalName) to $($user.Department)"
            $changes += "Update JobTitle for $($user.UserPrincipalName) to $($user.JobTitle)"
            $changes += "Update CompanyName for $($user.UserPrincipalName) to $($user.CompanyName)"
            $changes += "Add alias '$($user.Alias)' to '$($user.PrimaryEmail)'"

            $plannedChangesData += [PSCustomObject]@{
                ObjectId = $currentUser.Id
                OriginalUserPrincipalName = $currentUser.UserPrincipalName
                NewUserPrincipalName = $user.NewUserPrincipalName
                CompanyName = $user.CompanyName
                Alias = $user.Alias
                PrimaryEmail = $user.PrimaryEmail
            }
        } else {
            Log-Message "User $($user.UserPrincipalName) not found" "ERROR"
        }
    }

    if (Confirm-Changes -changes $changes) {
        $plannedChangesData | Export-Csv -Path $plannedChangesFilePath -NoTypeInformation
        Write-Host "Planned changes exported to $plannedChangesFilePath"
        Log-Message "Planned changes exported to $plannedChangesFilePath"
    } else {
        Write-Host "Operation cancelled." -ForegroundColor Red
    }
}

# Apply changes from CSV
function Apply-UserChanges {
    param (
        [Parameter(Mandatory=$true)][string]$plannedChangesFilePath,
        [Parameter(Mandatory=$true)][string]$rollbackFilePath
    )

    if (-not (Test-Path -Path $plannedChangesFilePath)) {
        Write-Host "CSV file not found." -ForegroundColor Red
        return
    }

    $userData = Import-Csv -Path $plannedChangesFilePath
    $rollbackData = @()

    foreach ($user in $userData) {
        $currentUser = Get-MgUser -UserId $user.OriginalUserPrincipalName

        if ($currentUser) {
            try {
                # Prepare rollback data
                $rollbackData += [PSCustomObject]@{
                    ObjectId = $currentUser.Id
                    OriginalUserPrincipalName = $currentUser.UserPrincipalName
                    OriginalCompanyName = $currentUser.CompanyName
                    Alias = $user.Alias
                    PrimaryEmail = $user.PrimaryEmail
                }

                # Update the user's UPN
                Update-MgUser -UserId $currentUser.Id -UserPrincipalName $user.NewUserPrincipalName -CompanyName $user.CompanyName
                Log-Message "Updated UPN for $($user.OriginalUserPrincipalName) to $($user.NewUserPrincipalName)"
            } catch {
                Log-Message "Error updating UPN for $($user.OriginalUserPrincipalName): $_" "ERROR"
            }
        } else {
            Log-Message "User $($user.OriginalUserPrincipalName) not found" "ERROR"
        }
    }

    # Save rollback data
    $rollbackData | Export-Csv -Path $rollbackFilePath -NoTypeInformation
    Write-Host "Rollback data exported to $rollbackFilePath"
    Log-Message "Rollback data exported to $rollbackFilePath"
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
            $csvFilePath = Read-Host "Enter the path to the CSV file with user data"
            $plannedChangesFilePath = Read-Host "Enter the path to save the planned changes CSV file"
            Export-UserChanges -csvFilePath $csvFilePath -plannedChangesFilePath $plannedChangesFilePath
        }
        2 {
            $plannedChangesFilePath = Read-Host "Enter the path to the CSV file with planned changes"
            $rollbackFilePath = Read-Host "Enter the path to save the rollback data CSV file"
            Apply-UserChanges -plannedChangesFilePath $plannedChangesFilePath -rollbackFilePath $rollbackFilePath
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

# Main script execution
try {
    # Connect to Microsoft Graph
    Connect-MgGraph -Scopes "User.ReadWrite.All"
    Display-Menu
} finally {
    # Disconnect from Microsoft Graph
    Disconnect-MgGraph
}
