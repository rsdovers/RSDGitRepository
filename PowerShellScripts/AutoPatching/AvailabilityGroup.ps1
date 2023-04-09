if (!(Get-Module -ListAvailable -Name "SQLPS")) {
    Write-Host -BackgroundColor Red -ForegroundColor White "Module Invoke-Sqlcmd is not loaded"
    exit
}

#Function to execute queries (depending on if the user will be using specific credentials or not)
function Execute-Query([string]$query,[string]$database,[string]$instance,[int]$trusted,[string]$username,[string]$password){
    if($trusted -eq 1){
        try{ 
            Invoke-Sqlcmd -Query $query -Database $database -ServerInstance $instance -ErrorAction Stop -ConnectionTimeout 5 -QueryTimeout 0      
        }
        catch{
            Write-Host -BackgroundColor Red -ForegroundColor White $_
            exit
        }
    }
    else{
        try{
            Invoke-Sqlcmd -Query $query -Database $database -ServerInstance $instance -Username $username -Password $password -ErrorAction Stop -ConnectionTimeout 5 -QueryTimeout 0
        }
         catch{
            Write-Host -BackgroundColor Red -ForegroundColor White $_
            exit
        }
    }
}

#Function to return the SQL Server version of a particular replica
function Get-SQLVersion([string]$replica,[int]$trusted,[string]$login,[string]$password){
    return $(Execute-Query 'SELECT SUBSTRING(@@VERSION,22,5) AS version' "master" $replica $trusted $login $password).version
}

#Function to return the name of the PrimaryReplica
function Get-PrimaryReplica([string]$replica,[string]$availabilityGroup,[int]$trusted,[string]$login,[string]$password){
    $agQuery = "
    SELECT ags.primary_replica AS name
    FROM sys.dm_hadr_availability_group_states ags
    JOIN sys.availability_groups ag ON ags.group_id = ag.group_id
    WHERE ag.name = '$($availabilityGroup)'
    "
    return $(Execute-Query $agQuery "master" $replica $trusted $login $password).name
}

#Function to return the information of the AvailabilityGroup to the user
function Get-AGInformation([string]$replica,[string]$availabilityGroup,[int]$trusted,[string]$login,[string]$password){
    
    $agQuery = "
    SELECT             
            cs.replica_server_name AS 'Replica'
           ,rs.role_desc AS 'Role'
           ,REPLACE(ar.availability_mode_desc,'_',' ') AS 'Availability Mode'
           ,ar.failover_mode_desc AS 'FailoverMode'
           ,ar.primary_role_allow_connections_desc AS 'Primary Connections'
           ,ar.secondary_role_allow_connections_desc AS 'Secondary Connections'
    "
    if($(Get-SQLVersion $replica $trusted $login $password) -lt 2016){
    $agQuery += "
           ,'N/A' AS 'Seeding Mode'
    "
    }else{
    $agQuery += "
           ,ar.seeding_mode_desc AS 'Seeding Mode'
    "
    }
    $agQuery += "
           ,CASE WHEN al.dns_name IS NULL THEN 'N/A' ELSE CONCAT(al.dns_name,',',al.port) END AS 'Listener'
           ,(SELECT cluster_name FROM sys.dm_hadr_cluster) AS 'WSFC'
        FROM sys.availability_groups ag 
        JOIN sys.dm_hadr_availability_group_states ags ON ag.group_id = ags.group_id
        JOIN sys.dm_hadr_availability_replica_cluster_states cs ON ags.group_id = cs.group_id 
        JOIN sys.availability_replicas ar ON ar.replica_id = cs.replica_id 
        JOIN sys.dm_hadr_availability_replica_states rs  ON rs.replica_id = cs.replica_id 
        LEFT JOIN sys.availability_group_listeners al ON ar.group_id = al.group_id
        WHERE ag.name = '$($availabilityGroup)'
    "
    $agQueryResult = Execute-Query $agQuery "master" $replica $trusted $login $password

    #Present the information in a nice way
    for($i=0; $i -lt $availabilityGroup.length+16; $i++){
    Write-Host -NoNewline "#"
    }
    Write-Host ""
    Write-Host "# Group Name: $($availabilityGroup) #"  
    for($i=0; $i -lt $availabilityGroup.length+16; $i++){ 
        Write-Host -NoNewline "#"
    }
    $agQueryResult | Format-Table -AutoSize
    
    return
}

