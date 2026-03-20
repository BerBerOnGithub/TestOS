# fix_encoding.ps1 - Strip encoding garbage from all source files
#
# Run this before committing to git if any file was written by PowerShell,
# which tends to introduce UTF-8/Windows-1252 mojibake. Safe to run repeatedly.
#
# Fixes:
#   1. UTF-8 BOM stripped
#   2. Non-ASCII bytes (>127) replaced with '-'
#   3. "EUR remnants (mangled box-drawing chars) removed
#   4. ,,!,,-< etc. remnants (mangled em-dash/arrows) replaced with '-'
#   5. Runs of 4+ punctuation chars [<>,"!.+-] collapsed to '-'

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$files = Get-ChildItem -Path $root -Recurse -Include "*.asm","*.py","*.bat","*.ps1","*.md"

$fixed = 0
$skipped = 0

foreach ($file in $files) {
    $bytes = [IO.File]::ReadAllBytes($file.FullName)

    # 1. Strip BOM
    $start = 0
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
        $start = 3
    }

    # 2. Replace non-ASCII byte runs with '-'
    $out = [Collections.Generic.List[byte]]::new($bytes.Length)
    $i = $start
    while ($i -lt $bytes.Length) {
        if ($bytes[$i] -le 127) {
            $out.Add($bytes[$i]); $i++
        } else {
            while ($i -lt $bytes.Length -and $bytes[$i] -gt 127) { $i++ }
            $out.Add(0x2D)
        }
    }
    $text = [Text.Encoding]::ASCII.GetString($out.ToArray())
    $orig = $text

    # 3. Remove "EUR mojibake remnants (from box-drawing chars)
    $text = [regex]::Replace($text, '(?:"EUR|"""EUR"|""EUR"|-EUR)+', '-')
    $text = [regex]::Replace($text, '-?EUR', '')

    # 4. Replace ,,!,,-< style em-dash/arrow mojibake
    $text = [regex]::Replace($text, '(?:,,!|,,-|<,!|\+\+|!\.\.\.-)+', '-')

    # 5. Collapse runs of 4+ punctuation to single '-'
    $text = [regex]::Replace($text, '[<>,"!.+\-]{4,}', '-')

    if ($text -ne $orig -or $start -gt 0) {
        [IO.File]::WriteAllBytes($file.FullName, [Text.Encoding]::ASCII.GetBytes($text))
        $fixed++
        Write-Host "Fixed: $($file.Name)"
    } else {
        $skipped++
    }
}

Write-Host ""
Write-Host "Done. Fixed: $fixed  Already clean: $skipped"
