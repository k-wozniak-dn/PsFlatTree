#region const
enum FileFormat {psd1; json; xml; csv; }
enum NodeSection { SA; A; }
enum SysAttrKey {
    Path; Id; NodeName; NextChildId; Idx; FilePath; TreeType; TreeId
}
enum Position {
    Unchanged; First; Last
}

# Path delimiter
Set-Variable -Name 'pdel' -Value ':' -Option ReadOnly;

Set-Variable -Name 'SA' -Value "$([NodeSection]::SA)" -Option ReadOnly;
Set-Variable -Name 'A' -Value "$([NodeSection]::A)" -Option ReadOnly;
$sysAttr = @(
    [SysAttrKey]::Path; [SysAttrKey]::Id; [SysAttrKey]::NodeName; [SysAttrKey]::NextChildId; 
    [SysAttrKey]::Idx; [SysAttrKey]::FilePath; [SysAttrKey]::TreeType; [SysAttrKey]::TreeId);

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
    PS> cvftp -P:"0:section_A:node_X"

    Level       : 3
    Descriptive : True
    Parts       : {0, section_A, node_X}
    Id          : node_X
    ParentPath  : 0:section_A
    FullPath    : 0:section_A:node_X

    .EXAMPLE
    PS> "0:4:9" | cvftp 

    Level       : 3
    Descriptive : False
    Parts       : {0, 4, 9}
    Id          : 9
    ParentPath  : 0:4
    FullPath    : 0:4:9

#>
function ConvertTo-FtPath {
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
Set-Alias -Name:cvftp -Value:ConvertTo-FtPath
Export-ModuleMember -Function:ConvertTo-FtPath
Export-ModuleMember -Alias:cvftp

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
    PS> $tp = ( "0:4:9" | cvftp )
    PS> $pp = ( "0:4:*" | cvftp )
    PS> crftp -P:$pp -T:$tp 
    True

    .EXAMPLE
    wildcard non-recurse
    PS> $tp = ( "0:4:9" | cvftp )
    PS> $pp = ( "0:*" | cvftp )
    PS> crftp -P:$pp -T:$tp 
    False

    .EXAMPLE
    wildcard recurse
    PS> $tp = ( "0:4:9" | cvftp )
    PS> $pp = ( "0:*" | cvftp )
    PS> crftp -P:$pp -T:$tp -R
    True

#>
function Compare-FtPath {
    [CmdletBinding(DefaultParameterSetName="Default")]
    [OutputType([bool], ParameterSetName="Default")]

    param (
        [Parameter(Mandatory = $true)] [PSCustomObject] $Pattern,
        [Parameter(Mandatory = $true)] [PSCustomObject] $Tested,
        [switch] $Recurse
    )

    if ($null -eq $Tested.Level -or $null -eq $Pattern.Level) { throw "FtPath object(s) must have Level property set." }

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
Set-Alias -Name:crftp -Value:Compare-FtPath
Export-ModuleMember -Function:Compare-FtPath
Export-ModuleMember -Alias:crftp

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
    PS> $node =  nnode -NodeName "child-A"
    PS> $node | gattr -All -System

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
                [PSCustomObject] @{ Key = $Key; Value = $Node.$A[$Key]; System = $false  } | Write-Output ; 
            }
        } 
    }
}
Set-Alias -Name:gattr -Value:Get-Attribute
Export-ModuleMember -Function:Get-Attribute
Export-ModuleMember -Alias:gattr

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
    PS> $node =  nnode -NodeName "child-A"
    PS> Set-AttributeValue -Node:$node -Key:"Normal" -Value:"I'm attr."
    PS> gattrv -N:$node -K:"Normal"

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
Set-Alias -Name:gattrv -Value:Get-AttributeValue
Export-ModuleMember -Function:Get-AttributeValue
Export-ModuleMember -Alias:gattrv

