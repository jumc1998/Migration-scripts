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

    foreach ($item in $rollbackData) {
        try {
            Update-SiteDisplayName -SiteId $item.SiteId -DisplayName $item.OldDisplayName
            Log-Message "Rolled back changes for site $($item.DisplayName)"
        } catch {
            Log-Message "Error rolling back changes for site $($item.DisplayName): $_" "ERROR"
        }
    }
}

# Function to update site display name
function Update-SiteDisplayName {
    param (
        [Parameter(Mandatory=$true)][string]$SiteId,
        [Parameter(Mandatory=$true)][string]$DisplayName
    )
    # Update SharePoint site
    $siteUri = "https://graph.microsoft.com/v1.0/sites/$SiteId"
    $body = @{ displayName = $DisplayName } | ConvertTo-Json
    Invoke-RestMethod -Uri $siteUri -Method PATCH -Body $body -Headers @{ "Authorization" = "Bearer $($global:accessToken)" } -ContentType "application/json"
}

# Export planned changes to CSV
function Export-SiteDisplayNameChanges {
    param (
        [string]$oldValue,
        [string]$newValue,
        [string]$exportFilePath
    )

    # Get all sites
    $sites = Get-MgSite -All | Select Id,DisplayName
    $exportData = @()
    $changes = @()

    foreach ($site in $sites) {
        if ($site.DisplayName -like "*$oldValue*") {
            $newDisplayName = $site.DisplayName -replace [regex]::Escape($oldValue), $newValue
            $exportData += [PSCustomObject]@{
                SiteId         = $site.Id
                DisplayName    = $site.DisplayName
                OldDisplayName = $site.DisplayName
                NewDisplayName = $newDisplayName
            }
            $changes += "Update display name for site $($site.DisplayName) to '$newDisplayName'"
        }
    }

    if (Confirm-Changes -changes $changes) {
        $exportData | Export-Csv -Path $exportFilePath -NoTypeInformation
        Write-Host "Exported site display name changes to $exportFilePath"
        Log-Message "Exported site display name changes to $exportFilePath"
    } else {
        Write-Host "Operation cancelled." -ForegroundColor Red
    }
}

# Apply changes from CSV
function Apply-SiteDisplayNameChanges {
    param (
        [Parameter(Mandatory=$true)][string]$importFilePath
    )

    if (-not (Test-Path -Path $importFilePath)) {
        Write-Host "Import file not found." -ForegroundColor Red
        return
    }

    $importData = Import-Csv -Path $importFilePath
    $importData | Export-Csv -Path $rollbackFilePath -NoTypeInformation

    foreach ($item in $importData) {
        try {
            Update-SiteDisplayName -SiteId $item.SiteId -DisplayName $item.NewDisplayName
            Log-Message "Updated display name for site $($item.DisplayName)"
        } catch {
            Log-Message "Error updating display name for site $($item.DisplayName): $_" "ERROR"
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
            Export-SiteDisplayNameChanges -oldValue $oldValue -newValue $newValue -exportFilePath $exportFilePath
        }
        2 {
            $importFilePath = Read-Host "Enter the path to the CSV file with changes"
            Apply-SiteDisplayNameChanges -importFilePath $importFilePath
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
    Connect-MgGraph -Scopes "Sites.ReadWrite.All"
    Display-Menu
} finally {
    # Disconnect from Microsoft Graph
    Disconnect-MgGraph
}
