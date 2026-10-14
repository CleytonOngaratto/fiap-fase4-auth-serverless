[CmdletBinding()]
param(
    [string]$Region = "us-east-1"
)

$ErrorActionPreference = "Continue"
$script:Failed = $false

function Write-Head($text) { Write-Host "`n=== $text ===" -ForegroundColor Cyan }
function Write-Ok($text) { Write-Host "  [OK]   $text" -ForegroundColor Green }
function Write-Warn2($text) { Write-Host "  [WARN] $text" -ForegroundColor Yellow }
function Write-Fail($text) { Write-Host "  [FAIL] $text" -ForegroundColor Red; $script:Failed = $true }

# PS 5.1: stderr de executavel nativo vira NativeCommandError; o 'Continue' local evita derrubar a sondagem.
function Invoke-Probe {
    param([Parameter(Mandatory)][string]$Exe, [Parameter(Mandatory)][string[]]$ProbeArgs)
    $ErrorActionPreference = "Continue"
    $out = & $Exe @ProbeArgs 2>$null
    if ($LASTEXITCODE -ne 0) { return $null }
    return $out
}

$repoRoot = Split-Path $PSScriptRoot -Parent

Write-Head "1. Sessao AWS"
$identity = Invoke-Probe -Exe "aws" -ProbeArgs @("sts", "get-caller-identity", "--output", "json") | ConvertFrom-Json
if ($null -eq $identity) {
    Write-Fail "Sem credenciais validas. A sessao do Learner Lab dura ~4h: abra o lab, copie o bloco 'AWS Details' para ~/.aws/credentials e rode de novo."
    exit 1
}
Write-Ok "Conta $($identity.Account) · $($identity.Arn)"

Write-Head "2. persistent/ ja aplicado? (uma vez por conta do lab)"
$apiId = Invoke-Probe -Exe "aws" -ProbeArgs @("ssm", "get-parameter", "--name", "/fase4/apigw/api-id", "--region", $Region, "--query", "Parameter.Value", "--output", "text")
if ($apiId) {
    Write-Ok "/fase4/apigw/api-id = $apiId"
}
else {
    Write-Warn2 "/fase4/apigw/api-id ausente: rode o workflow_dispatch com root=persistent e action=apply antes do session/."
    Write-Host "         Depois de um Reset do lab a API some e a URL muda: reconfigure o webhook no painel do Mercado Pago." -ForegroundColor Yellow
}

Write-Head "3. Contrato da plataforma (o session/ le estes parametros)"
$contract = @(
    "/fase4/vpc/id",
    "/fase4/vpc/private-subnets",
    "/fase4/alb/listener-arn",
    "/fase4/alb/sg-id"
)
foreach ($name in $contract) {
    $value = Invoke-Probe -Exe "aws" -ProbeArgs @("ssm", "get-parameter", "--name", $name, "--region", $Region, "--query", "Parameter.Value", "--output", "text")
    if ($value) { Write-Ok "$name = $value" }
    else { Write-Fail "$name AUSENTE — quem publica: fiap-fase4-infra-k8s. Ordem: plataforma -> infra dos servicos -> deploy -> borda." }
}

Write-Head "4. backend.hcl de cada root"
foreach ($root in @("persistent", "session")) {
    $backendPath = Join-Path $repoRoot "$root/backend.hcl"
    if (Test-Path $backendPath) {
        Write-Ok "$root/backend.hcl ja existe"
        continue
    }
    Write-Warn2 "$root/backend.hcl ausente. Crie com o conteudo abaixo (o bucket veio do bootstrap da plataforma):"
    Write-Host ""
    Write-Host "bucket       = `"fiap-fase4-tfstate-$($identity.Account)`"" -ForegroundColor DarkGray
    Write-Host "key          = `"auth-serverless/$root.tfstate`"" -ForegroundColor DarkGray
    Write-Host "region       = `"$Region`"" -ForegroundColor DarkGray
    Write-Host "use_lockfile = true" -ForegroundColor DarkGray
    Write-Host "encrypt      = true" -ForegroundColor DarkGray
    Write-Host ""
}

Write-Host ""
if ($script:Failed) {
    Write-Host "PREFLIGHT REPROVADO — resolva os [FAIL] acima antes do apply do session/." -ForegroundColor Red
    exit 1
}
Write-Host "PREFLIGHT OK — pode seguir para o plan/apply." -ForegroundColor Green
