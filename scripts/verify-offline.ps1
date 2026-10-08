[CmdletBinding()]
param(
    [string]$Cpf = "98765432100",
    [string]$Region = "us-east-1",
    [switch]$SkipCompose
)

# 'Continue', nao 'Stop': no PS 5.1 o stderr de executavel nativo vira NativeCommandError.
$ErrorActionPreference = "Continue"
$script:Failed = $false
$AppRoot = "http://localhost:8080/carworkshop/v1"

function Write-Head($text) { Write-Host "`n=== $text ===" -ForegroundColor Cyan }
function Write-Ok($text) { Write-Host "  [OK]   $text" -ForegroundColor Green }
function Write-Fail($text) { Write-Host "  [FAIL] $text" -ForegroundColor Red; $script:Failed = $true }

function Invoke-Probe {
    param([Parameter(Mandatory)][string]$Exe, [Parameter(Mandatory)][string[]]$ProbeArgs)
    $ErrorActionPreference = "Continue"
    $out = & $Exe @ProbeArgs 2>$null
    if ($LASTEXITCODE -ne 0) { return $null }
    return $out
}

# "$_" converte cada ErrorRecord em string; sem isso ele volta a agir como erro adiante.
function Invoke-Native {
    param([Parameter(Mandatory)][string]$Exe, [Parameter(Mandatory)][string[]]$NativeArgs)
    $ErrorActionPreference = "Continue"
    $out = & $Exe @NativeArgs 2>&1 | ForEach-Object { "$_" }
    return [pscustomobject]@{ ExitCode = $LASTEXITCODE; Lines = @($out) }
}

# curl.exe: no PS 5.1 "curl" e alias de Invoke-WebRequest.
# Corpo por arquivo (-d "@caminho"): o PS 5.1 remove as aspas de argumento nativo e o JSON chega quebrado.
function Invoke-Api {
    param(
        [Parameter(Mandatory)][string]$Method,
        [Parameter(Mandatory)][string]$Path,
        [string]$Body,
        [string]$Token
    )
    $cliArgs = @("-s", "-m", "30", "-X", $Method, "-w", "`n<<STATUS>>%{http_code}", "$AppRoot$Path")

    $bodyFile = $null
    if ($Body) {
        $bodyFile = Join-Path ([System.IO.Path]::GetTempPath()) "fase4-body-$([guid]::NewGuid()).json"
        [System.IO.File]::WriteAllText($bodyFile, $Body, [System.Text.UTF8Encoding]::new($false))
        $cliArgs += @("-H", "content-type: application/json", "-d", "@$bodyFile")
    }
    if ($Token) { $cliArgs += @("-H", "Authorization: Bearer $Token") }

    try {
        $raw = (Invoke-Probe -Exe "curl.exe" -ProbeArgs $cliArgs) -join "`n"
    }
    finally {
        if ($bodyFile) { Remove-Item $bodyFile -Force -ErrorAction SilentlyContinue }
    }

    $split = $raw -split "<<STATUS>>"
    return [pscustomobject]@{ Status = ($split[-1]).Trim(); Body = ($split[0]).Trim() }
}

$repoRoot = Split-Path $PSScriptRoot -Parent
$appRepo = Join-Path (Split-Path $repoRoot -Parent) "fiap-fase4-os-service"

Write-Head "1. Aplicacao local (docker compose do repo 4)"
if (-not (Test-Path $appRepo)) { Write-Host "  Repo 4 nao encontrado em $appRepo" -ForegroundColor Red; exit 1 }

if (-not $SkipCompose) {
    Push-Location $appRepo
    try {
        # --build: sem ele o compose sobe a imagem velha.
        $compose = Invoke-Native -Exe "docker" -NativeArgs @("compose", "up", "--build", "-d")
        if ($compose.ExitCode -ne 0) {
            Write-Fail "docker compose falhou — o Docker Desktop esta rodando?"
            $compose.Lines | Select-Object -Last 8 | ForEach-Object { Write-Host "         $_" -ForegroundColor DarkGray }
            exit 1
        }
    }
    finally { Pop-Location }
}

$ready = $false
foreach ($attempt in 1..60) {
    $code = Invoke-Probe -Exe "curl.exe" -ProbeArgs @("-s", "-o", "NUL", "-m", "5", "-w", "%{http_code}", "$AppRoot/q/health/ready")
    if ($code -eq "200") { $ready = $true; break }
    Start-Sleep -Seconds 3
}
if ($ready) { Write-Ok "app respondendo 200 em /q/health/ready" }
else { Write-Fail "app nao ficou pronta"; exit 1 }

Write-Head "2. A chave do SSM e o par da que a app valida?"

$scratch = Join-Path $env:TEMP "fase4-bloco5"
New-Item -ItemType Directory -Force -Path $scratch | Out-Null
$privPath = Join-Path $scratch "private-from-ssm.pem"

# O AWS CLI no Windows devolve CRLF, e o openssl recusa o PEM com \r.
$priv = ((Invoke-Probe -Exe "aws" -ProbeArgs @(
            "ssm", "get-parameter", "--name", "/fase4/jwt/private-key", "--with-decryption",
            "--region", $Region, "--query", "Parameter.Value", "--output", "text")) -join "`n") -replace "`r", ""
if (-not $priv) { Write-Fail "nao consegui ler /fase4/jwt/private-key do SSM"; exit 1 }
[System.IO.File]::WriteAllText($privPath, $priv)

