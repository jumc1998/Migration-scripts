# Import the Microsoft Teams module
Import-Module MicrosoftTeams

# Connect to Microsoft Teams
$teamsCredentials = Get-Credential
Connect-MicrosoftTeams -Credential $teamsCredentials

# Export planned changes to CSV
function Export-TeamChanges {
    param (
        [string]$oldValue,
        [string]$newValue,
        [string]$exportFilePath
    )

    # Get all teams
    $teams = Get-Team
    $exportData = @()

    foreach ($team in $teams) {
        $newTeamName = $team.DisplayName -replace $oldValue, $newValue

        if ($team.DisplayName -ne $newTeamName) {
            $exportData += [PSCustomObject]@{
                TeamId      = $team.GroupId
                OldName     = $team.DisplayName
                NewName     = $newTeamName
                OldDescription = $team.Description
                NewDescription = "Updated description for rebranding"
            }
        }
    }

    $exportData | Export-Csv -Path $exportFilePath -NoTypeInformation
    Write-Host "Exported team changes to $exportFilePath"
}

# Apply changes from CSV
function Apply-TeamChanges {
    param (
        [string]$importFilePath
    )

    $importData = Import-Csv -Path $importFilePath

    foreach ($item in $importData) {
        Set-Team -GroupId $item.TeamId -DisplayName $item.NewName -Description $item.NewDescription
        Write-Host "Updated team $($item.OldName) to new name $($item.NewName)"
    }
}

# Example usage:
# Export planned changes
Export-TeamChanges -oldValue "OldTeamName" -newValue "NewTeamName" -exportFilePath "TeamChanges.csv"

# After approval, apply changes
# Apply-TeamChanges -importFilePath "TeamChanges.csv"
