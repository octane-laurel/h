# ---------- Persist env (managed block) ----------
$rollEsc = $roll -replace "'", "''"
$hostEsc = $hostnameVar -replace "'", "''"
$apiEsc  = if ($geminiKey) { $geminiKey -replace "'", "''" } else { "" }

$hdr = "# >>> IITM-ENV-START >>>"
$ftr = "# <<< IITM-ENV-END <<<"

$block = @"
$hdr
`$env:ROLLNO = '$rollEsc'
`$env:HOSTNAME = '$hostEsc'
"@.Trim()

if ($apiEsc) {
    $block += "`r`n" + "`$env:GOOGLE_API_KEY = '$apiEsc'"
}

# Add commands
$block += @"
`r`nfunction run { & "`$HOME/run.ps1" }
function repobase { 
    & repomix --no-file-summary --no-security-check --remove-empty-lines --include-empty-directories --quiet --style markdown --copy "`$HOME/t/se2001"
}
$ftr
"@