$fromSsm = (Invoke-Probe -Exe "node" -ProbeArgs @((Join-Path $PSScriptRoot "key-fingerprint.mjs"), $privPath)) -join ""
$fromApp = (Invoke-Probe -Exe "node" -ProbeArgs @((Join-Path $PSScriptRoot "key-fingerprint.mjs"), (Join-Path $appRepo "secrets/publicKey.pem"))) -join ""

if ($fromSsm -and $fromSsm -eq $fromApp) {
    Write-Ok "privada do SSM e publica da app sao o MESMO par (spki sha256 $($fromSsm.Substring(0,16)))"
}
else {
    Write-Fail "par DIVERGENTE — o teste abaixo nao provaria nada. Republique .secrets/ no SSM."
    exit 1
}

Write-Head "3. Handler da Lambda (codigo real) contra o Postgres do compose"

$env:DB_PASSWORD = "postgres"
$env:DB_SSL = "disable"
$env:AWS_REGION = $Region

Push-Location $repoRoot
try {
    $invoke = Invoke-Native -Exe "node" -NativeArgs @("scripts/invoke-local.mjs", "--cpf", $Cpf)
}
finally { Pop-Location }

$payload = $invoke.Lines | Where-Object { $_ -match '"statusCode"' } | Select-Object -Last 1
if ($invoke.ExitCode -ne 0 -or -not $payload) {
    Write-Fail "handler nao devolveu 200 para o CPF $Cpf"
    $invoke.Lines | ForEach-Object { Write-Host "         $_" -ForegroundColor DarkGray }
    exit 1
}
$token = ($payload | ConvertFrom-Json).body.access_token
Write-Ok "token emitido ($(($token -split '\.').Count) segmentos, $($token.Length) chars)"

Write-Head "4. A app aceita o token? (o que custaria horas na nuvem)"

$noToken = Invoke-Api -Method GET -Path "/tracking/1"
if ($noToken.Status -eq "401") { Write-Ok "sem token -> 401 (a rota esta protegida)" }
else { Write-Fail "sem token -> $($noToken.Status), esperado 401" }

# 404 aqui e sucesso: o token passou na validacao e o interactor nao achou a OS.
$withToken = Invoke-Api -Method GET -Path "/tracking/1" -Token $token
if ($withToken.Status -eq "404") { Write-Ok "com token -> 404 'Work Order not found' = TOKEN ACEITO" }
elseif ($withToken.Status -eq "401") { Write-Fail "com token -> 401: o SmallRye RECUSOU o token. E este o bug que o bloco existe para evitar." }
elseif ($withToken.Status -eq "403") { Write-Fail "com token -> 403: assinatura ok, mas groups=[CUSTOMER] nao casou com @RolesAllowed." }
else { Write-Fail "com token -> $($withToken.Status) ($($withToken.Body))" }

Write-Head "5. O 200 do Definition of Done"

$admin = "dod-5"
$password = "S3nh4Forte!"
$signup = Invoke-Api -Method POST -Path "/auth/signup" -Body (@{username = $admin; password = $password; roles = @("ADMIN") } | ConvertTo-Json -Compress)
if ($signup.Status -eq "201") { Write-Ok "admin '$admin' criado" }
else { Write-Host "  [INFO] signup -> $($signup.Status) (provavelmente ja existe); o login decide" -ForegroundColor DarkGray }

$login = Invoke-Api -Method POST -Path "/auth/login" -Body (@{username = $admin; password = $password } | ConvertTo-Json -Compress)
if ($login.Status -ne "200") {
    Write-Fail "login do admin -> $($login.Status) (signup foi $($signup.Status)): $($login.Body)"
}
else {
    $parsed = $login.Body | ConvertFrom-Json
    $adminToken = if ($parsed.token) { $parsed.token } else { $parsed.access_token }

    # customer_id 2 / vehicle_id 2 sao o par semeado da Maria Santos — a dona do CPF do caminho feliz.
    $order = Invoke-Api -Method POST -Path "/work-orders" -Token $adminToken -Body (@{
            customer_id = 2; vehicle_id = 2; service_ids = @(1); parts_ids = @(1)
        } | ConvertTo-Json -Compress)

    if ($order.Status -notin @("200", "201")) {
        Write-Fail "criar OS -> $($order.Status): $($order.Body)"
    }
    else {
        $orderId = ($order.Body | ConvertFrom-Json).id
        $tracking = Invoke-Api -Method GET -Path "/tracking/$orderId" -Token $token
        if ($tracking.Status -eq "200") { Write-Ok "GET /tracking/$orderId com o token da Lambda -> 200" }
        else { Write-Fail "GET /tracking/$orderId -> $($tracking.Status): $($tracking.Body)" }
    }
}

Remove-Item $privPath -Force -ErrorAction SilentlyContinue

Write-Host ""
if ($script:Failed) {
    Write-Host "VERIFICACAO OFFLINE REPROVADA — corrija antes de gastar sessao de lab." -ForegroundColor Red
    exit 1
}
Write-Host "VERIFICACAO OFFLINE OK — o contrato do token esta provado." -ForegroundColor Green
Write-Host "Falta na nuvem: rede (VPC/subnet/SG/NAT), TLS do pg (verify-tls-probe.ps1) e a LabRole." -ForegroundColor Green
