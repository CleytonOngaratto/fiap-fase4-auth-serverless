[CmdletBinding()]
param(
    [string]$Region = "us-east-1",
    [string]$RoleName = "LabRole",
    [int]$LbDnsMaxAgeHours = 4
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

Write-Head "2. Contrato de entrada (repos 2, 3 e 4 aplicados?)"
$contract = [ordered]@{
    "/fase4/vpc/id"              = "repo 2 (fiap-fase4-infra-k8s)"
    "/fase4/vpc/private-subnets" = "repo 2 (fiap-fase4-infra-k8s)"
    "/fase4/rds/endpoint"        = "repo 3 (fiap-fase4-infra-db)"
    "/fase4/rds/port"            = "repo 3 (fiap-fase4-infra-db)"
    "/fase4/rds/db-name"         = "repo 3 (fiap-fase4-infra-db)"
    "/fase4/rds/username"        = "repo 3 (fiap-fase4-infra-db)"
    "/fase4/rds/client-sg-id"    = "repo 3 (fiap-fase4-infra-db)"
    "/fase4/jwt/private-key"     = "bootstrap manual (sobrevive ao destroy)"
}
foreach ($name in $contract.Keys) {
    $value = Invoke-Probe -Exe "aws" -ProbeArgs @("ssm", "get-parameter", "--name", $name, "--region", $Region, "--query", "Parameter.Value", "--output", "text")
    if ($value) {
        $shown = if ($name -like "*jwt*") { "<$(($value -join "`n").Length) chars>" } else { $value }
        Write-Ok "$name = $shown"
    }
    else {
        Write-Fail "$name AUSENTE — quem publica: $($contract[$name]). Ordem de deploy: 2 -> 3 -> 4 -> 1."
    }
}

Write-Head "3. /fase4/eks/lb-dns aponta para um LoadBalancer VIVO?"

$lb = Invoke-Probe -Exe "aws" -ProbeArgs @("ssm", "get-parameter", "--name", "/fase4/eks/lb-dns", "--region", $Region, "--query", "Parameter.[Value,LastModifiedDate]", "--output", "text")
if (-not $lb) {
    Write-Fail "/fase4/eks/lb-dns AUSENTE — rode o workflow_dispatch do cd.yml no repo 4 (fiap-fase4-os-service)."
}
else {
    $parts = ($lb -join " ") -split "\s+"
    $lbDns = $parts[0]
    $modified = [datetime]::Parse($parts[1])
    $ageHours = [math]::Round(((Get-Date) - $modified).TotalHours, 1)

    if ($ageHours -gt $LbDnsMaxAgeHours) {
        Write-Warn2 "publicado ha $ageHours h ($modified) — mais que uma sessao do lab. Provavelmente e lixo da sessao anterior."
    }
    else {
        Write-Ok "publicado ha $ageHours h ($modified)"
    }

    $health = "http://$lbDns/carworkshop/v1/q/health/ready"
    $code = Invoke-Probe -Exe "curl.exe" -ProbeArgs @("-s", "-o", "NUL", "-m", "15", "-w", "%{http_code}", $health)
    if ($code -eq "200") {
        Write-Ok "$lbDns responde 200 em /q/health/ready — o proxy vai nascer apontando para algo vivo"
    }
    else {
        Write-Fail "$lbDns NAO responde (codigo '$code'). O ANY /{proxy+} nasceria devolvendo 503."
        Write-Host "         Rode o workflow_dispatch do cd.yml no repo 4 e repita este preflight." -ForegroundColor Red
    }
}

Write-Head "4. Zip da Lambda tera as dependencias?"

$modules = Join-Path $repoRoot "lambda/node_modules"
if (Test-Path (Join-Path $modules "pg")) {
    Write-Ok "lambda/node_modules presente (pg, jsonwebtoken, @aws-sdk/client-ssm)"
}
else {
    Write-Fail "lambda/node_modules AUSENTE ou incompleto — rode:  npm ci --omit=dev --prefix lambda"
}

Write-Head "5. A LabRole consegue ler a chave RSA cifrada?"

$roleArn = "arn:aws:iam::$($identity.Account):role/$RoleName"
$simulated = Invoke-Probe -Exe "aws" -ProbeArgs @(
    "iam", "simulate-principal-policy", "--policy-source-arn", $roleArn,
    "--action-names", "ssm:GetParameters", "kms:Decrypt",
    "--query", "EvaluationResults[].[EvalActionName,EvalDecision]", "--output", "text")

if ($simulated) {
    $denied = @($simulated | Where-Object { $_ -notmatch "allowed" })
    if ($denied.Count -eq 0) { Write-Ok "simulate-principal-policy: ssm:GetParameters e kms:Decrypt permitidos para $RoleName" }
    else { Write-Fail "$RoleName SEM permissao: $($denied -join '; ') — ver 'Plano B' no README." }
}
else {
    $assumed = Invoke-Probe -Exe "aws" -ProbeArgs @(
        "sts", "assume-role", "--role-arn", $roleArn, "--role-session-name", "fase4-preflight",
        "--query", "Credentials.AccessKeyId", "--output", "text")
    if ($assumed) { Write-Warn2 "simulate negado, mas o assume-role funciona — teste manual descrito no README." }
    else {
        Write-Warn2 "iam:SimulatePrincipalPolicy e sts:AssumeRole negados ao seu usuario do lab (esperado)."
        Write-Host "         RISCO EM ABERTO: se a LabRole nao tiver kms:Decrypt, /auth devolve 500 e o" -ForegroundColor Yellow
        Write-Host "         CloudWatch da funcao mostra AccessDeniedException. Plano B no README." -ForegroundColor Yellow
    }
}

Write-Head "6. backend.hcl"
$backendPath = Join-Path $repoRoot "backend.hcl"
if (Test-Path $backendPath) {
    Write-Ok "backend.hcl ja existe"
}
else {
    Write-Warn2 "backend.hcl ausente. Crie com o conteudo abaixo (o bucket veio do bootstrap do repo 2):"
    Write-Host ""
    Write-Host "bucket       = `"fiap-fase4-tfstate-$($identity.Account)`"" -ForegroundColor DarkGray
    Write-Host "key          = `"auth-serverless/terraform.tfstate`"" -ForegroundColor DarkGray
    Write-Host "region       = `"$Region`"" -ForegroundColor DarkGray
    Write-Host "use_lockfile = true" -ForegroundColor DarkGray
    Write-Host "encrypt      = true" -ForegroundColor DarkGray
}

Write-Host ""
if ($script:Failed) {
    Write-Host "PREFLIGHT REPROVADO — resolva os [FAIL] acima antes do apply." -ForegroundColor Red
    exit 1
}
Write-Host "PREFLIGHT OK — pode seguir para terraform init/plan/apply." -ForegroundColor Green
