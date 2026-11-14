$ErrorActionPreference = 'Stop'
Set-Location (Resolve-Path (Join-Path $PSScriptRoot '../..'))
if (-not $env:BUILDKITE_COMMIT -or (git rev-parse HEAD) -ne $env:BUILDKITE_COMMIT) {
  throw 'Checkout does not match Buildkite commit'
}
if ($env:BUILDKITE_BRANCH -notmatch '^release/v(\d+\.\d+\.\d+(?:-[0-9A-Za-z.]+)?)$') {
  throw 'Expected release/vX.Y.Z branch'
}
$version = $Matches[1]
if ((node -p 'process.platform + "-" + process.arch') -ne 'win32-x64') {
  throw 'Windows x64 runner required'
}
$cynaVersion = if ($env:CYNA_VERSION) { $env:CYNA_VERSION } else { '0.5.1' }
$uri = "https://downloads.cyna.dev/distributions/$cynaVersion/x86_64-pc-windows-gnu.tar.gz"
$archive = Join-Path $env:TEMP 'cyna-windows-distribution.tar.gz'
$install = Join-Path $env:TEMP "cyna-weiv-$cynaVersion"
New-Item -ItemType Directory -Force -Path $install | Out-Null
Invoke-WebRequest -Uri $uri -OutFile $archive
tar -xzf $archive -C $install
if ($LASTEXITCODE -ne 0) { throw 'Cyna distribution extraction failed' }
$env:PATH = "$(Join-Path $install 'x86_64-pc-windows-gnu/bin');$env:PATH"
cyna version
if ($LASTEXITCODE -ne 0) { throw 'Cyna distribution cannot start' }
npm ci --ignore-scripts --no-audit --no-fund
if ($LASTEXITCODE -ne 0) { throw 'npm ci failed' }
npm run format:check
if ($LASTEXITCODE -ne 0) { throw 'format check failed' }
npm ci --prefix packages/vscode-extension --ignore-scripts --no-audit --no-fund
if ($LASTEXITCODE -ne 0) { throw 'extension install failed' }
npm test --prefix packages/vscode-extension
if ($LASTEXITCODE -ne 0) { throw 'extension tests failed' }
node tools/release.mjs plan --version=$version --preflight-only
if ($LASTEXITCODE -ne 0) { throw 'release preflight failed' }
npm run build:cyna
if ($LASTEXITCODE -ne 0) { throw 'Windows binary build failed' }
node tools/release.mjs plan --version=$version
if ($LASTEXITCODE -ne 0) { throw 'release plan failed' }
node tools/release.mjs verify
if ($LASTEXITCODE -ne 0) { throw 'release verification failed' }
buildkite-agent artifact upload 'dist/release/artifacts/*'
if ($LASTEXITCODE -ne 0) { throw 'artifact upload failed' }
buildkite-agent artifact upload 'dist/release/state/*.json'
if ($LASTEXITCODE -ne 0) { throw 'state upload failed' }
