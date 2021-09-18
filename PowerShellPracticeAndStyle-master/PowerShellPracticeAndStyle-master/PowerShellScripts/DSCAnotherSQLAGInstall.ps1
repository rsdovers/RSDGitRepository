$cd = @{
    AllNodes = @(
        @{
            Nodename = 'SQLSERVER-1'
            NICInterfaceAlias = 'Ethernet'
            NICIPAddress = '192.168.1.22/24'
            NICGateway = '192.168.1.1'
            NICDNSServerAddresses = '192.168.1.20','192.168.1.21'
            PSDscAllowPlainTextPassword = $true
            PSDscAllowDomainUser = $true
        }
    )
 
}
 
Configuration SQLDBEngine {
 
    param (
        [pscredential]$SACreds,
        [pscredential]$DomainCreds
    )
 
    Import-DscResource -ModuleName 'PSDesiredStateConfiguration'
    Import-DscResource -ModuleName 'xPendingReboot' -ModuleVersion '0.4.0.0'
    Import-DscResource -ModuleName 'ComputerManagementDsc' -ModuleVersion '6.0.0.0'
    Import-DscResource -ModuleName 'StorageDsc' -ModuleVersion '4.4.0.0'
    Import-DscResource -ModuleName 'NetworkingDsc' -ModuleVersion '6.2.0.0'
    Import-DscResource -ModuleName 'SqlServerDsc' -ModuleVersion '12.3.0.0'
    Import-DscResource -ModuleName 'xSMBShare' -moduleversion '2.2.0.0'
 
    Node $Allnodes.Nodename {
 
        LocalConfigurationManager {
            AllowModuleOverwrite = $true
            ActionAfterReboot = 'ContinueConfiguration'
            ConfigurationMode = 'ApplyAndAutoCorrect'
            RebootNodeIfNeeded = $true
        }
 
        xPendingReboot RB {
            Name = 'RebootWhenNeeded'
        }
 
        OpticalDiskDriveLetter CDROM {
            DiskId = 1
            DriveLetter = 'Z'
            Ensure = 'Present'
            DependsOn = '[xPendingReboot]RB'
        }
 
        Disk DATADrive {
            DiskId = 1
            DriveLetter = 'D'
            FSFormat = 'NTFS'
            FSLabel = 'MSSQLDATA'
            PartitionStyle = 'GPT'
            DependsOn = '[OpticalDiskDriveLetter]CDROM'
        }
 
        Disk DATADriveTwo {
            DiskId = 2
            DriveLetter = 'E'
            FSFormat = 'NTFS'
            FSLabel = 'LOGS'
            PartitionStyle = 'GPT'
            DependsOn = '[OpticalDiskDriveLetter]CDROM'
        }
        Disk DATADriveThree {
            DiskId = 3
            DriveLetter = 'F'
            FSFormat = 'NTFS'
            FSLabel = 'TEMPDB'
            PartitionStyle = 'GPT'
            DependsOn = '[OpticalDiskDriveLetter]CDROM'
        }
        Disk DATADriveFour {
            DiskId = 4
            DriveLetter = 'G'
            FSFormat = 'NTFS'
            FSLabel = 'BACKUPS'
            PartitionStyle = 'GPT'
            DependsOn = '[OpticalDiskDriveLetter]CDROM'
        }
 
        VirtualMemory PageFileInVM {
            Drive = 'C'
            Type = 'CustomSize'
            DependsOn = '[OpticalDiskDriveLetter]CDROM'
            InitialSize = 800
            MaximumSize = 2048
        }
 
        TimeZone EasternTZ {
            IsSingleInstance = 'Yes'
            TimeZone = 'Eastern Standard Time'
        }
 
        ###################################
        # ADD NETWORKING INFORMATION HERE #
        ###################################
 
        ## Networking Settings
        IPAddress LocalNetwork {
            IPAddress = $AllNodes.NICIPAddress
            AddressFamily = 'IPv4'
            InterfaceAlias = $AllNodes.NICInterfaceAlias
        }
 
        DefaultGatewayAddress LocalGateway {
            Address = $AllNodes.NICGateway
            AddressFamily = 'IPv4'
            InterfaceAlias = $AllNodes.NICInterfaceAlias
            DependsOn = '[IPAddress]LocalNetwork'
        }
 
        DNSServerAddress LocalDomainControllers {
            Address = $AllNodes.NICDNSServerAddresses
            AddressFamily = 'IPv4'
            InterfaceAlias = $AllNodes.NICInterfaceAlias
            DependsOn = '[DefaultGatewayAddress]LocalGateway'
        }
 
        WindowsFeature NetFramework45 {
            Name = 'NET-Framework-45-Core'
            Ensure = 'Present'
            DependsOn = '[VirtualMemory]PageFileInVM'
        }
 
        # SQL SERVER FOLDERS
 
        WaitForVolume ddrive {
            DriveLetter = 'D'
            DependsOn = '[Disk]DATADrive'
            RetryIntervalSec = 20
            RetryCount = 20
        }
        WaitForVolume edrive {
            DriveLetter = 'E'
            DependsOn = '[Disk]DATADriveTwo'
            RetryIntervalSec = 20
            RetryCount = 20
        }
        WaitForVolume fdrive {
            DriveLetter = 'E'
            DependsOn = '[Disk]DATADriveThree'
            RetryIntervalSec = 20
            RetryCount = 20
        }
        WaitForVolume gdrive {
            DriveLetter = 'G'
            DependsOn = '[Disk]DATADriveFour','[WaitForVolume]fdrive','[WaitForVolume]edrive','[WaitForVolume]ddrive'
            RetryIntervalSec = 20
            RetryCount = 20
        }
 
        File MSSQLDBFolder1 {
            DestinationPath = "D:\MSSQL"
            Ensure = "Present"
            Type = "Directory"
            DependsOn = '[WaitForVolume]gdrive'
        }
        File MSSQLDBFolder2 {
            DestinationPath = "D:\MSSQL\Data"
            Ensure = "Present"
            Type = "Directory"
            DependsOn = "[File]MSSQLDBFolder1"
        }
        File MSSQLDBFolder3 {
            DestinationPath = "D:\MSSQL\Backup"
            Ensure = "Present"
            Type = "Directory"
            DependsOn = "[File]MSSQLDBFolder1"
        }
        File MSSQLLogsFolder1 {
            DestinationPath = "E:\MSSQL"
            Ensure = "Present"
            Type = "Directory"
            DependsOn = '[WaitForVolume]gdrive'
        }
        File MSSQLLogsFolder2 {
            DestinationPath = "E:\MSSQL\Logs"
            Ensure = "Present"
            Type = "Directory"
            DependsOn = "[File]MSSQLLogsFolder1"
        }
        File MSSQLTempDBFolder1 {
            DestinationPath = "F:\MSSQL"
            Ensure = "Present"
            Type = "Directory"
            DependsOn = "[File]MSSQLLogsFolder1",'[WaitForVolume]gdrive'
        }
        File MSSQLTempDBFolder2 {
            DestinationPath = "F:\MSSQL\TempDB"
            Ensure = "Present"
            Type = "Directory"
            DependsOn = "[File]MSSQLTempDBFolder1"
        }
        File Transfer {
            DestinationPath = "G:\Transfer"
            Ensure = "Present"
            Type = "Directory"
            DependsOn = "[WaitForVolume]gdrive"
        }
        File SQLBackupFolder {
            DestinationPath = "G:\Transfer\Backups"
            Ensure = "Present"
            Type = "Directory"
            DependsOn = "[File]Transfer"
        }
        xSmbShare TransferShare {
            Name = "Transfer"
            Path = "G:\Transfer"
            FullAccess = 'Everyone'
            Ensure = 'Present'
            DependsOn = '[File]SQLBackupFolder'
        }
 
        # SQL SERVER SETUP
 
        SqlSetup BaseInstall {
            InstanceName = 'MSSQLSERVER'
            Action = 'Install'
            SqlSvcStartupType = "Automatic"
            BrowserSvcStartupType = 'Automatic'
            Features = 'SQLEngine,FullText,Conn'
            ForceReboot = $true
            SAPwd = $saCreds
            SecurityMode = "SQL"
            SourcePath = "\\dbat-fs-01a\Distribution\Applications\Microsoft\SQLServer\2017"
            InstallSharedDir      = 'C:\Program Files\Microsoft SQL Server'
            InstallSharedWOWDir   = 'C:\Program Files (x86)\Microsoft SQL Server'
            InstanceDir           = 'C:\Program Files\Microsoft SQL Server'
            InstallSQLDataDir     = 'C:\Program Files\Microsoft SQL Server\MSSQL14.MSSQLSERVER\MSSQL\Data'
            SQLUserDBDir = "D:\MSSQL\Data"
            SQLUserDBLogDir = "E:\MSSQL\Logs"
            SQLBackupDir = "G:\Transfer\Backups"
            SQLTempDBDir = "F:\MSSQL\TempDB"
            SQLTempDBLogDir = "F:\MSSQL\TempDB"
            UpdateEnabled = 'False'
            PsDscRunAsCredential = $DomainCreds
            DependsOn = '[File]MSSQLTempDBFolder2'
        }
 
        SqlServerMemory Set_SQLServerMaxMemory_To12GB
        {
            Ensure               = 'Present'
            DynamicAlloc         = $false
            MinMemory            = 1024
            MaxMemory            = 12288
            ServerName           = $AllNodes.Nodename
            InstanceName         = 'MSSQLSERVER'
            PsDscRunAsCredential = $DomainCreds
            DependsOn = '[SqlSetup]BaseInstall'
        }
 
        SqlServerNetwork ChangeTcpIpOnDefaultInstance {
            InstanceName         = 'MSSQLSERVER'
            ProtocolName         = 'Tcp'
            IsEnabled            = $true
            TCPDynamicPort       = $false
            TcpPort              = 1433
            RestartService       = $true
            PsDscRunAsCredential = $DomainCreds
            DependsOn = '[SqlServerMemory]Set_SQLServerMaxMemory_To12GB'
        }
    }
}