<#
    .SYNOPSIS
    Validates attribute.

    .PARAMETER Node
    Used in scenarios when we need to compare with other attributes in the node.

    .PARAMETER AttributeInfo
    [PSCustomObject] with Key, Value, System.

    .EXAMPLE
    PS> $node =  nnode -NodeName "child-A"
    PS> gattr -N:$node -A -S | Test-Attribute

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
                if ($AttributeInfo.Value -match '^[0-9]') { throw "Incorrect NodeName value." };
                if ($AttributeInfo.Value.Contains($pdel)) { throw "Node name can't contain path delimiter." }
            }
        }
        else {

        }

        $AttributeInfo | Write-Output;
    }
}
Set-Alias -Name:tattr -Value:Test-Attribute
Export-ModuleMember -Function:Test-Attribute
Export-ModuleMember -Alias:tattr

<#
    .SYNOPSIS
    Creates AttributeInfo object.

    .PARAMETER Key

    .PARAMETER Value

    .PARAMETER System
    Switch on for system attributes.

    .EXAMPLE
    PS> nattr -K:"Price" -V:999.99 | Test-Attribute

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
Set-Alias -Name:nattr -Value:New-Attribute
Export-ModuleMember -Function:New-Attribute
Export-ModuleMember -Alias:nattr

<#
    .SYNOPSIS
    Sets node with key and value contained in AttributeInfo object.

    .PARAMETER Node

    .PARAMETER AttributeInfo

    .PARAMETER PassThru
    Sends AttributeInfo object to output stream.

    .EXAMPLE
    PS> $node = nnode -NodeName "child-A";
    PS> nattr -K:"Price" -V:999.99 | sattr -Node:$node -PassThru

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
Set-Alias -Name:sattr -Value:Set-Attribute
Export-ModuleMember -Function:Set-Attribute
Export-ModuleMember -Alias:sattr

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
    PS> $node = nnode -NodeName "child-A";
    PS> sattrv -N:$node -K:"Price" -V:999.99 -PassThru

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
Set-Alias -Name:sattrv -Value:Set-AttributeValue
Export-ModuleMember -Function:Set-AttributeValue
Export-ModuleMember -Alias:sattrv

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
    PS> $node = nnode -NodeName "child-A";
    PS> nattr -K:"Price" -V:999.99 | sattr -Node:$node;
    PS> #   remove all attributes from node with PassThru
    PS> gattr -N:$node -A | rattr -N:$node -P

    Key         Value   System
    ---         -----   ------
    Price       999,99  False

    .EXAMPLE
    PS> $node = nnode -NodeName "child-A";
    PS> nattr -K:"Price" -V:999.99 | sattr -Node:$node;
    PS> #   remove selected attribute from node with PassThru
    PS>  rattr -N:$node -K:"Price" -P

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
Set-Alias -Name:rattr -Value:Remove-Attribute
Export-ModuleMember -Function:Remove-Attribute
Export-ModuleMember -Alias:rattr

<#
    .SYNOPSIS
    Creates new node and sets initial system attributes.

    .PARAMETER NodeName

    .EXAMPLE
    PS> $node = nnode -NodeName "child-A";
    PS> gattr -N:$node -A -S

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

    if ($NodeName) { Set-AttributeValue -Node:$nn -Key:([SysAttrKey]::NodeName) -Value:$NodeName -System ;}
    Set-AttributeValue -Node:$nn -Key:([SysAttrKey]::NextChildId) -Value:1 -System ;
    #   new node is not indexed until it's added to the tree
    Set-AttributeValue -Node:$nn -Key:([SysAttrKey]::Idx) -Value:-1 -System ;

    return $nn;
}
Set-Alias -Name:nnode -Value:New-Node
Export-ModuleMember -Function:New-Node
Export-ModuleMember -Alias:nnode

#endregion

#region tree

<#
    .SYNOPSIS
    Covverts numeric path to descriptive path.
    It's used internally by Get-Node command.

    .PARAMETER Tree

    .PARAMETER Path
    Could be either string or converted to FtPath (PSCustomObject).

    .EXAMPLE
    PS> $tree = gci .\test.psd1 | ipt     # importing tree
    PS> cvdftp -T:$t -P:"0"             # converting numeric root path to descriptive

    Level       : 1
    Descriptive : True
    Parts       : {Root}
    Id          : Root
    ParentPath  : 
    FullPath    : Root

    PS> cvdftp -T:$t -P:"0:1"           # converting numeric 2-part path to descriptive

    Level       : 2
    Descriptive : True
    Parts       : {Root, child-A}
    Id          : child-A
    ParentPath  : Root
    FullPath    : Root:child-A