#Function to return the monitoring information of the Availability Group
function Monitor-AvailabilityGroup([string]$replica,[string]$role,[string]$availabilityGroup,[int]$trusted,[string]$login,[string]$password){
    if($role -eq "PRIMARY"){
        $monitoringQuery = "
        SELECT instance_name, cntr_value 
        INTO #Logflushes1
        FROM sys.dm_os_performance_counters 
        WHERE object_name  LIKE '%:Databases%' 
        AND counter_name = 'Log Bytes Flushed/sec';

        WAITFOR DELAY '00:00:01';

        SELECT instance_name, cntr_value 
        INTO #Logflushes2
        FROM sys.dm_os_performance_counters 
        WHERE object_name  LIKE '%:Databases%' 
        AND counter_name = 'Log Bytes Flushed/sec';

        SELECT 
                 db_name(drs.database_id) AS 'Database'
                ,(SELECT CONVERT(DECIMAL(10,2),(mf.size * 8.0) / 1024.0) FROM sys.master_files mf WHERE mf.type = 0 AND mf.database_id = drs.database_id) AS 'MDF Size(MB)'
                ,(SELECT CONVERT(DECIMAL(10,2),(mf.size * 8.0) / 1024.0) FROM sys.master_files mf WHERE mf.type = 1 AND mf.database_id = drs.database_id) AS 'LDF Size(MB)'
                ,drs.synchronization_state_desc AS 'State'
                ,drs.synchronization_health_desc 'Health Status'
                ,CONVERT(DECIMAL(10,2), log_flushes / 1024.0 / 1024.0) AS 'Log Flushed'
        FROM sys.availability_groups ag
        JOIN sys.dm_hadr_availability_group_states ags ON ag.group_id = ags.group_id
        JOIN sys.dm_hadr_availability_replica_cluster_states cs ON ags.group_id = cs.group_id 
        JOIN sys.dm_hadr_availability_replica_states rs  ON rs.replica_id = cs.replica_id 
        JOIN sys.dm_hadr_database_replica_states drs ON rs.replica_id=drs.replica_id
        JOIN (SELECT l1.instance_name, l2.cntr_value - l1.cntr_value log_flushes
        FROM #Logflushes1 l1
        JOIN #Logflushes2 l2 ON l2.instance_name = l1.instance_name
             ) log_flushes ON log_flushes.instance_name = DB_NAME(drs.database_id) 
        WHERE rs.role_desc = 'PRIMARY' AND ag.name = '$($availabilityGroup)';

        DROP TABLE #Logflushes1;
        DROP TABLE #Logflushes2;
        "       
    }
    if($role -eq "SECONDARY"){
        $monitoringQuery = "
        SELECT instance_name, cntr_value 
        INTO #redo1
        FROM sys.dm_os_performance_counters
        WHERE object_name  LIKE '%:Database Replica%' 
        AND counter_name = 'Redone Bytes/sec';

        SELECT instance_name, cntr_value 
        INTO #send1
        FROM sys.dm_os_performance_counters 
        WHERE object_name  LIKE '%:Database Replica%' 
        AND counter_name = 'Log Bytes Received/sec';

        WAITFOR DELAY '00:00:01';

        SELECT instance_name, cntr_value 
        INTO #redo2
        FROM sys.dm_os_performance_counters
        WHERE object_name  LIKE '%:Database Replica%' 
        AND counter_name = 'Redone Bytes/sec';

        SELECT instance_name, cntr_value 
        INTO #send2
        FROM sys.dm_os_performance_counters 
        WHERE object_name  LIKE '%:Database Replica%' 
        AND counter_name = 'Log Bytes Received/sec';

        SELECT
            DB_NAME(rs.database_id) AS 'Database'
            ,drs.synchronization_state_desc AS 'State'
            ,drs.synchronization_health_desc 'Health'     
            ,CONVERT(DECIMAL(10,2), rs.log_send_queue_size / 1024.0) AS 'Log Send Queue Size'
            ,CONVERT(DECIMAL(10,2), send_rate / 1024.0 / 1024.0) AS 'Log Send Rate'
            ,CONVERT(DECIMAL(10,2), rs.log_send_queue_size / CASE WHEN send_rate = 0 THEN 1 ELSE send_rate / 1024.0 END) AS 'Send Latency'
            ,CONVERT(DECIMAL(10,2), rs.redo_queue_size / 1024.0) AS 'Redo Queue Size'
            ,CONVERT(DECIMAL(10,2), redo_rate.redo_rate / 1024.0 / 1024.0) AS 'Redo Rate' 
            ,CONVERT(DECIMAL(10,2), rs.redo_queue_size / CASE WHEN redo_rate.redo_rate = 0 THEN 1 ELSE redo_rate.redo_rate / 1024.0 END) AS 'Redo Latency'
        FROM sys.dm_hadr_database_replica_states rs
        JOIN sys.availability_replicas r ON r.group_id = rs.group_id AND r.replica_id = rs.replica_id
        JOIN sys.dm_hadr_database_replica_states drs ON rs.replica_id = drs.replica_id
        JOIN (SELECT l1.instance_name, l2.cntr_value - l1.cntr_value redo_rate
              FROM #redo1 l1
              JOIN #redo2 l2 ON l2.instance_name = l1.instance_name
             ) redo_rate ON redo_rate.instance_name = DB_NAME(rs.database_id)
        JOIN (SELECT l1.instance_name, l2.cntr_value - l1.cntr_value send_rate
              FROM #send1 l1
              JOIN #send2 l2 ON l2.instance_name = l1.instance_name
             ) send_rate ON send_rate.instance_name = DB_NAME(rs.database_id);

        DROP TABLE #send1;
        DROP TABLE #send2;
        DROP TABLE #redo1;
        DROP TABLE #redo2;
        "
    }
     
    return Execute-Query $monitoringQuery "master" $replica $trusted $login $password 
}

