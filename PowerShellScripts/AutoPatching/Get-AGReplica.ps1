<#The purpose of this function is to tell which instance is the
primary replica, and which is the secondary. Since the switch AG cmdlet
must be executed from the secondary node, and the test cmdlets should be
executed on the primary replica to get accurate results, this function
will allow us to determine the primary and secondary instances.
#>

$server = [System.Net.Dns]::GetHostByName($env:computerName)

$srv = New-Object Microsoft.SqlServer.Management.Smo.Server $Server 

## Dashboard only available on Primary Replica 

$Ags = $srv.AvailabilityGroups
<#There is a LocalReplicaRole property in the AvailabilityGroups class.
Below are the values that are returned:
Primary	    1	The replica is the current primary in the availability group
Resolving	0	The replica is in a resolving state
Secondary	2	The replica is a secondary in the availability group
https://docs.microsoft.com/en-us/dotnet/api/microsoft.sqlserver.management.smo.availabilitygroup.localreplicarole?view=sql-smo-160#microsoft-sqlserver-management-smo-availabilitygroup-localreplicarole
#>

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

    if ( (Test-SqlAvailabilityGroup -Path $path -ErrorAction SilentlyContinue).HealthState -eq "Healthy") { 

        write-verbose "Availabilty Group is reporting Healty" 

        $TimedOut = $false 

        $AgState = "Healthy" 

        break 

    } 

    else { 

        write-warning "Availabilty Group is not reporting Healty... retrying for max 10 minutes" 

    } 

    start-sleep -seconds 5 

    $TimedOut = $true 

} 

if ($TimedOut) { 

    $AgState = "UnHealthy" 

} 

$AGState 

$srv.ConnectionContext.Disconnect() 