#>
function ConvertTo-DescriptiveFtPath {
    [CmdletBinding(DefaultParameterSetName="Default")]
    [OutputType([PsCustomObject], ParameterSetName="Default")]

    param (
        [Parameter(Mandatory = $true)] [hashtable] $Tree,
        [Parameter(Mandatory = $true)] [object] $Path
    )

    [PSCustomObject] $FtPath = ($Path -is [string] ) ? (ConvertTo-FtPath -Path:$Path) : $Path;
    if ($FtPath.Descriptive -eq $true) { throw "Path is already descriptive." }

    [string[]] $descriptivePathArray = @();
    for ($partIdx = 0 ; $partIdx -lt $FtPath.Parts.Count ; $partIdx++) {
        [string[]] $subArray = $FtPath.Parts[0..$partIdx];
        [string] $subPath = $subArray -join $pdel;
        [hashtable] $node = $Tree[$subPath];
        if ($null -eq $node) { throw "Node not found." }
        [string] $name = Get-AttributeValue -N:$node -K:([SysAttrKey]::NodeName) -S;
        if (-not $name) { [string] $name = Get-AttributeValue -N:$node -K:([SysAttrKey]::Id) -S; }
        $descriptivePathArray += $name;
    }

    return ConvertTo-FtPath -P:($descriptivePathArray -join $pdel) ;

}
Set-Alias -Name:cvdftp -Value:ConvertTo-DescriptiveFtPath
Export-ModuleMember -Function:ConvertTo-DescriptiveFtPath
Export-ModuleMember -Alias:cvdftp

<#
    .SYNOPSIS
    Get node(s) from a tree using pattern path.

    .PARAMETER Tree
    Source tree.

    .PARAMETER PatternPath
    Could be either nomeric as "0:1:7" or descriptive as "Root:Section-A:ImportantNode".
    Descriptive path parts are constructed from node names.
    In case node has no name, Id is used instead, as "Root:Section-A:7" (Id = 7 is used for unnamed node).
    Wildcard are also permitted as "Root:Section-A:*" gets all children of  "Root:Section-A".

    .PARAMETER Recurse
    Switch, if used, result contains all descendants of selected node(s).

    .EXAMPLE
    PS> $t = gci .\test.psd1 | ipt        # importing tree
    PS> gnode -T:$t -P:"Root:child-a:*"    # get all direct children of "Root:child-a" node using descriptive pattern

    Name                           Value
    ----                           -----
    A                              {}
    SA                             {[Path, 0:1:1], [Id, 1], [NodeName, child-A], [NextChildId, 1]…}
    A                              {}
    SA                             {[Path, 0:1:2], [Id, 2], [NodeName, child-B], [NextChildId, 1]…}
    A                              {}
    SA                             {[Path, 0:1:3], [Id, 3], [NextChildId, 1], [Idx, 0]}

    PS> (gnode -T:$t -P:"Root:child-a:*").Count    # checks number of nodes in result collection

    3

    .EXAMPLE
    PS> $t = gci .\test.psd1 | ipt        # importing tree
    PS> gnode -T:$t -P:"Root:child-a" -Recurse    # get "Root:child-a" node with all descendants using -Recurse switch

    Name                           Value
    ----                           -----
    A                              {}
    SA                             {[Path, 0:1], [Id, 1], [NodeName, child-A], [NextChildId, 4]…}
    A                              {}
    SA                             {[Path, 0:1:1], [Id, 1], [NodeName, child-A], [NextChildId, 1]…}
    A                              {}
    SA                             {[Path, 0:1:2], [Id, 2], [NodeName, child-B], [NextChildId, 1]…}
    A                              {}
    SA                             {[Path, 0:1:3], [Id, 3], [NextChildId, 1], [Idx, 0]}