function Get-AGState([string]$availabilityGroup,[string]$primaryReplica,[int]$trusted,[string]$login,[string]$password){
    $agHealthQuery = "
    SELECT CASE WHEN ags.synchronization_health_desc = 'HEALTHY' THEN 1 ELSE 0 END AS health
    FROM sys.dm_hadr_availability_group_states ags
    JOIN sys.availability_groups ag ON ag.group_id = ags.group_id
    WHERE ag.name = '$($availabilityGroup)'
    "
    return $(Execute-Query $agHealthQuery "master" $primaryReplica $trusted $login $password)[0]
}

$replica    = Read-Host -Prompt 'Enter either the name of the instance acting as Primary Replica or the DB Listener'
#$replica = "DB2"
$availabilityGroup = Read-Host -Prompt 'Enter the name of the AvailabilityGroup you want to choose'
#$availabilityGroup = "TestAG"

$loginChoices = [System.Management.Automation.Host.ChoiceDescription[]] @("&Trusted", "&Windows Login", "&SQL Login")
$loginChoice = $host.UI.PromptForChoice('', 'Choose login type for instance', $loginChoices, 0)
switch($loginChoice)
{
    1 { 
        $login          = Read-Host -Prompt "Enter Windows Login"
        $securePassword = Read-Host -Prompt "Enter Password" -AsSecureString
        $password       = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePassword))
      }
    2 { 
        $login          = Read-Host -Prompt "Enter SQL Login"
        $securePassword = Read-Host -Prompt "Enter Password" -AsSecureString
        $password       = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePassword))
      }
}

