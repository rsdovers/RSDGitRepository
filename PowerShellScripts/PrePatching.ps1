<#
Parts of this script is exactly what I was looking for to help make it easy to navigate
the SQLSERVER:\ path. The -path parameter is on each of the AG cmdlets used to failover
and test the AG, Replica, and databases. Also, the way of swaping the blank instance name
to DEFAULT is in here, and I like the way that it uses varables to simplify the long path
names. The script is missing Test-SqlDatabaseReplicas, but that would be easy to add using
$Path = "SQLSERVER:\Sql\$Name\$InstanceName\AvailabilityGroups\$AgName\DatabaseReplicaStates"
#>

<##
Find an availability group's primary server
set $ServerName to any node that's part of the AG that you're interested in
 
$ServerName = 'SQL01'
 
[reflection.assembly]::LoadWithPartialName("Microsoft.SqlServer.Smo") | out-null
$svr = New-Object ('Microsoft.SqlServer.Management.Smo.Server') $ServerName;
$svr.ConnectionContext.StatementTimeout = 0;
 
foreach ($AvailabilityGroup in $svr.AvailabilityGroups)
{
    Write-Host "$($AvailabilityGroup.Name) : $($AvailabilityGroup.PrimaryReplicaServerName)"
}
#>
$server='your servername'

$srv = New-Object Microsoft.SqlServer.Management.Smo.Server $Server
              
        ## Dashboard only available on Primary Replica
        $Ags = $srv.AvailabilityGroups

        if ($AGs.PrimaryReplicaServerName -ne $Server) {
            $srv.ConnectionContext.Disconnect()
                       
            $AGName = $AGs.Name
       
            $srv = New-Object Microsoft.SqlServer.Management.Smo.Server $AGs.PrimaryReplicaServerName
            $Ags = $srv.AvailabilityGroups[$AGName]
        }

        $Name = $srv.Name
        if ($srv.InstanceName -eq '') {
            $InstanceName = 'DEFAULT'
        }
        else {
            $InstanceName = $srv.InstanceName
        }
                             
        $Path = "SQLSERVER:\Sql\$Name\$InstanceName\AvailabilityGroups\$AgName"
              
        $timeout = new-timespan -Minutes 10
        $sw = [diagnostics.stopwatch]::StartNew()

        while ($sw.elapsed -lt $timeout) {
            if ( (Test-SqlAvailabilityGroup -Path $path -ErrorAction SilentlyContinue).HealthState  -eq "Healthy") {
               
                write-verbose "Availabilty Group is reporting Healty"
                $TimedOut = $false
                $AgState= "Healthy"
                break
            }
            else {
                write-warning "Availabilty Group is not reporting Healty... retrying for max 10 minutes"
               
            }
         
            start-sleep -seconds 5
            $TimedOut = $true
        }
        if($TimedOut){
        $AgState= "UnHealthy"
        }

        $AGState
        $srv.ConnectionContext.Disconnect()