$ErrorActionPreference = "Stop"
$currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
  Write-Host "Please run as an administrator"
  exit 109
}

If ($args.Contains("-noconfirm")) {
  $noConfirm=1
}
If ($args.Contains("-nodevtools") -or $args.Contains("-production")) {
  $noDevTools=1
}

If ($args.Contains("-nogit")) {
  $noGit=1
}

If ($args.Contains("-novscode")) {
  $noVsCode=1
}

If ($args.Contains("-noterminal")) {
  $noTerminal=1
}

If ($args.Contains("-novagrant")) {
  $noVagrant=1
}

If ($args.Contains("-novirtualbox")) {
  $noVirtualBox=1
}

If ($args.Contains("-withvagrantmanager")) {
  $withVagrantManager=1
}

If ($args.Contains("-withosconfig")) {
  $withOsConfig=1
}

If ($args.Contains("-nohyperv")) {
  $noHyperv=1
}

if ($noDevTools) {
  $noVsCode=1
  $noTerminal=1
}

$OsVersion = (Get-WmiObject -class Win32_OperatingSystem).Caption
$OsArchBit = (Get-WMIObject Win32_Processor).AddressWidth
$OsArch = "x86"
if ($OsArchBit -ne 32) {
  $OsArch = "x64"
}
$OsBuildNumber = (Get-WmiObject -class Win32_OperatingSystem).BuildNumber
if ($OsBuildNumber -lt 19041) {
  write-error "Windows Build number should be at least 19041"
  exit 101
}

Write-Host "==================================
Note: This will turn off WSL2
  and upgrade exsting softwares like
  git, vscode, windows terminal,
  virtualbox, vagrant
=================================="
if (-not $noConfirm) {
Read-Host -Prompt "Press any key to continue or ^C to stop"
}

# read .env
$envfileContent = Get-Content $PSScriptRoot\.env -ErrorAction continue
$envfile=[ordered]@{}
$envfileContent|ForEach-Object{
  $key, $value = $_.split("=")
  if ($key) {
    $envfile[$key]=$value
  }
}

# apply path
$machine_path = [Environment]::GetEnvironmentVariables("Machine")['Path']
$user_path = [Environment]::GetEnvironmentVariables("User")['Path']
$env:Path = "$machine_path;$user_path"

if ($withOsConfig) {
  & "$PSScriptRoot\scripts\basic-config.ps1"
}

if (-not $noHyperv) {
# Disable hyper-v
Write-Host ---------------------------------------
Write-Host " Disabling Hypervisor Platform"

try {
function disable-optional-feature {
  param ($featureName)
  $feature = Get-WindowsOptionalFeature -online -FeatureName $featureName
  if ($feature) {
    if ($feature.State -eq "Disabled") {
      write-host $featureName is already disabled
    } else {
      Disable-WindowsOptionalFeature -Online -FeatureName $featureName -NoRestart
    }
  } else {
    write-host $featureName was not found
  }
}

disable-optional-feature -featureName Microsoft-Hyper-V-Hypervisor
disable-optional-feature -featureName VirtualMachinePlatform
disable-optional-feature -featureName HypervisorPlatform

Start-Process -Wait -PassThru powershell -Verb runAs -ArgumentList 'bcdedit /set hypervisorlaunchtype off'

} catch {
  $_
  exit 102
}

}

$virtualization_enabled = systeminfo |select-string "Virtualization Enabled"|out-string|ForEach-Object{$_.SubString($_.IndexOf(': ')+1).trim()}
Write-Host Virtualization support: $virtualization_enabled

function get_github_release_url {
  param($url, $pattern)
  $asset = Invoke-RestMethod -Method Get -Uri "$url" | foreach-object assets | where-object name -like "$pattern"
  if (!$asset) {
    Throw "Could not find asset, please review pattern: '$pattern'
 "
  }
  if (($asset).Count) {
    Throw "Could not find a unique assets, please review pattern: '$pattern'
matched $($asset.name -Join ", ")
 "
  }
  return @{"url" = $($asset.browser_download_url); "name" = $($asset.name)}
}

