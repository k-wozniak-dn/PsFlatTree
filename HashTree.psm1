#region const
enum FileFormat {psd1; json; xml; csv; }
enum NodeSection { SA; A; }
enum SysAttrKey {
    Path; Id; NodeName; NextChildId; Idx
}

# Path delimiter
Set-Variable -Name 'pdel' -Value ':' -Option ReadOnly;

Set-Variable -Name 'SA' -Value "$([NodeSection]::SA)" -Option ReadOnly;
Set-Variable -Name 'A' -Value "$([NodeSection]::A)" -Option ReadOnly;
$sysAttr = @([SysAttrKey]::Path; [SysAttrKey]::Id; [SysAttrKey]::NodeName; [SysAttrKey]::NextChildId; [SysAttrKey]::Idx);

#endregion

#region shared
function Copy-HashtableDeep {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [hashtable]$InputObject
    )

    $serialized = [System.Management.Automation.PSSerializer]::Serialize($InputObject)
    $deepCopy = [System.Management.Automation.PSSerializer]::Deserialize($serialized)
    return $deepCopy
}
#endregion

#region path

<#
    .SYNOPSIS
    Converts string path into PsCustomObject containing detailed info about path.

    .PARAMETER Path
    Path in the string format.

    .EXAMPLE
    PS> cvhtp -P:"0:section_A:node_X"

    Level       : 3
    Descriptive : True
    Parts       : {0, section_A, node_X}
    Id          : node_X
    ParentPath  : 0:section_A
    FullPath    : 0:section_A:node_X

    .EXAMPLE
    PS> "0:4:9" | cvhtp 

    Level       : 3
    Descriptive : False
    Parts       : {0, 4, 9}
    Id          : 9
    ParentPath  : 0:4
    FullPath    : 0:4:9

#>
function ConvertTo-HtPath {
    [CmdletBinding(DefaultParameterSetName="Default")]
    [OutputType([PSCustomObject], ParameterSetName="Default")]

    param (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [string] $Path
    )

    [string[]] $parts = $Path -split [regex]::Escape($pdel);
    [bool] $descriptive = $false;
    foreach ($part in $parts) {
        if ([string]::Empty -eq $part) { throw "Incorrect path '$path'." };
        # if path contains any non-numeric element, it's marked as descriptive
        if ( $part -notmatch '^[0-9*]+$' ) { $descriptive = $true };        
    }

    # id is the last element in path
    [string] $id = ($parts.Count -eq 1) ? $parts[0] : $parts[$parts.Count - 1];
    # parent path for root path is null
    [string] $parentPath = ($parts.Count -eq 1) ? $null : ($parts[0..($parts.Count - 2)]) -join $pdel;

    return [PSCustomObject] @{ 
        Level = ($parts).Count;
        Descriptive = $descriptive; 
        Parts = $parts;
        Id = $id;
        ParentPath = $parentPath; 
        FullPath = $Path;
    }
}
Set-Alias -Name:cvhtp -Value:ConvertTo-htPath
Export-ModuleMember -Function:ConvertTo-htPath
Export-ModuleMember -Alias:cvhtp

<#
    .SYNOPSIS
    Compares tested path with pattern path. Returns true if paths match.

    .PARAMETER Pattern
    Path in the PsCutomObject format.

    .PARAMETER Tested
    Path in the PsCutomObject format.

    .PARAMETER Recurse
    Switch if used in recurse scenario.

    .EXAMPLE
    wildcard non-recurse
    PS> $tp = ( "0:4:9" | cvhtp )
    PS> $pp = ( "0:4:*" | cvhtp )
    PS> crhtp -P:$pp -T:$tp 
    True

    .EXAMPLE
    wildcard non-recurse
    PS> $tp = ( "0:4:9" | cvhtp )
    PS> $pp = ( "0:*" | cvhtp )
    PS> crhtp -P:$pp -T:$tp 
    False

    .EXAMPLE
    wildcard recurse
    PS> $tp = ( "0:4:9" | cvhtp )
    PS> $pp = ( "0:*" | cvhtp )
    PS> crhtp -P:$pp -T:$tp -R
    True

