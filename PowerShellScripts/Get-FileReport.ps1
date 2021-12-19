# Get-FileReport.ps1
#Author: Kevin Trent, Whatdouknow.com
#Right click .ps1 file and Open with PowerShell
#Enter Filepath or share path.
 
$location = Read-Host "Enter Top Level File Path"
$folders = Get-ChildItem -Path $location -Recurse -Directory
 
$array = @()
 
foreach ($folder in $folders)
{
$foldername = $folder.FullName
 
# Find files in sub-folders
$files = Get-ChildItem $foldername -Attributes !Directory
 
# Calculate size in MB for files
$size = $Null
$null = $size
$files | ForEach-Object -Process {
$size += $_.Length
}
 
$sizeinmb = [math]::Round(($size / 1mb), 1)
 
# Add pscustomobjects to array
$array += [pscustomobject]@{
Folder = $foldername
Count = $files.count
'Size(MB)' = $sizeinmb
}
}
 
# Generate Report Results in your Documents Folder
$array|Export-Csv -Path $env:USERPROFILE\documents\file_report