function download_from_installer_url {
  param ($url, $filename)
  if ($url -like '//*') {
    $url = "https:$url"
  }
  if (-not $filename) {
    $filename = $url.split("=/?")[-1]
  }
  #write-host "Download-from-installer-url: $url, $filename"
  $temp_file = "$env:temp\$filename"
  if ($temp_file -notmatch ".exe" -and $temp_file -notmatch ".msi") {
    $temp_file = "$temp_file.exe"
  }
  if (Test-Path($temp_file)) {
    Write-Host Found $temp_file, skip downloading
  } else {
    Invoke-WebRequest -UseBasicParsing -Uri "$url" -OutFile $temp_file
  }
  return $temp_file
}

function download_github_release_installer {
  param($url, $pattern)
  $asset = get_github_release_url -url "$url" -pattern "$pattern"
  $installer = download_from_installer_url -url $asset.url
  return $installer
}

# Install terminal
If (-Not $noTerminal) {
Write-Host ---------------------------------------
$installed_terminal_version = (Get-AppxPackage -Name *WindowsTerminal).Version
$OsPrefix = "Win10"
if ($OsVersion -like '* 11*') {
  $OsPrefix = "Win11"
}
$terminal_asset = get_github_release_url -url "https://api.github.com/repos/microsoft/terminal/releases/latest" -pattern "*msixbundle"
Write-Host $terminal_asset.name
if ($installed_terminal_version -And $terminal_asset.name -match $installed_terminal_version) {
  Write-Host already installed
} else {
  Write-Host Installing $terminal_asset.name "(installed: $installed_terminal_version)"
  $terminal_installer = download_from_installer_url -url $terminal_asset.url -filename $terminal_asset.name
  Try {
    Add-AppPackage -path $terminal_installer
  } catch {
    Write-Host $_
  }
  Write-Host Installed Windows Terminal.
}
}

# Install vagrant manager
If ($withVagrantManager) {
  Write-Host ---------------------------------------
  $vmanager_location1="$env:ProgramFiles (x86)\Vagrant Manager\VagrantManager.exe"
  $vmanager_location2="$env:LOCALAPPDATA\Programs\Vagrant Manager\VagrantManager.exe"
  If ((Test-Path $vmanager_location1) -or (Test-Path $vmanager_location2)) {
    Write-Host Vagrant Manager is already installed
  } else {
    Write-Host Installing Vagrant Manager
    $vmanager_installer = download_github_release_installer -url "https://api.github.com/repos/lanayotech/vagrant-manager-windows/releases/latest" -pattern "*.exe"
    $install_args = "/SP- /SILENT /NOCANCEL /NORESTART /CLOSEAPPLICATIONS /RESTARTAPPLICATIONS"
    Write-Host Installing $vmanager_installer, $install_args
    Start-Process -FilePath $vmanager_installer -ArgumentList $install_args
    Write-Host Installed Vagrant Manager.
  }
}

