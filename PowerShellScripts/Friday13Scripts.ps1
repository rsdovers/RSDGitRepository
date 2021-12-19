#requires -version 2.0

# Jeffery Hicks
# http://jdhitsolutions.com/blog
# follow on Twitter: http://twitter.com/JeffHicks
#
# 
# "Those who forget to script are doomed to repeat their work."

#  ****************************************************************
#  * DO NOT USE IN A PRODUCTION ENVIRONMENT UNTIL YOU HAVE TESTED *
#  * THOROUGHLY IN A LAB ENVIRONMENT. USE AT YOUR OWN RISK.  IF   *
#  * YOU DO NOT UNDERSTAND WHAT THIS SCRIPT DOES OR HOW IT WORKS, *
#  * DO NOT USE IT OUTSIDE OF A SECURE, TEST SETTING.             *
#  ****************************************************************


#1. Get running services
$running={Param ([string]$computername=$env:computername) get-service -computername $computername | 
    where {$_.status -eq "Running"}}
    #&$running MyServer
    
    #2. Get logical disk information
    $disk={Param ([string]$computername=$env:computername) get-wmiobject win32_logicaldisk -filter "drivetype=3" -computername $computername | 
    Select "DeviceID","VolumeName",@{Name="SizeGB";Expression={"{0:N4}" -f ($_.size/1GB)}},`
    @{Name="Freespace";Expression={"{0:N4}" -f ($_.FreeSpace/1GB)}},@{Name="Utilization";
    Expression={ "{0:P2}" -f (1-($_.freespace -as [double])/($_.size -as [double]))}}}
    #&$disk 
    
    #3. Get day of the year
    $doy={(get-date).DayOfYear}
    #&$doy
    
    #4. Get top services by workingset size
    $top={Param([string]$computername=$env:computername,[int]$count=5) Get-Process -computername $computername |
    Sort WorkingSet -Descending | Select -first $count}
    #&$top "jdhit-dc01" 10
    
    #5. Get OS information
    $os={Param([string]$computername=$env:computername) Get-WmiObject win32_operatingsystem -computername $computername |
    Select @{name="Computer";Expression={$_.CSName}},@{Name="OS";Expression={$_.caption}},`
    Version,OSArchitecture,@{Name="ServicePack";Expression={
    "{0}.{1}" -f $_.ServicePackMajorVersion,$_.ServicePackMinorVersion}}, `
    @{Name="Installed";Expression={$_.ConvertToDateTime($_.InstallDate)}}  
    }
    #&$os 
    
    #6. Get system uptime
    $up={Param([string]$computername=$env:computername) Get-WmiObject win32_operatingsystem -computername $computername |
    Select  @{name="Computer";Expression={$_.CSName}}, `
    @{Name="LastBoot";Expression={$_.ConvertToDateTime($_.LastBootUpTime) }}, `
    @{Name="Uptime";Expression={(Get-Date)-($_.ConvertToDateTime($_.LastBootUpTime))}}}
    #&$up jdhit-dc01
    
    #7. get a random number between 1 and 13
    $rand={Param([int]$min=1,[int]$max=13) get-random -min $min -max $max}
    #&$rand
    
    #8. How old are you?
    $age={$b=Read-Host "Enter your birth date (dd/mm/yyyy)";((get-date)-($b -as [datetime])).ToString()}
    #&$age
    
    #9. get %TEMP% folder stats
    $t={Param([string]$Path=$env:temp) Get-ChildItem $path -Recurse -force -ea "silentlycontinue" | 
    measure-object -Property Length -sum | Select @{Name="Path";Expression={$path}},
    Count,@{Name="SizeMB";Expression={"{0:N4}" -f ($_.sum/1mb)}} }
    #&$t
    
    #10. Get event log information
    $el={Param([string]$computername=$env:computername) get-eventlog -list -computername $computername | 
    where {$_.entries.count -gt 0} | 
    Select Log,@{Name="Entries";Expression={$_.Entries.count}},MaximumKilobytes | 
    Sort Entries -descending }
    #&$el "jdhit-dc01"
    
    #11. Get local admin password age in days
    $adminpass={Param([string]$computername=$env:computername,[string]$user="Administrator") 
    [ADSI]$admin="WinNT://$computername/$user,user"
    $age=$admin.passwordage.value/86400
    $last=(Get-Date).AddDays(-$age)
    New-Object -type PSObject -property @{ 
        Computername=$computername.ToUpper()
        Account=$user
        Age=($age -as [int])
        LastSet=$last
    }}
    #&$adminpass
    
    #12. Get cmdlet summary
    $c={Get-command -CommandType cmdlet | sort Verb,Name | 
    format-table -GroupBy Verb -Property Name,ModuleName,Definition}
    #&$c
    
    #13. How much time before I can go home?
    $eod={[datetime]$end="5:00PM"
     $span=$end-(get-date)
     #strip off milliseconds
     $span.ToString().Substring(0,8)
     }
     #&$eod