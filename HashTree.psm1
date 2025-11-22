#region const
enum FileFormatEnum {psd1; json; xml; csv; }
enum ValueType { ht; s; i; dbl; b; }

Set-Variable -Name 'PathDelimiter' -Value ':' -Option ReadOnly
#endregion

#region tools
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
function ConvertTo-NPath {
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
Export-ModuleMember -Function:ConvertTo-DNPath
#endregion

#region new
function New-Node {
    [CmdletBinding()]
    param (
        [ValidateScript({ -not ($_ -match '^[0-9]') })]
        [string] $Name
    )

    $nn = @{ 
        SA = @{
            Name = $Name;
            ParentId = $null;
            NextId = 1;
        };
        A = @{};
        Idx = @();
        IdIdxMap = @{};
        NameIdMap = @{}; 
    }

    return $nn
}

Set-Alias -Name:nn -Value:New-Node
Export-ModuleMember -Function:New-Node
Export-ModuleMember -Alias:nn

function New-Tree {
    [CmdletBinding()]
    param (
        [string] $Path
    )

    $root = (nn -Name:"Root");
    $root.SA.Id = "0";

    $t = @{ 
        "TA" = @{
            "Path" = $Path;
        };
        "0" = $root;
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
            { $_ -eq ("." + [FileFormatEnum]::psd1) } { 
                $tree = Import-PowerShellDataFile -Path:($FileInfo.FullName) -SkipLimitCheck ;
                break; 
            }
            default { throw "File format '$ext' not supported." }
        }
        $tree.TA.Path = $FileInfo.FullName;
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
        $attrLines.Add("$("`t" * $offset)`t`t'${key}' = $(Get-ValuePsd1 -value:($attr[$key]));"); 
    }

    if ($attrLines.Count -eq 0) {
        $outputLines.Add("@{};");
    }
    else {
        $outputLines.Add("$("`t" * $offset)`t@{");
        $outputLines.AddRange($attrLines);
        $outputLines.Add("$("`t" * $offset)`t};");        
    }

    return ,$outputLines;
}

