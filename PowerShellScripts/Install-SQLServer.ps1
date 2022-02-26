Import-Module SqlServer
Invoke-Sqlcmd -Query $query

function Verb-Noun {
    <#
    .SYNOPSIS
        Short description
    .DESCRIPTION
        Long description
    .EXAMPLE
        PS C:\> <example usage>
        Explanation of what the example does
    .INPUTS
        Inputs (if any)
    .OUTPUTS
        Output (if any)
    .NOTES
        General notes
    #>
    [CmdletBinding()]
    param (
        [Parameter()]
        [TypeName]
        $ParameterName,
    
    # Parameter help description
    [Parameter(ValueFromPipeline)]
    [String]
    $query      
    
    )
    
    process {
        function FunctionName (OptionalParameters) {
    }
    
    end {
        
    }
