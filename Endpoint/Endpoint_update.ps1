# Restart Process using PowerShell 64-bit 
If ($ENV:PROCESSOR_ARCHITEW6432 -eq "AMD64") {
    Try {
        &"$ENV:WINDIR\SysNative\WindowsPowershell\v1.0\PowerShell.exe" -File $PSCOMMANDPATH
    }
    Catch {
        Throw "Failed to start $PSCOMMANDPATH"
    }
    Exit
}

Start-Transcript C:\Europameister.txt

# Get the last SID from registry
$loggedUserSID = (Get-ItemProperty -Path hklm:\SOFTWARE\Microsoft\Windows\CurrentVersion\Authentication\LogonUI -Name LastLoggedOnUserSID).LastLoggedOnUserSID
$loggedUser = (Get-WmiObject -Class Win32_ComputerSystem | Select-Object -ExpandProperty UserName).Split('\')[1]

write-host "$loggedUserSID"
write-host "$loggedUser"


taskkill.exe /IM outlook.exe /F

# ZeroConfigkey Outlook
$registryPathZeroConf = "Registry::\HKEY_USERS\$loggedUserSID\software\policies\microsoft\office\16.0\outlook\autodiscover"

# Check the registry value under the user's account
if (Test-Path "$registryPathZeroConf") {
    Write-Host "Registry key FOUND for user with SID: $loggedUserSID."
} else {
    new-Item -Path $registryPathZeroConf -ItemType Registry::Key -Force | Out-Null
    Set-ItemProperty -Path $registryPathZeroConf -Name "zeroconfigexchange" -Value "1" -Type "DWORD"
    Write-Host "Registry key created for the user with SID: $loggedUserSID."
}

# Create new profile and set as default
$Createnewprofile = "Registry::\HKEY_USERS\$loggedUserSID\Software\Microsoft\Office\16.0\Outlook"

# Check the registry value under the user's account
if ((Get-ItemProperty "$Createnewprofile" -Name DefaultProfile).DefaultProfile -ne 'Europameister') {
    try {
        New-Item -Path "$($Createnewprofile)\Profiles" -Name Europameister -Force:$true -ErrorAction Stop
        New-ItemProperty $Createnewprofile -Name DefaultProfile -PropertyType String -Value Europameister -Force:$true -ErrorAction Stop
        Write-Host "Registry key created for the user with SID: $loggedUserSID."
    }
    catch {
        Write-Warning ("Error setting value for {0}" -f $loggedUserSID)
    }
} else {
    Write-Host "Registry key FOUND for user with SID: $loggedUserSID."
}

# Remove the last LastLoggedOnUser from the lockscreen
$keyPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Authentication\LogonUI"

# Check if the registry key exists
if (Test-Path $keyPath) {
    # Remove the string value
    Remove-ItemProperty -Path $keyPath -Name "LastLoggedOnDisplayName" -Force
    Remove-ItemProperty -Path $keyPath -Name "LastLoggedOnProvider" -Force
    Remove-ItemProperty -Path $keyPath -Name "LastLoggedOnSAMUser" -Force
    Remove-ItemProperty -Path $keyPath -Name "LastLoggedOnUser" -Force
    Remove-ItemProperty -Path $keyPath -Name "LastLoggedOnUserSID" -Force
    Remove-ItemProperty -Path $keyPath -Name "SelectedUserSID" -Force
    Write-Host "String values removed successfully."
} else {
    Write-Host "Registry key not found."
}

taskkill.exe /IM onedrive.exe /F

Stop-Transcript

# Give users a grace period before shutting down so they can close applications
shutdown /s /t 300 /c "Device will restart in 5 minutes to finalize credential updates. Please save your work." /f