#Attempt to connect to the SQL Server instance using the information provided by the user
try{
    $agQuery = "
    SELECT ag.name, ar.replica_server_name AS replica, agrs.role_desc AS role
    FROM sys.dm_hadr_availability_replica_states agrs
    JOIN sys.availability_groups ag ON agrs.group_id = ag.group_id
    JOIN sys.availability_replicas ar ON agrs.replica_id = ar.replica_id
    WHERE agrs.is_local = 1 AND ag.name IS NOT NULL AND ar.replica_server_name IS NOT NULL AND agrs.role_desc IS NOT NULL
    "

    switch($loginChoice){
        0       {$agQueryResult = Execute-Query $agQuery "master" $replica 1 "" ""}
        default {$agQueryResult = Execute-Query $agQuery "master" $replica 0 $login $password}   
    }     
}
catch{
    Write-Host -BackgroundColor Red -ForegroundColor White $_
    exit
}

#Act accordingly upon the potential outcome from $agQuery
#Maybe an AvailabilityGroup with the specified name doesn't exist
#Maybe the replica provided is a Secondary Replica, so the Primary Replica would have to be fetched intentionally
if($agQueryResult.name -ne $availabilityGroup){
    Write-Host -BackgroundColor Red -ForegroundColor White "The AvailabilityGroup [$($availabilityGroup)] doesn't exist."
    exit
}
if($agQueryResult.role -ne 'PRIMARY'){
    switch($loginChoice){
        0       {$primaryReplica = Get-PrimaryReplica $replica $availabilityGroup 1 "" ""}
        default {$primaryReplica = Get-PrimaryReplica $replica $availabilityGroup 0 $login $password}
    }
}else{
    $primaryReplica = $replica
}

#Present information about the AvailabilityGroup to the user
Write-Host ""
switch($loginChoice){
    0       {Get-AGInformation $primaryReplica $availabilityGroup 1 "" ""}
    default {Get-AGInformation $primaryReplica $availabilityGroup 0 $login $password}
}

#Ask the user which action he wants to perform for the AvailabilityGroup
$availabilityGroupChoices = [System.Management.Automation.Host.ChoiceDescription[]] @("&Monitor", "&Failover")
$availabilityGroupChoice  = $host.UI.PromptForChoice('', 'Choose the action you want to perform for your AvailabilityGroup', $availabilityGroupChoices, 0)

