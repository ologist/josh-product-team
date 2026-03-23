#!/usr/bin/env bash
# Josh Product Team Plugin — Install Script
# 사용법: ./install.sh [--build-only]

set -e

PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_JSON="$PLUGIN_DIR/.claude-plugin/plugin.json"
PLUGINS_ROOT="$HOME/.claude/plugins"
INSTALLED_JSON="$PLUGINS_ROOT/installed_plugins.json"

PLUGIN_NAME=$(python3 -c "import json; d=json.load(open('$PLUGIN_JSON')); print(d['name'])")
PLUGIN_VERSION=$(python3 -c "import json; d=json.load(open('$PLUGIN_JSON')); print(d.get('version', '0.1.0'))")

MARKETPLACE="josh"
PLUGIN_KEY="${PLUGIN_NAME}@${MARKETPLACE}"
INSTALL_PATH="$PLUGINS_ROOT/cache/$MARKETPLACE/$PLUGIN_NAME/$PLUGIN_VERSION"
DIST_FILE="$PLUGIN_DIR/dist/${PLUGIN_NAME}-${PLUGIN_VERSION}.plugin"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " Josh Product Team Plugin Installer"
echo " 버전: $PLUGIN_VERSION"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# ── 1. dist/.plugin 파일 빌드 ───────────────────────────────
mkdir -p "$PLUGIN_DIR/dist"
echo "📦 .plugin 파일 빌드 중..."
(
  cd "$PLUGIN_DIR"
  zip -r "$DIST_FILE" \
    .claude-plugin \
    commands \
    skills \
    README.md \
    --exclude "*.DS_Store" \
    --exclude "*/.git/*" \
    -q
)
echo "   → $DIST_FILE"

if [[ "$1" == "--build-only" ]]; then
  echo ""
  echo "✅ 빌드 완료 (설치 스킵)"
  exit 0
fi

# ── 2. 이전 버전 캐시 정리 ──────────────────────────────────
PLUGIN_CACHE_DIR="$PLUGINS_ROOT/cache/$MARKETPLACE/$PLUGIN_NAME"
if [ -d "$PLUGIN_CACHE_DIR" ]; then
  for old_ver in "$PLUGIN_CACHE_DIR"/*/; do
    if [ "$(basename "$old_ver")" != "$PLUGIN_VERSION" ]; then
      rm -rf "$old_ver"
      echo "   🗑️  이전 버전 삭제: $(basename "$old_ver")"
    fi
  done
fi

rm -rf "$INSTALL_PATH"
mkdir -p "$INSTALL_PATH"

rsync -a --exclude='.git' --exclude='dist' --exclude='install.sh' \
  --exclude='*.plugin' --exclude='.DS_Store' \
  "$PLUGIN_DIR/" "$INSTALL_PATH/"

echo "   → $INSTALL_PATH"

# ── 3. Claude 앱(Cowork) 플러그인 경로 업데이트 ─────────────
COWORK_SESSIONS="$HOME/Library/Application Support/Claude/local-agent-mode-sessions"
if [ -d "$COWORK_SESSIONS" ]; then
  echo ""
  echo "🖥️  Claude 앱 플러그인 업데이트 중..."
  FOUND=0
  while IFS= read -r pjson; do
    UPLOAD_DIR="$(dirname "$(dirname "$pjson")")"
    COWORK_BASE="$(dirname "$(dirname "$(dirname "$UPLOAD_DIR")")")"
    cp "$PLUGIN_JSON" "$pjson"
    rsync -a --delete "$PLUGIN_DIR/skills/" "$UPLOAD_DIR/skills/"
    rsync -a --delete "$PLUGIN_DIR/commands/" "$UPLOAD_DIR/commands/"
    rsync -a "$PLUGIN_DIR/README.md" "$UPLOAD_DIR/"
    NOW=$(date -u +"%Y-%m-%dT%H:%M:%S.000Z")
    python3 -c "
import json
path = '$COWORK_BASE/installed_plugins.json'
try:
    with open(path) as f: d = json.load(f)
    key = '${PLUGIN_NAME}@local-desktop-app-uploads'
    if key in d.get('plugins', {}):
        d['plugins'][key][0]['version'] = '$PLUGIN_VERSION'
        d['plugins'][key][0]['lastUpdated'] = '$NOW'
        with open(path, 'w') as f: json.dump(d, f, indent=2); f.write('\n')
except: pass
"
    echo "   → $UPLOAD_DIR"
    FOUND=1
  done < <(find "$COWORK_SESSIONS" -path "*/local-desktop-app-uploads/$PLUGIN_NAME/.claude-plugin/plugin.json" 2>/dev/null)
  [ "$FOUND" -eq 0 ] && echo "   (업로드된 플러그인 없음 — 스킵)"
