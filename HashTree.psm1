#region const
enum FileFormat {psd1; json; xml; csv; }
enum TreeSection { TA; TAM }
enum NodeSection { SA; SAM; A; AM; Idx; IdIdxMap; NameIdMap  }
enum ValueSfx { s; i; dbl; b; }

# Path delimiter
Set-Variable -Name 'pdel' -Value ':' -Option ReadOnly

Set-Variable -Name 'TA' -Value "$([TreeSection]::TA)" -Option ReadOnly
Set-Variable -Name 'TAM' -Value "$([TreeSection]::TAM)" -Option ReadOnly
Set-Variable -Name 'SA' -Value "$([NodeSection]::SA)" -Option ReadOnly
Set-Variable -Name 'A' -Value "$([NodeSection]::A)" -Option ReadOnly
Set-Variable -Name 'SAM' -Value "$([NodeSection]::SAM)" -Option ReadOnly
Set-Variable -Name 'AM' -Value "$([NodeSection]::AM)" -Option ReadOnly
Set-Variable -Name 'Idx' -Value "$([NodeSection]::Idx)" -Option ReadOnly
Set-Variable -Name 'IdIdxMap' -Value "$([NodeSection]::IdIdxMap)" -Option ReadOnly
Set-Variable -Name 'NameIdMap' -Value "$([NodeSection]::NameIdMap)" -Option ReadOnly

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
        [ValidateScript({ -not ($_ -match '^[0-9]') })]
        [string] $Name
    )

    $nn = @{ 
        $SA = @{
            'Name' = $Name;
            'NextId' = 1;
        };
        $SAM = @{
            'Name' = "type=s;";
            'NextId' = "type=i;";
        };
        $A = @{};
        $AM = @{};
        $Idx = @();
        $IdIdxMap = @{};
        $NameIdMap = @{}; 
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
    $root.$SA.Id = "0";
    $root.$SAM.Id = "type=s;";

    $t = @{ 
        $TA = @{
            Path = $Path;
        };
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
        $tree.$TA.Path = $FileInfo.FullName;
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

function Get-IdxLinesPsd1 {
    param (
        [Parameter(Mandatory = $false)] [array] $idx,
        [Parameter(Mandatory = $false)] [int] $offset = 0
    )

    $outputLines = New-Object 'System.Collections.Generic.List[string]';
    $idxLines = New-Object 'System.Collections.Generic.List[string]';

    foreach ($key in $idx) 
    {
        $idxLines.Add("$("`t" * $offset)`t'${key}';"); 
    }

    if ($idxLines.Count -eq 0) {
        $outputLines.Add("@();");
    }
    else {
        $outputLines.Add("$("`t" * $offset)@(");
        $outputLines.AddRange($idxLines);
        $outputLines.Add("$("`t" * $offset));");        
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

    $lines = (Get-AttributeLinesPsd1 -attr:($node.$SAM) -offset:($offset + 1));
    if ($lines.Count -eq 1) { $output.Add("$("`t" * $offset)'${SAM}' = " + $lines[0]); }
    else { 
        $output.Add("$("`t" * $offset)'${SAM}' = ");
        $output.AddRange($lines); 
    }

    $lines = (Get-AttributeLinesPsd1 -attr:($node.$A) -offset:($offset + 1));
    if ($lines.Count -eq 1) { $output.Add("$("`t" * $offset)'${A}' = " + $lines[0]); }
    else { 
        $output.Add("$("`t" * $offset)'${A}' = ");
        $output.AddRange($lines); 
    }

    $lines = (Get-AttributeLinesPsd1 -attr:($node.$AM) -offset:($offset + 1));
    if ($lines.Count -eq 1) { $output.Add("$("`t" * $offset)'${AM}' = " + $lines[0]); }
    else { 
        $output.Add("$("`t" * $offset)'${AM}' = ");
        $output.AddRange($lines); 
    }

    $lines = (Get-IdxLinesPsd1 -idx:($node.$Idx) -offset:($offset + 1));
    if ($lines.Count -eq 1) { $output.Add("$("`t" * $offset)'${Idx}' = " + $lines[0]); }
    else { 
        $output.Add("$("`t" * $offset)'${Idx}' = ");
        $output.AddRange($lines); 
    }

    $lines = (Get-AttributeLinesPsd1 -attr:($node.$IdIdxMap) -offset:($offset + 1));
    if ($lines.Count -eq 1) { $output.Add("$("`t" * $offset)'${IdIdxMap}' = " + $lines[0]); }
    else { 
        $output.Add("$("`t" * $offset)'${IdIdxMap}' = ");
        $output.AddRange($lines); 
    }

    $lines = (Get-AttributeLinesPsd1 -attr:($node.$NameIdMap) -offset:($offset + 1));
    if ($lines.Count -eq 1) { $output.Add("$("`t" * $offset)'${NameIdMap}' = " + $lines[0]); }
    else { 
        $output.Add("$("`t" * $offset)'${NameIdMap}' = ");
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

    $output.Add("`t'${TA}' = ");
    $output.AddRange((Get-AttributeLinesPsd1 -attr:($tree.$TA) -offset:1));

    $output.Add("`t'${TAM}' = ");
    $output.AddRange((Get-AttributeLinesPsd1 -attr:($tree.$TAM) -offset:1));

    $keys = $tree.Keys | Where-Object { ($_ -ne $TA) -and ($_ -ne $TAM) } | Sort-Object
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
        if ( -not $Path) { $Path = $Tree.$TA.Path }
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