#If the user chooses "Monitor", then proceed
switch($availabilityGroupChoice){
    0{
        Write-Host " _______  _______  _       __________________ _______  _______ _________ _        _______ "
        Write-Host "(       )(  ___  )( (    /|\__   __/\__   __/(  ___  )(  ____ )\__   __/( (    /|(  ____ \"
        Write-Host "| () () || (   ) ||  \  ( |   ) (      ) (   | (   ) || (    )|   ) (   |  \  ( || (    \/"
        Write-Host "| || || || |   | ||   \ | |   | |      | |   | |   | || (____)|   | |   |   \ | || |      "
        Write-Host "| |(_)| || |   | || (\ \) |   | |      | |   | |   | ||     __)   | |   | (\ \) || | ____ "
        Write-Host "| |   | || |   | || | \   |   | |      | |   | |   | || (\ (      | |   | | \   || | \_  )"
        Write-Host "| )   ( || (___) || )  \  |___) (___   | |   | (___) || ) \ \_____) (___| )  \  || (___) |"
        Write-Host "|/     \|(_______)|/    )_)\_______/   )_(   (_______)|/   \__/\_______/|/    )_)(_______)"

        do{                                                                                          
            Write-Host ""
            $agReplicasQuery = "
            SELECT  cs.replica_server_name AS 'Replica',
                    rs.role_desc AS 'Role'
            FROM sys.availability_groups ag 
            JOIN sys.dm_hadr_availability_group_states ags ON ag.group_id = ags.group_id
            JOIN sys.dm_hadr_availability_replica_cluster_states cs ON ags.group_id = cs.group_id 
            JOIN sys.availability_replicas ar ON ar.replica_id = cs.replica_id 
            JOIN sys.dm_hadr_availability_replica_states rs  ON rs.replica_id = cs.replica_id 
            LEFT JOIN sys.availability_group_listeners al ON ar.group_id = al.group_id
            WHERE ag.name = '$($availabilityGroup)'
            ORDER BY rs.role_desc
            "
            switch($loginChoice){
                0       {$agReplicas = Execute-Query $agReplicasQuery "master" $primaryReplica 1 "" ""}
                default {$agReplicas = Execute-Query $agReplicasQuery "master" $primaryReplica 0 $login $password}
            }

            foreach($agReplica in $agReplicas){
                if($agReplica.Role -eq "PRIMARY"){
                    $longestString = 
                    ("# Group Name     : $($availabiityGroup) #",
                     "# Primary Replica: $($agReplica.Replica) #"| Measure-Object -Maximum -Property Length).Maximum + 1

                    for($i=0; $i -lt $longestString+2; $i++){
                        Write-Host -NoNewline "#"
                    }
                    Write-Host ""
                    Write-Host -NoNewline "# Group Name     : $($availabilityGroup)"
                    for($i=0; $i -lt $longestString - $availabilityGroup.Length - 18; $i++){Write-Host -NoNewline " "}
                    Write-Host "#"  
                    Write-Host -NoNewline "# Primary Replica: $($agReplica.Replica)"
                    for($i=0; $i -lt $longestString - $availabilityGroup.Length - 15; $i++){Write-Host -NoNewline " "}
                    Write-Host "#"
                    for($i=0; $i -lt $longestString+2; $i++){
                        Write-Host -NoNewline "#"
                    }
                }
                if($agReplica.Role -eq "SECONDARY"){
                    $longestString = 
                    ("# Group Name       : $($availabiityGroup) #",
                     "# Secondary Replica: $($agReplica.Replica) #"| Measure-Object -Maximum -Property Length).Maximum+1

                    for($i=0; $i -lt $longestString+2; $i++){
                        Write-Host -NoNewline "#"
                    }
                    Write-Host ""
                    Write-Host -NoNewline "# Group Name       : $($availabilityGroup)"
                    for($i=0; $i -lt $longestString - $availabilityGroup.Length - 20; $i++){Write-Host -NoNewline " "}
                    Write-Host "#"  
                    Write-Host -NoNewline "# Secondary Replica: $($agReplica.Replica)"
                    for($i=0; $i -lt $longestString - $availabilityGroup.Length - 17; $i++){Write-Host -NoNewline " "}
                    Write-Host "#"
                    for($i=0; $i -lt $longestString+2; $i++){
                        Write-Host -NoNewline "#"
                    }        
                }

                switch($loginChoice){
                    0       {$(Monitor-AvailabilityGroup $agReplica.Replica $agReplica.Role $availabilityGroup 1 "" "") | Format-Table -AutoSize}
                    default {$(Monitor-AvailabilityGroup $agReplica.Replica $agReplica.Role $availabilityGroup 0 $login $password) | Format-Table -AutoSize}
                }
            }
            Write-Host "###################################################################################################################"
            Write-Host ""
            Start-Sleep -s 5
        } while ($true)
    }

    1{
        $secondaryReplicasArray = @()
        Write-Host " _______  _______ _________ _        _______           _______  _______"
        Write-Host "(  ____ \(  ___  )\__   __/( \      (  ___  )|\     /|(  ____ \(  ____ )"
        Write-Host "| (    \/| (   ) |   ) (   | (      | (   ) || )   ( || (    \/| (    )|"
        Write-Host "| (__    | (___) |   | |   | |      | |   | || |   | || (__    | (____)|"
        Write-Host "|  __)   |  ___  |   | |   | |      | |   | |( (   ) )|  __)   |     __)"
        Write-Host "| (      | (   ) |   | |   | |      | |   | | \ \_/ / | (      | (\ (   "
        Write-Host "| )      | )   ( |___) (___| (____/\| (___) |  \   /  | (____/\| ) \ \__"
        Write-Host "|/       |/     \|\_______/(_______/(_______)   \_/   (_______/|/   \__/"
        Write-Host ""                                                                
        
        $agDatabasesQuery = "
        SELECT adc.database_name AS DBName
        FROM sys.availability_databases_cluster adc
        JOIN sys.availability_groups ag ON ag.group_id = adc.group_id
        WHERE ag.name = '$($availabilityGroup)'
        "
        switch($loginChoice){
            0      {$agDatabases = Execute-Query $agDatabasesQuery "master" $primaryReplica 1 "" ""}
            default{$agDatabases = Execute-Query $agDatabasesQuery "master" $primaryReplica 0 $login $password}
        }

        $agSecondaryReplicasQuery = "
        SELECT  cs.replica_server_name AS 'Replica',
                rs.role_desc AS 'Role'
        FROM sys.availability_groups ag 
        JOIN sys.dm_hadr_availability_group_states ags ON ag.group_id = ags.group_id
        JOIN sys.dm_hadr_availability_replica_cluster_states cs ON ags.group_id = cs.group_id 
        JOIN sys.availability_replicas ar ON ar.replica_id = cs.replica_id 
        JOIN sys.dm_hadr_availability_replica_states rs  ON rs.replica_id = cs.replica_id 
        LEFT JOIN sys.availability_group_listeners al ON ar.group_id = al.group_id
        WHERE ag.name = '$($availabilityGroup)' AND rs.role_desc = 'SECONDARY'
        "
        switch($loginChoice){
            0      {$agSecondaryReplicas = Execute-Query $agSecondaryReplicasQuery "master" $primaryReplica 1 "" ""}
            default{$agSecondaryReplicas = Execute-Query $agSecondaryReplicasQuery "master" $primaryReplica 0 $login $password}
        }
        foreach($agSecondaryReplica in $agSecondaryReplicas){
            $secondaryReplicasArray += $agSecondaryReplica.Replica
        }        
        $replicaChoices = [System.Management.Automation.Host.ChoiceDescription[]] $secondaryReplicasArray
        $replicaChoice  = $host.UI.PromptForChoice('', 'Choose your target Secondary Replica to failover to', $replicaChoices, 0)

        $replicaAvailabilityModeQuery = "
        SELECT  ar.availability_mode_desc
        FROM sys.availability_groups ag 
        JOIN sys.dm_hadr_availability_replica_cluster_states cs ON ag.group_id = cs.group_id 
        JOIN sys.availability_replicas ar ON ar.replica_id = cs.replica_id 
        WHERE ag.name = '$($availabilityGroup)' AND cs.replica_server_name = '$($secondaryReplicasArray[$replicaChoice])'
        "
        switch($loginChoice){
            0      {$replicaAvailabilityModeResult = Execute-Query $replicaAvailabilityModeQuery "master" $secondaryReplicasArray[$replicaChoice] 1 "" ""}
            default{$replicaAvailabilityModeResult = Execute-Query $replicaAvailabilityModeQuery "master" $secondaryReplicasArray[$replicaChoice] 0 $login $password}
        }
        if($replicaAvailabilityModeResult[0] -eq "ASYNCHRONOUS_COMMIT"){
            $availabilityModeSwapChoices = [System.Management.Automation.Host.ChoiceDescription[]] @("&Yes", "&No")
            $availabilityModeSwapChoice  = $host.UI.PromptForChoice('', 'Attempt to change it to SYNCHRONOUS COMMIT?', $availabilityModeSwapChoices, 0)
            switch($availabilityModeSwapChoice){
                0{
                    $synchronousCommitChangeQuery = "
                    BEGIN TRY
                        ALTER AVAILABILITY GROUP [$($availabilityGroup)]
                        MODIFY REPLICA ON N'$($secondaryReplicasArray[$replicaChoice])' WITH (AVAILABILITY_MODE = SYNCHRONOUS_COMMIT)
                        
                        SELECT 1
                    END TRY
                    BEGIN CATCH
                        SELECT ERROR_MESSAGE()
                    END CATCH
                    "
                    switch($loginChoice){
                        0      {$synchronousCommitChangeResult = Execute-Query $synchronousCommitChangeQuery "master" $primaryReplica 1 "" ""}
                        default{$synchronousCommitChangeResult = Execute-Query $synchronousCommitChangeQuery "master" $primaryReplica 0 $login $password}
                    }
                   
                    if($synchronousCommitChangeResult[0] -eq 1){
                        Write-Host -BackgroundColor Green -ForegroundColor White "Replica $($secondaryReplicasArray[$replicaChoice]) is now using SYNCHRONOUS COMMIT"
                        Write-Host ""
                        Write-Host "Performing Failover..."
                        Write-Host ""
                        $failoverQuery = "
                        BEGIN TRY
                            ALTER AVAILABILITY GROUP [$($availabilityGroup)] FAILOVER
                            SELECT 1
                        END TRY
                        BEGIN CATCH
                            SELECT ERROR_MESSAGE()
                        END CATCH
                        "

                        #Wait until the Availability Group is in a HEALTHY state before proceeding with the failover
                        switch($loginChoice){
                            0{
                                do{
                                    Start-Sleep -s 5
                                }while($(Get-AGState $availabilityGroup $primaryReplica 1 "" "") -ne 1)
                            }
                            default{
                                do{
                                    Start-Sleep -s 5
                                }while($(Get-AGState $availabilityGroup $primaryReplica 0 $login $password) -ne 1)
                            }
                        }
                                                
                        switch($loginChoice){
                            0      {$failoverResult = Execute-Query $failoverQuery "master" $secondaryReplicasArray[$replicaChoice] 1 "" ""}
                            default{$failoverResult = Execute-Query $failoverQuery "master" $secondaryReplicasArray[$replicaChoice] 0 $login $password}
                        }
                        if($failoverResult[0] -eq 1){
                            Write-Host -BackgroundColor Green -ForegroundColor White "Failover performed successfully."
                            Write-Host ""
                            switch($loginChoice){
                                0       {Get-AGInformation $secondaryReplicasArray[$replicaChoice] $availabilityGroup 1 "" ""}
                                default {Get-AGInformation $secondaryReplicasArray[$replicaChoice] $availabilityGroup 0 $login $password}
                            }
                        }else{
                            Write-Host -BackgroundColor Red -ForegroundColor White "$($failoverResult[0])" 
                        }
                    }else{
                        Write-Host -BackgroundColor Red -ForegroundColor White "$($synchronousCommitChangeResult[0])"
                    }                                       
                }
                1{
                    $failoverProceedChoices = [System.Management.Automation.Host.ChoiceDescription[]] @("&Yes", "&No")
                    $failoverProceedChoice  = $host.UI.PromptForChoice('', 'Would you like to force a failover with potential data loss?', $failoverProceedChoices, 0)
                    switch($failoverProceedChoice){
                        0{
                            Write-Host "Performing Failover..."
                            Write-Host ""
                            $forceFailoverQuery = "
                            BEGIN TRY
                                ALTER AVAILABILITY GROUP [$($availabilityGroup)] FORCE_FAILOVER_ALLOW_DATA_LOSS
                                SELECT 1
                            END TRY
                            BEGIN CATCH
                                SELECT ERROR_MESSAGE()
                            END CATCH
                            "

                            #Wait until the Availability Group is in a HEALTHY state before proceeding with the failover
                            switch($loginChoice){
                                0{
                                    do{
                                        Start-Sleep -s 5
                                    }while($(Get-AGState $availabilityGroup $primaryReplica 1 "" "") -ne 1)
                                }
                                default{
                                    do{
                                        Start-Sleep -s 5
                                    }while($(Get-AGState $availabilityGroup $primaryReplica 0 $login $password) -ne 1)
                                }
                            }

                            switch($loginChoice){
                                0      {$forceFailoverResult = Execute-Query $forceFailoverQuery "master" $secondaryReplicasArray[$replicaChoice] 1 "" ""}
                                default{$forceFailoverResult = Execute-Query $forceFailoverQuery "master" $secondaryReplicasArray[$replicaChoice] 0 $login $password}
                            }
                            if($forceFailoverResult[0] -eq 1){
                                Write-Host -BackgroundColor Green -ForegroundColor White "Failover performed successfully!"
                                
                                #Wait 10s before resuming data movement in all secondary databases
                                Start-Sleep -s 10cls
                                                                

                                $agSecondaryReplicasQuery = "
                                SELECT  cs.replica_server_name AS 'Replica',
                                        rs.role_desc AS 'Role'
                                FROM sys.availability_groups ag 
                                JOIN sys.dm_hadr_availability_group_states ags ON ag.group_id = ags.group_id
                                JOIN sys.dm_hadr_availability_replica_cluster_states cs ON ags.group_id = cs.group_id 
                                JOIN sys.availability_replicas ar ON ar.replica_id = cs.replica_id 
                                JOIN sys.dm_hadr_availability_replica_states rs  ON rs.replica_id = cs.replica_id 
                                LEFT JOIN sys.availability_group_listeners al ON ar.group_id = al.group_id
                                WHERE ag.name = '$($availabilityGroup)' AND rs.role_desc <> 'RESOLVING'
                                "
                                switch($loginChoice){
                                    0      {$agSecondaryReplicas = Execute-Query $agSecondaryReplicasQuery "master" $secondaryReplicasArray[$replicaChoice] 1 "" ""}
                                    default{$agSecondaryReplicas = Execute-Query $agSecondaryReplicasQuery "master" $secondaryReplicasArray[$replicaChoice] 0 $login $password}
                                }
                                foreach($agSecondaryReplica in $agSecondaryReplicas){
                                    foreach($agDatabase in $agDatabases){
                                        $resumeDataMovementQuery = "
                                        ALTER DATABASE [$($agDatabase.DBName)] SET HADR RESUME
                                        "                                        
                                        switch($loginChoice){
                                            0      {Execute-Query $resumeDataMovementQuery "master" $agSecondaryReplica.Replica 1 "" ""}
                                            default{Execute-Query $resumeDataMovementQuery "master" $agSecondaryReplica.Replica 0 $login $password}
                                        }                                        
                                    }                                
                                }
                                Write-Host -BackgroundColor Green -ForegroundColor White "The data movement has been resumed in all the Secondary Replicas!"
                                Write-Host ""
                                switch($loginChoice){
                                    0       {Get-AGInformation $secondaryReplicasArray[$replicaChoice] $availabilityGroup 1 "" ""}
                                    default {Get-AGInformation $secondaryReplicasArray[$replicaChoice] $availabilityGroup 0 $login $password}
                                }
                            }
                        }                        
                        1{
                            Write-Host -BackgroundColor Green -ForegroundColor White "No modificaion was made."
                            exit
                        }
                    }
                }
            }                      
        }
        if($replicaAvailabilityModeResult[0] -eq "SYNCHRONOUS_COMMIT"){
            Write-Host "Performing Failover..."
            Write-Host ""
            $failoverQuery = "
            BEGIN TRY
                ALTER AVAILABILITY GROUP [$($availabilityGroup)] FAILOVER
                SELECT 1
            END TRY
            BEGIN CATCH
                SELECT ERROR_MESSAGE()
            END CATCH
            "
            
            #Wait until the Availability Group is in a HEALTHY state before proceeding with the failover
            switch($loginChoice){
                0{
                    do{
                        Start-Sleep -s 5
                    }while($(Get-AGState $availabilityGroup $primaryReplica 1 "" "") -ne 1)
                }
                default{
                    do{
                        Start-Sleep -s 5
                    }while($(Get-AGState $availabilityGroup $primaryReplica 0 $login $password) -ne 1)
                }
            }

            switch($loginChoice){
                0      {$failoverResult = Execute-Query $failoverQuery "master" $secondaryReplicasArray[$replicaChoice] 1 "" ""}
                default{$failoverResult = Execute-Query $failoverQuery "master" $secondaryReplicasArray[$replicaChoice] 0 $login $password}
            }
            if($failoverResult[0] -eq 1){
                Write-Host -BackgroundColor Green -ForegroundColor White "Failover performed successfully."
                Write-Host ""
                switch($loginChoice){
                    0       {Get-AGInformation $secondaryReplicasArray[$replicaChoice] $availabilityGroup 1 "" ""}
                    default {Get-AGInformation $secondaryReplicasArray[$replicaChoice] $availabilityGroup 0 $login $password}
                }
            }else{
                Write-Host -BackgroundColor Red -ForegroundColor White "$($failoverResult[0])" 
            }
        }                                        
    }
}