#>
function Get-Node {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)] [hashtable] $Tree,
        [Parameter(Mandatory = $false)] [string] $PatternPath,
        [switch] $Recurse
    )

    if (-not $PatternPath) {
        $PatternPath = "*";
        $Recurse = $true;
    }

    [PSCustomObject] $patternFtPath = ConvertTo-FtPath -Path:$PatternPath;
    [hashtable[]] $nodes = @();

    [string[]] $sortedKeys =  $Tree.Keys | Sort-Object;

    foreach ($nodeKey in $sortedKeys)
    {
        [PSCustomObject] $nodeFtPath = ConvertTo-FtPath -Path:$nodeKey;  
        if ($patternFtPath.Descriptive -eq $false) {
            [bool] $match = (Compare-FtPath -Pattern:$patternFtPath -Tested:$nodeFtPath -Recurse:$Recurse);
        } 
        elseif ($patternFtPath.Descriptive -eq $true) {
            [PSCustomObject] $nodeDescriptiveFtPath = ConvertTo-DescriptiveFtPath -T:$Tree -Path:$nodeFtPath;
            [bool] $match = (Compare-FtPath -Pattern:$patternFtPath -Tested:$nodeDescriptiveFtPath -Recurse:$Recurse);
        }
        
        if ($match) { 
            $nodes += $Tree[$nodeKey] ; 
        }
    }

    $nodes | Write-Output;
}
Set-Alias -Name:gnode -Value:Get-Node
Export-ModuleMember -Function:Get-Node
Export-ModuleMember -Alias:gnode

function Set-NodeIndex {
    param (
        [Parameter(Mandatory = $true)] [hashtable] $Tree,
        [Parameter(Mandatory = $true)] [string] $Path,
        [Parameter(Mandatory = $false)] [Position] $Position = [Position]::Unchanged,
        [Parameter(Mandatory = $false)] [int] $Move = 0,
        [switch] $PassThru
    )

    # list to hold sibling paths ordered by Idx
    $indexedList = New-Object 'System.Collections.Generic.List[string]';

    # node to set Idx
    [hashtable] $nodeToSet = Get-Node -Tree:$Tree -PatternPath:$Path;
    if (-not $nodeToSet) { throw "Node to set not found." }

    [PSCustomObject] $ftPath = ConvertTo-FtPath -Path:$Path;
    [string] $allChildrenPath = "$($ftPath.ParentPath)${pdel}*";

    # selecting siblings of the node to set Idx
    [PSCustomObject[]] $allChildren = ( Get-Node -Tree:$Tree -PatternPath:($allChildrenPath) | 
        Sort-Object @{ Expression = { $_[$SA]["$([SysAttrKey]::Idx)"] } } | 
        Select-Object @{ n='Path'; e = { $_[$SA]["$([SysAttrKey]::Path)"] } } )

    # load the list of siblings
    foreach ($child in $allChildren) {
        # node to set excluded from the list
        if ($child.Path -ne $Path) { $indexedList.Add($child.Path); }
    }

    # calculating Idx for node to set
    [int] $currentPos = Get-AttributeValue -Node:$nodeToSet -Key:([SysAttrKey]::Idx) -System;
    [int] $setIdx = ($Position -eq [Position]::Unchanged) ? $currentPos : (($Position -eq [Position]::First) ? 0 : $indexedList.Count);
    $setIdx += $Move;
    # protect against out of boundaries exception
    if ($setIdx -lt 0) { $setIdx = 0; } elseif ($setIdx -gt $indexedList.Count) { $setIdx = $indexedList.Count }
    # inserting or adding node to set to the list at required position
    if ($setIdx -lt $indexedList.Count) { $indexedList.Insert($setIdx, $Path) } else { $indexedList.Add($Path); }

    # resetting all siblings Idx according to the position on the list
    foreach ($childPath in $indexedList) {
        [hashtable] $childNode = $Tree[$childPath];
        [int] $childIdx = $indexedList.IndexOf($childPath);
        Set-AttributeValue -Node:$childNode -Key:([SysAttrKey]::Idx) -Value:$childIdx -System;
    }

    if ($PassThru) { $nodeToSet | Write-Output; }
}
Export-ModuleMember -Function:Set-NodeIndex

