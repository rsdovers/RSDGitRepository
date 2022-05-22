$namespace = @{nsl = "http://schemas.serviceml.org/smlif/2007/02"
xs = "ttp://www.w3.org/2001/XMLSchema"
DMF = "http://schemas.microsoft.com/sqlserver/DMF/2007/08"
sfc = "http://schemas.microsoft.com/sqlserver/sfc/serialization/2007/08"
sml = "http://schemas.serviceml.org/sml/2007/02"
}
$file = "/home/rsdovers/SQLAutomation/PBM/policy-result-2021-02-04.xml"

try {
    Select-Xml -Path $file -Namespace $namespace -XPath "//DMF:TargetQueryExpression | //DMF:Result" | ForEach-Object {$_.node.InnerXML}  
}
catch {
   write-output $_.exception
}

<#Another Example of how to do this, but with a more
modular approach that returns pscustomerobjects.
This is mainly for and XML file with attributes:
 <students>
      <student name="Bob" subject="Math" year="5">
         <details SID="38571273" code="1122" group="" />
      </student>

$XMLPath = "ENTER_PATH"
function Get-StudentInfo {
    param (
        $xPATH,
        $title)
    Select-Xml -Path $XMLPath -XPath "/school/students/$xPATH" | ForEach-Object { $_.Node.$title }
}

$students = [PSCustomObject]@{
    Names    = Get-StudentInfo -xPath "student" -title "name"
    Subjects = Get-StudentInfo -xPath "student" -title "subject"
    Years    = Get-StudentInfo -xPath "student" -title "year"
    SIDs     = Get-StudentInfo -xPath "student/details" -title "SID"
    Codes    = Get-StudentInfo -xPath "student/details" -title "code"
    Groups   = Get-StudentInfo -xPath "student/details" -title "group"
}

$students.Names

#>