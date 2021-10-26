# Some configuration options. Just play with them and see how they work.
$newLine = "`r`n"
$noNewLineForOneFinding = $true
$noNewLineForOneDatabase = $true

# I love dbatools, so I use Invoke-DbaQuery to get the data. But Invoke-Sqlcmd would probably work as well.
$sqlInstance = 'sql01'
$spBlitzOutput = Invoke-DbaQuery -SqlInstance $sqlInstance -Query 'sp_Blitz @CheckServerInfo = 1'

# We filter the data the same way "sp_Blitz @OutputType = 'markdown'" would do, but still include the security findings. You can adjust this if needed.
$spBlitzOutput = $spBlitzOutput | Where-Object -FilterScript { $_.Priority -gt 0 -and $_.Priority -lt 255 -and $_.FindingsGroup -ne [DBNull]::Value -and $_.Finding -ne [DBNull]::Value }

# Let's start with a blank output string.
$output = ''

# First we group by both Priority and FindingsGroup and loop through the groups.
$groupsForFindingsGroup = $spBlitzOutput | Group-Object Priority, FindingsGroup
foreach ($groupForFindingsGroup in $groupsForFindingsGroup) {
    # The name of the group contains both Priority and FindingsGroup in one string, 
    # so we have to split and rearrange.
    ($priority, $findingsGroup) = $groupForFindingsGroup.Name -split ', '
    $output += '**Priority ' + $priority + ': ' + $findingsGroup + '**' + $newLine

    # Second we group on Finding and loop through the groups.
    $groupsForFinding = $groupForFindingsGroup.Group | Group-Object Finding
    foreach ($groupForFinding in $groupsForFinding) {
        # We just output the Finding as an item in a bulleted list.
        $finding = $groupForFinding.Name
        $output += '- ' + $finding + $newLine

        # Third we group on Details and loop through the groups.
        # Here it is important to get an array of groups, even if we have one group, 
        # because we need the Count as number of groups in the array 
        # and not the number of members in the group.
        # So we start with an empty array and add the groups to it. 
        # (Declaring the variable would be another way, just go for it if you like.)
        $groupsForDetails = @( )
        $groupsForDetails += $groupForFinding.Group | Group-Object Details
        $groupsForDetailsCount = $groupsForDetails.Count
        foreach ($groupForDetails in $groupsForDetails) {
            $details = $groupForDetails.Name
            # Depending on what you have configured, if we only have one Details group, 
            # we may just append the Details to the previous line with the Finding.
            # Otherwise we output the Details as a bulleted list one level below the Finding.
            if ($groupsForDetailsCount -eq 1 -and $noNewLineForOneFinding) {
                $output = $output.TrimEnd($newLine) + ': ' + $details + $newLine
            } else {
                $output += '  - ' + $details + $newLine
            }

            # Forth we group on DatabaseName and loop through the groups.
            # Again we need the number of groups to be able to append the previous line.
            $groupsForDatabaseName = @( )
            $groupsForDatabaseName += $groupForDetails.Group | Group-Object DatabaseName | Where-Object Name
            $groupsForDatabaseNameCount = $groupsForDatabaseName.Count
            foreach ($groupForDatabaseName in $groupsForDatabaseName) {
                $databaseName = $groupForDatabaseName.Name
                if ($groupsForDatabaseNameCount -eq 1 -and $noNewLineForOneDatabase) {
                    $output = $output.TrimEnd($newLine) + ' (' + $databaseName + ')' + $newLine
                } else {
                    $output += '    * ' + $databaseName + $newLine
                }
            }
        }
    }
    # To have an empty line between the different FindingsGroups, we need three empty lines.
    $output += $newLine + $newLine + $newLine
}
# Just trim the empty lines at the end and copy the output to the clipboard.
$output = $output.TrimEnd($newLine)
$output | Set-Clipboard

# Now just paste the clipboard into you favorite markdown editor.
# If you don't have one yet, have a look at Typora or just use Notepad or Notepad++.
