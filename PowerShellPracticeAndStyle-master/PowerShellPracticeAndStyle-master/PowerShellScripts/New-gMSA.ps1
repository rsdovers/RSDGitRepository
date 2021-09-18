Import-Module ActiveDirectory; 
# Get Domain Name
$DomainName = (Get-ADDomain).DNSRoot;

# Get admin credential to run scripts
Write-Output “Enter RunAs (Admin) credentials.”
$pscred = Get-Credential;

[string]$ConfigJSON = “C:\Install\Config.json”;
# Load JSON Config File
$Config = ConvertFrom-Json -InputObject (Get-Content -Path “$ConfigJSON” -Raw);

# Get the server names 
[array]$ServerList = (($Config).Servers).ServerName
# Get gMSA names
$gMSANames = ((($Config).Accounts).Services).Where{$_.AccountType -eq “gMSA”};

# Create the AD service accounts
ForEach ($Name in $gMSANames) {
      $Acct = $Name.Username;
      $AcctDNS = “$Acct.$DomainName”
      $gMSA_HostNames = $ServerList | ForEach-Object { Get-ADComputer -Identity $_ };
      # Create new gMSA
      New-ADServiceAccount -Name $Acct -DNSHostName $AcctDNS -PrincipalsAllowedToRetrieveManagedPassword $gMSA_HostNames;
      Write-Output “gMSA Created: $Acct”;
      Set-ADServiceAccount -Identity $Acct -TrustedForDelegation $true;
        }

ForEach ($Server in $ServerList) {
Write-Output “Executing on server: $Server”;
ForEach ($Name in $gMSANames) {
$Acct = ($Name).Username;
$MSAblock = @”
Add-WindowsFeature RSAT-AD-Powershell;
Import-Module ActiveDirectory; 
Write-Output “Add gMSA: $Acct”;
Install-ADServiceAccount $Acct;
“@;
    write-output “Add gMSA: $Acct”;
    # Install gMSA on the SQL Server
    Invoke-Command -ComputerName $Server -ScriptBlock {$MSAblock} -Credential $pscred;
    }
}