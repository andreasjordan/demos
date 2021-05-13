function Remove-DbaInstance {
    <#
    .SYNOPSIS
        This function will help you to quickly uninstall a SQL Server instance.
    .DESCRIPTION
        This function will help you to quickly uninstall a SQL Server instance on one or many computers.
    .PARAMETER SqlInstance
        The target computer and, optionally, the instance name and the port number.
        Use one of the following generic formats:
        Server1
        Server2\Instance1
        Server1\Alpha:1533, Server2\Omega:1566
        "ServerName\NewInstanceName,1534"
    .PARAMETER Credential
        Used when executing installs against remote servers
    .PARAMETER Authentication
        Chooses an authentication protocol for remote connections.
        Allowed values: 'Default', 'Basic', 'Negotiate', 'NegotiateWithImplicitCredential', 'Credssp', 'Digest', 'Kerberos'
        If the protocol fails to establish a connection
        Defaults:
        * CredSSP when -Credential is specified - due to the fact that repository Path is usually a network share and credentials need to be passed to the remote host
          to avoid the double-hop issue.
        * Default when -Credential is not specified. Will likely fail if a network path is specified.
    .PARAMETER Path
        Path to the folder(s) with SQL Server installation media downloaded. It will be scanned recursively for a corresponding setup.exe.
        Path should be available from the remote server.
        If a setup.exe file is missing in the repository, the installation will fail.
        Consider setting the following configuration in your session if you want to omit this parameter: `Set-DbatoolsConfig -Name Path.SQLServerSetup -Value '\\path\to\installations'`
    .PARAMETER Restart
        Restart computer automatically if a restart is required before or after the uninstallation.
    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.
    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.
    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command.
    .NOTES
        Tags: Uninstall
        Author: Andreas Jordan (@JordanOrdix), based on code from Reitse Eskens (@2meterDBA), Kirill Kravtsov (@nvarscar)
        Website: https://dbatools.io
        Copyright: (c) 2021 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT
    .LINK
        https://dbatools.io/
    .Example
        PS C:\> Remove-DbaInstance -SqlInstance sql2017\sqlexpress, server01
        Uninstall a named SQL Server instance named sqlexpress on sql2017, and a default instance on server01.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param (
        [Alias('ComputerName')]
        [DbaInstanceParameter[]]$SqlInstance = $env:COMPUTERNAME,
        [PSCredential]$Credential,
        [ValidateSet('Default', 'Basic', 'Negotiate', 'NegotiateWithImplicitCredential', 'Credssp', 'Digest', 'Kerberos')]
        [string]$Authentication = 'Credssp',
        [string[]]$Path = (Get-DbatoolsConfigValue -Name 'Path.SQLServerSetup'),
        [switch]$Restart = $false,
        [switch]$EnableException = $false
    )
    & (Import-Module -Name dbatools -PassThru) { 
        param ($param)

        Function Get-SqlInstallSummary {
            # Reads Summary.txt from the SQL Server Installation Log folder
            Param (
                [DbaInstanceParameter]$ComputerName,
                [pscredential]$Credential,
                [parameter(Mandatory)]
                [version]$Version
            )
            $getSummary = {
                Param (
                    [parameter(Mandatory)]
                    [version]$Version
                )
                $versionNumber = "$($Version.Major)$($Version.Minor)".Substring(0, 3)
                $rootPath = "$([System.Environment]::GetFolderPath("ProgramFiles"))\Microsoft SQL Server\$versionNumber\Setup Bootstrap\Log"
                $summaryPath = "$rootPath\Summary.txt"
                $output = [PSCustomObject]@{
                    Path              = $null
                    Content           = $null
                    ExitMessage       = $null
                    ConfigurationFile = $null
                }
                if (Test-Path $summaryPath) {
                    $output.Path = $summaryPath
                    $output.Content = Get-Content -Path $summaryPath
                    $output.ExitMessage = ($output.Content | Select-String "Exit message").Line -replace '^ *Exit message: *', ''
                    # get last folder created - that's our setup
                    $lastLogFolder = Get-ChildItem -Path $rootPath -Directory | Sort-Object -Property Name -Descending | Select-Object -First 1 -ExpandProperty FullName
                    if (Test-Path $lastLogFolder\ConfigurationFile.ini) {
                        $output.ConfigurationFile = "$lastLogFolder\ConfigurationFile.ini"
                    }
                    return $output
                }
            }
            $params = @{
                ComputerName = $ComputerName.ComputerName
                Credential   = $Credential
                ScriptBlock  = $getSummary
                ArgumentList = @($Version.ToString())
                ErrorAction  = 'Stop'
                Raw          = $true
            }
            return Invoke-Command2 @params
        }


        $SqlInstance     = $Param.SqlInstance
        $Credential      = $Param.Credential
        $Authentication  = $Param.Authentication
        $Path            = $Param.Path
        $Restart         = $Param.Restart
        $EnableException = $Param.EnableException

        # using -Verbose outputs a lot of line from Import-Module, so in case of debugging I use the line below
        $VerbosePreference = 'Continue'

        Write-Message -Level Verbose -Message "SqlInstance = $SqlInstance"
        Write-Message -Level Verbose -Message "Credential = $Credential"
        Write-Message -Level Verbose -Message "Authentication = $Authentication"
        Write-Message -Level Verbose -Message "Path = $Path"
        Write-Message -Level Verbose -Message "Restart = $Restart"
        Write-Message -Level Verbose -Message "EnableException = $EnableException"

        foreach ($instance in $SqlInstance) {
            Write-Message -Level Verbose -Message "Processing $instance"

            Write-Message -Level Verbose -Message 'Starting Test-ElevationRequirement'
            $null = Test-ElevationRequirement -ComputerName $instance -Continue -EnableException:$EnableException

            $output = [PSCustomObject]@{
                ComputerName      = $instance.ComputerName
                InstanceName      = $instance.InstanceName
                Version           = $null
                InstancePath      = $null
                Successful        = $false
                Restarted         = $false
                Installer         = $null
                Notes             = @()
                ExitCode          = $null
                ExitMessage       = $null
                Log               = $null
                LogFile           = $null
                ConfigurationFile = $null
            }

            $restartParams = @{
                ComputerName = $instance.ComputerName
                ErrorAction  = 'Stop'
                For          = 'WinRM'
                Wait         = $true
                Force        = $true
            }
            if ($Credential) {
                $restartParams.Credential = $Credential
            }

            $activity = "Uninstalling SQL Server instance $($instance.InstanceName) on $($instance.ComputerName)"


            # Step 1: Test for reboot
            #########################

            try {
                Write-Message -Level Verbose -Message 'Starting Test-PendingReboot'
                # I use  -PendingRename to get informed about pending file rename operations
                $restartNeeded = Test-PendingReboot -ComputerName $instance -Credential $Credential -PendingRename
            } catch {
                $restartNeeded = $false
                Stop-Function -Message "Failed to get reboot status from $($instance.ComputerName)" -ErrorRecord $_
            }
            if ($restartNeeded -and (-not $Restart -or $instance.IsLocalHost)) {
                #Exit the actions loop altogether - nothing can be installed here anyways
                Stop-Function -Message "$instance is pending a reboot. Reboot the computer before proceeding." -Continue
            }
            if ($restartNeeded -and $Restart) {
                # Restart the computer prior to doing anything
                $msgPending = "Restarting computer $($instance.ComputerName) due to pending restart"
                Write-ProgressHelper -ExcludePercent -Activity $activity -Message $msgPending
                Write-Message -Level Verbose $msgPending
                try {
                    $null = Restart-Computer @restartParams
                    $output.Restarted = $true
                } catch {
                    Stop-Function -Message "Failed to restart computer" -ErrorRecord $_ -Continue
                }
            }


            # Step 2: Get version and path of instance
            ##########################################

            $getInfoScript = {
                param($InstanceName)
                $instanceID = (Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\Instance Names\SQL').$InstanceName
                [PSCustomObject]@{
                    # Version includes service pack as minor version, which is not allowed in Find-SqlInstanceSetup, so we use a dirty hack and just set it to 0 (does not work on 2008 R2)
                    Version      = (Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\$instanceID\Setup").PatchLevel -replace '\.\d\.', '.0.'
                    InstancePath = (Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\$instanceID\Setup").SQLPath -replace 'MSSQL$', ''
                }
            }
            $getInfoParams = @{
                ComputerName   = $instance
                Credential     = $Credential
                Authentication = $Authentication
                ScriptBlock    = $getInfoScript
                ArgumentList   = $instance.InstanceName
                ErrorAction    = 'Stop'
                Raw            = $true
            }
            try {
                Write-Message -Level Verbose -Message 'Starting Invoke-Command2 @getInfoParams'
                $info = Invoke-Command2 @getInfoParams
                Write-Message -Level Verbose -Message "Found Version $($info.Version) in Path $($info.InstancePath)"
                $output.Version = [version]$info.Version
                $output.InstancePath = $info.InstancePath
            } catch {
                Stop-Function -Message "Failed to enumerate information for instance $instance" -ErrorRecord $_ -Continue
            }


            # Step 3: Get path of setup.exe
            ###############################

            $findSetupParams = @{
                ComputerName   = $instance
                Credential     = $Credential
                Authentication = $Authentication
                Version        = $info.Version
                Path           = $Path
            }
            try {
                Write-Message -Level Verbose -Message 'Starting Find-SqlInstanceSetup @findSetupParams'
                $setupFile = Find-SqlInstanceSetup @findSetupParams
                Write-Message -Level Verbose -Message "Found setupFile $setupFile"
                $output.Installer = $setupFile
            } catch {
                Stop-Function -Message "Failed to enumerate files in $Path" -ErrorRecord $_ -Continue
            }

            if ($setupFile -eq $null) {
                Stop-Function -Message "Failed to enumerate files in $Path" -ErrorRecord $_ -Continue
            }


            # Step 4: Run setup.exe to uninstall instance
            #############################################

            $invokeProgramParams = @{
                ComputerName    = $instance
                Credential      = $Credential
                Authentication  = $Authentication
                Path            = $setupFile
                ArgumentList    = @('/ACTION=UNINSTALL', "/INSTANCENAME=$($instance.InstanceName)", '/FEATURES=SQLEngine', '/Q')
                Fallback        = $false
                EnableException = $true
            }
            try {
                Write-Message -Level Verbose -Message 'Starting Invoke-Program @invokeProgramParams'
                $setupResult = Invoke-Program @invokeProgramParams 
                Write-Message -Level Verbose -Message "Returned ExitCode $($setupResult.ExitCode)"
                $output.ExitCode = $setupResult.ExitCode
                # Get setup log summary contents
                try {
                    Write-Message -Level Verbose -Message 'Starting Get-SqlInstallSummary'
                    $summary = Get-SqlInstallSummary -ComputerName $instance -Credential $Credential -Version $info.Version
                    $output.ExitMessage = $summary.ExitMessage
                    $output.Log = $summary.Content
                    $output.LogFile = $summary.Path
                    $output.ConfigurationFile = $summary.ConfigurationFile
                } catch {
                    Write-Message -Level Warning -Message "Could not get the contents of the summary file from $($instance.ComputerName). Related properties will be empty" -ErrorRecord $_
                }
            } catch {
                Stop-Function -Message "Installation failed" -ErrorRecord $_
                $output.Notes += $_.Exception.Message
                $output
                continue
            }

            if ($setupResult.Successful) {
                $output.Successful = $true
            } else {
                $msg = "Installation failed with exit code $($setupResult.ExitCode). Expand 'ExitMessage' and 'Log' property to find more details."
                $output.Notes += $msg
                Stop-Function -Message $msg
                $output
                continue
            }


            # Step 5: Remove instance path
            ##############################

            $removeFolderScript = {
                param($InstancePath)
                Remove-Item -Path $InstancePath -Recurse -Force
            }
            $removeFolderParams = @{
                ComputerName   = $instance
                Credential     = $Credential
                Authentication = $Authentication
                ScriptBlock    = $removeFolderScript
                ArgumentList   = $info.InstancePath
                ErrorAction    = 'Stop'
                Raw            = $true
            }
            try {
                Invoke-Command2 @removeFolderParams
            } catch {
                Stop-Function -Message "Failed to remove folder $($info.InstancePath)" -ErrorRecord $_ -Continue
            }


            # Step 6: Test for reboot
            #########################

            try {
                # I use  -PendingRename to get informed about pending file rename operations
                $restartNeeded = Test-PendingReboot -ComputerName $instance -Credential $Credential -PendingRename
            } catch {
                $restartNeeded = $false
                Stop-Function -Message "Failed to get reboot status from $($instance.ComputerName)" -ErrorRecord $_
            }
            if ($setupResult.ExitCode -eq 3010 -or $restartNeeded) {
                if ($Restart) {
                    # Restart the computer
                    $restartMsg = "Restarting computer $($instance.ComputerName) and waiting for it to come back online"
                    Write-ProgressHelper -ExcludePercent -Activity $activity -Message $restartMsg
                    Write-Message -Level Verbose -Message $restartMsg
                    try {
                        $null = Restart-Computer @restartParams
                        $output.Restarted = $true
                    } catch {
                        Stop-Function -Message "Failed to restart computer $($instance.ComputerName)" -ErrorRecord $_ -FunctionName Remove-DbaInstance
                        return $output
                    }
                } else {
                    $output.Notes += "Restart is required for computer $($instance.ComputerName) to finish the installation of Sql Server version $Version"
                }
            }

            $output | Select-DefaultView -Property ComputerName, InstanceName, Version, InstancePath, Successful, Restarted, Installer, ExitCode, Notes
            Write-Progress -Activity $activity -Completed

            Write-Message -Level Verbose -Message "Finished $instance"

        } # foreach ($instance in $SqlInstance)

        $VerbosePreference = 'SilentlyContinue'

    } @{SqlInstance = $SqlInstance ; Credential = $Credential ; Authentication = $Authentication ; Path = $Path ; Restart = $Restart ; EnableException = $EnableException}
}
