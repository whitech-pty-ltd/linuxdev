<!---
title: Tips
date: 2021-09-26
--->

# Tips

## Useful Commands

- `vagrant halt` to shut down the VM
- `vagrant up` to turn on the VM
- `vagrant reload` apply .env settings like MEMORY, CPUS with **rebooting vm**
- `./destory.sh` to destroy the VM and start from scratch

If you want to repeat from scratch for some reason, you can run `./destroy.sh` and retry `bootstrap.sh`.

## Docker

docker is available and you will see the samba container running for the VM

Please use install-docker-clients script if you don't have docker clients installed.

[Vagrant Manager](https://www.vagrantmanager.com/) would be nice to have. Try setup.ps1 with `-withvagrantmanager`

## Mapping network drive from the machine

Virtualbox machine has IP of 192.168.99.123 by default
and it shares Projects directory so Host machine can see the files in it.

```
\\192.168.99.123\Projects
```

** Windows git global config should have filemode turned off


## Setup parameters

```powershell
.\setup.ps1 -nodevtools
```

or

```bash
./setup.sh --no-devtools
```

will skip installing git(for Mac), vscode, and terminal.

`--no-{vscode,git,vagrant,virtualbox,...}` is also available

** git should be required for Windows to run git-bash

### basic os setting

`-withosconfig` will update registry for

- Disable Secure Desktop (UAC Dimming)
- Set active hour (8am to 2am)
- Show hidden files and extensions
- Disable Windows Update

You can also run separately by `scripts/basic-config.ps1`

## Docker Storage

Docker tend to use many small files especially for node.js projects

If the main storage has not enough inodes, docker can fail because of the disk space.
You can check that `df -h` has some free space but `df -hi` shows a low free space.

BTW, You can prune unused file by following docker command but it would rebuild required files soon.

```bash
docker system prune --volumes
```

This vgrantfile has additional space file of 40GB and it can be configured by `DOCKER_DISK_SIZE_GB=40`

## Details For Windows 10 users


### setup.ps1

> :warning: **Note that this script will disable WSL2(Hyper-V).**
>
> Please backup any required files before running. Docker will be still available by this VM

Right click windows menu and click Windows Powershell (Admin)

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
```

Run the setup script in the directory of this repo

```powershell
\Users\xxx\linuxdev\setup.ps1
```

** Running setup script again will check updates and install if newer version found

### bootstrap.sh

Open Windows Terminal for Gitbash or just Git Bash

In linuxdev dir (this repo)

```bash
./bootstrap.sh
```

This will create virtualbox machine and bootup and config
    
