if (!$args[0]) {
  write-error "taskName is require as the first argument"
  exit -1;
}
if (!$args[1]) {
  write-error "schedScript is require as the second argument"
  exit -1;
}
$taskName=$args[0]
$schedScript=$args[1] # $Env:REIMAGINE_KIOSK_PATH\start.ps1

Write-host "Registinering new '$taskName'"
$Action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NonInteractive -NoLogo -ExecutionPolicy Bypass -File `"$schedScript`""
## whenever machine started
## every morning at 6 am
$Trigger =  @(
  $(New-ScheduledTaskTrigger -AtLogon),
  $(New-ScheduledTaskTrigger -Daily -At 6am)
)
$Settings = New-ScheduledTaskSettingsSet
$Task = New-ScheduledTask -Action $Action -Trigger $Trigger -Settings $Settings

$user=((Get-WMIObject -class Win32_ComputerSystem | Select-Object -ExpandProperty username)) 
#$user

Register-ScheduledTask -TaskName $taskName -InputObject $Task -User "$user" # -Password 'passhere'
