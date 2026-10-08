[CmdletBinding()]
param(
    [int]$Port = 55432,
    [string]$ContainerName = "fase4-tls-probe"
)

# 'Continue', nao 'Stop': no PS 5.1 o stderr de executavel nativo vira NativeCommandError.
$ErrorActionPreference = "Continue"
$script:Failed = $false

function Write-Head($text) { Write-Host "`n=== $text ===" -ForegroundColor Cyan }
function Write-Ok($text) { Write-Host "  [OK]   $text" -ForegroundColor Green }
function Write-Fail($text) { Write-Host "  [FAIL] $text" -ForegroundColor Red; $script:Failed = $true }

# "$_" converte cada ErrorRecord em string; sem isso ele volta a agir como erro adiante.
function Invoke-Native {
    param([Parameter(Mandatory)][string]$Exe, [Parameter(Mandatory)][string[]]$NativeArgs)
    $ErrorActionPreference = "Continue"
    $out = & $Exe @NativeArgs 2>&1 | ForEach-Object { "$_" }
    return [pscustomobject]@{ ExitCode = $LASTEXITCODE; Lines = @($out); Text = ($out -join "`n") }
}

$repoRoot = Split-Path $PSScriptRoot -Parent
$build = Join-Path $env:TEMP "fase4-tls-probe"
Remove-Item $build -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $build | Out-Null

Write-Head "1. Certificado self-signed para o servidor"

$openssl = $null
foreach ($candidate in @(
        "openssl.exe",
        "$env:ProgramFiles\Git\usr\bin\openssl.exe",
        "${env:ProgramFiles(x86)}\Git\usr\bin\openssl.exe",
        "$env:LOCALAPPDATA\Programs\Git\usr\bin\openssl.exe")) {
    $found = Get-Command $candidate -ErrorAction SilentlyContinue
    if ($found) { $openssl = $found.Source; break }
}
if (-not $openssl) { Write-Fail "openssl nao encontrado (o Git for Windows traz um em usr\bin)"; exit 1 }

$req = Invoke-Native -Exe $openssl -NativeArgs @(
    "req", "-new", "-x509", "-days", "1", "-nodes", "-newkey", "rsa:2048",
    "-keyout", (Join-Path $build "server.key"), "-out", (Join-Path $build "server.crt"),
    "-subj", "/CN=localhost")
if (-not (Test-Path (Join-Path $build "server.crt"))) {
    Write-Fail "openssl nao gerou o certificado"
    $req.Lines | ForEach-Object { Write-Host "         $_" -ForegroundColor DarkGray }
    exit 1
}
Write-Ok "server.crt / server.key gerados no scratchpad"

Write-Head "2. Imagem descartavel que se comporta como o RDS"

# Sem linha host: o servidor recusa conexao em claro, como o rds.force_ssl. A local fica para o entrypoint.
@"
local   all   all               trust
hostssl all   all   all         scram-sha-256
"@ | Set-Content -Path (Join-Path $build "pg_hba.conf") -Encoding ascii

