param(
    [ValidateSet("validate","patch","heal","full")]
    [string]$Mode = "full"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

$ROOT = Split-Path -Parent $MyInvocation.MyCommand.Definition
Set-Location $ROOT

$STATE_DIR      = "$ROOT\.infinity"
$REPORT_DIR     = "$STATE_DIR\reports"
$QUARANTINE_DIR = "$STATE_DIR\quarantine"
$LOG_FILE       = "$STATE_DIR\validator.log"
$TIMESTAMP      = Get-Date -Format "yyyyMMdd-HHmmss"

New-Item -ItemType Directory -Force $STATE_DIR      | Out-Null
New-Item -ItemType Directory -Force $REPORT_DIR     | Out-Null
New-Item -ItemType Directory -Force $QUARANTINE_DIR | Out-Null

$RESULT = @{
    meta = @{
        platform  = "Infinity XOS"
        validator = "Infinity Platform Validator v1"
        mode      = $Mode
        timestamp = $TIMESTAMP
        root      = $ROOT
    }
    python_errors = @()
    patched       = @()
    healed        = @()
}

Get-ChildItem -Recurse -Filter *.py | ForEach-Object {
    $out = cmd /c "python -m py_compile `"$($_.FullName)`"" 2>&1
    if ($LASTEXITCODE -ne 0) {
        $RESULT.python_errors += @{ file=$_.FullName; error=($out -join "`n") }
        if ($Mode -in @("heal","full")) {
            Move-Item $_.FullName "$QUARANTINE_DIR\$($_.Name)" -Force
            $RESULT.healed += "Quarantined: $($_.FullName)"
        }
    }
}

if ($Mode -in @("patch","full")) {
    Get-ChildItem -Recurse -Filter *.py | ForEach-Object {
        $c = Get-Content $_.FullName -Raw
        if ($c -match "FastAPI" -and $c -notmatch "/health") {
@"
@app.get("/health")
def health(): return {"status":"ok"}
@app.get("/ready")
def ready(): return {"ready":True}
"@ | Add-Content $_.FullName
            $RESULT.patched += "Patched health endpoints: $($_.FullName)"
        }
    }
}

if ($Mode -in @("heal","full")) {
    "services","services/agents","services/memory",".github",".github/workflows" |
      ForEach-Object {
        if (!(Test-Path $_)) {
            New-Item -ItemType Directory -Force $_ | Out-Null
            $RESULT.healed += "Created dir: $_"
        }
      }
}

$RESULT | ConvertTo-Json -Depth 12 |
  Out-File "$REPORT_DIR\report-$TIMESTAMP.json" -Encoding utf8
