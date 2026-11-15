#!/usr/bin/env bash
# Prepara os 5 repositórios para o ambiente efêmero (ADR-013). Requer gh autenticado.
set -euo pipefail

acao=${1:-}
[[ "$acao" =~ ^(ligar|desligar|status|segredos)$ ]] || {
  echo "uso: $0 {ligar|desligar|status|segredos}" >&2
  exit 2
}

REPOS=(
  tech-challenge-f4-plataforma
  tech-challenge-f4-os-service
  tech-challenge-f4-execucao-service
  tech-challenge-f4-billing-service
  tech-challenge-f4-auth-lambda
)
dono=${GITHUB_OWNER:-$(git config --get remote.origin.url | sed -E 's#^.*github\.com[:/]([^/]+)/.*$#\1#')} || {
  echo "Defina GITHUB_OWNER ou configure o remote 'origin'." >&2
  exit 1
}
command -v gh >/dev/null || { echo "Instale o GitHub CLI: https://cli.github.com" >&2; exit 1; }
gh auth status >/dev/null 2>&1 || { echo "Autentique o gh: gh auth login" >&2; exit 1; }

case "$acao" in
  ligar|desligar)
    valor=$([[ "$acao" == ligar ]] && echo true || echo false)
    for repo in "${REPOS[@]}"; do
      gh variable set AMBIENTE_ATIVO --body "$valor" --repo "$dono/$repo"
      echo "✓ $repo AMBIENTE_ATIVO=$valor"
    done
    ;;
  status)
    for repo in "${REPOS[@]}"; do
      printf '%-38s %s\n' "$repo" "$(gh variable get AMBIENTE_ATIVO --repo "$dono/$repo" 2>/dev/null || echo 'não definida')"
    done
    ;;
  segredos)
    laboratorio=$(aws iam list-roles --query "Roles[?contains(RoleName, 'LabEksClusterRole')].RoleName" --output text)
    if [[ -n "$laboratorio" && "$laboratorio" != "None" ]]; then
      # Laboratório: credenciais da sessão, que expiram; rode de novo a cada sessão.
      declare -A cred=()
      while IFS='=' read -r chave valor; do
        [[ "$chave" =~ ^AWS_(ACCESS_KEY_ID|SECRET_ACCESS_KEY|SESSION_TOKEN)$ ]] && cred[$chave]=$valor
      done < <(aws configure export-credentials --format env-no-export)
      for chave in AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN; do
        [[ -n "${cred[$chave]:-}" ]] || { echo "Credencial $chave ausente na sessão atual." >&2; exit 1; }
      done
      for repo in "${REPOS[@]}"; do
        for chave in AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN; do
          printf '%s' "${cred[$chave]}" | gh secret set "$chave" --repo "$dono/$repo"
        done
        # Com AWS_ROLE_ARN os pipelines escolheriam o OIDC, que não existe no laboratório.
        gh secret delete AWS_ROLE_ARN --repo "$dono/$repo" >/dev/null 2>&1 || true
        echo "✓ $repo credenciais da sessão do laboratório"
      done
    else
      role=$(terraform output -raw github_role_arn 2>/dev/null) && [[ -n "$role" ]] || {
        echo "Role do OIDC indisponível: rode 'make up' antes." >&2
        exit 1
      }
      for repo in "${REPOS[@]}"; do
        printf '%s' "$role" | gh secret set AWS_ROLE_ARN --repo "$dono/$repo"
        echo "✓ $repo AWS_ROLE_ARN"
      done
    fi
    if [[ -n "${NEW_RELIC_LICENSE_KEY:-}" ]]; then
      printf '%s' "$NEW_RELIC_LICENSE_KEY" | gh secret set NEW_RELIC_LICENSE_KEY --repo "$dono/tech-challenge-f4-plataforma"
    else
      echo "⚠ NEW_RELIC_LICENSE_KEY não exportada: o New Relic fica desligado nos pipelines."
    fi
    if [[ -n "${NEW_RELIC_API_KEY:-}" && -n "${NEW_RELIC_ACCOUNT_ID:-}" ]]; then
      printf '%s' "$NEW_RELIC_API_KEY" | gh secret set NEW_RELIC_API_KEY --repo "$dono/tech-challenge-f4-plataforma"
      printf '%s' "$NEW_RELIC_ACCOUNT_ID" | gh secret set NEW_RELIC_ACCOUNT_ID --repo "$dono/tech-challenge-f4-plataforma"
    else
      echo "⚠ NEW_RELIC_API_KEY e NEW_RELIC_ACCOUNT_ID não exportadas: dashboards e alertas ficam fora do pipeline."
    fi
    echo "✓ segredos gravados em $dono"
    ;;
esac
