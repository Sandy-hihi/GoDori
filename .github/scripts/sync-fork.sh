#!/usr/bin/env bash
set -euo pipefail

ref="${SYNC_REF:?SYNC_REF must be set}"
git check-ref-format "$ref"
case "$ref" in
  refs/heads/*) source_ref=HEAD ;;
  refs/tags/*) source_ref="$ref" ;; # 주석이 붙은 태그 객체도 유지합니다.
  *) echo 'Only branch and tag refs can be synced.' >&2; exit 1 ;;
esac

# 테스트에서는 로컬 bare 저장소를 지정할 수 있습니다.
remote="${FORK_REMOTE:-https://x-access-token:${FORKED_REPO_TOKEN:?FORKED_REPO_TOKEN must be set}@github.com/hgyngl/GoDori.git}"
# 이번 이벤트의 ref만 갱신하고 다른 태그는 보내지 않습니다.
git push "$remote" "$source_ref:$ref" --force
