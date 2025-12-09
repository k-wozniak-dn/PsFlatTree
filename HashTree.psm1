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
function ConvertTo-HtPath {
    param (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [string] $Path
    )

    $parts = $Path -split [regex]::Escape($pdel);
    $parts | ForEach-Object { if ([string]::Empty -eq $_) { throw "Incorrect path '$path'." }}
    $byName = $false;
    $parts | ForEach-Object { if ( -not ($_ -match '^[0-9*]+$')) { $byName = $true }; }

    if ($parts.Count -eq 1) {
        $id = $parts[0];
        $parentPath = $null;
    }
    else {
        $id = $parts[$parts.Count - 1];
        $parentPath = ($parts[0..($parts.Count - 2)]) -join $pdel;
    }

    return [PSCustomObject] @{ 
        Level = ($parts).Count;
        ByName = $byName; 
        Parts = $parts;
        Id = $id;
        ParentPath = $parentPath; 
        FullPath = $Path;
    }
}
Set-Alias -Name:htp -Value:ConvertTo-htPath
Export-ModuleMember -Function:ConvertTo-htPath
Export-ModuleMember -Alias:htp

function Compare-HtPath {
    param (
        [Parameter(Mandatory = $true)] [PSCustomObject] $Pattern,
        [Parameter(Mandatory = $true)] [PSCustomObject] $ToCompare,
        [switch] $Recurse
    )

    if ($Recurse) {
        if ($Pattern.Level -gt $ToCompare.Level) { return $false; }
    }
    else {
        if ($Pattern.Level -ne $ToCompare.Level) { return $false; }
    }

    $match = $true
    $idx = @(0..($Pattern.Level - 1))
    $idx | ForEach-Object { if (($ToCompare.Parts[$_]) -notlike ($Pattern.Parts[$_])) { $match = $false }  }
    return $match;    
}
Export-ModuleMember -Function:Compare-HtPath
#endregion

#region node
function New-Node {
    [CmdletBinding()]
    param (
        [string] $Id,

        [ValidateScript({ -not ($_ -match '^[0-9]') })]
        [string] $NodeName
    )

    $nn = @{ 
        $SA = @{};
        $A = @{};
    }

    $nn = Set-SysAttribute -N:$nn -K:"Id" -V:$Id |
    Set-SysAttribute -K:"NodeName" -V:$NodeName |
    Set-SysAttribute -K:"NextChildId" -V:1 |
    Set-SysAttribute -K:"Idx" -V:0 ;

    return $nn;
}

Set-Alias -Name:nn -Value:New-Node
Export-ModuleMember -Function:New-Node
Export-ModuleMember -Alias:nn

function Get-Attribute {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)] [hashtable] $Node,
        [Parameter(Mandatory = $true)] [string] $Key,
        [switch] $System
    )

    if ($System) { return $Node.$SA[$Key]; }
    else { return $Node.$A[$Key]; }
}
Set-Alias -Name:ga -Value:Get-Attribute
Export-ModuleMember -Function:Get-Attribute
Export-ModuleMember -Alias:ga

function Test-SysAttribute {
    param (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)] [hashtable] $Node,
        [Parameter(Mandatory = $false)] [string] $Key,

        [Parameter(Mandatory = $false)]
        [ValidateScript({ ($_ -is [string]) -or ($_ -is [int]) -or ($_ -is [double]) -or ($_ -is [bool]) })]
        [object] $Value,

        [switch] $All 
    )

    $kvList = @();
    if ($All) { 
        $Node.$SA.Keys | 
        ForEach-Object { [PSCustomObject]@{ Key = $_; Value = $Value ?? (ga -N:$Node -K:$_ -System) } } |
        ForEach-Object { $kvList += $_ }
    }
    elseif ($Key) {
        $kvList += [PSCustomObject]@{ Key = $Key; Value = $Value ?? (ga -N:$Node -K:$_ -System) }
    }
    else {
        return $true;
    }

    $kvList | 
    ForEach-Object { 
        if (-not $sysAttr.Contains([SysAttrKey]::($_.Key))) {throw "Illegal Sys Key Attribute."} 
    }

    return $true;
}

function Set-SysAttribute {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)] [hashtable] $Node,
        [Parameter(Mandatory = $true)] [string] $Key,

        [Parameter(Mandatory = $true)]
        [ValidateScript({ ($_ -is [string]) -or ($_ -is [int]) -or ($_ -is [double]) -or ($_ -is [bool]) })]
        [object] $Value
    )

    if ($Node -ne $null) {
        if (Test-SysAttribute -N:$Node -K:$Key -V:$Value) {
            $Node.$SA[$Key] = $Value;                 
        }
        return $Node;             
    }
}

function Set-Attribute {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)] [hashtable] $Node,
        [Parameter(Mandatory = $true)] [string] $Key,

        [Parameter(Mandatory = $true)]
        [ValidateScript({ ($_ -is [string]) -or ($_ -is [int]) -or ($_ -is [double]) -or ($_ -is [bool]) })]
        [object] $Value
    )

    if ($null -ne $Node) {
        $Node.$A[$Key] = $Value;
        return $Node;             
    }
}
Set-Alias -Name:sa -Value:Set-Attribute
Export-ModuleMember -Function:Set-Attribute
Export-ModuleMember -Alias:sa
#endregion

#region tree
function ConvertTo-ByNameHtPath {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)] [hashtable] $Tree,
        [Parameter(Mandatory = $true)] [object] $Path
    )

    $htPath = ($Path -is [string] ) ? (ConvertTo-HtPath -Path:$Path) : [PSCustomObject] $Path;
    if ($htPath.ByName -eq $true) { throw "Path must be id type." }

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

    $Tree.Keys | 
    ForEach-Object {
        $nodeHtPath = ConvertTo-htPath -Path:$_;  
        if ($patternHtPath.ByName -eq $false) {
            $match = (Compare-HtPath -Pattern:$patternHtPath -ToCompare:$nodeHtPath -Recurse:$Recurse);
        } 
        elseif ($patternHtPath.ByName -eq $true) {
            $nodeByNameHtPath = ConvertTo-ByNameHtPath -T:$Tree -Path:$nodeHtPath;
            $match = (Compare-HtPath -Pattern:$patternHtPath -ToCompare:$nodeByNameHtPath -Recurse:$Recurse);
        }
        
        if ($match) { Write-Output ($Tree[$_]); }
    }

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


}
Set-Alias -Name:an -Value:Add-Node
Export-ModuleMember -Function:Add-Node
Export-ModuleMember -Alias:an

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


Write-Host "DataNode imported"