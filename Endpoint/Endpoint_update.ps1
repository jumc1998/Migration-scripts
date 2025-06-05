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

Add-Type -AssemblyName PresentationCore,PresentationFramework
$msgBody = "Your user credentials are being updated. Your Outlook and OneDrive will be unavailable. In a few minutes, you will receive a notification that the migration is finished and that your machine will shutdown. Please power-on your device and sign in again with your new @panelclaw.eu credentials after this."
$msgTitle = "Europameister change"
$msgButton = 'OK'
$msgImage = 'Information'

# Display the message to the currently logged on user through a temporary scheduled task
$taskName = "EuropameisterMsg1"
$cmd = "Add-Type -AssemblyName PresentationCore,PresentationFramework; [System.Windows.MessageBox]::Show('$msgBody','$msgTitle','$msgButton','$msgImage')"
$action = New-ScheduledTaskAction -Execute 'PowerShell.exe' -Argument "-NoProfile -WindowStyle Hidden -Command \"$cmd\""
$principal = New-ScheduledTaskPrincipal -UserId $loggedUser -LogonType Interactive -RunLevel Highest
$task = New-ScheduledTask -Action $action -Principal $principal
Register-ScheduledTask -TaskName $taskName -InputObject $task -Force | Out-Null
Start-ScheduledTask -TaskName $taskName
Start-Sleep -Seconds 5
Unregister-ScheduledTask -TaskName $taskName -Confirm:$false

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

Add-Type -AssemblyName PresentationCore,PresentationFramework
$msgBody = "Your user credentials have been updated. You're PC will shutdown now. Please sign in again with your new @panelclaw.eu credentials."
$msgTitle = "Europameister change"
$msgButton = 'OK'
$msgImage = 'Information'

# Display the final message in the user's session
$taskName = "EuropameisterMsg2"
$cmd = "Add-Type -AssemblyName PresentationCore,PresentationFramework; [System.Windows.MessageBox]::Show('$msgBody','$msgTitle','$msgButton','$msgImage')"
$action = New-ScheduledTaskAction -Execute 'PowerShell.exe' -Argument "-NoProfile -WindowStyle Hidden -Command \"$cmd\""
$principal = New-ScheduledTaskPrincipal -UserId $loggedUser -LogonType Interactive -RunLevel Highest
$task = New-ScheduledTask -Action $action -Principal $principal
Register-ScheduledTask -TaskName $taskName -InputObject $task -Force | Out-Null
Start-ScheduledTask -TaskName $taskName
Start-Sleep -Seconds 5
Unregister-ScheduledTask -TaskName $taskName -Confirm:$false

shutdown /s
