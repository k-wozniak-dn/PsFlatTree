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
Set-Variable -Name 'AllSysAttrKeys' -Value $sysAttr -Option ReadOnly;

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

#region attributes
function Get-Attribute {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)] [Alias("N")] [hashtable] $Node,
        [Parameter(Mandatory = $true)] [Alias("K")] [string] $Key,
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
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)] [Alias("N")] [hashtable] $Node,
        [Parameter(Mandatory = $false)] [Alias("K")] [string] $Key,

        [Parameter(Mandatory = $false)] [Alias("V")]
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
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)] [Alias("N")] [hashtable] $Node,
        [Parameter(Mandatory = $true)] [Alias("K")] [string] $Key,

        [Parameter(Mandatory = $true)] [Alias("V")]
        [ValidateScript({ ($_ -is [string]) -or ($_ -is [int]) -or ($_ -is [double]) -or ($_ -is [bool]) })]
        [object] $Value
    )

    Process {
        if ($Node -ne $null) {
            if (Test-SysAttribute -N:$Node -K:$Key -V:$Value) {
                $Node.$SA[$Key] = $Value;                 
            }
            return $Node;             
        } 
    }
}

function Set-Attribute {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)] [Alias("N")] [hashtable] $Node,
        [Parameter(Mandatory = $true)] [Alias("K")] [string] $Key,

        [Parameter(Mandatory = $true)] [Alias("V")]
        [ValidateScript({ ($_ -is [string]) -or ($_ -is [int]) -or ($_ -is [double]) -or ($_ -is [bool]) })]
        [object] $Value
    )

    Process {
        if ($Node -ne $null) {
            $Node.$A[$Key] = $Value;
            return $Node;             
        }
    }
}
Set-Alias -Name:sa -Value:Set-Attribute
Export-ModuleMember -Function:Set-Attribute
Export-ModuleMember -Alias:sa
#endregion

#region path
function ConvertTo-htPath {
    param (
        [Parameter(Mandatory = $true)] [Alias("P")]
        [string] $Path,

        [switch] $ByName
    )

    $parts = $Path -split [regex]::Escape($PathDelimiter);
    $count = ($parts).Count;
    if ($count -gt 3) { throw "Incorrect path '$path'." }
    $parts | ForEach-Object { if ([string]::Empty -eq $_) { throw "Incorrect path '$path'." }}

    return [PSCustomObject] @{ 
        PathType = ($count -eq 1) ? [ChildType]::Section : (($count -eq 2) ? [ChildType]::Item : [ChildType]::Property); 
        SectionPart = $parts[0]; 
        ItemPart = $count -gt 1 ? $parts[1] : $null ;
        PropertyPart = $count -gt 2 ? $parts[2] : $null ;
        ParentPath = ($count -eq 1) ? $null : (($count -eq 2) ? $parts[0] : $parts[0] + $PathDelimiter + $parts[1]); 
        FullPath = $Path;
    }
}
Set-Alias -Name:htp -Value:New-Node
Export-ModuleMember -Function:ConvertTo-htPath
Export-ModuleMember -Alias:htp

#endregion

#region new
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

    Set-SysAttribute -N:$nn -K:"Id" -V:$Id |
    Set-SysAttribute -K:"NodeName" -V:$NodeName |
    Set-SysAttribute -K:"NextChildId" -V:1 |
    Set-SysAttribute -K:"Idx" -V:0 | Write-Output;
}

Set-Alias -Name:nn -Value:New-Node
Export-ModuleMember -Function:New-Node
Export-ModuleMember -Alias:nn

function New-Tree {
    [CmdletBinding()]
    param (
        [string] $Path
    )

    $root = (nn -Id:"0" -NodeName:"Root" | Set-SysAttribute -K:"Path" -Value:$Path);

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

    Process {
        $ext = $FileInfo.Extension;
        switch ($ext) {
            { $_ -eq ("." + [FileFormat]::psd1) } { 
                $tree = Import-PowerShellDataFile -Path:($FileInfo.FullName) -SkipLimitCheck ;
                break; 
            }
            default { throw "File format '$ext' not supported." }
        }
        Set-SysAttribute -N:($tree.'0') -K:'Path' -V:($FileInfo.FullName);
        $tree | Write-Output;
    }
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