#>
function Compare-HtPath {
    [CmdletBinding(DefaultParameterSetName="Default")]
    [OutputType([bool], ParameterSetName="Default")]

    param (
        [Parameter(Mandatory = $true)] [PSCustomObject] $Pattern,
        [Parameter(Mandatory = $true)] [PSCustomObject] $Tested,
        [switch] $Recurse
    )

    if ($null -eq $Tested.Level -or $null -eq $Pattern.Level) { throw "HtPath object(s) must have Level property set." }

    if ($Recurse) {
        # if Recurse, pattern can be shorter or equal length as tested path.
        if ($Pattern.Level -gt $Tested.Level) { return $false; }
    }
    else {
        # if non-recurse, pattern must be exactly as long as tested path.
        if ($Pattern.Level -ne $Tested.Level) { return $false; }
    }

    For ([int] $idx = 0; $idx -lt $Pattern.Level; $idx++) {
        if (($Tested.Parts[$idx]) -notlike ($Pattern.Parts[$idx])) { return $false }
    }

    return $true;    
}
Set-Alias -Name:crhtp -Value:Compare-htPath
Export-ModuleMember -Function:Compare-HtPath
Export-ModuleMember -Alias:crhtp

#endregion

#region node

<#
    .SYNOPSIS
    Get one or all attributes or system attributes from node. Outputs collection of PSCstomObjects with properties:
    Key, Value, System

    .PARAMETER Node
    Source node.

    .PARAMETER Key
    Attribute key.

    .PARAMETER System
    Switch, if used, system attributes are searched for a key.

    .PARAMETER All
    Switch, if used collection of all attributes is returned.

    .EXAMPLE
    PS> $node =  nn -NodeName "child-A"
    PS> $node | ga -All -System

    Key         Value   System
    ---         -----   ------
    NodeName    child-A True
    Idx         0       True
    NextChildId 1       True

#>
function Get-Attribute {
    [CmdletBinding(DefaultParameterSetName="Single")]
    [OutputType([PsCustomObject], ParameterSetName="Single")]
    [OutputType([PsCustomObject], ParameterSetName="All")]

    param (
        [Parameter(ParameterSetName = 'Single')]
        [Parameter(ParameterSetName = 'All')]
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)] [hashtable] $Node,

        [Parameter(ParameterSetName = 'Single')]
        [Parameter(Mandatory = $false)] [string] $Key,

        [Parameter(ParameterSetName = 'All')]
        [switch] $All,

        [Parameter(ParameterSetName = 'Single')]
        [Parameter(ParameterSetName = 'All')]
        [switch] $System
    )

    if ($All) { 
        if ($System) {
            foreach ($akey in $Node.$SA.Keys) 
            { 
                [PSCustomObject] @{ Key = $akey; Value = $Node.$SA[$akey]; System = $true } | Write-Output ; 
            }            
        }
        else {
            foreach ($akey in $Node.$A.Keys) 
            { 
                [PSCustomObject] @{ Key = $akey; Value = $Node.$A[$akey]; System = $false  } | Write-Output; 
            }    
        }
    }
    else { 
        if ($System) {
            if ($Node.$SA.ContainsKey($Key)) 
            {
                [PSCustomObject] @{ Key = $Key; Value = $Node.$SA[$Key]; System = $true  } | Write-Output ;     
            }
        }
        else {
            if ($Node.$A.ContainsKey($Key)) 
            {
                [PSCustomObject] @{ Key = $key; Value = $Node.$A[$key]; System = $false  } | Write-Output ; 
            }
        } 
    }
}
Set-Alias -Name:ga -Value:Get-Attribute
Export-ModuleMember -Function:Get-Attribute
Export-ModuleMember -Alias:ga

<#
    .SYNOPSIS
    Get attribute value.

    .PARAMETER Node
    Source node.

    .PARAMETER Key
    Attribute key.

    .PARAMETER System
    Switch, if used, system attributes are searched for a key.

    .EXAMPLE
    PS> $node =  nn -NodeName "child-A"
    PS> Set-AttributeValue -Node:$node -Key:"Normal" -Value:"I'm attr."
    PS> gav -N:$node -K:"Normal"

    I'm attr.