function Get-IdxLinesPsd1 {
    param (
        [Parameter(Mandatory = $false)] [array] $idx,
        [Parameter(Mandatory = $false)] [int] $offset = 0
    )

    $outputLines = New-Object 'System.Collections.Generic.List[string]';
    $idxLines = New-Object 'System.Collections.Generic.List[string]';

    foreach ($key in $idx) 
    {
        $idxLines.Add("$("`t" * $offset)`t`t'${key}';"); 
    }

    if ($idxLines.Count -eq 0) {
        $outputLines.Add("@();");
    }
    else {
        $outputLines.Add("$("`t" * $offset)`t@(");
        $outputLines.AddRange($idxLines);
        $outputLines.Add("$("`t" * $offset)`t);");        
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

    $lines = (Get-AttributeLinesPsd1 -attr:($node.SA) -offset:($offset + 1));
    if ($lines.Count -eq 1) { $output.Add("$("`t" * $offset)'SA' = " + $lines[0]); }
    else { 
        $output.Add("$("`t" * $offset)'SA' = ");
        $output.AddRange($lines); 
    }

    $lines = (Get-AttributeLinesPsd1 -attr:($node.A) -offset:($offset + 1));
    if ($lines.Count -eq 1) { $output.Add("$("`t" * $offset)'A' = " + $lines[0]); }
    else { 
        $output.Add("$("`t" * $offset)'A' = ");
        $output.AddRange($lines); 
    }

    $lines = (Get-IdxLinesPsd1 -idx:($node.Idx) -offset:($offset + 1));
    if ($lines.Count -eq 1) { $output.Add("$("`t" * $offset)'Idx' = " + $lines[0]); }
    else { 
        $output.Add("$("`t" * $offset)'Idx' = ");
        $output.AddRange($lines); 
    }

    $lines = (Get-AttributeLinesPsd1 -attr:($node.IdIdxMap) -offset:($offset + 1));
    if ($lines.Count -eq 1) { $output.Add("$("`t" * $offset)'IdIdxMap' = " + $lines[0]); }
    else { 
        $output.Add("$("`t" * $offset)'IdIdxMap' = ");
        $output.AddRange($lines); 
    }

    $lines = (Get-AttributeLinesPsd1 -attr:($node.NameIdMap) -offset:($offset + 1));
    if ($lines.Count -eq 1) { $output.Add("$("`t" * $offset)'NameIdMap' = " + $lines[0]); }
    else { 
        $output.Add("$("`t" * $offset)'NameIdMap' = ");
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

    $output.Add("`t'TA' = ");
    $output.AddRange((Get-AttributeLinesPsd1 -attr:($tree.TA) -offset:1));

    $keys = $tree.Keys | Where-Object { $_ -ne "TA" } | Sort-Object
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
        if ( -not $Path) { $Path = $Tree.TA.Path }
        if (-not $Path) { throw "Path not specified." }
        $ext = [System.IO.Path]::GetExtension($Path);

        switch ($ext) {
            { $_ -eq ("." + [FileFormatEnum]::psd1) } { 
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

#region get

function Get-NodeItemCore {
    [CmdletBinding()]
    param (
        [Parameter(ValueFromPipeline = $true, ParameterSetName = 'FromSection')] 
        [ValidateScript({ [ChildType]::Section -eq [ChildType]::($_.ChildType) })]
        [PSCustomObject] $Section,

        [Parameter(Mandatory = $false, ParameterSetName = 'FromSection')] [Alias("I")] [string] $Include = "*",
        [Parameter(Mandatory = $false, ParameterSetName = 'FromSection')] [Alias("Ex")] [string] $Exclude = $null
    )

    Process {
        $value = $Section.Value;

        $includeKeys = $value.Keys | 
        Where-Object { $_ -like $Include } | 
        Where-Object { -not ($_ -like $Exclude) } | 
        Sort-Object;

        foreach ($itemKey in $includeKeys) {
            $item = $value[$itemKey];
            ndni -K:$itemKey -V:$item -Parent:$Section | Write-Output ;    
        }
    }
}

function Get-NodeItem {
    [CmdletBinding()]
    param (
        [Parameter(ValueFromPipeline = $true, ParameterSetName = 'FromSection')] 
        [ValidateScript({ [ChildType]::Section -eq [ChildType]::($_.ChildType) })]
        [PSCustomObject] $Section,

        [Parameter(Mandatory = $false, ParameterSetName = 'FromSection')] [Alias("I")] [string] $Include = "*",
        [Parameter(Mandatory = $false, ParameterSetName = 'FromSection')] [Alias("Ex")] [string] $Exclude = $null,

        [Parameter(ParameterSetName = 'FromDN')] 
        [ValidateScript({ [ChildType]::DN -eq [ChildType]::($_.ChildType) })]
        [PSCustomObject] $DN,

        [Parameter(Mandatory = $false, ParameterSetName = 'FromDN')] [Alias("IP")] [string] $IncludePath = "*${PathDelimiter}*",
        [Parameter(Mandatory = $false, ParameterSetName = 'FromDN')] [Alias("ExP")] [string] $ExcludePath = $null
    )

    Begin {
        $sections = @();
        if ($PSCmdlet.ParameterSetName -eq 'FromDN') {
            $dnIncludePath = ConvertTo-DNPath -Path:$IncludePath;
            $dnExcludePath = $ExcludePath ? (ConvertTo-DNPath -Path:$ExcludePath) : $null;
            if ([ChildType]::Item -ne [ChildType]::($dnIncludePath.PathType)) { throw "Incorrect Path Type." }
            if ($dnExcludePath -and ([ChildType]::Item -ne [ChildType]::($dnExcludePath.PathType))) { throw "Incorrect Path Type." }
            gdns -DN:$DN -I:($dnIncludePath.SectionPart) -Ex:($dnExcludePath?.SectionPart) | ForEach-Object { $sections += $_; }
        }
    }

    Process {
        if ($PSCmdlet.ParameterSetName -eq 'FromSection') {
            if ($Section) { $sections += $Section; }
        }
    }

    End {
        $inc = ($PSCmdlet.ParameterSetName -eq 'FromSection') ? $Include : $dnIncludePath.ItemPart;
        $ex = ($PSCmdlet.ParameterSetName -eq 'FromSection') ? $Include : $dnExcludePath.ItemPart;
        $sections | Get-DNItemCore -I:$inc -Ex:$ex | Write-Output
    }
}
Set-Alias -Name:gni -Value:Get-NodeItem
Export-ModuleMember -Function:Get-NodeItem
Export-ModuleMember -Alias:gni

#endregion

#region set
function Set-NodeAttribute {
    [CmdletBinding()]
    param (
        [Parameter(ValueFromPipeline = $true)] [Alias("S")] 
        [ValidateScript({ [ChildType]::Section -eq [ChildType]::($_.ChildType) })]
        [PSCustomObject] $Section,

        [Parameter(Mandatory = $true)] [Alias("T")]         
        [ValidateScript({ [ChildType]::DN -eq [ChildType]::($_.ChildType) })]
        [PSCustomObject] $TargetDN,

        [Parameter(Mandatory = $false)] [Alias("NO")] [switch] $NotOverride,
        [Parameter(Mandatory = $false)] [Alias("NC")] [switch] $NoCopyHashtable
    )

    Process {
        $targetPath = ConvertTo-DNPath -Path $Section.Key;

        $root = $TargetDN.Value;
        if ($NotOverride -and $root.ContainsKey($targetPath.SectionPart)) { throw "Overriding prohibited." }
        else {
            $root[$targetPath.SectionPart] = (($NoCopyHashtable) ? $Section.Value : (Copy-HashtableDeep -InputObject:$Section.Value ));
        }        
    }

    End {
        Write-Output $TargetDN;
    }
}
Set-Alias -Name:sna -Value:Set-NodeAttribute
Export-ModuleMember -Function:Set-NodeAttribute
Export-ModuleMember -Alias:sna

function Set-Node {
    [CmdletBinding()]
    param (
        [Parameter(ValueFromPipeline = $true)] [Alias("I")] 
        [ValidateScript({ [ChildType]::Item -eq [ChildType]::($_.ChildType) })]
        [PSCustomObject] $Item,

        [Parameter(Mandatory = $true)] [Alias("T")]
        [ValidateScript({ [ChildType]::Section -eq [ChildType]::($_.ChildType) })]
        [PSCustomObject] $TargetSection,

        [Parameter(Mandatory = $false)] [Alias("NO")] [switch] $NotOverride,
        [Parameter(Mandatory = $false)] [Alias("NC")] [switch] $NoCopyHashtable
    )

    Process {
        $section = $TargetSection.Value;

        if ($NotOverride -and $section.ContainsKey($Item.Key)) { throw "Overriding prohibited." }
        else {
            $section[$Item.Key] = (($NoCopyHashtable) ? $Item.Value : (Copy-HashtableDeep -InputObject:$Item.Value ));
        }
    }

    End {
        Write-Output $TargetSection;
    }
}
Set-Alias -Name:sn -Value:Set-Node
Export-ModuleMember -Function:Set-Node
Export-ModuleMember -Alias:sn

#endregion

#region remove
function Remove-Node {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)] 
        [ValidateScript({ 
                @([ChildType]::Section, [ChildType]::Item, [ChildType]::Property).Contains([ChildType]::($_.ChildType))
            })]
        [PSCustomObject] $ChildItem,

        [Parameter(Mandatory = $true)] 
        [ValidateScript({ [ChildType]::DN -eq $_.ChildType })]
        [PSCustomObject] $DN,

        [Parameter(Mandatory = $false)] [switch] $KeepEmpty
    )

    $root = $DN.Value;

    if ( [ChildType]::($ChildItem.Path.PathType) -eq [ChildType]::Section) {
        $root.Remove($ChildItem.Path.Key);
    }
    elseif ( [ChildType]::($ChildItem.Path.PathType) -eq [ChildType]::Item) {
        $section = ($root) ? $root[($ChildItem.Path.SectionPart)] : $null
        if ($section) { 
            $section.Remove($ChildItem.Path.Key); 
            if (-not $KeepEmpty) {
                if ($section.Keys.Count -eq 0) { $root.Remove($ChildItem.Path.SectionPart); }
            }
        }
    }
    elseif ( [ChildType]::($ChildItem.Path.PathType) -eq [ChildType]::Property) {
         
        $section = ($root) ? $root[($ChildItem.Path.SectionPart)] : $null;
        $item = ($section) ? $section[($ChildItem.Path.ItemPart)] : $null;         
        if ($item) { 
            $item.Remove($ChildItem.Path.Key);

            if (-not $KeepEmpty) {
                if ($item.Keys.Count -eq 0) { $section.Remove($ChildItem.Path.ItemPart); }
                if ($section.Keys.Count -eq 0) { $root.Remove($ChildItem.Path.SectionPart); }
            }
        }
    }
    else { throw "Unhandled ChildType." }

    return $DN;
}

Set-Alias -Name:rmn -Value:Remove-Node
Export-ModuleMember -Function:Remove-Node
Export-ModuleMember -Alias:rmn

#endregion

Write-Host "DataNode imported"