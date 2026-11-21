# Picky / check.ps1 : checks the addon for syntax errors before it is copied into the game.
#   .\check.ps1            check only
#   .\check.ps1 -Install   check and copy into the game folder ONLY when there are zero errors
# There is no Lua interpreter, so the script checks by itself:
#   1. Block structure with line numbers: function/if/do/repeat against end/until (strings and comments are ignored)
#   2. Klammern () {} []
#   3. Glued-together words like "endfunction" oder "thenreturn"
#   4. All files named in Picky.toc exist, and every .lua file is listed in the TOC
#   5. Every L["..."] text has a German translation, and there are no orphaned translations
param([switch]$Install, [string]$Target = "C:\Program Files (x86)\World of Warcraft\_forever_\Interface\AddOns\Picky")

$dir = Split-Path -Parent $MyInvocation.MyCommand.Path
$enc = New-Object Text.UTF8Encoding $false
$errors = New-Object System.Collections.ArrayList
function Fail($file, $line, $msg) { [void]$errors.Add("$($file):$($line)  $msg") }

# Replace strings and comments with whitespace, line breaks are kept (line numbers stay correct)
$strip = [regex]'(?s)--\[(=*)\[.*?\]\1\]|--[^\n]*|\[(=*)\[.*?\]\2\]|"(?:[^"\\\n]|\\.)*"|''(?:[^''\\\n]|\\.)*'''
$blank = { param($m) ($m.Value -replace '[^\n]', ' ') }

$closeOf = @{ '(' = ')'; '{' = '}'; '[' = ']' }
$joinBad = '^(end|then|do|else|return|local|function|if|for|while|repeat|until|elseif)(end|then|do|else|return|local|function|if|for|while|repeat|until|elseif)$'

foreach ($f in Get-ChildItem $dir -Filter *.lua) {
    $name = $f.Name
    $raw = [IO.File]::ReadAllText($f.FullName, $enc)
    $code = $strip.Replace($raw, $blank)
    $lines = $code -split "`n"
    $blocks = New-Object System.Collections.Stack   # entries: @(word, line)
    $brackets = New-Object System.Collections.Stack
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $ln = $i + 1; $line = $lines[$i]
        foreach ($m in [regex]::Matches($line, '[A-Za-z_][A-Za-z0-9_]*|[(){}\[\]]')) {
            $w = $m.Value
            if ($w -match '^[(){}\[\]]$') {
                if ($closeOf.ContainsKey($w)) { $brackets.Push(@($w, $ln)) }
                else {
                    if ($brackets.Count -eq 0) { Fail $name $ln "unmatched '$w'" }
                    else { $o = $brackets.Pop(); if ($closeOf[$o[0]] -ne $w) { Fail $name $ln "'$w' does not match '$($o[0])' from line $($o[1])" } }
                }
                continue
            }
            if ($w -ne 'elseif' -and $w -match $joinBad) { Fail $name $ln "glued-together words: '$w'"; continue }
            switch ($w) {
                { $_ -in 'function', 'if', 'do', 'repeat' } { $blocks.Push(@($w, $ln)) }
                'end' {
                    if ($blocks.Count -eq 0) { Fail $name $ln "'end' ohne offenen Block" }
                    else { $o = $blocks.Pop(); if ($o[0] -eq 'repeat') { Fail $name $ln "'end' closes 'repeat' from line $($o[1]) ('until' belongs there)" } }
                }
                'until' {
                    if ($blocks.Count -eq 0) { Fail $name $ln "'until' ohne 'repeat'" }
                    else { $o = $blocks.Pop(); if ($o[0] -ne 'repeat') { Fail $name $ln "'until' closes '$($o[0])' from line $($o[1])" } }
                }
            }
        }
    }
    foreach ($o in $blocks) { Fail $name $o[1] "'$($o[0])' is never closed with 'end'" }
    foreach ($o in $brackets) { Fail $name $o[1] "'$($o[0])' is never closed" }
    # a line that ends with an operator and is directly followed by a block end is almost always a typo
    $rawLines = $raw -split "`n"
    for ($i = 0; $i -lt $rawLines.Count - 1; $i++) {
        $a = $rawLines[$i].TrimEnd()
        if ($a -notmatch '--' -and $a -match '(=|\+|\.\.|\s(and|or))$' -and $rawLines[$i + 1] -match '^\s*end\b') {
            Fail $name ($i + 1) "line ends with an operator, 'end' follows below (missing a value?)"
        }
    }}

# TOC <-> files
$toc = Join-Path $dir "Picky.toc"
$listed = @()
foreach ($l in ([IO.File]::ReadAllText($toc, $enc) -split "`n")) {
    $t = $l.Trim()
    if ($t -and -not $t.StartsWith("#") -and $t -match '\.(lua|xml)$') { $listed += $t }
}
foreach ($t in $listed) { if (-not (Test-Path (Join-Path $dir $t))) { Fail "Picky.toc" 0 "file missing: $t" } }
foreach ($f in Get-ChildItem $dir -Filter *.lua) { if ($listed -notcontains $f.Name) { Fail $f.Name 0 "not listed in Picky.toc (will not be loaded in game)" } }

# Translations
$ll = [IO.File]::ReadAllText((Join-Path $dir "Locale.lua"), $enc)
$de = @{}; $sec = ""
foreach ($line in ($ll -split "`n")) {
    if ($line -match '^local DE = \{') { $sec = "DE" } elseif ($line -match '^\}') { $sec = "" }
    elseif ($sec -eq "DE" -and $line -match '^\s*\["((?:[^"\\]|\\.)*)"\]\s*=') { $de[$Matches[1]] = 1 }
}
$used = @{}
foreach ($f in Get-ChildItem $dir -Filter *.lua) {
    if ($f.Name -eq "Locale.lua") { continue }
    foreach ($m in [regex]::Matches([IO.File]::ReadAllText($f.FullName, $enc), 'L\["((?:[^"\\]|\\.)*)"\]')) { $used[$m.Groups[1].Value] = $f.Name }
}
foreach ($k in $used.Keys) { if (-not $de.ContainsKey($k) -and $k -notmatch '^[a-z0-9]+\.[a-z0-9]+$') { Fail $used[$k] 0 "no German translation for: $k" } }
foreach ($k in $de.Keys) { if (-not $used.ContainsKey($k)) { Fail "Locale.lua" 0 "unused translation: $k" } }

if ($errors.Count -gt 0) {
    Write-Host "ERRORS ($($errors.Count)):" -ForegroundColor Red
    $errors | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
    if ($Install) { Write-Host "Not installed." -ForegroundColor Yellow }
    exit 1
}
Write-Host "OK: $((Get-ChildItem $dir -Filter *.lua).Count) files, no syntax errors found." -ForegroundColor Green
if ($Install) {
    Get-ChildItem $dir -Exclude check.ps1 | Copy-Item -Destination $Target -Force
    Write-Host "Installed to $Target" -ForegroundColor Green
}
exit 0