#>
function Get-AttributeValue {
    [CmdletBinding(DefaultParameterSetName="Default")]
    [OutputType([System.Object], ParameterSetName="Default")]

    param (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)] [hashtable] $Node,

        [Parameter(Mandatory = $true)] [string] $Key,

        [switch] $System
    )

    [PSCustomObject] $attr = $System ? (Get-Attribute -Node:$Node -Key:$Key -System) : (Get-Attribute -Node:$Node -Key:$Key);
    if ($attr) { return $attr.Value; }
}
Set-Alias -Name:gav -Value:Get-AttributeValue
Export-ModuleMember -Function:Get-AttributeValue
Export-ModuleMember -Alias:gav

<#
    .SYNOPSIS
    Validates attribute.

    .PARAMETER Node
    Used in scenarios when we need to compare with other attributes in the node.

    .PARAMETER AttributeInfo
    [PSCustomObject] with Key, Value, System.

    .EXAMPLE
    PS> $node =  nn -NodeName "child-A"
    PS> ga -N:$node -A -S | Test-Attribute

    Key         Value   System
    ---         -----   ------
    NodeName    child-A True
    Idx         0       True
    NextChildId 1       True
    
#>
function Test-Attribute {
    [CmdletBinding(DefaultParameterSetName="Default")]
    [OutputType([PSCustomObject], ParameterSetName="Default")]

    param (
        [Parameter(Mandatory = $false)] [hashtable] $Node,

        [Parameter(Mandatory = $false, ValueFromPipeline = $true)] [PSCustomObject] $AttributeInfo
    )

    Process { 
        if ( -not (
                ($AttributeInfo.Value -is [string]) -or 
                ($AttributeInfo.Value -is [int]) -or 
                ($AttributeInfo.Value -is [double]) -or 
                ($AttributeInfo.Value -is [bool]))) { throw "Attribute value type not allowed." }

        if ($AttributeInfo.System) 
        { 
            if (-not $sysAttr.Contains([SysAttrKey]::($AttributeInfo.Key))) { throw "System Attribute Key not allowed." } 

            if ([SysAttrKey]::NodeName -eq [SysAttrKey]::($AttributeInfo.Key)) {
                if ($AttributeInfo.Value -match '^[0-9]') { throw "Incorrect NodeName value." }
            }
        }
        else {

        }

        $AttributeInfo | Write-Output;
    }
}
Set-Alias -Name:ta -Value:Test-Attribute
Export-ModuleMember -Function:Test-Attribute
Export-ModuleMember -Alias:ta

<#
    .SYNOPSIS
    Creates AttributeInfo object.

    .PARAMETER Key

    .PARAMETER Value

    .PARAMETER System
    Switch on for system attributes.

    .EXAMPLE
    PS> na -K:"Price" -V:999.99 | Test-Attribute

    Key         Value   System
    ---         -----   ------
    Price       999,99  False

    
#>
function New-Attribute {
    [CmdletBinding(DefaultParameterSetName="Default")]
    [OutputType([PSCustomObject], ParameterSetName="Default")]

    param (
        [Parameter(Mandatory = $true)] [string] $Key,

        [Parameter(Mandatory = $true)] [object] $Value,

        [switch] $System
    )

    return [PSCustomObject]@{ Key = $Key; Value = $Value; System = $System } ; 
}
Set-Alias -Name:na -Value:New-Attribute
Export-ModuleMember -Function:New-Attribute
Export-ModuleMember -Alias:na

<#
    .SYNOPSIS
    Sets node with key and value contained in AttributeInfo object.

    .PARAMETER Node

    .PARAMETER AttributeInfo

    .PARAMETER PassThru
    Sends AttributeInfo object to output stream.

    .EXAMPLE
    PS> $node = nn -NodeName "child-A";
    PS> na -K:"Price" -V:999.99 | sa -Node:$node -PassThru

    Key         Value   System
    ---         -----   ------
    Price       999,99  False