# COPY + chmod na imagem: em bind mount do Docker Desktop o arquivo fica 0777 e o Postgres recusa iniciar.
@"
FROM postgres:16
COPY server.crt server.key pg_hba.conf /etc/pg/
RUN chown postgres:postgres /etc/pg/* && chmod 600 /etc/pg/server.key
"@ | Set-Content -Path (Join-Path $build "Dockerfile") -Encoding ascii

$image = Invoke-Native -Exe "docker" -NativeArgs @("build", "-q", "-t", "fase4-tls-probe:local", $build)
if ($image.ExitCode -ne 0) {
    Write-Fail "docker build falhou — o Docker Desktop esta rodando?"
    $image.Lines | Select-Object -Last 8 | ForEach-Object { Write-Host "         $_" -ForegroundColor DarkGray }
    exit 1
}
Write-Ok "imagem construida (permissao da chave na layer, nao em bind mount)"

Write-Head "3. Subir o servidor"
Invoke-Native -Exe "docker" -NativeArgs @("rm", "-f", $ContainerName) | Out-Null
$run = Invoke-Native -Exe "docker" -NativeArgs @(
    "run", "-d", "--name", $ContainerName,
    "-e", "POSTGRES_PASSWORD=postgres", "-e", "POSTGRES_DB=oficina_db",
    "-p", "${Port}:5432", "fase4-tls-probe:local",
    "-c", "ssl=on", "-c", "ssl_cert_file=/etc/pg/server.crt", "-c", "ssl_key_file=/etc/pg/server.key",
    "-c", "hba_file=/etc/pg/pg_hba.conf")
if ($run.ExitCode -ne 0) {
    Write-Fail "docker run falhou"
    $run.Lines | ForEach-Object { Write-Host "         $_" -ForegroundColor DarkGray }
    exit 1
}

try {
    $up = $false
    foreach ($attempt in 1..40) {
        Start-Sleep -Seconds 2
        $log = (Invoke-Native -Exe "docker" -NativeArgs @("logs", $ContainerName)).Text
        if ($log -match "has group or world access") {
            Write-Fail "o Postgres recusou a chave por permissao — a imagem nao aplicou o chmod"
            break
        }
        # O entrypoint sobe um servidor temporario antes; so o que vem depois de "ready for start up" e o definitivo.
        if ($log -match "ready for start up" -and $log -match "database system is ready to accept connections") {
            $up = $true; break
        }
    }
    if (-not $up) { Write-Fail "servidor nao ficou pronto"; exit 1 }
    Write-Ok "postgres com ssl=on e pg_hba so-hostssl na porta $Port"

    $seed = Invoke-Native -Exe "docker" -NativeArgs @(
        "exec", $ContainerName, "psql", "-U", "postgres", "-d", "oficina_db", "-c",
        "CREATE TABLE customers (id int8 PRIMARY KEY, document varchar(255), name varchar(255)); INSERT INTO customers VALUES (2, '98765432100', 'Maria Santos');")
    if ($seed.ExitCode -ne 0) {
        Write-Fail "nao consegui semear a tabela"
        $seed.Lines | ForEach-Object { Write-Host "         $_" -ForegroundColor DarkGray }
        exit 1
    }

    $env:DB_HOST = "localhost"
    $env:DB_PORT = "$Port"
    $env:DB_NAME = "oficina_db"
    $env:DB_USER = "postgres"
    $env:DB_PASSWORD = "postgres"
    $env:AWS_REGION = "us-east-1"

    Push-Location $repoRoot
    try {
        Write-Head "4. DB_SSL=disable -> tem que FALHAR como na nuvem"
        $env:DB_SSL = "disable"
        # Processo separado por caso: o pool do `pg` vive no escopo do modulo e seria reaproveitado.
        $plain = Invoke-Native -Exe "node" -NativeArgs @("scripts/invoke-local.mjs", "--cpf", "98765432100")
        if ($plain.Text -match "no encryption|no pg_hba.conf entry") {
            Write-Ok "recusado com 'no pg_hba.conf entry ... no encryption' — MESMO erro do RDS"
        }
        else {
            Write-Fail "conectou sem TLS: o servidor de teste nao esta forcando SSL, a sonda daria falso verde."
            $plain.Lines | ForEach-Object { Write-Host "         $_" -ForegroundColor DarkGray }
        }

        Write-Head "5. DB_SSL=require -> tem que CONECTAR (o caminho que vai para a nuvem)"
        $env:DB_SSL = "require"
        $tls = Invoke-Native -Exe "node" -NativeArgs @("scripts/invoke-local.mjs", "--cpf", "98765432100")
        if ($tls.ExitCode -eq 0 -and $tls.Text -match '"statusCode":200') {
            Write-Ok "conectou por TLS e emitiu o token — ssl rejectUnauthorized:false funciona"
        }
        else {
            Write-Fail "nao conectou com TLS habilitado."
            $tls.Lines | ForEach-Object { Write-Host "         $_" -ForegroundColor DarkGray }
        }
    }
    finally { Pop-Location }
}
finally {
    Invoke-Native -Exe "docker" -NativeArgs @("rm", "-f", $ContainerName) | Out-Null
    Remove-Item $build -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ""
if ($script:Failed) {
    Write-Host "SONDA DE TLS REPROVADA." -ForegroundColor Red
    exit 1
}
Write-Host "SONDA DE TLS OK — o caminho TLS do pg esta provado sem gastar sessao de lab." -ForegroundColor Green
