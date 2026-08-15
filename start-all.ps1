$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$backendDir = Join-Path $root 'backend'
$frontendDir = Join-Path $root 'frontend'
$adminDir = Join-Path $root 'admin'

Write-Host 'Starting ShopNow backend...'
Start-Process powershell -NoNewWindow -WorkingDirectory $backendDir -ArgumentList '-NoExit', '-Command', 'npm start'

Write-Host 'Starting ShopNow frontend...'
Start-Process powershell -NoNewWindow -WorkingDirectory $frontendDir -ArgumentList '-NoExit', '-Command', 'npm start'

Write-Host 'Starting ShopNow admin...'
Start-Process powershell -NoNewWindow -WorkingDirectory $adminDir -ArgumentList '-NoExit', '-Command', 'npm start'

Write-Host ''
Write-Host 'Services started.'
Write-Host 'Backend: http://localhost:5000/api/health'
Write-Host 'Frontend: http://localhost:3000'
Write-Host 'Admin: http://localhost:3002'