######################
# Install vscode
If (-Not $noVsCode) {
Write-Host ---------------------------------------
Try {
  $installed_vscode_version = code --version| select-object -First 1
} catch {}
#Write-Host VS Code version: $installed_vscode_version

$vscode_url = "https://code.visualstudio.com/sha/download?build=stable&os=win32-x64-user"
$vscode_installer_url = [System.Uri](Invoke-WebRequest -UseBasicParsing -Method Head -MaximumRedirection 0 -Uri $vscode_url -ErrorAction SilentlyContinue).Headers.Location

#Write-Host VS Code installer url: $vscode_installer_url
$vscode_installer_filename = $vscode_installer_url.Segments | Select-Object -Last 1
$vscode_installer_version = $vscode_installer_filename| select-string -Pattern '([0-9]+(\.[0-9]+)+)' | ForEach-Object{$_.Matches[0].Value}
Write-Host "$vscode_installer_filename, $vscode_installer_version"

$vscode_installer = "$env:temp\$($vscode_installer_filename)"
Write-Host "VS Code installer `"$vscode_installer_version`" (installed: $installed_vscode_version)"
if ($installed_vscode_version -And $vscode_installer_version -match $installed_vscode_version) {
  Write-Host already installed
} else {
  # download installer unless exists
  if (Test-Path($vscode_installer)) {
    Write-Host Found $vscode_installer, skip downloading
  } Else {
    Write-Host Downloading $vscode_installer_url
    Invoke-WebRequest -UseBasicParsing -Uri $vscode_installer_url -OutFile $vscode_installer
  }
  # Install vs code
  Write-Host Installing $vscode_installer_filename
  Try {
    Start-Process -Wait -FilePath $vscode_installer -Argument "/SILENT /NORESTART /MERGETASKS=!runcode" -PassThru
  } catch {
    Write-Host $_
  }
  Write-Host Installed VS Code.
}
}

If (-Not $noGit) {
######################
# run installer if git-bash not found
Write-Host ---------------------------------------
Try {
  $installed_git_version = git --version | %{$_.split(' ')[-1]} | %{$_.SubString(0, $_.IndexOf('.windows'))}
} catch {}
$git_asset = get_github_release_url -url "https://api.github.com/repos/git-for-windows/git/releases/latest" -pattern "*$OsArchBit-bit.exe"
Write-Host $git_asset.name "(installed: $installed_git_version)"
if ($installed_git_version -And $git_asset.name -match $installed_git_version) {
  Write-Host already installed
} Else {
  # download installer unless exists
  $git_installer = download_from_installer_url -url $git_asset.url -name $git_asset.name
  $git_install_inf = "$PSScriptRoot\config\git.inf"
  $install_args = "/SP- /SILENT /NOCANCEL /NORESTART /CLOSEAPPLICATIONS /RESTARTAPPLICATIONS /LOADINF=""$git_install_inf"""
  Write-Host Installing $git_installer, $install_args
  Start-Process -FilePath $git_installer -ArgumentList $install_args -Wait
  Write-Host Installed Git.
}
}

If (-Not $noVirtualBox) {
######################
# Install virtual box
Write-Host ---------------------------------------
$vbox_path = "$Env:Programfiles\Oracle\VirtualBox"
$vbox_manage = "$vbox_path\VBoxManage"
Try {
  $installed_vbox_version = (& $vbox_manage --version)
} catch {}
#Write-Host VBox version: $installed_vbox_version
try {
  if ($envfile._VER_VIRTUALBOX) {
    $versionString = $envfile._VER_VIRTUALBOX | select-string -Pattern '[0-9.]+' | ForEach-Object{$_.Matches[0].Value}
    $versionPrefix = $versionString | select-string -Pattern '[0-9]+\.[0-9]+' | ForEach-Object{$_.Matches[0].Value -replace "\.","_"}
    $vbox_url = "https://www.virtualbox.org/wiki/Download_Old_Builds_$versionPrefix"
    $vbox_link = (Invoke-WebRequest -UseBasicParsing -Uri $vbox_url).Links | Where-Object {$_.href -like "*$versionString*Win.exe"}
  }
  if (!$vbox_link) {
    $vbox_url = "https://www.virtualbox.org/wiki/Downloads"
    $vbox_link = (Invoke-WebRequest -UseBasicParsing -Uri $vbox_url).Links | Where-Object {$_.href -like "*$versionString*Win.exe"}
  }
} catch {
  $_.Exception.Response.StatusCode
}
$vbox_installer_url = [System.Uri]$vbox_link.href
#Write-Host VBox installer url: $vbox_installer_url
$vbox_installer_filename = $vbox_installer_url.Segments | Select-Object -Last 1
$vbox_installer_version = Write-Output $vbox_installer_filename | select-string -Pattern '([0-9]+(\.[0-9]+)+)' | ForEach-Object{$_.Matches[0].Value}
$vbox_installer = "$env:temp\$($vbox_installer_filename)"
#Write-Host $vbox_installer_version, $installed_vbox_version
Write-Host "VirtualBox installer `"$vbox_installer_version`" (installed: $installed_vbox_version)"

function save-vm-states {
  # list running vms and savestate
  & $vbox_manage list runningvms|foreach-object -Process {
    if ($_ -match '"(.+?)"') {
      $vm_name = $matches[1]
      write-host Saving state $vm_name
      & $vbox_manage controlvm "$vm_name" savestate
    }
  }
}

if (!$vbox_installer_url) {
  Write-Host "Could not find the download url $versionString"
} elseif ($installed_vbox_version -And $installed_vbox_version -match $vbox_installer_version) {
  Write-Host already installed
} else {
  # download installer unless exists
  if (Test-Path($vbox_installer)) {
    Write-Host Found $vbox_installer, skip downloading
  } Else {
    Write-Host Downloading $vbox_installer_url
    Invoke-WebRequest -UseBasicParsing -Uri $vbox_installer_url -OutFile $vbox_installer
  }
  # Install vbox
  Write-Host Installing $vbox_installer_filename
  if ($installed_vbox_version) {
    save-vm-states
  }
  Try {
    Start-Process -Wait -FilePath $vbox_installer -Argument "--silent --ignore-reboot" -PassThru
  } catch {
    Write-Host $_
  }
  Write-Host Installed VirtualBox.
}
}

