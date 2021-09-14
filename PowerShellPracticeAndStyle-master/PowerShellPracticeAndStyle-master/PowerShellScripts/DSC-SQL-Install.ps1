# Configuration data to be supplied during for DSC Configuration
$CD = @{
    AllNodes = @(
        @{
            NodeName = '*'
            InstanceName = 'MSSQLSERVER'
            SqlVersion = "2019"
            WindowsVersion = "2019"
            SQLSysAdminAccounts = 'SQLAdminAccounts'
            Features = 'SQLENGINE,FullText,Replication'
            SQLSvcAccountName = 'gMSASvcAccount'
            AgtSvcAccountName = 'GMSAAgtAccount'
            AvailabilityGroupName = 'SQLAGN'
            AvailabilityGroupIPAddress = '192.168.1.101/255.255.255.0'
            ClusterName = 'Clustername'
            ClusterIPAddress = '192.168.1.100/24'
            FileShareWitness = '\\FileShareWitnessPath\Clustername'
            PSDscAllowDomainUser = $true
            PSDscAllowPlainTextPassword = $true
        },
        @{
            NodeName = 'TestNodeOne'
            SqlAGRole = 'PrimaryReplica'
        },
        @{
            NodeName = 'TestNodeTwo'
            SqlAGRole = 'SecondaryReplica'
        }
    )
}

