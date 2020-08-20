# Setup a lab environment for demos

### Install PSAutoLab

I use the PowerShell module [PSAutoLab](https://github.com/pluralsight/PS-AutoLab-Env) to setup labs. Install the module as explained on the linked Github page.


### Setup the lab

I use a special configuration SqlServerLab, which is based on the [PowerShellLab](https://github.com/pluralsight/PS-AutoLab-Env/blob/master/Configurations/PowerShellLab/Instructions.md) configuration. See details about the configuration on the linked Github page.

What I've changed from PowerShellLab to SqlServerLab:

- SRV2 has no webserver
- SRV3 is joined to the domain

To use the configuration, just download the folder SqlServerLab to the configuration folder of PSAutoLab (should be C:\Autolab\Configurations). 

I use the script ```00_setup_lab.ps1``` to setup the lab and install the latest windows updates in one step, but you can only run the installation with ```-InstallOnly``` or only install the latest windows updates with ```-PatchOnly```.

The script helps solving the following problems:

- Sometimes a VM has problems joining the domain and only a hard reboot can solve the problem
- Sometimes WIN10 shuts down after installing an update

The script does everything without user interaction in about 3 to 4 hours. You just have to keep an eye on the output to see if you have other problems, that are not yet solved by the script. Use ```-Verbose``` to get a detailed output. And have a look at the parameters, maybe you would like to change some of them.

The script changes the current location to the configuration folder. But as it does this with ```Push-Location```, you can easily return to the previous location with ```Pop-Location```.


### Setup the client WIN10 (part 1)

I use the script ```01_setup_client.ps1``` to transfer a script to configure some settings onto the client WIN10. Edit the script so it fits your needs. If you add cool new stuff then let me know, maybe I like it, too.

At the moment I do the following:

* configure package manager and repository for PowerShell and install favorite modules
* install package manager Chocolatey and install favorite programs
* set my favorite explorer settings

For company specific things that I will not share here on Github, the script imports a second script from the Resources folder of PSAutoLab.


### First login to the client WIN10

These steps are especially for me with a german keyboard.

Connect via Hyper-V-Manager and transfer the login information via clipboard:

* COMPANY\Administrator
* P@ssw0rd

The first login takes a long time, then the screen resolution changes and you have to login a second time. At this time, the german keyboard can be activated with Alt + Left-Shift.
After the login completes, press Alt + Left-Shift to activate the german keyboard, reboot to install it permanently and then login again.


### Setup the client WIN10 (part 2)

Inside of WIN10, execute the script ```C:\setup_client.ps1```. Every PowerShell in WIN10 is running with elevated privileges, so you don't have to run it explicitly as administrator. If you use other configurations, this may not be the case. I would suggest running it in PowerShell ISE, because at the moment there is no error handling in the script.


### Take a snapshot

This is the perfect time to take a snapshot of the lab to be able to come back to this point. If you are in the configuration folder, then simply use ```Snapshot-Lab```.  


### Setup the SQL Server sources and demo databases

I use the script ```02_setup_sources.ps1``` to copy the SQL Server sources to the harddrive of WIN10 via a virtual dvd drive for the ISO files in the resources folder. I also transfer SQL Server updates and demo databases onto the client WIN10. Edit the script so it fits your needs. If you add cool new stuff then let me know, maybe I like it, too.

You want to know where the StackOverflow2010.zip comes from? Have a look at [this blog post](https://www.brentozar.com/archive/2015/10/how-to-download-the-stack-overflow-database-via-bittorrent/) from Brent Ozar.


### Some statements just for me

	# To change the number of processors:
	Shutdown-Lab -NoMessages ; Set-VMProcessor -VMName SRV1, SRV2 -Count 4 ; Run-Lab -NoMessages

	# To take a snapshot and start the lab:
	Snapshot-Lab -NoMessages ; Run-Lab -NoMessages

	# To revert to a snapshot:
	Stop-VM -VMName (Get-Labsummary).VMName -TurnOff ; Refresh-Lab -NoMessages ; Run-Lab -NoMessages

	# To wipe the lab:
	Wipe-Lab -NoMessages -Force

	# If networks change and internet is lost:
	Enable-Internet

	# To start the lab when in a new powershell session:
	$ErrorActionPreference = 'Stop'
	$AutoLabConfiguration = 'SqlServerLab'
	Import-Module -Name PSAutoLab
	Push-Location -Path ((Get-PSAutoLabSetting).AutoLab + '\Configurations\' + $AutoLabConfiguration)
	Run-Lab -NoMessages

	# To set the file attibutes (needed when files are copied from my OneDrive):
	Get-ChildItem -Path ((Get-PSAutoLabSetting).AutoLab + '\Resources') | ForEach-Object -Process { $_.Attributes = 'Normal' }