[CmdletBinding()]
param (
    [string]$AutoLabConfiguration = 'SqlServerLab',
    [int]$MinutesToWaitForFirstPester = 15,
    [int]$MinutesToWaitForNextPester = 5,
    [int]$MinutesToWaitForLabSetup = 60,
    [int]$MinutesToWaitForUpdateJobs = 5,
    [switch]$InstallOnly,
    [switch]$PatchOnly
)

function Write-LocalWarning {
    param (
        [string]$Message
    )
    Write-Warning -Message ('{0}: {1}' -f (Get-Date), $Message)
}

function Write-LocalHost {
    param (
        [string]$Message,
        [string]$ForegroundColor = 'Yellow'
    )
    Microsoft.PowerShell.Utility\Write-Host -Object ('{0}: {1}' -f (Get-Date), $Message) -ForegroundColor $ForegroundColor
}

function Write-LocalVerbose {
    param (
        [string]$Message
    )
    Write-Verbose -Message ('{0}: {1}' -f (Get-Date), $Message)
}

$ErrorActionPreference = 'Stop'
Write-LocalHost -Message 'Starting'
Import-Module -Name PSAutoLab

Push-Location -Path ((Get-PSAutoLabSetting).AutoLab + '\Configurations\' + $AutoLabConfiguration)

if ( -not $PatchOnly ) {
    Write-LocalHost -Message 'Starting Setup-Lab'
    Setup-Lab -UseLocalTimeZone -NoMessages | Out-Null
    Enable-Internet -NoMessages

    Write-LocalHost -Message 'Starting Run-Lab'
    Run-Lab -NoMessages

    Write-LocalHost -Message 'Waiting for completion of lab configuration'
    $waitUntil = (Get-Date).AddMinutes($MinutesToWaitForLabSetup)
    Start-Sleep -Seconds (($MinutesToWaitForFirstPester - $MinutesToWaitForNextPester) * 60)
    while ( $true ) {
        Start-Sleep -Seconds ($MinutesToWaitForNextPester * 60)
        Write-LocalVerbose -Message 'Starting Pester'
        $pesterResults = Invoke-Pester -Script .\VMValidate.test.ps1 -Show None -PassThru
        if ( $pesterResults.FailedCount -eq 0 ) { 
            Write-LocalHost -Message 'All Pester tests sucessful'
            break 
        } else {
            Write-LocalHost -Message ('{0} Pester test(s) failed' -f $pesterResults.FailedCount)
        }
        Write-LocalVerbose -Message 'Failed Pester tests:'
        foreach ( $test in $pesterResults.TestResult.Where({$_.Passed -eq $false}) ) {
            Write-LocalVerbose -Message $test.Name
            # Should allow a PSSession but got error: Die Anmeldeinformationen sind ungültig.
            # Background: Sometimes a VM has problems joining the domain and only a hard reboot can solve the problem
            if ( $test.Name -match 'Should allow a PSSession but got error' ) {
                $vm = $test.Describe
                Write-LocalHost -Message "Restarting VM: $vm"
                Stop-VM -Name $vm -TurnOff -WarningAction SilentlyContinue
                Start-VM -Name $vm        
            }
        }
        if ( (Get-Date) -gt $waitUntil ) {
            Write-LocalWarning -Message 'Completion of lab configuration has not finished in time, stopping now'
            return
        }
    }
}


if ( -not $InstallOnly ) {
    while ( $true ) {
        Write-LocalHost -Message 'Starting Update-Lab -AsJob'
        Update-Lab -AsJob | Out-Null

        $jobResults = @()
        while ( $true ) {
            Start-Sleep -Seconds ($MinutesToWaitForUpdateJobs * 60)
            foreach ( $job in (Get-Job).Where({$_.Name -eq 'WUUpdate'}) ) {
                if ( $job.State -notin 'Running', 'Completed' ) {
                    Write-LocalWarning 'Problem with job:'
                    $job | Format-Table
                }
                if ( $job.HasMoreData ) {
                    try { 
                        $jobResults += Receive-Job -Job $job 6>&1 
                    } catch {
                        # Vom Hintergrundvorgang wurde ein Fehler mit der folgenden Meldung ausgegeben: "Der Hyper-V-Socket-Zielprozess wurde beendet.".
                        # Background: Sometimes WIN10 shuts down after installing an update
                        Write-LocalVerbose -Message ('Receiving failed: ' + $_)
                        Remove-Job -Job $job
                    }
                }
                if ( $job.State -eq 'Completed' ) {
                    Write-LocalVerbose -Message ('Job at {0} completed' -f $job.Location)
                    Remove-Job -Job $job
                }
            }
            if ( (Get-Job).Where({$_.Name -eq 'WUUpdate'}).Count -eq 0 ) { 
                Write-LocalHost -Message 'All jobs finnished'
                break 
            } else {
                Write-LocalVerbose -Message ('VMs with running jobs: ' + ((Get-Job).Where({$_.Name -eq 'WUUpdate'}).Location -join ' '))
            }
        }
        $newUpdates = $jobResults | Select-String -Pattern 'Found \d+ updates to install on ' | Select-String -NotMatch -Pattern 'Found 0 updates'

        if ( $null -eq $newUpdates ) {
            Write-LocalHost -Message 'All updates installed'
            break
        }

        Write-LocalVerbose -Message 'Shutdown Lab'
        Shutdown-Lab -NoMessages

        Write-LocalVerbose -Message 'Starting Lab'
        Run-Lab -NoMessages

        Write-LocalVerbose -Message 'Waiting to finish updates'
        Start-Sleep -Seconds ($MinutesToWaitForUpdateJobs * 60)
    }
}

Write-LocalHost -Message 'Finished'
