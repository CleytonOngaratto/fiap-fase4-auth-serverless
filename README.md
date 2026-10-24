# fiap-fase4-auth-serverless

Borda da Fase 4 do Tech Challenge (FIAP SOAT): o **API Gateway** (HTTP API) que é a única entrada pública dos três
serviços, e a Lambda de autenticação por CPF. Terraform + Node.js.

> Evolução de [fiap-fase3-auth-serverless](https://github.com/CleytonOngaratto/fiap-fase3-auth-serverless).
> Arquitetura em
> [fiap-fase4-os-service/docs/arquitetura](https://github.com/CleytonOngaratto/fiap-fase4-os-service/tree/main/docs/arquitetura)
> — em especial o [ADR-003 (borda privada)](https://github.com/CleytonOngaratto/fiap-fase4-os-service/blob/main/docs/arquitetura/adr/ADR-003-borda-privada.md)
> e o [ADR-004 (Gateway persistente)](https://github.com/CleytonOngaratto/fiap-fase4-os-service/blob/main/docs/arquitetura/adr/ADR-004-gateway-persistente.md).

```
Internet ──HTTPS──► API Gateway (persistent/) ──rotas explícitas──► VPC Link (session/) ──► ALB interno ──► pods
```

## Dois roots de Terraform

| Root | O que cria | Ciclo de vida | Como aplica |
|---|---|---|---|
| [`persistent/`](persistent/) | HTTP API `fiap-fase4-api`, stage `$default` (*auto deploy*) e log group de acesso; publica `/fase4/apigw/api-id` e `/fase4/apigw/url` | **uma vez por conta do laboratório**; não entra no teardown de sessão; `prevent_destroy` no HTTP API | só `workflow_dispatch` (`root=persistent`) |
| [`session/`](session/) | VPC Link nas subnets privadas (o security group dele só sai para o ALB interno, na 80), uma integração com o listener do ALB e as rotas | sobe e desce com a sessão | `push` na `main` com mudança em `session/`, ou `workflow_dispatch` (`root=session`) |

A URL do Gateway fica **estável entre sessões** porque o HTTP API mora no `persistent/`: é ela que vai para o painel
do Mercado Pago (webhook). States separados: `auth-serverless/persistent.tfstate` e `auth-serverless/session.tfstate`.

### Rotas publicadas (allowlist)

O casamento é **sensível a maiúsculas**, e nunca existe rota genérica (`/{proxy+}`) nem rota para `/q/*`: uma rota
genérica expõe health, métricas e OpenAPI. Tudo o que não está aqui recebe **404 do próprio Gateway**.

| Serviço | Rotas |
|---|---|
| OS | `POST /carworkshop/v1/auth/login` · `ANY /carworkshop/v1/{customers,vehicles}/{proxy+}` · `ANY /carworkshop/v1/{service,parts-and-supplies,work-orders}` e `…/{proxy+}` · `GET /carworkshop/v1/tracking/{id}` |
| Billing | `GET /billing/v1/info` |
| Execution | `GET /execution/v1/info` |

`/carworkshop/v1/auth/signup` **não** é publicado: criar administrador é ação de atendimento, não de cliente.

A Lambda de CPF (`lambda/`, testada no CI) vive no `session/`, e a rota `POST /auth` aponta para ela.

**A função não acessa banco nenhum.** Ela valida os dígitos do CPF, confirma o cliente num **endpoint interno
do OS Service** pelo ALB privado e assina o JWT. Suas únicas dependências são o Parameter Store (chave RSA e a
credencial de serviço, lidas em runtime por *nome*) e o ALB interno; o grupo de segurança dela só sai para 443,
para a porta 80 do ALB e para o DNS da VPC. OS Service indisponível resulta em **503**, distinto de erro
interno. O porquê desse desenho e as duas camadas que protegem o endpoint estão no
[ADR-007](https://github.com/CleytonOngaratto/fiap-fase4-os-service/blob/main/docs/arquitetura/adr/ADR-007-lambda-sem-banco-do-os.md).

## Ordem

**Subida:** plataforma ([fiap-fase4-infra-k8s](https://github.com/CleytonOngaratto/fiap-fase4-infra-k8s)) →
`persistent/` (só na primeira vez da conta) → infra e deploy dos serviços → **`session/`**. O `session/` lê do SSM o
ID do HTTP API e o contrato da plataforma, e falha dizendo quem publica se faltar algo.

**Teardown:** o `session/` é o **primeiro** a sair (`scripts/destroy-all.ps1` da plataforma); o `persistent/`
**nunca** entra.

**O merge aplica.** Um merge que mude `session/` ou o workflow aplica o `session/` — só com a sessão do laboratório
ligada, a plataforma e os serviços de pé, e o teardown na mesma sessão.

## O que um *Reset* do laboratório apaga

Tudo o que foi criado na conta, inclusive o que é persistente: o HTTP API (a **URL muda**), o log group, os
parâmetros do SSM e o bucket de state. Depois de um Reset: recriar o bucket (`bootstrap-backend.ps1` da plataforma),
republicar o bootstrap do SSM, aplicar o `persistent/` de novo e **reconfigurar a URL do webhook no painel do Mercado
Pago**.

Apagar o HTTP API de propósito exige um PR que tire o `prevent_destroy` de
[`persistent/apigateway.tf`](persistent/apigateway.tf); um `destroy` do `persistent/` sem isso falha.

## CI

[`.github/workflows/terraform.yml`](.github/workflows/terraform.yml):

| Gatilho | O que roda |
|---|---|
| `pull_request` → `main` | `fmt-validate` (testes da Lambda + `fmt -check` + `init -backend=false` e `validate` nos dois roots — **check obrigatório**) e `terraform` (`plan` do `session/`) |
| `push` → `main` com mudança em `session/` ou no workflow | `fmt-validate` e `terraform` (`plan` → `apply` do `session/` → smoke pelo Gateway) |
| `workflow_dispatch` | `root` = `session` \| `persistent` · `action` = `plan` \| `apply` \| `destroy` |

**Smoke do `session/`:** `GET /billing/v1/info` e `GET /execution/v1/info` → **200**;
`GET /carworkshop/v1/tracking/1` sem token → **401** (vem do Quarkus: o Gateway não tem autorizador);
`GET /carworkshop/v1/q/health/ready` → **404** no Gateway.

O job `terraform` depende da credencial temporária do laboratório (secrets `AWS_*` e a variable `TF_STATE_BUCKET`,
gravados pelo `scripts/refresh-gh-secrets.ps1` da plataforma): com o laboratório desligado ele fica vermelho, por
isso não é check obrigatório.

## Uso local

```powershell
.\scripts\preflight.ps1        # sessão, persistent/ aplicado?, contrato da plataforma, backend.hcl dos dois roots
Copy-Item session\backend.hcl.example session\backend.hcl   # e preencha o bucket
terraform -chdir=session init "-backend-config=backend.hcl" -lockfile=readonly
terraform -chdir=session plan -out tfplan
```
