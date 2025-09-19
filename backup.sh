#!/bin/bash
# backup_gitlab_full.sh

# Configurações
GITLAB_URL="https://gitlab-URL.br"
GROUP_ID="GROUP_NAME"
ACCESS_TOKEN="TOKEN"
DEST="/root/bkp-gitlab"
DIAS=7
DATE=$(date +%Y%m%d)
# ===================== Preparar diretório do backup =====================
mkdir -p "$DEST/$DATE"
cd "$DEST/$DATE" || exit 1

# ===================== Funções =====================
ALL_GROUPS=()
collect_all_groups() {
    local group=$1
    ALL_GROUPS+=("$group")
    local subs
    subs=$(curl --silent --header "PRIVATE-TOKEN: $ACCESS_TOKEN" \
        "$GITLAB_URL/api/v4/groups/$group/subgroups?per_page=100" | jq -r '.[].id')
    for sg in $subs; do
        collect_all_groups "$sg"
    done
}

get_projects() {
    local group=$1
    local page=1
    while : ; do
        projects=$(curl --silent --header "PRIVATE-TOKEN: $ACCESS_TOKEN" \
          "$GITLAB_URL/api/v4/groups/$group/projects?per_page=100&page=$page")
        [ "$projects" = "[]" ] && break
        echo "$projects" | jq -r '.[].id'
        page=$((page + 1))
    done
}

# ===================== Coletar todos os grupos =====================
collect_all_groups "$GROUP_ID"

# ===================== Backup completo dos projetos =====================
for g in "${ALL_GROUPS[@]}"; do
    for project_id in $(get_projects "$g"); do
        info=$(curl --silent --header "PRIVATE-TOKEN: $ACCESS_TOKEN" \
            "$GITLAB_URL/api/v4/projects/$project_id")
        name=$(echo "$info" | jq -r '.path_with_namespace')

        echo "==> Backup do projeto: $name"
        mkdir -p "$name"
        cd "$name" || continue

        # Clone completo espelhado
        if [ ! -d "repo.git" ]; then
            git clone --mirror "https://oauth2:${ACCESS_TOKEN}@git.cbpf.br/${name}.git" repo.git \
                || echo "⚠️ Falha ao clonar $name"
        else
            echo "Repositório já existe, atualizando..."
            cd repo.git
            git remote update
            cd ..
        fi

        # Issues
        curl --silent --header "PRIVATE-TOKEN: $ACCESS_TOKEN" \
          "$GITLAB_URL/api/v4/projects/$project_id/issues?per_page=100" -o issues.json

        # Merge Requests
        curl --silent --header "PRIVATE-TOKEN: $ACCESS_TOKEN" \
          "$GITLAB_URL/api/v4/projects/$project_id/merge_requests?per_page=100" -o merge_requests.json

        cd ..
    done
done