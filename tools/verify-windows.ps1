$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
Push-Location -LiteralPath $projectRoot
try {
    foreach ($relative in @('App/Info.plist', 'App/PrivacyInfo.xcprivacy', 'FrameGuide.xcodeproj/xcshareddata/xcschemes/FrameGuide.xcscheme')) {
        $full = Join-Path $projectRoot $relative
        [xml]$document = Get-Content -LiteralPath $full -Raw -Encoding utf8
        if (-not $document.DocumentElement) { throw "Invalid XML: $relative" }
        Write-Output "XML parsed: $relative"
    }
    node tools/generate-project.mjs --check
    if ($LASTEXITCODE -ne 0) { throw 'Generated project is stale' }
    node --test --test-reporter=tap tools/tests/project.test.mjs
    if ($LASTEXITCODE -ne 0) { throw 'Project checks failed' }
    Write-Output 'PASS: Windows structural checks only. Swift compilation, XCTest and device validation were NOT run.'
} finally { Pop-Location }