<#
    .SYNOPSIS
    Adds node to the Tree.
    At least root must exist prior nodes can be added to the tree.
    Root is automatically created during Tree creation. 

    .PARAMETER Tree

    .PARAMETER Node

    .PARAMETER ParentPath
    Path to the parent node to which node is added.

    .PARAMETER PassThru
    Sends added node object to output stream.

    .EXAMPLE
    PS> $t = gci .\test.psd1 | ipt        #   tree import
    PS> $n = nnode -NodeName "child-B-1"   # new node creation
    PS> $n | anode -T:$t -Parent:"Root:child-b" -Pass      #   adding node

    Name                           Value
    ----                           -----
    A                              {}
    SA                             {[Path, 0:2:1], [Id, 1], [NodeName, child-B-1], [NextChildId, 1]…}

    PS> gnode -T:$t -P:"Root:child-b" -Recurse     #   getting nodes to check new node was added

    Name                           Value
    ----                           -----
    A                              {[NextChildId, 2]}
    SA                             {[Path, 0:2], [Id, 2], [NodeName, child-B], [NextChildId, 1]…}
    A                              {}
    SA                             {[Path, 0:2:1], [Id, 1], [NodeName, child-B-1], [NextChildId, 1]…}

#>
function Add-Node {
    param (
        [Parameter(Mandatory = $true)] [hashtable] $Tree,
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)] [hashtable] $Node,
        [Parameter(Mandatory = $false)] [string] $ParentPath,
        [switch] $PassThru
    )

    Process {

        [hashtable] $copy = Copy-HashtableDeep -InputObject:$Node;
        
        #   getting new node's parent; root must exist and can't be added; root is created when tree is created
        if (-not $ParentPath) {
            [string] $nodePath = Get-AttributeValue -N:$copy -K:([SysAttrKey]::Path) -S;
            if (-not $nodePath) { throw "Undefined path." }
            [PSCustomObject] $nodeFtPath = ConvertTo-FtPath -Path:$nodePath;
            [string] $ParentPath = $nodeFtPath.ParentPath ;
            if (-not $ParentPath) { throw "Undefined parent path." }
        }

        [hashtable] $parent = Get-Node -Tree:$Tree -PatternPath:$ParentPath;
        if (-not $parent) { throw "Parent not found." }

        #   protect against adding node with the name which already exist 
        [string] $copyName = Get-AttributeValue -N:$copy -K:([SysAttrKey]::NodeName) -S;
        [hashtable[]] $allChilds = Get-Node -Tree:$Tree -PatternPath:("${ParentPath}${pdel}*");
        foreach ( $child in $allChilds)
        {
            [string] $childName = Get-AttributeValue -Node:$child -K:([SysAttrKey]::NodeName) -S;
            if ($copyName -eq $childName) { throw "Child with the same name already exists." }            
        }

        #   attaching new node to the tree
        [int] $nextId = Get-AttributeValue -Node:$parent -Key:([SysAttrKey]::NextChildId) -S;
        [string] $newPath = "${ParentPath}${pdel}${nextId}";    
        Set-AttributeValue -Node:$copy -Key:([SysAttrKey]::Id) -Value:$nextId -System;
        Set-AttributeValue -Node:$copy -Key:([SysAttrKey]::Path) -Value:$newPath -System;
        #   new node will be unindexed
        Set-AttributeValue -Node:$copy -Key:([SysAttrKey]::Idx) -Value:-1 -System ;
        $Tree[$newPath] = $copy;

        #   increment parent's next id
        $nextId++;
        Set-AttributeValue -Node:$parent -Key:([SysAttrKey]::NextChildId) -Value:$nextId -System;

        #   Set Idx of new node to Last
        Set-NodeIndex -T:$Tree -Path:$newPath -Position:([Position]::Last);

        if ($PassThru) { $copy | Write-Output; }
    }
}
Set-Alias -Name:anode -Value:Add-Node
Export-ModuleMember -Function:Add-Node
Export-ModuleMember -Alias:anode

