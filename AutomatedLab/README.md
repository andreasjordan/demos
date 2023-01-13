# AutomatedLab

Information and resources for using the PowerShell module AutomatedLab (https://automatedlab.org/) to set up labs.

This is a modified copy of a private repository, so some things might not work without further modification. All information and scripts are intended as inspiration for own developments.


## Installation

All commands must be executed in an administrative PowerShell.

For installation, the commands from the scripts in this directory can simply be copied into a PowerShell ISE and executed there line by line or block by block.


### 01_Install_HyperV.ps1

In advance, the ExecutionPolicy is tested here and set to RemoteSigned if necessary.

The Windows Hyper-V function is then installed and the computer is restarted. If Hyper-V is already in use, this step can be skipped.


### 02_Install_AutomatedLab.ps1

First, PSGallery is set up as a trusted source for PowerShell packages. Since Microsoft servers only support the current TLS 1.2 protocol, the commented out line may still need to be used on older operating systems. On current operating systems, however, this should no longer be necessary. If errors occur, this may be due to the temporary inaccessibility of the PSGallery. Then some time later a new attempt has to be started.

In addition to the PowerShell module AutomatedLab, Posh-SSH is also installed to enable convenient access to the Linux machines via SSH. The additional options during the installation of AutomatedLab are necessary, details are described [here](https://automatedlab.org/en/latest/Wiki/Basic/install/).

The environment variable AUTOMATEDLAB_TELEMETRY_OPTIN controls whether a corresponding information should be sent to the developers when setting up and dismantling labs. We want to switch this off in our case.

Deviating from the standard configuration, two configurations are changed to adjust the paths used. These are my recommendations, but anyone can deviate from them.

The configuration "LabSourcesLocation" is later always accessible under the global variable `$labSources` and is also referenced in this way in all scripts. In this path above all the ISOs of the used operating systems are stored, which are needed only during the construction of the labs. Additional components and examples are also stored here. Also the ISOs of the SQL Servers and installation media of Oracle are stored later under this path. The default is only "LabSources" and offers thus first no reference to the used program, therefore the adjustment.

The "VmPath" configuration controls the location of the created Hyper-V machines. Without this configuration, the fastest drive is automatically used and the directory is created there.

After setting the configuration, the module is loaded and initialized. During this process, additional files are loaded from the internet. 

Since the module itself does not provide any operating system ISOs, you have to obtain them yourself. I recommend using the ISOs provided by Microsoft with evaluation versions of the operating systems here. The client operating systems Windows 10 and 11 have a test period of 90 days, the server operating system Windows Server 2022 has a test period of 180 days. In addition, the deployment of Windows Server 2022 is a lot faster than the deployment of Windows 10 or 11, which is why I only use Windows Server 2022 in my labs myself. The Linux variants specified here can be installed automatically, newer versions are not currently supported. I mainly use CentOS-7, because the installation is finished faster than with CentOS-Stream-9 or openSUSE-Leap-15.2.


### 03_Setup_TestLab.ps1

At this point you can build a first lab to test the functionality.

The lab can be configured in a few places: Firstly, the creation of the domain can be switched off to shorten the installation time. Only the two machines "Windows" and "Linux" are then set up. On the other hand the used DNS server can be fixed, because the automatic determination could not be tested sufficiently. However, the DNS server setting is only used in the configuration without domain, because with domain the DC takes over the role of the DNS proxy. In addition, the Chocolatey packages, PowerShell modules and Docker containers installed for testing can be customized.


### 04_Download_CustomAssets.ps1

The script downloads this repository and moves the "CustomAssets" and "CustomScripts" directories to the "$labSources" directory. Directly contained there are currently only the backups of GPOs that I regularly use in my labs. There are also subdirectories for other files, but I don't want to include these files in the repository here. I only provide a list of files that I use internally.