#>
function Set-Attribute {
    [CmdletBinding(DefaultParameterSetName="Default")]
    [OutputType([PSCustomObject], ParameterSetName="Default")]

    param (
        [Parameter(Mandatory = $true)] [hashtable] $Node,

        [Parameter(Mandatory = $false, ValueFromPipeline = $true)] [PSCustomObject] $AttributeInfo,

        [switch] $PassThru
    )

    Process
    { 
        if ($AttributeInfo.System) {
            $Node.$SA[$AttributeInfo.Key] = $AttributeInfo.Value; 
        }
        else {
            $Node.$A[$AttributeInfo.Key] = $AttributeInfo.Value; 
        }

        if ($PassThru) { $AttributeInfo | Write-Output; }
    }
}
Set-Alias -Name:sa -Value:Set-Attribute
Export-ModuleMember -Function:Set-Attribute
Export-ModuleMember -Alias:sa

<#
    .SYNOPSIS
    Combines New-Attribute, Test-Attribute and Set-Attribute.

    .PARAMETER Node

    .PARAMETER Key

    .PARAMETER Value

    .PARAMETER System

    .PARAMETER PassThru
    Sends AttributeInfo object to output stream.

    .EXAMPLE
    PS> $node = nn -NodeName "child-A";
    PS> sav -N:$node -K:"Price" -V:999.99 -PassThru

    Key         Value   System
    ---         -----   ------
    Price       999,99  False

#>
function Set-AttributeValue {
    [CmdletBinding(DefaultParameterSetName="Default")]
    [OutputType([PSCustomObject], ParameterSetName="Default")]

    param (
        [Parameter(Mandatory = $true)] [hashtable] $Node,

        [Parameter(Mandatory = $true)] [string] $Key,

        [Parameter(Mandatory = $true)] [object] $Value,

        [switch] $System,

        [switch] $PassThru
    )

    New-Attribute -Key:$Key -Value:$Value -System:$System |
    Test-Attribute -Node:$Node |
    Set-Attribute -Node:$Node -PassThru:$PassThru;
}
Set-Alias -Name:sav -Value:Set-AttributeValue
Export-ModuleMember -Function:Set-AttributeValue
Export-ModuleMember -Alias:sav

<#
    .SYNOPSIS
    Removes attribute(s) from node. Attribute to remove can be passed as AttributeInfo objects in pipe or by Key.
    System attributes can't be removed.

    .PARAMETER Node

    .PARAMETER AttributeInfo

    .PARAMETER Key

    .PARAMETER PassThru
    Pass removed AttributeInfo object(s) to output stream.

    .EXAMPLE
    PS> $node = nn -NodeName "child-A";
    PS> na -K:"Price" -V:999.99 | sa -Node:$node;
    PS> #   remove all attributes from node with PassThru
    PS> ga -N:$node -A | ra -N:$node -P

    Key         Value   System
    ---         -----   ------
    Price       999,99  False

    .EXAMPLE
    PS> $node = nn -NodeName "child-A";
    PS> na -K:"Price" -V:999.99 | sa -Node:$node;
    PS> #   remove selected attribute from node with PassThru
    PS>  ra -N:$node -K:"Price" -P

    Key         Value   System
    ---         -----   ------
    Price       999,99  False

#>
function Remove-Attribute {
    [CmdletBinding(DefaultParameterSetName="Pipe")]
    [OutputType([PSCustomObject], ParameterSetName="Pipe")]
    [OutputType([PSCustomObject], ParameterSetName="Key")]

    param (
        [Parameter(ParameterSetName = 'Pipe')]
        [Parameter(ParameterSetName = 'Key')]
        [Parameter(Mandatory = $true)] [hashtable] $Node,

        [Parameter(ParameterSetName = 'Pipe')]
        [Parameter(Mandatory = $false, ValueFromPipeline = $true)] [PSCustomObject] $AttributeInfo,

        [Parameter(ParameterSetName = 'Key')]
        [Parameter(Mandatory = $false)] [string] $Key,

        [Parameter(ParameterSetName = 'Pipe')]
        [Parameter(ParameterSetName = 'Key')]
        [switch] $PassThru
    )

    Begin {
        [PSCustomObject[]] $toRemove = @();

        if ($Key) {
            $toRemove += (Get-Attribute -Node:$Node -Key:$Key);
        }
    }

    Process
    { 
        if ($AttributeInfo) {
            $toRemove += $AttributeInfo;            
        }
    }

    End {
        foreach ($ai in $toRemove) {
            if ($ai.System) {
                Write-Error "Removing system attributes not allowed.";
                # $Node.$SA.Remove($AttributeInfo.Key); 
            }
            else {
                $Node.$A.Remove($ai.Key); 
            }

            if ($PassThru) { $ai | Write-Output; }            
        }
    }
}
Set-Alias -Name:ra -Value:Remove-Attribute
Export-ModuleMember -Function:Remove-Attribute
Export-ModuleMember -Alias:ra

