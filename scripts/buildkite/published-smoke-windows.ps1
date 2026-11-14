$ErrorActionPreference = 'Stop'
Set-Location (Resolve-Path (Join-Path $PSScriptRoot '../..'))
buildkite-agent artifact download 'dist/release/collected/manifest.json' . --step collect-release
if ($LASTEXITCODE -ne 0) { throw 'Release manifest download failed' }
$manifest = Get-Content 'dist/release/collected/manifest.json' -Raw | ConvertFrom-Json
if ($manifest.commit -ne $env:BUILDKITE_COMMIT) { throw 'Release commit mismatch' }
$consumer = Join-Path $env:TEMP ("weiv-release-smoke-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $consumer | Out-Null
try {
  Set-Location $consumer
  npm install --no-audit --no-fund --ignore-scripts "weivjs@$($manifest.version)"
  if ($LASTEXITCODE -ne 0) { throw 'Published npm install failed' }
  node node_modules/weivjs/bin/weiv.mjs --help
  if ($LASTEXITCODE -ne 0) { throw 'Published Windows CLI failed' }
  node --input-type=module -e "await import('weivjs/vite'); await import('weivjs/bun')"
  if ($LASTEXITCODE -ne 0) { throw 'Published adapter import failed' }
} finally {
  Set-Location (Resolve-Path (Join-Path $PSScriptRoot '../..'))
  Remove-Item -Recurse -Force $consumer
}
