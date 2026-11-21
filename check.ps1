# Picky / check.ps1 : prüft das Addon auf Syntaxfehler, bevor es ins Spiel kopiert wird.
#   .\check.ps1            nur prüfen
#   .\check.ps1 -Install   prüfen und NUR bei null Fehlern in den Spielordner kopieren
# Es gibt keinen Lua-Interpreter, deshalb prüft das Skript selbst:
#   1. Block-Struktur mit Zeilennummern: function/if/do/repeat gegen end/until (Strings und Kommentare werden ignoriert)
#   2. Klammern () {} []
#   3. Zusammengeklebte Wörter wie "endfunction" oder "thenreturn"
#   4. Alle in Picky.toc genannten Dateien gibt es, und jede .lua-Datei steht im TOC
#   5. Jeder L["..."]-Text hat eine deutsche Übersetzung, es gibt keine verwaisten Übersetzungen
param([switch]$Install, [string]$Target = "C:\Program Files (x86)\World of Warcraft\_forever_\Interface\AddOns\Picky")

$dir = Split-Path -Parent $MyInvocation.MyCommand.Path
$enc = New-Object Text.UTF8Encoding $false
$errors = New-Object System.Collections.ArrayList
function Fail($file, $line, $msg) { [void]$errors.Add("$($file):$($line)  $msg") }

# Strings und Kommentare durch Leerraum ersetzen, Zeilenumbrüche bleiben erhalten (Zeilennummern stimmen weiter)
$strip = [regex]'(?s)--\[(=*)\[.*?\]\1\]|--[^\n]*|\[(=*)\[.*?\]\2\]|"(?:[^"\\\n]|\\.)*"|''(?:[^''\\\n]|\\.)*'''
$blank = { param($m) ($m.Value -replace '[^\n]', ' ') }

$closeOf = @{ '(' = ')'; '{' = '}'; '[' = ']' }
$joinBad = '^(end|then|do|else|return|local|function|if|for|while|repeat|until|elseif)(end|then|do|else|return|local|function|if|for|while|repeat|until|elseif)$'

foreach ($f in Get-ChildItem $dir -Filter *.lua) {
    $name = $f.Name
    $raw = [IO.File]::ReadAllText($f.FullName, $enc)
    $code = $strip.Replace($raw, $blank)
    $lines = $code -split "`n"
    $blocks = New-Object System.Collections.Stack   # Einträge: @(Wort, Zeile)
    $brackets = New-Object System.Collections.Stack
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $ln = $i + 1; $line = $lines[$i]
        foreach ($m in [regex]::Matches($line, '[A-Za-z_][A-Za-z0-9_]*|[(){}\[\]]')) {
            $w = $m.Value
            if ($w -match '^[(){}\[\]]$') {
                if ($closeOf.ContainsKey($w)) { $brackets.Push(@($w, $ln)) }
                else {
                    if ($brackets.Count -eq 0) { Fail $name $ln "überzählige '$w'" }
                    else { $o = $brackets.Pop(); if ($closeOf[$o[0]] -ne $w) { Fail $name $ln "'$w' passt nicht zu '$($o[0])' aus Zeile $($o[1])" } }
                }
                continue
            }
            if ($w -ne 'elseif' -and $w -match $joinBad) { Fail $name $ln "zusammengeklebte Wörter: '$w'"; continue }
            switch ($w) {
                { $_ -in 'function', 'if', 'do', 'repeat' } { $blocks.Push(@($w, $ln)) }
                'end' {
                    if ($blocks.Count -eq 0) { Fail $name $ln "'end' ohne offenen Block" }
                    else { $o = $blocks.Pop(); if ($o[0] -eq 'repeat') { Fail $name $ln "'end' schließt 'repeat' aus Zeile $($o[1]) (dort gehört 'until' hin)" } }
                }
                'until' {
                    if ($blocks.Count -eq 0) { Fail $name $ln "'until' ohne 'repeat'" }
                    else { $o = $blocks.Pop(); if ($o[0] -ne 'repeat') { Fail $name $ln "'until' schließt '$($o[0])' aus Zeile $($o[1])" } }
                }
            }
        }
    }
    foreach ($o in $blocks) { Fail $name $o[1] "'$($o[0])' wird nie mit 'end' geschlossen" }
    foreach ($o in $brackets) { Fail $name $o[1] "'$($o[0])' wird nie geschlossen" }
    # eine Zeile, die mit einem Operator endet und danach direkt ein Block-Ende hat, ist fast immer ein Tippfehler
    $rawLines = $raw -split "`n"
    for ($i = 0; $i -lt $rawLines.Count - 1; $i++) {
        $a = $rawLines[$i].TrimEnd()
        if ($a -notmatch '--' -and $a -match '(=|\+|\.\.|\s(and|or))$' -and $rawLines[$i + 1] -match '^\s*end\b') {
            Fail $name ($i + 1) "Zeile endet mit Operator, darunter folgt 'end' (fehlt ein Wert?)"
        }
    }}

# TOC <-> Dateien
$toc = Join-Path $dir "Picky.toc"
$listed = @()
foreach ($l in ([IO.File]::ReadAllText($toc, $enc) -split "`n")) {
    $t = $l.Trim()
    if ($t -and -not $t.StartsWith("#") -and $t -match '\.(lua|xml)$') { $listed += $t }
}
foreach ($t in $listed) { if (-not (Test-Path (Join-Path $dir $t))) { Fail "Picky.toc" 0 "Datei fehlt: $t" } }
foreach ($f in Get-ChildItem $dir -Filter *.lua) { if ($listed -notcontains $f.Name) { Fail $f.Name 0 "steht nicht in Picky.toc (wird im Spiel nicht geladen)" } }

# Übersetzungen
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
foreach ($k in $used.Keys) { if (-not $de.ContainsKey($k) -and $k -notmatch '^[a-z0-9]+\.[a-z0-9]+$') { Fail $used[$k] 0 "keine deutsche Übersetzung für: $k" } }
foreach ($k in $de.Keys) { if (-not $used.ContainsKey($k)) { Fail "Locale.lua" 0 "unbenutzte Übersetzung: $k" } }

if ($errors.Count -gt 0) {
    Write-Host "FEHLER ($($errors.Count)):" -ForegroundColor Red
    $errors | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
    if ($Install) { Write-Host "Nicht installiert." -ForegroundColor Yellow }
    exit 1
}
Write-Host "OK: $((Get-ChildItem $dir -Filter *.lua).Count) Dateien, keine Syntaxfehler gefunden." -ForegroundColor Green
if ($Install) {
    Get-ChildItem $dir -Exclude check.ps1 | Copy-Item -Destination $Target -Force
    Write-Host "Installiert in $Target" -ForegroundColor Green
}
exit 0