<#
    .SYNOPSIS
    Creates new node and sets initial system attributes.

    .PARAMETER NodeName

    .EXAMPLE
    PS> $node = nn -NodeName "child-A";
    PS> ga -N:$node -A -S

    Key         Value   System
    ---         -----   ------
    NodeName    child-A True
    Idx         0       True
    NextChildId 1       True

#>
function New-Node {
    [CmdletBinding(DefaultParameterSetName="Default")]
    [OutputType([hashtable], ParameterSetName="Default")]

    param (
        [string] $NodeName
    )

    [hashtable] $nn = @{ 
        $SA = @{};
        $A = @{};
    }

    Set-AttributeValue -Node:$nn -Key:([SysAttrKey]::NodeName) -Value:$NodeName -System ;
    Set-AttributeValue -Node:$nn -Key:([SysAttrKey]::NextChildId) -Value:1 -System ;
    Set-AttributeValue -Node:$nn -Key:([SysAttrKey]::Idx) -Value:0 -System ;

    return $nn;
}
Set-Alias -Name:nn -Value:New-Node
Export-ModuleMember -Function:New-Node
Export-ModuleMember -Alias:nn

#endregion

#region tree
function ConvertTo-ByNameHtPath {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)] [hashtable] $Tree,
        [Parameter(Mandatory = $true)] [object] $Path
    )

    $htPath = ($Path -is [string] ) ? (ConvertTo-HtPath -Path:$Path) : [PSCustomObject] $Path;
    if ($htPath.Descriptive -eq $true) { throw "Path must be id type." }

    $byNamePathArray = @();
    for ($idx = 0 ; $idx -lt $htPath.Parts.Count ; $idx++) {
        $subArray = $htPath.Parts[0..$idx];
        $subPath = $subArray -join $pdel;
        $node = $Tree[$subPath];
        if ($null -eq $node) { throw "Node not found" }
        $name = Get-Attribute -N:$node -K:([SysAttrKey]::NodeName) -S;
        if (-not $name) { $name = Get-Attribute -N:$node -K:([SysAttrKey]::Id) -S; }
        $byNamePathArray += $name;
    }

    return ConvertTo-HtPath -P:($byNamePathArray -join $pdel) ;

}
Export-ModuleMember -Function:ConvertTo-ByNameHtPath

function Get-Node {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)] [hashtable] $Tree,
        [Parameter(Mandatory = $false)] [string] $Path,
        [switch] $Recurse
    )

    if (-not $Path) {
        $Path = "*";
        $Recurse = $true;
    }

    $patternHtPath = ConvertTo-HtPath -Path:$Path;
    $out = @();

    $Tree.Keys | 
    ForEach-Object {
        $nodeHtPath = ConvertTo-htPath -Path:$_;  
        if ($patternHtPath.Descriptive -eq $false) {
            $match = (Compare-HtPath -Pattern:$patternHtPath -ToCompare:$nodeHtPath -Recurse:$Recurse);
        } 
        elseif ($patternHtPath.Descriptive -eq $true) {
            $nodeByNameHtPath = ConvertTo-ByNameHtPath -T:$Tree -Path:$nodeHtPath;
            $match = (Compare-HtPath -Pattern:$patternHtPath -ToCompare:$nodeByNameHtPath -Recurse:$Recurse);
        }
        
        if ($match) { $out += $Tree[$_]; }
    }
    return ,$out;
}
Set-Alias -Name:gn -Value:Get-Node
Export-ModuleMember -Function:Get-Node
Export-ModuleMember -Alias:gn

