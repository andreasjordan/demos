$ErrorActionPreference = 'Stop'

# Change execution policy to remote signed if needed:
#####################################################

$currentPolicy = Get-ExecutionPolicy
if ($currentPolicy -ne 'RemoteSigned') {
    Write-Warning -Message "ExecutionPolicy is currently $currentPolicy, so we change it to RemoteSigned"
    Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Force
}

<# Just for information:

Get-ExecutionPolicy -List

        Scope ExecutionPolicy
        ----- ---------------
MachinePolicy       Undefined
   UserPolicy       Undefined
      Process       Undefined
  CurrentUser       Undefined
 LocalMachine    RemoteSigned

#>


# Enable Hyper-V (restart needed):
##################################

$currentHyperV = Get-WindowsOptionalFeature -FeatureName Microsoft-Hyper-V -Online
if ($currentHyperV.State -ne 'Enabled') {
    Write-Warning -Message "State of Microsoft-Hyper-V is currently $($currentHyperV.State), so we enable it and restart the computer"
    Enable-WindowsOptionalFeature -FeatureName Microsoft-Hyper-V -All -Online -NoRestart
    Restart-Computer -Force
}
