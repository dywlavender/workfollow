#!/bin/bash
# REA + Ghidra 12.2 接入验证脚本
# 用法: bash docs/audits/rea-ghidra-check.sh
set -uo pipefail

GHIDRA_DIR="/opt/homebrew/Cellar/ghidra/12.2/libexec"
export GHIDRA_INSTALL_DIR="$GHIDRA_DIR"
export JAVA_HOME="/opt/homebrew/opt/openjdk@25/libexec/openjdk.jdk/Contents/Home"

echo "=== 1. 基础路径 ==="
[ -d "$GHIDRA_DIR" ] && echo "  ✅ Ghidra: $GHIDRA_DIR" || { echo "  ❌ 缺 Ghidra"; exit 1; }
[ -x "$JAVA_HOME/bin/java" ] && echo "  ✅ JDK 25: $JAVA_HOME" || { echo "  ❌ 缺 JDK 25"; exit 1; }

echo "=== 2. 版本 ==="
grep '^application.version' "$GHIDRA_DIR/Ghidra/application.properties"
grep '^application.java.min' "$GHIDRA_DIR/Ghidra/application.properties"
"$JAVA_HOME/bin/java" -version 2>&1 | head -1

echo "=== 3. 补丁是否在位 ==="
POLICY="/opt/homebrew/lib/node_modules/rea-agents/dist/ghidra/GhidraReleasePolicy.js"
if grep -q 'SUPPORTED_GHIDRA_VERSION = "12.2"' "$POLICY"; then
  echo "  ✅ 版本白名单已改为 12.2"
else
  echo "  ⚠️  白名单仍是原值，REA 会拒绝 12.2："
  grep 'SUPPORTED_GHIDRA_VERSION' "$POLICY"
fi

echo "=== 4. doctor 检查 ==="
cd /opt/homebrew/lib/node_modules/rea-agents
node scripts/rea.mjs doctor --client dsh --format json 2>/dev/null \
  | node -e '
let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{
  const j=JSON.parse(s);
  const g=(j.providerInspections||[]).find(x=>x.id==="ghidra");
  if(!g){console.log("  ❌ doctor 未报告 ghidra");return}
  console.log("  available:",g.available,"| version:",g.providerVersion);
  for(const c of g.checks) console.log("   ",c.name.padEnd(18),c.ok?"OK":"FAIL",c.code||"");
})'

echo "=== 5. 端到端反编译自测 ==="
TEST_BIN="/opt/homebrew/bin/node"
[ -x "$TEST_BIN" ] || { echo "  跳过（无测试二进制）"; exit 0; }
node scripts/rea.mjs decompile "$TEST_BIN" --procedure entry --format json 2>&1 \
  | node -e '
let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{
  try{
    const j=JSON.parse(s);
    if(j.error){console.log("  ❌ 失败:",j.message||j.error);return}
    const v=j.raw_result?.value||{};
    const pc=Object.keys(v).sort((a,b)=>a-b).map(k=>v[k]).join("");
    console.log("  ✅ provider:",j.provider.id,j.provider.version);
    console.log("  ✅ 伪代码",pc.length,"字符");
    console.log(pc.split("\n").slice(0,4).map(l=>"     "+l).join("\n"));
  }catch(e){console.log("  ❌ 解析失败:",s.slice(0,200))}
})'