function Add-Node {
    param (
        [Parameter(Mandatory = $true)] [hashtable] $Tree,
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)] [hashtable] $Node,
        [Parameter(Mandatory = $false)] [string] $ParentPath
    )

    Process {

        $copy = Copy-HashtableDeep -InputObject:$Node;
        
        if (-not $ParentPath) {
            $nodePath = Get-Attribute -N:$copy -K:([SysAttrKey]::Path) -S;
            if (-not $nodePath) { throw "Undefined path." }
            $nodeHtPath = ConvertTo-HtPath -Path:$nodePath;
            if (-not $nodeHtPath.ParentPath) { throw "Undefined parent path." }
            $ParentPath = $nodeHtPath.ParentPath;
        }

        $parents = Get-Node -Tree:$Tree -Path:$ParentPath;
        if (-not $parents) { throw "Parent not found." }
        if ($parents.Count -gt 1) { throw "Multiple parent not allowed." }

        $parent = $parents | Select-Object -First 1;

        $copyName = Get-Attribute -N:$copy -K:([SysAttrKey]::NodeName) -S;
        $allChilds = Get-Node -Tree:$Tree -Path:("${ParentPath}${pdel}*");
        $allChilds | ForEach-Object { 
            $childName = Get-Attribute -N:$_ -K:([SysAttrKey]::NodeName) -S;
            if ($copyName -eq $childName) { throw "Child with the same name already exists." }
        }

        $nextId = Get-Attribute -N:$parent -K:([SysAttrKey]::NextChildId) -S;

        $newPath = "${ParentPath}${pdel}${nextId}";        
        $copy | Set-SysAttribute -Key:([SysAttrKey]::Id) -Value:$nextId |
        Set-SysAttribute -Key:([SysAttrKey]::Path) -Value:$newPath | Out-Null
        $Tree[$newPath] = $copy;

        $nextId++;
        Set-SysAttribute -Node:$parent -Key:([SysAttrKey]::NextChildId) -Value:$nextId | Out-Null;

    }
}
Set-Alias -Name:an -Value:Add-Node
Export-ModuleMember -Function:Add-Node
Export-ModuleMember -Alias:an

function Remove-Node {
    param (
        [Parameter(Mandatory = $true)] [hashtable] $Tree,
        [Parameter(Mandatory = $false, ValueFromPipeline = $true)] [hashtable] $Node,
        [Parameter(Mandatory = $false)] [string] $Path
    )

    Begin {
        [string[]] $keys = @(); 
        if ($Path) {
            $allChilds = Get-Node -Tree:$Tree -Path:$Path -Recurse;
            $allChilds | ForEach-Object { 
                $childPath = Get-Attribute -Node:$_ -Key:([SysAttrKey]::Path) -S;
                $keys += $childPath;
            }
        }
    }

    Process {
        if ($Node) 
        {
            $nodePath = Get-Attribute -Node:$Node -Key:([SysAttrKey]::Path) -S;
            $allChilds = Get-Node -Tree:$Tree -Path:$nodePath -Recurse;
            $allChilds | ForEach-Object { 
                $childPath = Get-Attribute -Node:$_ -Key:([SysAttrKey]::Path) -S;
                $keys += $childPath;
            }            
        }
    }
    End {
        $keys | Sort-Object -Descending | ForEach-Object { $Tree.Remove($_); }
    }
}
Set-Alias -Name:rmn -Value:Remove-Node
Export-ModuleMember -Function:Remove-Node
Export-ModuleMember -Alias:rmn

function New-Tree {
    [CmdletBinding()]
    param (
        [string] $Path
    )

    $root = (nn -Id:"0" -NodeName:"Root" | 
    Set-SysAttribute -K:"Path" -Value:$Path);

    $t = @{ 
        '0' = $root;
    }

    return $t
}

Set-Alias -Name:nt -Value:New-Tree
Export-ModuleMember -Function:New-Tree
Export-ModuleMember -Alias:nt

#endregion

#region export
function Import-Tree {
    [CmdletBinding()]
    param (
        [Parameter(ValueFromPipeline = $true)]
        [System.IO.FileInfo] $FileInfo
    )

    $ext = $FileInfo.Extension;
    switch ($ext) {
            { $_ -eq ("." + [FileFormat]::psd1) } { 
                $tree = Import-PowerShellDataFile -Path:($FileInfo.FullName) -SkipLimitCheck ;
                break; 
            }
            default { throw "File format '$ext' not supported." }
    }
    Set-SysAttribute -N:($tree.'0') -K:'Path' -V:($FileInfo.FullName) | Out-Null;
    return $tree;
}