<#
    .SYNOPSIS
    Removes node(s) from tree. Node to remove can be passed in pipe or by Path.
    Path may contain wildcards.
    Removed node's descendats are also removed.

    .PARAMETER Tree

    .PARAMETER Node

    .PARAMETER Path

    .PARAMETER PassThru
    Pass removed node object(s) to output stream.

    .EXAMPLE
    PS> $t = gci .\test.psd1 | ipt   #   import tree
    PS> rnode -T:$t -Path:"0:1" -Pass ;   #   remove node "0:1" (with descendants) and PassThru

    Name                           Value
    ----                           -----
    A                              {}
    SA                             {[Path, 0:1:3], [Id, 3], [NextChildId, 1], [Idx, 0]}
    A                              {}
    SA                             {[Path, 0:1:2], [Id, 2], [NodeName, child-B], [NextChildId, 1]…}
    A                              {}
    SA                             {[Path, 0:1:1], [Id, 1], [NodeName, child-A], [NextChildId, 1]…}
    A                              {}
    SA                             {[Path, 0:1], [Id, 1], [NodeName, child-A], [NextChildId, 4]…}


#>
function Remove-Node {
    [CmdletBinding(DefaultParameterSetName="Pipe")]
    [OutputType([hashtable], ParameterSetName="Pipe")]
    [OutputType([hashtable], ParameterSetName="Path")]

    param (
        [Parameter(ParameterSetName = 'Pipe')]
        [Parameter(ParameterSetName = 'Path')]
        [Parameter(Mandatory = $true)] [hashtable] $Tree,

        [Parameter(ParameterSetName = 'Pipe')]
        [Parameter(Mandatory = $false, ValueFromPipeline = $true)] [hashtable] $Node,

        [Parameter(ParameterSetName = 'Path')]
        [Parameter(Mandatory = $false)] [string] $Path,

        [Parameter(ParameterSetName = 'Pipe')]
        [Parameter(ParameterSetName = 'Path')]
        [switch] $PassThru
    )

    Begin {
        [string[]] $keys = @(); 
        if ($Path) {
            $allChilds = Get-Node -Tree:$Tree -PatternPath:$Path -Recurse;
            foreach ($child in $allChilds) 
            { 
                [string] $childPath = Get-AttributeValue -Node:$child -Key:([SysAttrKey]::Path) -S;
                $keys += $childPath;
            }
        }
    }

    Process {
        if ($Node) 
        {
            [string] $nodePath = Get-AttributeValue -Node:$Node -Key:([SysAttrKey]::Path) -S;
            [hashtable[]] $allChilds = Get-Node -Tree:$Tree -PatternPath:$nodePath -Recurse;
            foreach ($child in $allChilds) 
            { 
                [string] $childPath = Get-AttributeValue -Node:$child -Key:([SysAttrKey]::Path) -S;
                $keys += $childPath;
            }
        }
    }
    End {
        $keys | 
        Sort-Object -Descending | 
        ForEach-Object {
            [hashtable] $removed = $Tree[$_];
            $Tree.Remove($_);
            if ($PassThru) { $removed | Write-Output }
        }
    }
}
Set-Alias -Name:rnode -Value:Remove-Node
Export-ModuleMember -Function:Remove-Node
Export-ModuleMember -Alias:rnode

function New-Tree {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)] [string] $TreeType,
        [Parameter(Mandatory = $false)] [string] $TreeId
    )

    [PSCustomObject] $root = New-Node -NodeName:"Root" ;
    [string] $rootPath = '0';
    Set-AttributeValue -Node:$root -Key:([SysAttrKey]::Id) -Value:0 -System;
    Set-AttributeValue -Node:$root -Key:([SysAttrKey]::Path) -Value:$rootPath -System;
    Set-AttributeValue -Node:$root -Key:([SysAttrKey]::Idx) -Value:0 -System;

    if ($TreeType) { Set-AttributeValue -Node:$root -Key:([SysAttrKey]::TreeType) -Value:$TreeType -System; }
    if ($TreeId) { Set-AttributeValue -Node:$root -Key:([SysAttrKey]::TreeId) -Value:$TreeId -System; }

    [hashtable] $tree = @{ $rootPath = $root }
    return $tree
}

Set-Alias -Name:ntree -Value:New-Tree
Export-ModuleMember -Function:New-Tree
Export-ModuleMember -Alias:ntree

#endregion