######################
# Install vagrant
If (-Not $noVagrant) {
Write-Host ---------------------------------------
Try {
  $installed_vagrant_version = vagrant --version | %{$_.split(' ')[1]}
} catch {}

if ($envfile._VER_VAGRANT) {
  $versionString = $envfile._VER_VAGRANT | select-string -Pattern '[0-9.]+' | ForEach-Object{$_.Matches[0].Value}
}

if ($versionString) {
  $vagrant_url = "https://releases.hashicorp.com/vagrant/$versionString"
} else {
  $vagrant_url = "https://www.vagrantup.com/downloads"
}
try {
  $vagrant_link = (Invoke-WebRequest -UseBasicParsing -Uri $vagrant_url).Links | Where-Object {$_.href -like "*$OsArchBit.msi"}
} catch {
  $_.Exception.Response.StatusCode
}
$vagrant_installer_url = [System.Uri]$vagrant_link.href
$vagrant_installer_filename = $vagrant_installer_url.Segments | Select-Object -Last 1
$vagrant_installer_version = $vagrant_installer_filename | select-string -Pattern '([0-9]+(\.[0-9]+)+)' | ForEach-Object{$_.Matches[0].Value}
$vagrant_installer = "$env:temp\$($vagrant_installer_filename)"
Write-Host "Vagrant installer `"$vagrant_installer_version`" (installed: $installed_vagrant_version)"
if (!$vagrant_installer_url) {
  Write-Host "Could not find the download url $versionString"
} elseif ($installed_vagrant_version -And $installed_vagrant_version -match $vagrant_installer_version) {
  Write-Host already installed
} else {
  # download installer unless exists
  if (Test-Path($vagrant_installer)) {
    Write-Host Found $vagrant_installer, skip downloading
  } Else {
    Write-Host Downloading $vagrant_installer_url
    Invoke-WebRequest -UseBasicParsing -Uri $vagrant_installer_url -OutFile $vagrant_installer
  }
  # Install vagrant
  Write-Host Installing $vagrant_installer_filename
  Try {
    Start-Process -Wait -FilePath $vagrant_installer -Argument "/passive /norestart" -PassThru
  } catch {
    Write-Host $_
  }
  Write-Host Installed Vagrant.
}
}

Write-Host ==================================

if ($virtualization_enabled -ne "Yes") {
  Write-Host "Virtualization is not enabled, please follow this link and try to enable"
  Write-Host "https://www.smarthomebeginner.com/enable-hardware-virtualization-vt-x-amd-v/"
  exit 108
} else {
  Write-Host "Done. Please continue to bootstrap"
}