Set-Alias -Name:impt -Value:Import-Tree
Export-ModuleMember -Function:Import-Tree
Export-ModuleMember -Alias:impt

function Get-ValuePsd1 {
    param (
        [Parameter(Mandatory = $false)] [object] $value
    )

    if ($value -is [string]) { $formatted = "'$($value)'"; }
    elseif ($value -is [boolean]) { $formatted = $value ? "`$true" : "`$false"; }
    elseif ($null -eq $value) { $formatted = "`$null"; }
    else { $formatted = $value; }

    return $formatted;
}

function Get-AttributeLinesPsd1 {
    param (
        [Parameter(Mandatory = $true)] [hashtable] $attr,
        [Parameter(Mandatory = $false)] [int] $offset = 0
    )

    $outputLines = New-Object 'System.Collections.Generic.List[string]';
    $attrLines = New-Object 'System.Collections.Generic.List[string]';

    $keys = ($attr.Keys | Sort-Object);

    foreach ($key in $keys) 
    {
        if ($null -eq $attr[$key]) { continue; } 
        $attrLines.Add("$("`t" * $offset)`t'${key}' = $(Get-ValuePsd1 -value:($attr[$key]));"); 
    }

    if ($attrLines.Count -eq 0) {
        $outputLines.Add("@{};");
    }
    else {
        $outputLines.Add("$("`t" * $offset)@{");
        $outputLines.AddRange($attrLines);
        $outputLines.Add("$("`t" * $offset)};");        
    }

    return ,$outputLines;
}

function Get-NodeLinesPsd1 {
    param (
        [Parameter(Mandatory = $true)] [hashtable] $node,
        [Parameter(Mandatory = $false)] [int] $offset = 0
    )

    $output = New-Object 'System.Collections.Generic.List[string]';
    $output.Add("$("`t" * $offset)@{");

    $lines = (Get-AttributeLinesPsd1 -attr:($node.$SA) -offset:($offset + 1));
    if ($lines.Count -eq 1) { $output.Add("$("`t" * $offset)'${SA}' = " + $lines[0]); }
    else { 
        $output.Add("$("`t" * $offset)'${SA}' = ");
        $output.AddRange($lines); 
    }

    $lines = (Get-AttributeLinesPsd1 -attr:($node.$A) -offset:($offset + 1));
    if ($lines.Count -eq 1) { $output.Add("$("`t" * $offset)'${A}' = " + $lines[0]); }
    else { 
        $output.Add("$("`t" * $offset)'${A}' = ");
        $output.AddRange($lines); 
    }

    $output.Add("$("`t" * $offset)};");

    return ,$output;
}

function Get-TreeContentPsd1 {
    param (
        [Parameter(Mandatory = $true)] [hashtable] $tree
    )

    $output = New-Object 'System.Collections.Generic.List[string]';
    $output.Add("@{");

    $keys = $tree.Keys | Sort-Object
    foreach ($key in $keys) 
    {
        $output.Add("`t'${key}' =");
        $output.AddRange((Get-NodeLinesPsd1 -node:($tree[$key]) -offset:2 ));
    }

    $output.Add("};");

    return $output.ToArray() -join "`n";
}

function Export-Tree {
    [CmdletBinding()]
    param (
        [Parameter(ValueFromPipeline = $true)] 
        [hashtable] $Tree,

        [Parameter(Mandatory = $false)] [Alias("P")] [string] $Path
    )

    Process {
        if ( -not $Path) { $Path = (ga -N:($Tree.'0') -K:"Path" -S) }
        if (-not $Path) { throw "Path not specified." }
        $ext = [System.IO.Path]::GetExtension($Path);

        switch ($ext) {
            { $_ -eq ("." + [FileFormat]::psd1) } { 
                $content = Get-TreeContentPsd1 -tree:$Tree;
                break; 
            }
            default { throw "File format '$ext' not supported." }
        }

        Set-Content -Path:$Path -Value:$content;
        Get-Item -Path:$Path;           
    }
}

Set-Alias -Name:expt -Value:Export-Tree
Export-ModuleMember -Function:Export-Tree
Export-ModuleMember -Alias:expt
#endregion


Write-Host "HashTree imported"