#region export

<#
    .SYNOPSIS
    Imports FlatTree stored in a file.
    Supported formats : psd1.

    .PARAMETER FileInfo
    Object returned by Get-ChildItem, Get-Item from FileProvider

    .EXAMPLE
    PS> $tree = gi .\test.psd1 | iptree ;


#>
function Import-Tree {
    [CmdletBinding()]
    param (
        [Parameter(ValueFromPipeline = $true)]
        [System.IO.FileInfo] $FileInfo
    )

    [string] $ext = $FileInfo.Extension;
    switch ($ext) {
            { $_ -eq ("." + [FileFormat]::psd1) } { 
                [hashtable] $tree = Import-PowerShellDataFile -Path:($FileInfo.FullName) -SkipLimitCheck ;
                break; 
            }
            default { throw "File format '$ext' not supported." }
    }
    [hashtable] $root = Get-Node -Tree:$tree -PatternPath:'0';
    if (-not $root) { throw "Root not found." }
    Set-AttributeValue -N:$root -K:([SysAttrKey]::FilePath) -V:($FileInfo.FullName) -System;
    return $tree;
}

Set-Alias -Name:iptree -Value:Import-Tree
Export-ModuleMember -Function:Import-Tree
Export-ModuleMember -Alias:iptree

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
        [Parameter(Mandatory = $true)] [hashtable] $Node,
        [Parameter(Mandatory = $false)] [int] $offset = 0
    )

    $output = New-Object 'System.Collections.Generic.List[string]';
    $output.Add("$("`t" * $offset)@{");

    $lines = (Get-AttributeLinesPsd1 -attr:($Node.$SA) -offset:($offset + 1));
    if ($lines.Count -eq 1) { $output.Add("$("`t" * $offset)'${SA}' = " + $lines[0]); }
    else { 
        $output.Add("$("`t" * $offset)'${SA}' = ");
        $output.AddRange($lines); 
    }

    $lines = (Get-AttributeLinesPsd1 -attr:($Node.$A) -offset:($offset + 1));
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

    [string[]] $keys = $tree.Keys | Sort-Object;
    foreach ($key in $keys) 
    {
        $output.Add("`t'${key}' =");
        $output.AddRange((Get-NodeLinesPsd1 -Node:($tree[$key]) -offset:2 ));
    }

    $output.Add("};");

    return $output.ToArray() -join "`n";
}

<#
    .SYNOPSIS
    Exports FlatTree to the file.
    Supported formats : psd1.

    .PARAMETER Tree
    Hashtable comtaining FlatTree.

    .PARAMETER Path
    Path in a FileSystem provider.

    .EXAMPLE
    PS> $tree = gi .\test.psd1 | iptree ;
    PS> $tree | eptree -F:"./test-copy.psd1"    #   creating a copy, it's not the same as cp because file path is stored in root node

#>
function Export-Tree {
    [CmdletBinding()]
    param (
        [Parameter(ValueFromPipeline = $true)] 
        [hashtable] $Tree,

        [Parameter(Mandatory = $false)] [string] $FilePath
    )

    Process {
        [hashtable] $root = Get-Node -Tree:$Tree -PatternPath:'0';

        if ( -not $FilePath) { 
            $FilePath = (Get-AttributeValue -N:$root -K:([SysAttrKey]::FilePath) -System) 
        }
        if (-not $FilePath) { throw "File Path not specified." }

        [string] $fullPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($FilePath);
        Set-AttributeValue -N:$root -K:([SysAttrKey]::FilePath) -Value:$fullPath -System

        [string] $ext = [System.IO.Path]::GetExtension($FilePath);

        switch ($ext) {
            { $_ -eq ("." + [FileFormat]::psd1) } { 
                [string] $content = Get-TreeContentPsd1 -Tree:$Tree;
                break; 
            }
            default { throw "File format '$ext' not supported." }
        }

        Set-Content -Path:$FilePath -Value:$content;
        Get-Item -Path:$FilePath;           
    }
}

Set-Alias -Name:eptree -Value:Export-Tree
Export-ModuleMember -Function:Export-Tree
Export-ModuleMember -Alias:eptree
#endregion