fi

# ── 4. ~/.claude/commands/ 에 커맨드 복사 ──────────────────
echo ""
echo "📋 커맨드 등록 중..."
CLAUDE_COMMANDS_DIR="$HOME/.claude/commands"
mkdir -p "$CLAUDE_COMMANDS_DIR"

for f in "$PLUGIN_DIR/commands/"*.md; do
  fname=$(basename "$f")
  cp "$f" "$CLAUDE_COMMANDS_DIR/$fname"
  echo "   → $CLAUDE_COMMANDS_DIR/$fname"
done

# ── 5. ~/.claude/skills/ 에 스킬 복사 ──────────────────────
echo ""
echo "🧠 스킬 등록 중..."
CLAUDE_SKILLS_DIR="$HOME/.claude/skills"
mkdir -p "$CLAUDE_SKILLS_DIR"

for skill_dir in "$PLUGIN_DIR/skills/"/*/; do
  skill_name=$(basename "$skill_dir")
  mkdir -p "$CLAUDE_SKILLS_DIR/$skill_name"
  cp "$skill_dir/SKILL.md" "$CLAUDE_SKILLS_DIR/$skill_name/SKILL.md"
  echo "   → $CLAUDE_SKILLS_DIR/$skill_name/SKILL.md"
done

# ── 6. installed_plugins.json 업데이트 ─────────────────────
echo ""
echo "🔧 installed_plugins.json 업데이트 중..."

mkdir -p "$PLUGINS_ROOT"
INSTALLED_AT=$(date -u +"%Y-%m-%dT%H:%M:%S.000Z")
GIT_SHA=$(cd "$PLUGIN_DIR" && git rev-parse HEAD 2>/dev/null || echo "")

python3 - <<PYEOF
import json, sys

path = "$INSTALLED_JSON"
try:
    with open(path) as f:
        data = json.load(f)
except FileNotFoundError:
    data = {"version": 2, "plugins": {}}

entry = {
    "scope": "local",
    "installPath": "$INSTALL_PATH",
    "version": "$PLUGIN_VERSION",
    "installedAt": "$INSTALLED_AT",
    "lastUpdated": "$INSTALLED_AT",
    "gitCommitSha": "$GIT_SHA",
    "projectPath": "$PLUGIN_DIR"
}

key = "$PLUGIN_KEY"
if key not in data["plugins"]:
    data["plugins"][key] = []

existing = [e for e in data["plugins"][key] if e.get("scope") not in ("local", "user")]
existing.insert(0, entry)
data["plugins"][key] = existing

with open(path, "w") as f:
    json.dump(data, f, indent=2)
    f.write("\n")

print(f"   → {key} 등록 완료")
PYEOF

# ── 완료 ────────────────────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ 설치 완료!"
echo ""
echo "   Claude Code를 재시작하면 반영됩니다."
echo ""
echo "   ── 워크플로우 커맨드 ──────────────────────"
echo "   /feature-plan   기능 기획 (PM→백엔드→프론트엔드)"
echo "   /code-review    코드 리뷰 (백엔드+프론트엔드+PM)"
echo "   /sprint-plan    스프린트 계획 (우선순위→공수산정→백로그)"
echo ""
echo "   ── 개별 에이전트 단독 호출 ────────────────"
echo "   /product-manager      🗂️  PM"
echo "   /backend-engineer     ⚙️  백엔드 엔지니어"
echo "   /frontend-engineer    🎨 프론트엔드 엔지니어"
echo "   /test-engineer        🧪 테스트 엔지니어"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
