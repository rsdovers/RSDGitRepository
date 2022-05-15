$namespace = @{nsl = "http://schemas.serviceml.org/smlif/2007/02"
xs = "ttp://www.w3.org/2001/XMLSchema"
DMF = "http://schemas.microsoft.com/sqlserver/DMF/2007/08"
sfc = "http://schemas.microsoft.com/sqlserver/sfc/serialization/2007/08"
sml = "http://schemas.serviceml.org/sml/2007/02"
}
$file = "/home/rsdovers/SQLAutomation/PBM/policy-result-2021-02-04.xml"

try {
    Select-Xml -Path $file -Namespace $namespace -XPath "//DMF:TargetQueryExpression" | ForEach-Object {$_.node.InnerXML}  
}
catch {
   {write-output "$($Error[0])"}
}