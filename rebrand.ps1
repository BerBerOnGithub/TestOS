# This gets the folder where the script is saved
$targetFolder = $PSScriptRoot

$oldText = "ClaudeOS"
$newText = "NatureOS"

# We use -LiteralPath to prevent PS from misinterpreting special characters
$files = Get-ChildItem -LiteralPath $targetFolder -Filter *.asm -Recurse

foreach ($file in $files) {
    # Encoding UTF8 ensures it saves your special characters correctly inside the files too
    $content = Get-Content -LiteralPath $file.FullName
    $content -replace $oldText, $newText | Set-Content -LiteralPath $file.FullName -Encoding UTF8
    
    Write-Host "Fixed: $($file.Name)" -ForegroundColor Cyan
}