Configuration DSC_SQL_AG
{
    param
	(
        [Parameter(Mandatory = $true)]
        [System.Management.Automation.PSCredential]$SqlAdministratorCredential,
		[Parameter(Mandatory = $true)]
        [System.Management.Automation.PSCredential]$ActiveDirectoryAdministratorCredential
    )
    Import-DscResource -ModuleName SqlServerDsc
    Import-DscResource -ModuleName xFailOverCluster

    Node $AllNodes.NodeName
    {
        # Switch statement defines role specific dependencies for SQL setup resource
		Switch($Node.SqlAGRole)
		{
			'PrimaryReplica'
			{
				$RoleDependsOn = '[xCluster]CreateCluster'
			}
			'SecondaryReplica'
			{
				$RoleDependsOn = '[xCluster]JoinSecondNodeToCluster'
			}
		}
    
        # Switch statement defines Sql version specific depenedencies for SQL setup resource
        Switch($Node.SqlVersion)
        {
            "2016"
            {
                $SqlSourcePath = '\\SqlSourcePath\SQL-2016'
                $NetFramework35 = $True
                $SqlDependsOn = '[WindowsFeature]NetFramework35', '[WindowsFeature]NetFramework45', $RoleDependsOn
            }
            "2017"
            {
                $SqlSourcePath = '\\SqlSourcePath\SQL-2017'
                $NetFramework35 = $True
                $SqlDependsOn = '[WindowsFeature]NetFramework35', '[WindowsFeature]NetFramework45', $RoleDependsOn
            }
            "2019"
            {
                $SqlSourcePath = '\\SqlSourcePath\SQL-2019'
                $SqlDependsOn = '[WindowsFeature]NetFramework45', $RoleDependsOn
            }
        }

        # Switch statement defines SXS source path for dotnet35 dependencies 
        Switch($Node.WindowsVersion)
        {
            "2016"
            {
                $WindowsSXSPath = '\\SxsSourcePath\SXS-2016'
            }
            "2019"
            {
                $WindowsSXSPath = '\\SxsSourcePath\SXS-2019'
            }
        }
        
        # Convert the gMSA account names into domain\username format for future use
        $SqlSvcAccount = ('DomainName\' + $Node.SQLSvcAccountName + '$')
        $SqlAgtAccount = ('DomainName\' + $Node.AgtSvcAccountName + '$')
        # Generate a fake password string to prevent NULL password errors during execution
        $password = ('temppassword' | ConvertTo-SecureString -AsPlainText -Force)
        # Create PSCredential objects for use in SQL setup resource
        $SqlSvcCred = new-object -typename System.Management.Automation.PSCredential -argumentlist $SqlSvcAccount,$password
        $SqlAgtCred = new-object -typename System.Management.Automation.PSCredential -argumentlist $SqlAgtAccount,$password

        WindowsFeature AddFailoverFeature
        {
            Ensure = 'Present'
            Name   = 'Failover-clustering'
        }

        WindowsFeature AddRemoteServerAdministrationToolsClusteringPowerShellFeature
        {
            Ensure    = 'Present'
            Name      = 'RSAT-Clustering-PowerShell'
            DependsOn = '[WindowsFeature]AddFailoverFeature'
        }

        WindowsFeature AddRemoteServerAdministrationToolsClusteringCmdInterfaceFeature
        {
            Ensure    = 'Present'
            Name      = 'RSAT-Clustering-CmdInterface'
            DependsOn = '[WindowsFeature]AddRemoteServerAdministrationToolsClusteringPowerShellFeature'
        }

        if ($Node.SqlAGRole -eq 'PrimaryReplica')
        {
            xCluster CreateCluster
            {
                Name                          = $Node.ClusterName
                StaticIPAddress               = $Node.ClusterIPAddress
                DomainAdministratorCredential = $ActiveDirectoryAdministratorCredential
                DependsOn                     = '[WindowsFeature]AddRemoteServerAdministrationToolsClusteringCmdInterfaceFeature'
            }
            
            xClusterQuorum SetQuorumToNodeAndFileShareMajority
            {
                IsSingleInstance = 'Yes'
                Type             = 'NodeAndFileShareMajority'
                Resource         = $Node.FileShareWitness
                DependsOn        = '[xCluster]JoinSecondNodeToCluster'
            }
        }

        if ($Node.SqlAGRole -eq 'SecondaryReplica')
        {
            xWaitForCluster WaitForClusterCreation
            {
                Name             = $Node.ClusterName
                RetryIntervalSec = 10
                RetryCount       = 60
                DependsOn        = '[WindowsFeature]AddRemoteServerAdministrationToolsClusteringCmdInterfaceFeature'
            }
    
            xCluster JoinSecondNodeToCluster
            {
                Name                          = $Node.ClusterName
                StaticIPAddress               = $Node.ClusterIPAddress
                DomainAdministratorCredential = $ActiveDirectoryAdministratorCredential
                DependsOn                     = '[xWaitForCluster]WaitForClusterCreation'
            }
        }
			
        WindowsFeature 'NetFramework45'
        {
            Name   = 'NET-Framework-45-Core'
            Ensure = 'Present'
        }

        If($NetFramework35)
        {
            WindowsFeature 'NetFramework35'
            {
                Name   = 'NET-Framework-Core'
                Source = $WindowsSXSPath
                Ensure = 'Present'
            }
        }

        SqlSetup 'InstallSqlInstance'
        {
            InstanceName         = $Node.InstanceName
            Features             = $Node.Features
            SQLCollation         = 'SQL_Latin1_General_CP1_CI_AS'
            SQLSysAdminAccounts  = $Node.SQLSysAdminAccounts
            InstallSharedDir     = 'C:\Program Files\Microsoft SQL Server'
            InstallSharedWOWDir  = 'C:\Program Files (x86)\Microsoft SQL Server'
            InstanceDir          = 'C:\Program Files\Microsoft SQL Server'
            SQLUserDBDir         = 'G:\MSSQL\Data'
            SQLUserDBLogDir      = 'F:\MSSQL\Data'
            SQLTempDBDir         = 'T:\MSSQL\Data'
            SQLTempDBLogDir      = 'T:\MSSQL\Data'
            SQLBackupDir         = 'G:\SQLBackups'
            SourcePath           = $SqlSourcePath
            SQLSvcAccount        = $SqlSvcCred
            AgtSvcAccount        = $SqlAgtCred
            UpdateEnabled        = 'False'
            ForceReboot          = $false
            PsDscRunAsCredential = $SqlAdministratorCredential
            DependsOn            = $SqlDependsOn
        }
        
        SqlServerLogin Add_WindowsUserSqlSvc
        {
            Ensure               = 'Present'
            Name                 = $SqlSvcAccount
            LoginType            = 'WindowsUser'
            ServerName           = 'LocalHost'
            InstanceName         = $Node.InstanceName
            PsDscRunAsCredential = $SqlAdministratorCredential
            DependsOn            = '[SqlSetup]InstallSqlInstance'
        }

        SqlServerLogin Add_WindowsUserSqlAgt
        {
            Ensure               = 'Present'
            Name                 = $SqlAgtAccount
            LoginType            = 'WindowsUser'
            ServerName           = 'LocalHost'
            InstanceName         = $Node.InstanceName
            PsDscRunAsCredential = $SqlAdministratorCredential
            DependsOn            = '[SqlSetup]InstallSqlInstance'
        }

        SqlServerLogin Add_WindowsUserClusSvc
        {
            Ensure               = 'Present'
            Name                 = 'NT SERVICE\ClusSvc'
            LoginType            = 'WindowsUser'
            ServerName           = 'LocalHost'
            InstanceName         = $Node.InstanceName
            PsDscRunAsCredential = $SqlAdministratorCredential
            DependsOn            = '[SqlSetup]InstallSqlInstance'
        }

        SqlServerPermission SQLConfigureServerPermissionSYSTEMSvc
        {
            Ensure               = 'Present'
            ServerName           = 'LocalHost'
            InstanceName         = $Node.InstanceName
            Principal            = $SqlSvcAccount
            Permission           = 'AlterAnyAvailabilityGroup', 'ViewServerState', 'AlterAnyEndPoint', 'ConnectSql'
            DependsOn            = '[SqlServerLogin]Add_WindowsUserSqlSvc'

            PsDscRunAsCredential = $SqlAdministratorCredential
        }

        SqlServerPermission SQLConfigureServerPermissionSYSTEMAgt
        {
            Ensure               = 'Present'
            ServerName           = 'LocalHost'
            InstanceName         = $Node.InstanceName
            Principal            = $SqlAgtAccount
            Permission           = 'AlterAnyAvailabilityGroup', 'ViewServerState', 'AlterAnyEndPoint', 'ConnectSql'
            DependsOn            = '[SqlServerLogin]Add_WindowsUserSqlAgt'
            PsDscRunAsCredential = $SqlAdministratorCredential
        }
        
        SqlServerPermission AddNTServiceClusSvcPermissions
        {
            Ensure               = 'Present'
            ServerName           = 'LocalHost'
            InstanceName         = $Node.InstanceName
            Principal            = 'NT SERVICE\ClusSvc'
            Permission           = 'AlterAnyAvailabilityGroup', 'ViewServerState'
            DependsOn            = '[SqlServerLogin]Add_WindowsUserClusSvc'
            PsDscRunAsCredential = $SqlAdministratorCredential
        }
            
        SqlServerRole Add_ServerRole_AdminSqlforBI
        {
            Ensure               = 'Present'
            ServerRoleName       = 'sysadmin'
            MembersToInclude     = $SqlSvcAccount, $SqlAgtAccount
            ServerName           = 'LocalHost'
            InstanceName         = $Node.InstanceName
            DependsOn            = '[SqlServerLogin]Add_WindowsUserSqlSvc', '[SqlServerLogin]Add_WindowsUserSqlAgt'
            PsDscRunAsCredential = $SqlAdministratorCredential
        }

        SqlServerMemory Set_SQLServerMaxMemory_ToAuto
        {
            Ensure               = 'Present'
            DynamicAlloc         = $true
            ServerName           = 'LocalHost'
            InstanceName         = $Node.InstanceName
            DependsOn            = '[SqlSetup]InstallSqlInstance'
            PsDscRunAsCredential = $SqlAdministratorCredential
        }
        
        # Configure service dependencies to prevent SQL service from trying to authenticate the gMSA accounts before the netlogon service has started.
        Service SqlSvcDependencies
        {
            Name = 'MSSQLSERVER'
            Ensure = 'Present'
            Dependencies = 'W32Time','Netlogon'
            DependsOn            = '[SqlSetup]InstallSqlInstance'
            PsDscRunAsCredential    = $SqlAdministratorCredential
        }

        Registry SqlSvcDelayAutoStart
        {
            Key = 'HKLM:\SYSTEM\CurrentControlSet\Services\MSSQLSERVER'
            Ensure = 'Present'
            ValueName = 'DelayedAutoStart'
            ValueType = 'Binary'
            ValueData = '0x01'
            Force = $true
            DependsOn = '[Service]SqlSvcDependencies'
            PsDscRunAsCredential    = $SqlAdministratorCredential
        }

        Registry SqlAgtDelayAutoStart
        {
            Key = 'HKLM:\SYSTEM\CurrentControlSet\Services\sqlserveragent'
            Ensure = 'Present'
            ValueName = 'DelayedAutoStart'
            ValueType = 'Binary'
            ValueData = '0x01'
            Force = $true
            DependsOn = '[Service]SqlSvcDependencies'
            PsDscRunAsCredential    = $SqlAdministratorCredential
        }

        SqlServerEndpoint HADREndpoint
        {
            EndPointName         = 'HADR'
            Ensure               = 'Present'
            Port                 = 5022
            ServerName           = $Node.NodeName
            InstanceName         = $Node.InstanceName
            DependsOn            = '[SqlSetup]InstallSqlInstance'
            PsDscRunAsCredential = $SqlAdministratorCredential
        }

        SqlAlwaysOnService EnableHADR
        {
            Ensure               = 'Present'
            InstanceName         = $Node.InstanceName
            ServerName           = $Node.NodeName
            DependsOn            = '[SqlServerEndpoint]HADREndpoint'
            PsDscRunAsCredential = $SqlAdministratorCredential
        }

        if ( $Node.SqlAGRole -eq 'PrimaryReplica' )
        {
            SqlAG AddAG
            {
                Ensure               = 'Present'
                Name                 = $Node.AvailabilityGroupName
                InstanceName         = $Node.InstanceName
                ServerName           = $Node.NodeName
                AvailabilityMode     = 'SynchronousCommit'
                FailoverMode         = 'Automatic'
                DependsOn            = '[SqlAlwaysOnService]EnableHADR', '[SqlServerEndpoint]HADREndpoint', '[SqlServerPermission]AddNTServiceClusSvcPermissions'
                PsDscRunAsCredential = $SqlAdministratorCredential
            }

            SqlAGListener AvailabilityGroupListener
            {
                Ensure               = 'Present'
                ServerName           = $Node.NodeName
                InstanceName         = $Node.InstanceName
                AvailabilityGroup    = $Node.AvailabilityGroupName
                Name                 = $Node.AvailabilityGroupName
                IpAddress            = $Node.AvailabilityGroupIPAddress
                Port                 = 1433
                DependsOn            = '[SqlAG]AddAG'
                PsDscRunAsCredential = $SqlAdministratorCredential
            }
        }

        if ( $Node.SqlAGRole -eq 'SecondaryReplica' )
        {
            # Wait for SQL AG to be created on primary node before attempting to join secondary node
            SqlWaitForAG SQLConfigureAGWait
            {
                Name                 = $Node.AvailabilityGroupName
                RetryIntervalSec     = 20
                RetryCount           = 30
                PsDscRunAsCredential = $SqlAdministratorCredential
            }

            SqlAGReplica AddReplica
            {
                Ensure                     = 'Present'
                Name                       = $Node.NodeName
                AvailabilityGroupName      = $Node.AvailabilityGroupName
                ServerName                 = $Node.NodeName
                InstanceName               = $Node.InstanceName
                AvailabilityMode           = 'SynchronousCommit'
                FailoverMode               = 'Automatic'
                PrimaryReplicaServerName   = ( $AllNodes | Where-Object { $_.SqlAGRole -eq 'PrimaryReplica' } ).NodeName
                PrimaryReplicaInstanceName = ( $AllNodes | Where-Object { $_.SqlAGRole -eq 'PrimaryReplica' } ).InstanceName
                DependsOn                  = '[SqlAlwaysOnService]EnableHADR', '[SqlWaitForAG]SQLConfigureAGWait'
                PsDscRunAsCredential = $SqlAdministratorCredential
            }
        }
    }
}