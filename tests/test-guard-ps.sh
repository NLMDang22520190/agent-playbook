#!/usr/bin/env bash
# Lane w (v0.29.0) slice P1: scripts/guard-irreversible.sh, PreToolUse mode for the PowerShell tool (AC-P1..AC-P10, spec
# Revision 2 F4 and AC-P4b, Revision 3). Hook JSON is the documented Claude Code shape with "tool_name":"PowerShell" and the
# PowerShell text in tool_input.command (https://code.claude.com/docs/en/hooks, section "PowerShell"; spec R3).
# The guard only reads these commands as text; nothing here runs a delete, a push or SQL. Git cases use throwaway repos under
# the suite's temp dirs. Cases marked [UNVERIFIED] pin a reading the spec leaves open; they are the first to revisit.
. "$(dirname "$0")/lib.sh"
. "$PB_ROOT/tests/guard-fixture.sh"

W='C:\work\app'          # the hook cwd for Windows-path cases: the project root is /c/work/app (never created)
PSE=()                   # extra VAR=val words for grun
PSM=1                    # PB_HEADLESS value

# psh CMD [CWD] -> the guard on a PowerShell call (headless unless PSM=0), sets RC, GOUT, GERR
psh() { grun PB_HEADLESS="$PSM" "${PSE[@]}" -- "$(jps "$1" "${2:-$W}")"; }
# list helpers: the cases come one per line on stdin (here-documents keep the PowerShell quoting readable)
blk() { # KIND [CWD] : each line BLOCKs with KIND
  local list c; list="$(cat)"
  while IFS= read -r c <&3; do [ -n "$c" ] || continue; psh "$c" "${2:-}"; expect_block "[$c]" "$1"; done 3<<<"$list"
}
pas() { # [CWD] : each line PASSes
  local list c; list="$(cat)"
  while IFS= read -r c <&3; do [ -n "$c" ] || continue; psh "$c" "${1:-}"; expect_pass "[$c]"; done 3<<<"$list"
}
# nocrash NAME -> exit 0 and no shell error text on stderr (D1 fail-open, AC-P9)
nocrash() {
  if [ "$RC" = 0 ] && ! has "$GERR" 'syntax error' && ! has "$GERR" 'unbound variable' && ! has "$GERR" 'bad substitution' &&
    ! has "$GERR" ': line ' && ! has "$GERR" 'command not found'; then t_ok "$1 (exit 0, no crash)"; else t_bad "$1 (exit 0, no crash)" "rc=$RC $OUT"; fi
}
NLC=$'\n' # a real newline ($(printf '\n') would be empty: command substitution strips it)

echo "P1 AC-P1 the PowerShell tool is checked (headless BLOCK, interactive WARN, harmless PASS)"
psh 'Remove-Item -Recurse -Force C:\Users\me\docs'
expect_block "AC-P1 headless: recursive delete outside the project" rm-outside
assert_contains "AC-P1 the BLOCK quotes the matched PowerShell text" "$GERR" 'Remove-Item -Recurse -Force C:\Users\me\docs'
assert_contains "AC-P1 the BLOCK says the run is headless" "$(printf '%s' "$GERR" | tr 'A-Z' 'a-z')" headless
PSM=0 psh 'Remove-Item -Recurse -Force C:\Users\me\docs'
expect_warn "AC-P1 interactive: recursive delete outside only warns"
assert_contains "AC-P1 interactive warning names the kind rm-outside" "$GOUT" rm-outside
PSM=0 psh 'git push --force origin main'
expect_warn "AC-P1 interactive: force push only warns"
assert_contains "AC-P1 interactive warning names the kind git-push-force" "$GOUT" git-push-force
PSM=0 psh 'sqlcmd -S . -Q "DROP TABLE dbo.t"'
expect_warn "AC-P1 interactive: destructive SQL only warns"
assert_contains "AC-P1 interactive warning names the kind sql" "$GOUT" sql
grun CI=true -- "$(jps 'git push -f origin main')"
expect_block "AC-P1 PB_HEADLESS unset, CI=true is headless for PowerShell too" git-push-force
grun -- "$(jps 'git push -f origin main')"
expect_warn "AC-P1 PB_HEADLESS and CI unset: interactive for PowerShell too"
pas <<'EOF'
Get-ChildItem -Recurse
git status
Remove-Item .\build -Recurse -Force
Write-Host "hello"
Get-Content .\README.md | Select-String TODO
EOF
PSM=0 psh 'Get-ChildItem -Recurse'; expect_pass "AC-P1 interactive: a harmless command prints nothing"
# the same text under another tool name is not this guard's business; and the PowerShell call with a different tool name
grun PB_HEADLESS=1 -- '{"session_id":"s1","cwd":"C:\\work\\app","hook_event_name":"PreToolUse","tool_name":"Read","tool_input":{"command":"git push --force origin main"},"tool_use_id":"t"}'
expect_pass "AC-P1 tool Read with a command field is still ignored"
# a sample whose values differ from their labels: the description says force push, the command is harmless
grun PB_HEADLESS=1 -- '{"session_id":"s1","cwd":"C:\\work\\app","hook_event_name":"PreToolUse","tool_name":"PowerShell","tool_input":{"command":"git status","description":"git push --force origin main"},"tool_use_id":"t"}'
expect_pass "AC-P1 only tool_input.command is scanned, not the description"
# key order and spacing as another client may send them
grun PB_HEADLESS=1 -- '{ "tool_input" : { "description" : "x", "command" : "git push --force origin main" }, "tool_name" : "PowerShell", "cwd" : "C:\\work\\app", "session_id" : "s9" }'
expect_block "AC-P1 keys in another order with spaces are parsed" git-push-force
grun PB_HEADLESS=1 -- '{"session_id":"s1","cwd":"C:\\work\\app","hook_event_name":"PreToolUse","tool_name":"PowerShell","tool_input":{"command":"Remove-Item -Recurse \"C:\\Users\\me\\docs\"","timeout":5000,"run_in_background":false},"tool_use_id":"t"}'
expect_block "AC-P1 escaped quotes and backslashes of the JSON are decoded (documented fields timeout, run_in_background)" rm-outside

echo "P1 AC-P1 regression: the Bash tool with the same texts behaves as before (AC-P10)"
grun PB_HEADLESS=1 -- "$(jbash 'rm -rf /opt/pbguard-x')"
expect_block "AC-P10 Bash rm -rf /opt/pbguard-x still blocks" rm-outside
grun PB_HEADLESS=1 -- "$(jbash 'git push --force origin main')"
expect_block "AC-P10 Bash git push --force still blocks" git-push-force
grun PB_HEADLESS=1 -- "$(jbash 'sqlite3 app.db "DROP TABLE users;"')"
expect_block "AC-P10 Bash sqlite3 DROP TABLE still blocks" sql
grun PB_HEADLESS=1 -- "$(jbash 'd=/opt/pbguard; rm -rf "$d"')"
expect_block "AC-P10 Bash-only form (assignment then \$d) still blocks" rm-outside
grun PB_HEADLESS=1 -- "$(jbash 'rm -rf build')"
expect_pass "AC-P10 Bash rm -rf build (inside) still passes"
grun PB_HEADLESS=1 -- "$(jbash 'Remove-Item -Recurse -Force C:\Users\me\docs')"
expect_pass "AC-P10 PowerShell cmdlet text under the Bash tool gets no PowerShell treatment"
grun PB_HEADLESS=1 -- "$(jbash 'Remove-Item -Recurse -Force /opt/pbguard-x')"
expect_pass "AC-P10 Bash call 'Remove-Item -Recurse /opt/..' is not an rm (Bash tokenizer unchanged)"
grun PB_HEADLESS=1 -- "$(jbash 'echo ok; Get-ChildItem -Recurse')"
expect_pass "AC-P10 Bash call with a PowerShell word passes"

echo "P1 AC-P2 Remove-Item, its aliases and case forms (recursive, target outside)"
for n in Remove-Item remove-item REMOVE-ITEM rm RM ri del erase rmdir rd Rd 'Microsoft.PowerShell.Management\Remove-Item' 'microsoft.powershell.management\remove-item'; do
  psh "$n"' -Recurse -Force C:\Users\me\docs'; expect_block "AC-P2 command word [$n]" rm-outside
  psh "$n"' C:\Users\me\docs -Recurse'; expect_block "AC-P2 command word [$n], switch after the target" rm-outside
done
echo "P1 AC-P2 recursive switch spellings"
for s in -r -R -Re -rec -recu -recurs -recurse -Recurse -RECURSE '-Recurse:$true' '-Recurse:$True' '-r:$true' '-re:$TRUE'; do
  psh "Remove-Item $s C:\\Users\\me\\docs"; expect_block "AC-P2 switch [$s]" rm-outside
  psh "Remove-Item C:\\Users\\me\\docs -Force $s -Confirm:\$false"; expect_block "AC-P2 switch [$s] among -Force and -Confirm:\$false" rm-outside
done
pas <<'EOF'
Remove-Item C:\Users\me\docs
Remove-Item C:\Users\me\docs -Force
Remove-Item -Force C:\Users\me\docs\a.txt
Remove-Item C:\Users\me\docs -Confirm:$false
Remove-Item C:\Users\me\docs -ErrorAction SilentlyContinue
rm C:\Users\me\docs\old.log
del C:\Users\me\docs\*.tmp
Remove-Item -Recurse:$false C:\Users\me\docs
Remove-Item -Recurse:$False C:\Users\me\docs
Remove-Item -recurse:$false -Force C:\Users\me\docs
Remove-Item -Rx C:\Users\me\docs
Remove-Item -Recurses C:\Users\me\docs
Get-ChildItem C:\Users\me\docs -Recurse
Get-ChildItem -Recurse -Force C:\Users\me\docs | Select-Object Name
Write-Host Remove-Item -Recurse C:\Users\me\docs
EOF
psh 'Remove-Item -Recurse -Force -Confirm:$false -ErrorAction SilentlyContinue C:\Users\me\docs'
expect_block "AC-P2 -Force, -Confirm:\$false and -ErrorAction before the target do not hide it" rm-outside

echo "P1 AC-P2 targets: positional, -Path, -LiteralPath (-LP, -PSPath), colon-bound, comma lists (F4)"
blk rm-outside <<'EOF'
Remove-Item -Recurse -Path C:\Users\me\docs
Remove-Item -Recurse -path C:\Users\me\docs
Remove-Item -Recurse -PATH C:\Users\me\docs
Remove-Item -Recurse -LiteralPath C:\Users\me\docs
Remove-Item -Recurse -literalpath C:\Users\me\docs
Remove-Item -Recurse -LP C:\Users\me\docs
Remove-Item -Recurse -PSPath C:\Users\me\docs
Remove-Item -Path C:\Users\me\docs -Recurse
Remove-Item -Recurse -Path:C:\Users\me\docs
Remove-Item -Recurse -LiteralPath:C:\Users\me\docs
Remove-Item -Recurse -LiteralPath:'..\x'
Remove-Item -Recurse -Path:"$HOME\x"
Remove-Item -Recurse -Path:'C:\Users\me\docs'
Remove-Item -Recurse .\build, C:\Users\me\docs
Remove-Item -Recurse .\build,C:\Users\me\docs
Remove-Item -Recurse C:\Users\me\docs, .\build
Remove-Item -Recurse C:\Users\me\docs,.\build
Remove-Item -Recurse -Path .\build, C:\Users\me\docs
Remove-Item -Recurse -Path .\build,C:\Users\me\docs
Remove-Item -Recurse -LiteralPath .\a,.\b,C:\Users\me\docs
rm -r .\build C:\Users\me\docs
rm -r C:\Users\me\docs .\build
Remove-Item -Recurse -Force 'C:\Users\me\docs'
Remove-Item -Recurse -Force "C:\Users\me\docs"
Remove-Item -Recurse -Force 'C:\Program Files\Some App'
Remove-Item -Recurse -Force "C:\Users\me\my docs"
Remove-Item -Recurse -Force 'C:\Users\o''brien\x'
Remove-Item -Recurse -Force -Path 'C:\Users\me\my docs'
Remove-Item -Force -Recurse C:\Users\me\docs
Remove-Item -WhatIf -Recurse C:\Users\me\docs
Remove-Item -Verbose -Recurse C:\Users\me\docs
Remove-Item -Confirm -Recurse C:\Users\me\docs
Remove-Item -Force C:\Users\me\docs -Recurse
Remove-Item -Verbose C:\Users\me\docs -Recurse
Remove-Item -WhatIf C:\Users\me\docs -Recurse
Remove-Item -Confirm C:\Users\me\docs -Recurse
Remove-Item -Recurse -Filter *.tmp C:\Users\me\docs
Remove-Item -Recurse -ErrorAction SilentlyContinue C:\Users\me\docs
Remove-Item -Recurse -WarningAction SilentlyContinue C:\Users\me\docs
Remove-Item -Recurse -InformationAction Ignore C:\Users\me\docs
Remove-Item -Recurse -Include *.log -Exclude keep.log C:\Users\me\docs
Remove-Item -Recurse -OutVariable ov C:\Users\me\docs
Remove-Item -Recurse -Stream :Zone.Identifier C:\Users\me\docs
EOF
pas <<'EOF'
Remove-Item -Recurse -Force .\dist
Remove-Item -Recurse -Path .\dist
Remove-Item -Recurse -LiteralPath .\dist
Remove-Item -Recurse -LP .\dist
Remove-Item -Recurse -PSPath .\dist
Remove-Item -Recurse -Path:.\dist
Remove-Item -Recurse -LiteralPath:'.\dist'
Remove-Item -Recurse -Path:".\dist"
Remove-Item -Recurse .\dist, .\build
Remove-Item -Recurse .\dist,.\build
Remove-Item -Recurse -Path .\dist,.\build
Remove-Item -Recurse -Force '.\my dir\x'
Remove-Item -Recurse -Force ".\my dir\x"
rm -r dist
del -Recurse -Force .\dist
Remove-Item -Recurse -Include C:\elsewhere\x.log .\build
Remove-Item -Recurse -Exclude C:\elsewhere\keep .\build
Remove-Item -Recurse -Filter C:\elsewhere\x .\build
Remove-Item -Recurse -Stream C:\elsewhere\s .\build
Remove-Item -Recurse -Credential C:\elsewhere\c .\build
Remove-Item -Recurse -ErrorAction C:\elsewhere\e .\build
Remove-Item -Recurse -WarningAction C:\elsewhere\w .\build
Remove-Item -Recurse -InformationAction C:\elsewhere\i .\build
Remove-Item -Recurse -OutVariable C:\elsewhere\o .\build
Remove-Item .\build -Recurse -Filter C:\elsewhere\x
Remove-Item .\build -Recurse -ErrorAction C:\elsewhere\e
EOF
psh 'Remove-Item -Recurse -Force .\build; Remove-Item -Recurse -Force C:\Users\me\docs'
expect_block "AC-P2 two Remove-Item commands, the second one is outside" rm-outside

echo "P1 AC-P3 Windows path forms (hook cwd C:\\work\\app, HOME=$GH)"
blk rm-outside <<'EOF'
Remove-Item -Recurse -Force ..\other
Remove-Item -Recurse -Force ../other
rm -r C:\Users\me\docs
rm -r C:/Users/me/docs
rm -r c:\users\me\docs
Remove-Item -Recurse -Force D:\work\app\tmp
Remove-Item -Recurse -Force C:\work\app
Remove-Item -Recurse -Force C:\work\app\
Remove-Item -Recurse -Force C:/work/app
Remove-Item -Recurse -Force c:\WORK\APP
Remove-Item -Recurse -Force .
Remove-Item -Recurse -Force .\
Remove-Item -Recurse -Force ..
Remove-Item -Recurse -Force .\sub\..\..\other
Remove-Item -Recurse -Force C:\work\app\..\other
Remove-Item -Recurse -Force C:\work\appx\tmp
Remove-Item -Recurse -Force C:\work
Remove-Item -Recurse -Force ~\x
Remove-Item -Recurse -Force ~/x
Remove-Item -Recurse -Force ~
Remove-Item -Recurse -Force /opt/pbguard-data
Remove-Item -Recurse -Force C:\
Remove-Item -Recurse -Force \\server\share\x
Remove-Item -Recurse -Force ..\*
EOF
pas <<'EOF'
Remove-Item -Recurse -Force .\dist
Remove-Item -Recurse -Force ./dist
Remove-Item -Recurse -Force dist
Remove-Item -Recurse -Force x\y
Remove-Item -Recurse -Force .\x\y\
Remove-Item -Recurse -Force C:\WORK\APP\tmp
Remove-Item -Recurse -Force c:\work\app\tmp
Remove-Item -Recurse -Force C:/work/app/tmp
Remove-Item -Recurse -Force C:\work\app\sub\..\tmp
Remove-Item -Recurse -Force .\sub\..\build
Remove-Item -Recurse -Force ..\app\tmp
Remove-Item -Recurse -Force .\node_modules
Remove-Item -Recurse -Force .\src\old\*
EOF
# a project under the home: ~ and $HOME expand through pb_home
pas /pbguard-home/proj <<'EOF'
Remove-Item -Recurse -Force ~\proj\build
Remove-Item -Recurse -Force ~/proj/build
Remove-Item -Recurse -Force $HOME\proj\build
EOF
blk rm-outside /pbguard-home/proj <<'EOF'
Remove-Item -Recurse -Force ~\other
Remove-Item -Recurse -Force $HOME\proj
Remove-Item -Recurse -Force ~
EOF
# CLAUDE_PROJECT_DIR is the root when set (Windows form), the hook cwd may be below or above it
PSE=(CLAUDE_PROJECT_DIR='C:\work\app')
psh 'Remove-Item -Recurse ..\build' 'C:\work\app\sub'; expect_pass "AC-P3 root from CLAUDE_PROJECT_DIR: cwd below it, ..\\build is inside"
psh 'Remove-Item -Recurse other' 'C:\work'; expect_block "AC-P3 root from CLAUDE_PROJECT_DIR: cwd above it, other is outside" rm-outside
PSE=()
# temp dirs: TMPDIR (the guard's own temp dir) and /tmp allow a delete below them
psh "Remove-Item -Recurse -Force $GT/pbguard-x"; expect_pass "AC-P3 a path below the guard's TMPDIR passes"
psh 'Remove-Item -Recurse -Force /tmp/pbguard-x'; expect_pass "AC-P3 a path below /tmp passes"
psh 'Remove-Item -Recurse -Force /tmp'; expect_block "AC-P3 the temp dir itself is not below it (outside)" rm-outside
PSM=0 psh 'Remove-Item -Recurse -Force ..\other'; expect_warn "AC-P3 interactive: a path outside only warns"

echo "P1 AC-P4 / AC-P4b targets that cannot be resolved count as outside"
blk rm-outside <<'EOF'
Remove-Item -Recurse $x
Remove-Item -Recurse $x\y
Remove-Item -Recurse "$x\y"
Remove-Item -Recurse $unknown_var\build
Remove-Item -Recurse "$env:PBGUARD_UNKNOWN\x"
Remove-Item -Recurse $env:PBGUARD_UNKNOWN
Remove-Item -Recurse $(Get-Location)
Remove-Item -Recurse "$(Get-Location)\x"
Remove-Item -Recurse (Join-Path $PWD x)
Remove-Item -Recurse (Join-Path $PWD 'x')
Get-ChildItem | ForEach-Object { Remove-Item $_ -Recurse }
Get-ChildItem .\build | ForEach-Object { Remove-Item $_.FullName -Recurse -Force }
Get-ChildItem | Where-Object { $_.Name -like 'old*' } | ForEach-Object { Remove-Item -Recurse $_ }
Remove-Item -Recurse $env:USERPROFILE\..\x
Remove-Item -Recurse -Path $p
Remove-Item -Recurse -LiteralPath $p
Remove-Item -Recurse -Path:$p
Remove-Item -Recurse .\build, $x
Remove-Item -Recurse .\build,$x
$p = 'C:\Users\me\docs'; Remove-Item -Recurse $p
$p = '.\build'; Remove-Item -Recurse $p
Get-ChildItem C:\other | Remove-Item -Recurse -Force
Get-ChildItem .\build | Remove-Item -Recurse
Get-ChildItem .\build | Remove-Item -r
Get-ChildItem | Remove-Item -Recurse -Force
Get-ChildItem -Directory | Where-Object Name -like 'tmp*' | Remove-Item -Recurse -Force
Get-ChildItem C:\other | rm -r -fo
Get-ChildItem C:\other | Remove-Item -Force -Recurse
Remove-Item @p -Recurse
Remove-Item -Recurse @p
Remove-Item @args -Recurse -Force
Remove-Item -Recurse -Force @p
EOF
pas <<'EOF'
Get-ChildItem .\build | Remove-Item
Get-ChildItem .\build | Remove-Item -Force
Get-ChildItem C:\other | Remove-Item -Recurse:$false
Remove-Item @p
Remove-Item @p -Force
Get-ChildItem .\build | Select-Object Name
EOF
PSM=0 psh 'Get-ChildItem C:\other | Remove-Item -Recurse -Force'; expect_warn "AC-P4b interactive: pipeline-bound recursive delete only warns"

echo "P1 AC-P5 variables that resolve (HOME=$GH, TMPDIR=\$GT)"
blk rm-outside <<'EOF'
Remove-Item -Recurse $HOME\x
Remove-Item -Recurse "$HOME\x"
Remove-Item -Recurse $env:USERPROFILE\x
Remove-Item -Recurse "$env:USERPROFILE\x"
Remove-Item -Recurse $env:HOME\x
Remove-Item -Recurse "$env:HOME\x"
Remove-Item -Recurse $Env:UserProfile\x
Remove-Item -Recurse $HOME
Remove-Item -Recurse $env:USERPROFILE
Remove-Item -Recurse $PWD
Remove-Item -Recurse "$PWD"
Remove-Item -Recurse $PWD\..\x
Remove-Item -Recurse "$PWD\..\x"
Remove-Item -Recurse $pwd\..\x
Remove-Item -Recurse $env:CLAUDE_PROJECT_DIR
Remove-Item -Recurse "$env:CLAUDE_PROJECT_DIR\build"
Remove-Item -Recurse "${env:HOME}\x"
Remove-Item -Recurse "$($HOME)\x"
EOF
# [UNVERIFIED] "${env:HOME}" and "$($HOME)" are listed above only as BLOCK: either resolved to home\x (outside) or unresolved (outside)
pas <<'EOF'
Remove-Item -Recurse $PWD\build
Remove-Item -Recurse "$PWD\build"
Remove-Item -Recurse $pwd\build
Remove-Item -Recurse $PWD/build
Remove-Item -Recurse -Path $PWD\build
Remove-Item -Recurse '$HOME\x'
Remove-Item -Recurse '$env:USERPROFILE\x'
Remove-Item -Recurse '$x\y'
Remove-Item -Recurse "`$HOME\x"
Remove-Item -Recurse "`$x\y"
EOF
pas /pbguard-home/proj <<'EOF'
Remove-Item -Recurse $HOME\proj\build
Remove-Item -Recurse "$HOME\proj\build"
Remove-Item -Recurse $env:USERPROFILE\proj\build
Remove-Item -Recurse "$env:USERPROFILE\proj\build"
Remove-Item -Recurse $env:HOME\proj\build
Remove-Item -Recurse "$env:HOME/proj/build"
Remove-Item -Recurse $Env:Home\proj\build
Remove-Item -Recurse $ENV:HOME\proj\build
EOF
# $env:TEMP, TMP, TMPDIR: the value as the guard sees it
PSE=(TEMP=/tmp/pbguard-tempA TMPDIR=)   # a temp dir the guard knows without cygpath (/tmp); never created
psh 'Remove-Item -Recurse -Force "$env:TEMP\pbx"'; expect_pass "AC-P5 spec example: \"\$env:TEMP\\pbx\" with TEMP a temp dir"
psh 'Remove-Item -Recurse -Force "$Env:Temp\pbx"'; expect_pass "AC-P5 \$Env:Temp is case-insensitive"
psh 'Remove-Item -Recurse -Force "$ENV:TEMP/pbx"'; expect_pass "AC-P5 \$ENV:TEMP with a forward slash"
PSE=(TMP=/tmp/pbguard-tempB TMPDIR=)
psh 'Remove-Item -Recurse -Force "$env:TMP\pbx"'; expect_pass "AC-P5 \$env:TMP resolves"
PSE=()
psh 'Remove-Item -Recurse -Force "$env:TMPDIR\pbx"'; expect_pass "AC-P5 \$env:TMPDIR resolves (the guard's TMPDIR)"
# the value matters: a TEMP inside the project passes, a TEMP outside both roots blocks (so \$env:TEMP is neither always safe nor always unresolved)
PSE=(TEMP='C:\work\app\.tmp' TMPDIR=)
psh 'Remove-Item -Recurse -Force "$env:TEMP\x"'; expect_pass "AC-P5 TEMP=C:\\work\\app\\.tmp resolves to a path inside the project"
PSE=(TEMP='C:\elsewhere\tmp' TMPDIR=)
psh 'Remove-Item -Recurse -Force "$env:TEMP\x"'; expect_block "AC-P5 TEMP=C:\\elsewhere\\tmp resolves to an outside path" rm-outside
psh 'Remove-Item -Recurse -Force $env:TEMP\x'; expect_block "AC-P5 unquoted \$env:TEMP\\x with an outside TEMP" rm-outside
PSE=(CLAUDE_PROJECT_DIR='C:\work\app')
psh 'Remove-Item -Recurse "$env:CLAUDE_PROJECT_DIR\build"' 'C:\other'; expect_pass "AC-P5 \$env:CLAUDE_PROJECT_DIR\\build is inside (cwd elsewhere)"
psh 'Remove-Item -Recurse $env:CLAUDE_PROJECT_DIR\build' 'C:\other'; expect_pass "AC-P5 unquoted \$env:CLAUDE_PROJECT_DIR\\build is inside"
psh 'Remove-Item -Recurse $env:CLAUDE_PROJECT_DIR' 'C:\other'; expect_block "AC-P5 \$env:CLAUDE_PROJECT_DIR itself is the root (outside)" rm-outside
PSE=()
psh 'Remove-Item -Recurse "$env:CLAUDE_PROJECT_DIR\build"'; expect_block "AC-P5 CLAUDE_PROJECT_DIR unset: unresolved, outside" rm-outside
PSM=0 psh 'Remove-Item -Recurse "$x\y"'; expect_warn "AC-P4 interactive: an unresolved target only warns"

echo "P1 AC-P6 git through the PowerShell tool (same seg_git logic)"
blk git-push-force <<'EOF'
git push --force origin main
git push -f
git push -f origin feature
git push -uf origin main
git push --force-with-lease
git push --force-with-lease=main:abc123 origin main
git push --force-if-includes origin main
git push origin +main
git push origin "+main"
git push origin '+HEAD:refs/heads/main'
git push --mirror backup
git -C .. push -f origin main
git -c push.default=current push --force
git.exe push --force origin main
GIT push --force origin main
Git.EXE push -f
& git push -f
& git push --force origin main
& "C:\Program Files\Git\cmd\git.exe" push -f
& 'C:\Program Files\Git\cmd\git.exe' push --force origin main
C:\Git\bin\git.exe push -f origin main
git push --force origin main 2>&1
git push -f origin main > out.txt
git push -f | Out-Null
EOF
pas <<'EOF'
git push origin main
git push -u origin feature
git push --tags
git push --follow-tags origin main
git -C .. push origin main
git fetch -f origin
git pull --force
git status
git.exe status
& git status
& "C:\Program Files\Git\cmd\git.exe" status
git commit -m "push -f later"
git commit -m 'git push --force'
Write-Host "git push --force origin main"
Write-Host 'git push -f'
git log --grep="DROP TABLE"
Get-Content notes.txt | Select-String "git push -f"
EOF
fresh() { R="$(mk_tmp)/repo"; mk_repo "$R" >/dev/null; GRUNDIR="$R"; }
fresh
for c in 'git reset --hard' 'git checkout -- .' 'git checkout .' 'git restore .' 'git restore src/app.js' 'git clean -fd'; do
  psh "$c" "$R"; expect_pass "AC-P6 clean tree, nothing to lose [$c]"
done
printf 'module.exports = 2;\n' > "$R/src/app.js"
for c in 'git reset --hard' 'git reset --hard HEAD' 'git checkout -- src/app.js' 'git checkout -- .' 'git checkout .' 'git restore .' 'git restore src/app.js' \
  'git.exe reset --hard' '& git reset --hard' '& "C:\Program Files\Git\cmd\git.exe" reset --hard' 'GIT reset --hard' 'git -C . reset --hard' 'git status; git reset --hard' \
  'git status && git reset --hard'; do
  psh "$c" "$R"; expect_block "AC-P6 tracked change would be lost [$c]" git-discard
done
for c in 'git restore --staged src/app.js' 'git reset --soft HEAD' 'git checkout -b feature' 'git status'; do
  psh "$c" "$R"; expect_pass "AC-P6 tracked change, harmless git form [$c]"
done
PSM=0 psh 'git reset --hard' "$R"; expect_warn "AC-P6 interactive: reset --hard with changes only warns"
assert_contains "AC-P6 interactive warning names git-discard" "$GOUT" git-discard
fresh
printf 'scratch\n' > "$R/notes.txt"
for c in 'git clean -fd' 'git clean -f'; do psh "$c" "$R"; expect_block "AC-P6 an untracked file would be lost [$c]" git-discard; done
psh 'git clean -n' "$R"; expect_pass "AC-P6 git clean -n (dry run) with an untracked file"
psh 'git reset --hard' "$R"; expect_pass "AC-P6 only an untracked file: reset --hard keeps it"
GRUNDIR="$GW"

echo "P1 AC-P7 destructive SQL through client programs"
P="$(mk_tmp)"
mkdir -p "$P/db"
printf 'DROP TABLE legacy_orders;\n' > "$P/db/drop.sql"
printf 'SELECT 1;\n' > "$P/db/read.sql"
printf -- '-- cleanup\nDELETE FROM sessions;\n' > "$P/db/wipe.sql"
blk sql "$P" <<'EOF'
sqlcmd -S . -Q "DROP TABLE dbo.t"
sqlcmd -S . -d shop -Q "TRUNCATE TABLE dbo.t"
sqlcmd -Q "DELETE FROM dbo.t"
sqlcmd -Q "SELECT 1; DROP TABLE t"
sqlcmd -S . -Q 'DROP DATABASE shop'
SQLCMD -Q "DROP TABLE t"
sqlcmd.exe -Q "DROP TABLE t"
sqlite3 app.db "DROP TABLE t"
sqlite3 app.db 'drop table t'
sqlite3.exe app.db "DROP TABLE t"
Sqlite3 app.db "DROP TABLE t"
.\tools\sqlite3.exe app.db "DROP TABLE t"
& .\tools\sqlite3.exe app.db "DROP TABLE t"
& "C:\Tools\sqlite3.exe" app.db "DROP TABLE t"
psql -c 'TRUNCATE t'
psql -c "DROP SCHEMA s CASCADE"
psql.exe -d shop -c "DROP TABLE t"
& "C:\Program Files\PostgreSQL\16\bin\psql.exe" -c "DROP TABLE t"
mysql -e "DELETE FROM t"
mysql -e "delete from t;"
mysql.exe -e "DROP TABLE t"
mariadb -e "DROP TABLE t"
duckdb x.db "DROP SCHEMA s CASCADE"
Invoke-Sqlcmd -Query "DROP TABLE t"
invoke-sqlcmd -Query 'DROP TABLE t'
Invoke-Sqlcmd -ServerInstance . -Query "TRUNCATE TABLE t"
sqlcmd -i .\db\drop.sql
sqlcmd -i .\db\wipe.sql
sqlcmd -S . -i db\drop.sql
Invoke-Sqlcmd -InputFile .\db\drop.sql
Invoke-Sqlcmd -InputFile db\wipe.sql
psql -f .\db\drop.sql
sqlite3 app.db ".read .\db\drop.sql"
"DROP TABLE t" | sqlite3 app.db
'DROP TABLE t' | sqlite3 app.db
"drop table t;" | sqlite3 app.db
Write-Output "TRUNCATE t" | mysql
echo 'DROP TABLE t' | psql
echo "DROP DATABASE shop" | mysql
Get-Content .\db\drop.sql | sqlite3 app.db
Get-Content .\db\wipe.sql | psql
Get-Content -Path .\db\drop.sql | sqlite3 app.db
cd db; sqlite3 ..\app.db "DROP TABLE x"
sqlite3 app.db "SELECT 1"; sqlite3 app.db "DROP TABLE t"
sqlite3 app.db "DROP TABLE t" 2>&1
sqlite3 app.db "DELETE FROM a WHERE id=1; DELETE FROM b;"
EOF
HS1="$(printf '%s\n' '@"' 'DROP TABLE t' '"@ | sqlite3 app.db')"
HS2="$(printf '%s\n' "@'" 'CREATE TABLE t2 (id INTEGER);' 'DROP TABLE users;' "'@ | sqlite3 app.db")"
for c in "$HS1" "$HS2"; do psh "$c" "$P"; expect_block "AC-P7 a here-string piped to sqlite3 keeps its text [${c%%$NLC*}...]" sql; done
# [UNVERIFIED] a here-string held in a variable and piped later: the spec lists no variable flow (Limit); not pinned either way
pas "$P" <<'EOF'
sqlite3 app.db "SELECT 1"
sqlite3 app.db "DELETE FROM t WHERE id = 3"
sqlite3 app.db ".tables"
sqlite3 app.db "SELECT 1" > C:\other\out.txt
psql -c "SELECT * FROM users"
mysql -e "SELECT 1"
sqlcmd -Q "SELECT 1"
sqlcmd -i .\db\read.sql
sqlcmd -i .\db\missing.sql
Invoke-Sqlcmd -InputFile .\db\read.sql
Invoke-Sqlcmd -Query "SELECT 1"
"DROP TABLE t" | Out-File notes.txt
'DROP TABLE t' | Set-Content notes.txt
Write-Output "DROP TABLE"
Write-Output "DROP TABLE t" > notes.txt
Write-Host "TRUNCATE is fast"
Get-Content .\db\drop.sql
Get-Content .\db\drop.sql | Out-Host
Get-Content .\db\drop.sql | Select-String DROP
Set-Content .\db\new.sql "DROP TABLE t"
Select-String -Path .\db\*.sql -Pattern "DROP TABLE"
git log --grep="DROP TABLE"
EOF
PSM=0 psh 'sqlite3 app.db "DROP TABLE users;"' "$P"; expect_warn "AC-P7 interactive: a DROP through sqlite3 only warns"
psh 'sqlite3 app.db "DROP TABLE users;"' "$P"
assert_contains "AC-P7 the BLOCK quotes the SQL client command" "$GERR" 'sqlite3 app.db "DROP TABLE users;"'
psh 'sqlcmd -i .\db\drop.sql' "$P"
expect_block "AC-P7 -i with a backslash path reads the file under the hook cwd" sql
psh 'sqlcmd -i .\db\drop.sql' "$(mk_tmp)"
expect_pass "AC-P7 the same -i path in a cwd without that file is not read"

echo "P1 AC-P8 tokenizer: quotes, escapes, here-strings, separators, comments, blocks, redirections"
# separators: a hit after each form, and before it
blk git-push-force <<'EOF'
cd x; git push -f
cd x;git push -f
git status && git push -f
git status&&git push -f
Write-Host a || git push -f
Write-Host a||git push -f
Get-Date | git push -f
git status | git push -f
git push -f; Write-Host done
git push -f && Write-Host done
git push -f || Write-Host failed
git push -f | Out-Null
Write-Host "a;b" ; git push -f
Write-Host 'a;b'; git push -f
Write-Host a ;  git push -f
EOF
psh "echo start${NLC}git push -f"; expect_block "AC-P8 a newline starts a new command" git-push-force
psh "$(printf 'echo start\r\ngit push -f')"; expect_block "AC-P8 CR LF starts a new command" git-push-force
psh "echo start${NLC}${NLC}${NLC}git push -f origin main${NLC}echo end"; expect_block "AC-P8 blank lines between commands" git-push-force
psh "git status;${NLC}git push -f"; expect_block "AC-P8 separator then newline" git-push-force
# quotes
pas <<'EOF'
Write-Host 'git push -f'
Write-Host "git push -f"
git commit -m 'it''s; git push -f'
git commit -m 'a''b''c; git push -f'
Write-Host "a `" ; git push -f"
Write-Host "say `"hi`"; git push -f now"
Write-Host "tick `` ; git push -f"
Write-Host "a`; git push -f"
Write-Host a`;git push -f
Write-Host a`&git push -f
Write-Host a`|git push -f
Write-Host "x $(Get-Date) ; git push -f"
EOF
blk git-push-force <<'EOF'
echo 'a''b'; git push -f
echo 'it''s'; git push -f
echo "a `" b"; git push -f
echo "a `" b" ; git push -f
echo "tick `` x"; git push -f
echo "a" 'b'; git push -f
echo 'git push -f'; git push -f
echo "$x"; git push -f
echo "${x}"; git push -f
echo "$(Get-Date)"; git push -f
echo "a $(Get-Date -Format "yyyy") b"; git push -f
git pus`h -f origin main
git pu`sh --force
g`it push -f
git push `-f
git push -`f origin main
EOF
# backtick escapes outside quotes, and backtick-newline continuation
psh "git push \`${NLC} -f origin main"; expect_block "AC-P8 backtick-newline continues the line (-f is an argument of git push)" git-push-force
psh "git push \`${NLC}origin main"; expect_pass "AC-P8 backtick-newline continuation without a force flag"
psh "git push \`${NLC} --force \`${NLC} origin main"; expect_block "AC-P8 two continuations" git-push-force
psh "Remove-Item -Recurse \`${NLC}  C:\\Users\\me\\docs"; expect_block "AC-P8 continuation between -Recurse and the target" rm-outside
psh "git status \`${NLC}${NLC}git push -f"; expect_block "AC-P8 a continuation followed by a blank line ends the command" git-push-force
psh 'Remove-Item -Recurse -Force C:\my` docs\x'; expect_block "AC-P8 escaped space keeps one word; the target is outside" rm-outside
psh 'Remove-Item -Recurse -Force .\my` dir\x'; expect_pass "AC-P8 escaped space in a path inside the project"
# here-strings
HP="$(printf '%s\n' '$x = @'"'" 'git push -f' "'"'@')"
HB="$(printf '%s\n' '$x = @"' 'git push -f' 'Remove-Item -Recurse C:\other' '"@')"
psh "$HP"; expect_pass "AC-P8 a git push -f inside @'...'@ is text, not a command"
psh "$HB"; expect_pass "AC-P8 commands inside @\"...\"@ are text, not commands"
HP2="$(printf '%s\n' '$x = @'"'" 'it is "quoted" and has '"'"'quotes'"'" 'git push -f' "'"'@' 'git push -f')"
psh "$HP2"; expect_block "AC-P8 a command after a multi-line single-quoted here-string is seen" git-push-force
HB2="$(printf '%s\n' '$x = @"' 'a "quoted" word' '"@; git push -f')"
psh "$HB2"; expect_block "AC-P8 tokens may follow the closing \"@ on its line (like '@ | Out-File): a git push -f after \"@; is a command" git-push-force
HP3="$(printf '%s\n' '$x = @"' 'line one' '"@' 'git push -f')"
psh "$HP3"; expect_block "AC-P8 a command after a double-quoted here-string is seen" git-push-force
HE="$(printf '%s\n' 'Write-Host @'"'" "it's" "'"'@' 'Remove-Item -Recurse -Force C:\Users\me\docs')"
psh "$HE"; expect_block "AC-P8 here-string as an argument, then a delete outside" rm-outside
HE2="$(printf '%s\n' 'Remove-Item -Recurse -Force @'"'" 'C:\Users\me\docs' "'"'@')"
psh "$HE2"; expect_block "AC-P8 a here-string as the Remove-Item target is one word: its text C:\\Users\\me\\docs is outside the project" rm-outside
HS="$(printf '%s\n' '@'"'" 'DROP TABLE t' "'"'@ | Out-File notes.txt')"
psh "$HS" "$P"; expect_pass "AC-P8 a here-string piped to Out-File is not SQL"
# comments
pas <<'EOF'
# git push -f
git status # git push -f
Write-Host ok # Remove-Item -Recurse C:\Users\me\docs
<# git push -f #> git status
<# Remove-Item -Recurse C:\Users\me\docs #>
git status <# git push -f #>
EOF
psh "<# a note${NLC}git push -f${NLC}#> git status"; expect_pass "AC-P8 a multi-line block comment hides its lines"
psh "<# a note${NLC}git push -f${NLC}#>${NLC}git push -f"; expect_block "AC-P8 a command after a multi-line block comment is seen" git-push-force
psh "# note${NLC}git push -f"; expect_block "AC-P8 a # comment ends at the newline" git-push-force
psh "git status # git push -f${NLC}git push -f"; expect_block "AC-P8 a trailing # comment ends at the newline" git-push-force
psh '<# c #> git push -f'; expect_block "AC-P8 a command right after a block comment" git-push-force
psh 'git push -f # because'; expect_block "AC-P8 the command before a trailing comment is seen" git-push-force
psh 'Write-Host "#"; git push -f'; expect_block "AC-P8 # inside double quotes is not a comment" git-push-force
psh "Write-Host '#x'; git push -f"; expect_block "AC-P8 # inside single quotes is not a comment" git-push-force
psh 'Write-Host "<#"; git push -f'; expect_block "AC-P8 <# inside quotes does not start a block comment" git-push-force
psh 'git status; <# keep #> Remove-Item -Recurse C:\Users\me\docs'; expect_block "AC-P8 a delete after a block comment" rm-outside
# blocks and parentheses do not hide a command
blk rm-outside <<'EOF'
if (Test-Path x) { Remove-Item -Recurse -Force C:\other }
if (Test-Path x) { Remove-Item -Recurse -Force C:\other } else { Write-Host no }
if ($x) { Write-Host a } else { Remove-Item -Recurse -Force C:\other }
foreach ($d in 1..3) { Remove-Item -Recurse -Force C:\other\$d }
Get-ChildItem | ForEach-Object { Remove-Item $_ -Recurse }
try { Remove-Item -Recurse -Force C:\other } catch { Write-Host failed }
& { Remove-Item -Recurse -Force C:\other }
(Remove-Item -Recurse -Force C:\other)
$(Remove-Item -Recurse -Force C:\other)
if ($x){Remove-Item -Recurse -Force C:\other}
function clean { Remove-Item -Recurse -Force C:\other }
EOF
blk git-push-force <<'EOF'
if (Test-Path x) { git push -f }
foreach ($b in 'a','b') { git push --force origin $b }
try { git push -f } catch { Write-Host failed }
if ($x){git push -f}
if ((Test-Path x)) { git push -f }
(git push -f)
EOF
pas <<'EOF'
if (Test-Path .\build) { Remove-Item -Recurse -Force .\build }
if (Test-Path x) { git status } else { Write-Host none }
foreach ($d in 1..3) { Write-Host $d }
if ($x) { Write-Host "{ git push -f }" }
Get-ChildItem | ForEach-Object { Write-Host $_.Name }
EOF
# redirections do not become arguments
pas <<'EOF'
git status > out.txt
git status >> C:\other\log.txt
git status 2>&1
Remove-Item -Recurse .\build > C:\other\log.txt
Remove-Item -Recurse .\build >> C:\other\log.txt
Remove-Item -Recurse .\build 2> C:\other\err.txt
Remove-Item -Recurse .\build *> C:\other\all.txt
Remove-Item -Recurse .\build 2>&1
Remove-Item -Recurse .\build 2>&1 | Out-Null
Remove-Item -Recurse .\build 2>$null
Remove-Item -Recurse .\build *>$null
Remove-Item -Recurse .\build 6>&1
Remove-Item -Recurse > C:\other\log.txt .\build
Remove-Item -Recurse -Force .\build > $null
EOF
blk rm-outside <<'EOF'
Remove-Item -Recurse C:\Users\me\docs 2>&1
Remove-Item -Recurse C:\Users\me\docs > out.txt
Remove-Item -Recurse C:\Users\me\docs 2>$null
Remove-Item -Recurse C:\Users\me\docs *> all.txt
Remove-Item -Recurse -Force C:\Users\me\docs >> log.txt
EOF
blk git-push-force <<'EOF'
git push -f 2>&1
git push -f *> all.txt
git push -f >> log.txt 2>&1
EOF

echo "P1 AC-P9 wrappers are not followed (documented Limits); D1 fail-open"
pas <<'EOF'
iex "git status"
iex 'git push --force origin main'
Invoke-Expression "git status"
Invoke-Expression 'Remove-Item -Recurse -Force C:\Users\me\docs'
powershell -Command "git push -f"
powershell -c "git status"
pwsh -c 'Remove-Item -Recurse C:\Users\me\docs'
pwsh -Command "git push --force origin main"
powershell -EncodedCommand ZwBpAHQAIABwAHUAcwBoACAALQBmAA==
pwsh -EncodedCommand ZwBpAHQA
cmd /c rmdir /s /q C:\Users\me\docs
cmd /c "git push -f"
Start-Process git -ArgumentList 'push','-f'
Start-Process -FilePath git -ArgumentList "push --force"
EOF
psh 'Write-Host "abc; git push -f'; nocrash "AC-P9 unterminated double quote"
psh "Write-Host 'abc; git push -f"; nocrash "AC-P9 unterminated single quote"
psh "\$x = @'${NLC}git push -f"; nocrash "AC-P9 unterminated single-quoted here-string"
psh "\$x = @\"${NLC}git push -f"; nocrash "AC-P9 unterminated double-quoted here-string"
psh '<# git push -f'; nocrash "AC-P9 unterminated block comment"
psh 'git push -f `'; nocrash "AC-P9 trailing backtick"
psh 'Remove-Item -Recurse "C:\Users\me\docs'; nocrash "AC-P9 unterminated quote around a delete target"
psh ''; expect_pass "AC-P9 empty command"
psh '   '; expect_pass "AC-P9 blank command"
psh '# only a comment'; expect_pass "AC-P9 comment-only command"
psh ';;;'; nocrash "AC-P9 only separators"
psh '|'; nocrash "AC-P9 a lone pipe"
psh '&& ||'; nocrash "AC-P9 lone && and ||"
psh '{ { ( ('; nocrash "AC-P9 unbalanced braces and parens"
grun PB_HEADLESS=1 -- '{"session_id":"s1","cwd":"C:\\work\\app","hook_event_name":"PreToolUse","tool_name":"PowerShell","tool_input":{"command":"git push --force'
expect_pass "AC-P9 truncated JSON is PASS (fail-open)"
grun PB_HEADLESS=1 -- '{"session_id":"s1","cwd":"C:\\work\\app","hook_event_name":"PreToolUse","tool_name":"PowerShell","tool_input":{"description":"x"},"tool_use_id":"t"}'
expect_pass "AC-P9 a PowerShell call without a command field is PASS"
grun PB_HEADLESS=1 -- '{"tool_name":"PowerShell","tool_input":{"command":"git push -f"}}'
expect_block "AC-P9 a call without cwd and session: headless git push -f still blocks, no crash" git-push-force
if ! has "$GERR" 'syntax error' && ! has "$GERR" 'unbound variable' && ! has "$GERR" 'bad substitution' && ! has "$GERR" ': line ' &&
  ! has "$GERR" 'command not found'; then t_ok "AC-P9 no cwd and no session: no shell error text"; else t_bad "AC-P9 no cwd and no session: no shell error text" "$OUT"; fi
grun PB_HEADLESS=1 -- 'tool_name PowerShell; git push --force origin main'
expect_pass "AC-P9 non-JSON text is PASS"


# ---- review round 1 fixes (05-review.md findings 1, 2, 3, 5, 6, 7): same text, fail closed ----
# Characters as bytes (the suite stays ASCII): U+2013 en dash, U+2014 em dash, U+2015 horizontal bar; the curly quotes
# U+2018 U+2019 U+201A U+201B (single) and U+201C U+201D U+201E (double). PowerShell treats all of them as dashes / quote marks.
ED=$'\xe2\x80\x93' EM=$'\xe2\x80\x94' HB=$'\xe2\x80\x95'
LS=$'\xe2\x80\x98' RS=$'\xe2\x80\x99' SL=$'\xe2\x80\x9a' SH=$'\xe2\x80\x9b'
LQ=$'\xe2\x80\x9c' RQ=$'\xe2\x80\x9d' DL=$'\xe2\x80\x9e'
CR=$'\r'

echo "P1 review F1 Unicode dashes (U+2013, U+2014, U+2015) start a parameter word like -"
blk rm-outside <<EOF
Remove-Item ${ED}Recurse ${ED}Force C:\Users\me\docs
Remove-Item ${EM}Recurse ${EM}Force C:\Users\me\docs
Remove-Item ${HB}Recurse ${HB}Force C:\Users\me\docs
Remove-Item ${ED}Recurse C:\Users\me\docs
Remove-Item ${EM}Recurse C:\Users\me\docs
Remove-Item ${HB}Recurse C:\Users\me\docs
Remove-Item ${ED}r C:\Users\me\docs
Remove-Item -Recurse ${ED}Path C:\Users\me\docs
Remove-Item -Recurse ${EM}LiteralPath C:\Users\me\docs
Remove-Item -Recurse ${ED}Path:C:\Users\me\docs
rm ${ED}r ${ED}fo C:\Users\me\docs
Remove-Item ${ED}Recurse ${ED}Force ..\other
EOF
blk git-push-force <<EOF
git push ${EM}force origin main
git push ${ED}force origin main
git push ${HB}force origin main
git push origin main ${EM}force-with-lease
EOF
# controls: a dash character inside a word (a path in the project) is not a parameter; a non-recursive delete stays a PASS
pas <<EOF
Remove-Item -Recurse -Force .\dist${ED}old
Remove-Item -Recurse -Force C:\work\app\a${ED}b
Remove-Item -Recurse -Force .\my${EM}dir\x
Remove-Item -Recurse -Force .\my${HB}dir
Remove-Item ${ED}Force C:\Users\me\docs
Remove-Item ${ED}Recurse -Force .\dist
Write-Host ${ED}Recurse
EOF

echo "P1 review F2 curly quotes (U+2018 U+2019 U+201A U+201B, U+201C U+201D U+201E) are quote characters"
blk rm-outside <<EOF
Remove-Item -Recurse -Force ${LQ}C:\Users\me\docs${RQ}
Remove-Item -Recurse -Force ${LS}C:\Users\me\docs${RS}
Remove-Item -Recurse -Force ${SL}C:\Users\me\docs${SH}
Remove-Item -Recurse -Force ${DL}C:\Users\me\docs${LQ}
Remove-Item -Recurse -Force ${LQ}C:\Users\me\my docs${RQ}
Remove-Item -Recurse -Force ${LS}C:\Users\me\my docs${RS}
Remove-Item -Recurse -Force ${LQ}..\other${RQ}
Remove-Item -Recurse -Force ${LS}..\other${RS}
Remove-Item -Recurse -Path ${LQ}C:\Users\me\docs${RQ}
Remove-Item -Recurse -Path:${LQ}C:\Users\me\docs${RQ}
Remove-Item -Recurse -LiteralPath ${LS}C:\Users\me\docs${RS}
EOF
blk git-push-force <<EOF
git push ${LQ}--force${RQ} origin main
git push ${LS}-f${RS} origin main
git push ${DL}--force${RQ} origin main
git push origin ${LQ}+main${RQ}
EOF
blk sql <<EOF
sqlite3 app.db ${LQ}DROP TABLE t${RQ}
psql -c ${LS}TRUNCATE t${RS}
${LQ}DROP TABLE t${RQ} | sqlite3 app.db
EOF
# controls: a quoted path in the project passes; text inside curly quotes is one string (a ; in it separates nothing)
pas <<EOF
Remove-Item -Recurse -Force ${LQ}.\dist${RQ}
Remove-Item -Recurse -Force ${LS}.\dist${RS}
Remove-Item -Recurse -Force ${LQ}.\my dist${RQ}
Remove-Item -Recurse -Force ${LQ}C:\work\app\dist${RQ}
Write-Host ${LQ}a; git push -f${RQ}
Write-Host ${LS}a; Remove-Item -Recurse C:\Users\me${RS}
EOF

echo "P1 review F3 a same-command assignment to a variable the guard resolves makes it unresolved (fail closed)"
PSE=(TEMP=/tmp/pbfix2tempA TMP=/tmp/pbfix2tempB TMPDIR=/tmp/pbfix2tempC)   # temp dirs the guard knows without cygpath; never created
blk rm-outside <<'EOF'
$env:TEMP = "C:\Users\me"; Remove-Item -Recurse -Force $env:TEMP
$Env:Temp="C:\Users\me"; Remove-Item -Recurse -Force $env:TEMP
$env:TEMP='C:\Users'; Remove-Item -Recurse -Force "$env:TEMP\me"
Set-Item env:TEMP C:\Users; Remove-Item -Recurse $env:TEMP\me
Set-Item -Path env:TEMP -Value C:\Users; Remove-Item -Recurse $env:TEMP\me
$env:TMP = "C:\Users"; Remove-Item -Recurse -Force "$env:TMP\me"
$env:TMPDIR = "C:\Users"; Remove-Item -Recurse -Force "$env:TMPDIR\me"
Write-Host x; $env:TEMP = "C:\Users\me"; Remove-Item -Recurse -Force $env:TEMP
EOF
# the same, assignment and delete on separate lines
psh "\$env:TEMP = \"C:\\Users\\me\"${NLC}Remove-Item -Recurse -Force \$env:TEMP"; expect_block "F3 assignment on its own line, delete on the next" rm-outside
psh "\$env:TEMP = \"C:\\Users\\me\"${CR}${NLC}Remove-Item -Recurse -Force \$env:TEMP"; expect_block "F3 CRLF between the assignment and the delete" rm-outside
# controls: without the assignment the temp delete passes; an assignment to another variable changes nothing
pas <<'EOF'
Remove-Item -Recurse -Force $env:TEMP\pbx
Remove-Item -Recurse -Force "$env:TMP\pbx"
$x = 1; Remove-Item -Recurse -Force $env:TEMP\pbx
$env:FOO = "C:\Users"; Remove-Item -Recurse -Force "$env:TEMP\pbx"
Set-Item env:FOO C:\Users; Remove-Item -Recurse -Force $env:TEMP\pbx
Set-Variable x C:\; Remove-Item -Recurse -Force $env:TEMP\pbx
EOF
PSE=(CLAUDE_PROJECT_DIR='C:\work\app')
blk rm-outside 'C:\other' <<'EOF'
$env:CLAUDE_PROJECT_DIR = "C:\"; Remove-Item -Recurse -Force "$env:CLAUDE_PROJECT_DIR\Users"
$Env:CLAUDE_PROJECT_DIR="C:\"; Remove-Item -Recurse -Force $env:CLAUDE_PROJECT_DIR\Users
Set-Item env:CLAUDE_PROJECT_DIR C:\; Remove-Item -Recurse -Force $env:CLAUDE_PROJECT_DIR\Users
EOF
pas 'C:\other' <<'EOF'
Remove-Item -Recurse -Force "$env:CLAUDE_PROJECT_DIR\build"
$x = "C:\"; Remove-Item -Recurse -Force "$env:CLAUDE_PROJECT_DIR\build"
EOF
PSE=()
# HOME, USERPROFILE and the home-like names: the project is inside the fixture home (cwd /pbguard-home/proj), so $HOME\proj\build
# passes unless an assignment in the same command changed what $HOME means
blk rm-outside /pbguard-home/proj <<'EOF'
$HOME = "C:\"; Remove-Item -Recurse -Force $HOME\proj\build
$Home="C:\"; Remove-Item -Recurse -Force "$HOME\proj\build"
Set-Variable HOME C:\; Remove-Item -Recurse -Force $HOME\proj\build
Set-Variable -Name HOME -Value C:\; Remove-Item -Recurse -Force $HOME\proj\build
$env:USERPROFILE = "C:\Windows"; Remove-Item -Recurse -Force $env:USERPROFILE\proj\build
$env:HOME = "C:\Windows"; Remove-Item -Recurse -Force "$env:HOME\proj\build"
Set-Item env:USERPROFILE C:\Windows; Remove-Item -Recurse -Force $env:USERPROFILE\proj\build
EOF
pas /pbguard-home/proj <<'EOF'
Remove-Item -Recurse -Force $HOME\proj\build
$x = "C:\"; Remove-Item -Recurse -Force $HOME\proj\build
$env:FOO = "C:\"; Remove-Item -Recurse -Force $env:USERPROFILE\proj\build
EOF

echo "P1 review F5 a pipe continued on the next line keeps the pipeline (SQL client on the next line)"
psh "\"DROP TABLE t\" |${NLC}sqlite3 app.db"; expect_block "F5 \"DROP TABLE t\" |<newline>sqlite3 app.db" sql
psh "'DROP TABLE t' |${NLC}${NLC}psql"; expect_block "F5 'DROP TABLE t' |<newline><newline>psql" sql
psh "\"DROP TABLE t\" |${NLC}  psql -d x"; expect_block "F5 the next line is indented" sql
psh "echo 'DROP TABLE t' |${NLC}psql"; expect_block "F5 echo 'DROP TABLE t' |<newline>psql" sql
psh "\"DROP TABLE t\" |  ${NLC}sqlite3 app.db"; expect_block "F5 spaces after the pipe, then the newline" sql
psh "\"DROP TABLE t\" |${CR}${NLC}sqlite3 app.db"; expect_block "F5 CRLF after the pipe" sql
psh "\"DROP TABLE t\" |${NLC}Out-File notes.txt"; expect_pass "F5 control: the pipe continues into Out-File (no SQL client)"
psh "\"DROP TABLE t\"${NLC}sqlite3 app.db"; expect_pass "F5 control: no pipe, so the next line is a separate command with no SQL"

echo "P1 review F6 dot-sourcing . CMD is a call like & CMD"
blk rm-outside <<'EOF'
. Remove-Item -Recurse -Force C:\Users\me\docs
.  rm -r C:\Users\me\docs
cd x; . Remove-Item -Recurse C:\Users\me\docs
if ($true) { . Remove-Item -Recurse -Force C:\Users\me\docs }
EOF
blk git-push-force <<'EOF'
. git push -f
. git push --force origin main
EOF
pas <<'EOF'
. Remove-Item -Recurse -Force .\dist
. .\env.ps1
. git status
EOF

echo "P1 review F7 drive-relative and provider-qualified delete targets fail closed"
blk rm-outside <<'EOF'
Remove-Item -Recurse -Force C:..\other
Remove-Item -Recurse -Force "C:..\other"
Remove-Item -Recurse -Path C:..\other
Remove-Item -Recurse -Force FileSystem::C:\Users\me
Remove-Item -Recurse -Force Microsoft.PowerShell.Core\FileSystem::C:\x
Remove-Item -Recurse -Force "FileSystem::C:\Users\me"
Remove-Item -Recurse -Force -Path FileSystem::C:\Users\me
Remove-Item -Recurse -Force FileSystem::C:\work\app\dist
Remove-Item -Recurse -Force Registry::HKEY_CURRENT_USER\Software\x
EOF
pas <<'EOF'
Remove-Item FileSystem::C:\Users\me
Write-Host FileSystem::C:\Users\me
Get-ChildItem -Recurse FileSystem::C:\Users\me
EOF

# ---- review round 2 fixes (blocker 1, majors 2-5, minors 6-7): same text, fail closed ----
# Hook text arrives JSON-decoded; a form feed travels as the JSON escape \f (the guard decodes it). A vertical tab has no short
# JSON escape (real clients send \u000b, which the guard documents as not decoded), so VT is sent as the raw byte here: [UNVERIFIED]
# whether a real client's \u000b form would reach the guard decoded; the row pins the decoded byte only.
WNB=$'\xc2\xa0' WEN=$'\xe2\x80\x82' WEM=$'\xe2\x80\x83' WTH=$'\xe2\x80\x89' WIS=$'\xe3\x80\x80'
FFC=$'\f' VTC=$'\v'
# psj CMD [CWD]: like psh, but a raw form feed byte is sent as the JSON escape \f
psj() { local j; j="$(jps "$1" "${2:-$W}")"; j="${j//$FFC/\\f}"; grun PB_HEADLESS="$PSM" "${PSE[@]}" -- "$j"; }
# expect_block_any NAME: BLOCK (exit 2, no stdout) of any kind; used where the spec leaves the kind open
expect_block_any() { if [ "$RC" = 2 ] && [ -z "$GOUT" ]; then t_ok "$1 (BLOCK any kind)"; else t_bad "$1 (BLOCK any kind)" "rc=$RC $OUT"; fi; }

echo "P1 review2 R1 [blocker] an assignment prefix does not hide the command that runs on its right"
blk rm-outside <<'EOF'
$null = Remove-Item -Recurse -Force C:\Users\me
$x += Remove-Item -Recurse C:\Users\me
$x -= Remove-Item -Recurse C:\Users\me
[void](Remove-Item -Recurse C:\Users\me)
$a, $b = Remove-Item -Recurse C:\Users\me
[string]$o = Remove-Item -Recurse -Force C:\Users\me
$x = (Remove-Item -Recurse C:\Users\me)
$x = $(Remove-Item -Recurse C:\Users\me)
$r = Remove-Item -Recurse -Force ..\other
$r = rm -r C:\Users\me
EOF
blk git-push-force <<'EOF'
$r = git push -f origin main
$r = git push --force origin main
$a, $b = git push --force
[string]$o = git push -f
$x += git push -f
[void](git push -f)
$x = (git push --force-with-lease)
$null = git push origin +main
EOF
blk sql <<'EOF'
$r = "DROP TABLE t" | sqlite3 app.db
$null = 'DROP TABLE t' | psql
$r = sqlite3 app.db "DROP TABLE t"
EOF
# controls: an assignment alone, or one whose right side is harmless, stays a PASS
pas <<'EOF'
$x = 'C:\Users\me'
$n = git status
$r = Remove-Item -Recurse -Force .\dist
$null = Remove-Item .\a.txt
[void](Get-ChildItem -Recurse)
$r = "DROP TABLE t" | Out-String
EOF

echo "P1 review2 R2 built-in location functions cd.. cd\ and drive switches move the working location"
blk rm-outside <<'EOF'
cd..; cd..; Remove-Item -Recurse -Force .\other
cd..; Remove-Item -Recurse -Force .\other
cd\; Remove-Item -Recurse -Force .\Users\me
cd \; Remove-Item -Recurse -Force .\Users\me
D:; Remove-Item -Recurse -Force .\x
d:; Remove-Item -Recurse -Force .\x
C:; Remove-Item -Recurse -Force .\x
E:; rm -r .\x
Write-Host go; D:; Remove-Item -Recurse -Force .\x
EOF
psh "cd..${NLC}Remove-Item -Recurse -Force .\\other"; expect_block "R2 cd.. on its own line, delete on the next" rm-outside
psh 'cd..; git push -f'; expect_block "R2 cd.. then a force push still blocks" git-push-force
pas <<'EOF'
cd .\sub; Remove-Item -Recurse -Force .\x
cd .\sub; cd..; Remove-Item -Recurse -Force .\x
Set-Location .\sub; Remove-Item -Recurse -Force .\x
Write-Host "cd..; Remove-Item -Recurse .\other"
EOF

echo "P1 review2 R3 Unicode and control whitespace separates words like a space"
set -- NBSP:"$WNB" EN-SPACE:"$WEN" EM-SPACE:"$WEM" THIN-SPACE:"$WTH" IDEOGRAPHIC-SPACE:"$WIS" VT:"$VTC"
for wsp in "$@"; do
  wn="${wsp%%:*}"; wc="${wsp#*:}"
  psh "Remove-Item${wc}-Recurse${wc}C:\\Users\\me"; expect_block "R3 [$wn] Remove-Item<ws>-Recurse<ws>C:\\Users\\me" rm-outside
  psh "Remove-Item -Recurse${wc}-Force${wc}..\\other"; expect_block "R3 [$wn] between -Recurse, -Force and a relative outside target" rm-outside
  psh "git${wc}push -f"; expect_block "R3 [$wn] git<ws>push -f" git-push-force
  psh "git push${wc}-f origin main"; expect_block "R3 [$wn] git push<ws>-f" git-push-force
  psh "git push --force${wc}origin main"; expect_block "R3 [$wn] git push --force<ws>origin" git-push-force
  psh "sqlite3${wc}app.db \"DROP TABLE t\""; expect_block "R3 [$wn] sqlite3<ws>app.db DROP TABLE" sql
  psh "Remove-Item -Recurse -Force .\\dist${wc}; git status"; expect_pass "R3 [$wn] control: inside delete, then harmless"
done
psj "Remove-Item${FFC}-Recurse${FFC}C:\\Users\\me"; expect_block "R3 [FORM-FEED \\f] Remove-Item<ff>-Recurse<ff>C:\\Users\\me" rm-outside
psj "git${FFC}push -f"; expect_block "R3 [FORM-FEED \\f] git<ff>push -f" git-push-force
psj "git push${FFC}--force"; expect_block "R3 [FORM-FEED \\f] git push<ff>--force" git-push-force
psj "Remove-Item -Recurse${FFC}-Force${FFC}..\\other"; expect_block "R3 [FORM-FEED \\f] relative outside target" rm-outside
psj "Remove-Item -Recurse -Force .\\dist${FFC}"; expect_pass "R3 [FORM-FEED \\f] control: inside delete"
# controls: a no-break or ideographic space inside a quoted in-project path is part of the name (the path stays inside)
pas <<EOF
Remove-Item -Recurse -Force ".\my${WNB}dir"
Remove-Item -Recurse -Force '.\my${WNB}dir'
Remove-Item -Recurse -Force ".\my${WIS}dir\x"
Remove-Item -Recurse -Force "C:\work\app\my${WNB}dir"
Remove-Item${WNB}-Recurse${WNB}.\dist
git${WNB}status
Write-Host "a${WNB}git push -f"
Write-Host 'a${WIS}Remove-Item -Recurse C:\Users\me'
EOF

echo "P1 review2 R4 \$(...) inside an expandable here-string runs; in a literal here-string it is text"
psh "Remove-Item -Recurse -Force @\"${NLC}\$(git push -f)${NLC}\"@"; expect_block "R4 expandable here-string as a delete target with \$(git push -f)" git-push-force
psh "Write-Output @\"${NLC}\$(git push -f)${NLC}\"@"; expect_block "R4 Write-Output @\"..\"@ with \$(git push -f)" git-push-force
psh "Write-Output @\"${NLC}text \$(git push --force origin main) more${NLC}\"@"; expect_block "R4 \$(git push --force) in the middle of a line of the here-string" git-push-force
psh "Write-Host @\"${NLC}\$(Remove-Item -Recurse C:\\Users\\me)${NLC}\"@"; expect_block "R4 Write-Host @\"..\"@ with \$(Remove-Item -Recurse C:\\Users\\me)" rm-outside
psh "Remove-Item -Recurse -Force @\"${NLC}\$(Remove-Item -Recurse C:\\Users\\me)${NLC}\"@"; expect_block "R4 delete target here-string holding \$(Remove-Item -Recurse C:\\Users\\me)" rm-outside
psh "\$s = @\"${NLC}\$(git push -f)${NLC}\"@"; expect_block "R4 assigned here-string with \$(git push -f)" git-push-force
psh "Write-Output @\"${NLC}\$(\"DROP TABLE t\" | sqlite3 app.db)${NLC}\"@"; expect_block "R4 \$(\"DROP TABLE t\" | sqlite3 app.db) in a here-string" sql
# literal here-string: no subexpression runs, so the text passes; as a delete target it is still a non-path word (BLOCK as before)
psh "Write-Output @'${NLC}\$(git push -f)${NLC}'@"; expect_pass "R4 control: literal @'..'@ holding \$(git push -f) is text"
psh "Write-Output @'${NLC}\$(Remove-Item -Recurse C:\\Users\\me)${NLC}'@"; expect_pass "R4 control: literal @'..'@ holding a \$(Remove-Item) is text"
psh "Write-Output @\"${NLC}git push -f${NLC}\"@"; expect_pass "R4 control: expandable here-string with plain text git push -f and no \$( ) is text"
psh "Remove-Item -Recurse -Force @'${NLC}C:\\Users\\me${NLC}'@"; expect_block "R4 literal here-string as a delete target outside (as before)" rm-outside

echo "P1 review2 R5 more assignment forms make a resolved variable unresolved (fail closed)"
PSE=(TEMP=/tmp/pbfix3tempA TMP=/tmp/pbfix3tempB TMPDIR=/tmp/pbfix3tempC)   # temp dirs the guard knows without cygpath; never created
blk rm-outside <<'EOF'
$env:TEMP, $b = 'C:\Users\me', 1; Remove-Item -Recurse -Force $env:TEMP
$env:TEMP,$b = 'C:\Users\me', 1; Remove-Item -Recurse -Force $env:TEMP
$b, $env:TEMP = 1, 'C:\Users\me'; Remove-Item -Recurse -Force $env:TEMP
[string]$env:TEMP = 'C:\Users\me'; Remove-Item -Recurse -Force $env:TEMP
Set-Item Env:/TEMP C:\Users; Remove-Item -Recurse $env:TEMP\me
Set-Item Env:TEMP C:\Users; Remove-Item -Recurse $env:TEMP\me
set-item ENV:temp C:\Users; Remove-Item -Recurse $env:TEMP\me
Set-Item -Path Env:\TEMP -Value C:\Users; Remove-Item -Recurse $env:TEMP\me
Set-Item -Path Env:/TMP -Value C:\Users; Remove-Item -Recurse $env:TMP\me
si Env:TEMP C:\Users; Remove-Item -Recurse $env:TEMP\me
Rename-Item env:FOO TEMP; Remove-Item -Recurse $env:TEMP
Rename-Item -Path Env:FOO -NewName TEMP; Remove-Item -Recurse $env:TEMP
rni env:FOO TMP; Remove-Item -Recurse $env:TMP
New-Item -Path Env:\TEMP -Value C:\Users -Force; Remove-Item -Recurse $env:TEMP\me
New-Item Env:TEMP -Value C:\Users -Force; Remove-Item -Recurse $env:TEMP\me
ni -Path Env:\TMPDIR -Value C:\Users -Force; Remove-Item -Recurse $env:TMPDIR\me
[Environment]::SetEnvironmentVariable('TEMP','C:\Users'); Remove-Item -Recurse $env:TEMP
[System.Environment]::SetEnvironmentVariable("TEMP", "C:\Users"); Remove-Item -Recurse $env:TEMP\me
[Environment]::SetEnvironmentVariable('TMP','C:\Users',[EnvironmentVariableTarget]::Process); Remove-Item -Recurse $env:TMP\me
EOF
pas <<'EOF'
Set-Item Env:FOO C:\Users; Remove-Item -Recurse -Force $env:TEMP\pbx
Rename-Item env:FOO BAR; Remove-Item -Recurse -Force $env:TEMP\pbx
New-Item -Path Env:\FOO -Value C:\Users -Force; Remove-Item -Recurse -Force $env:TEMP\pbx
[Environment]::SetEnvironmentVariable('FOO','C:\Users'); Remove-Item -Recurse -Force $env:TEMP\pbx
$env:FOO, $b = 'C:\Users', 1; Remove-Item -Recurse -Force $env:TEMP\pbx
Rename-Item .\a.txt TEMP.txt; Remove-Item -Recurse -Force $env:TEMP\pbx
EOF
PSE=()
blk rm-outside /pbguard-home/proj <<'EOF'
Set-Item Env:USERPROFILE C:\Windows; Remove-Item -Recurse -Force $env:USERPROFILE\proj\build
Rename-Item env:FOO HOME; Remove-Item -Recurse -Force $env:HOME\proj\build
[Environment]::SetEnvironmentVariable('USERPROFILE','C:\Windows'); Remove-Item -Recurse -Force $env:USERPROFILE\proj\build
$HOME, $b = 'C:\', 1; Remove-Item -Recurse -Force $HOME\proj\build
EOF

echo "P1 review2 R6 a call operator whose command is a group or a variable is an unknown command"
blk rm-outside <<'EOF'
& (Get-Command Remove-Item) -Recurse C:\Users\me
& (gcm Remove-Item) -Recurse -Force C:\Users\me
& $cmd -Recurse C:\x
& $cmd C:\x -Recurse
& ${cmd} -Recurse C:\x
EOF
blk git-push-force <<'EOF'
. (gcm git) push -f
& (Get-Command git) push --force origin main
& $g push -f
& $g push --force-with-lease
EOF
psh '& $cmd -Recurse .\dist'; expect_block_any "R6 & \$cmd -Recurse with an inside target (command unknown) [kind open, UNVERIFIED]"
psh '& (Get-Command Remove-Item) -Recurse .\dist'; expect_block_any "R6 & (Get-Command Remove-Item) -Recurse inside target [kind open, UNVERIFIED]"
pas <<'EOF'
& (Get-Command foo) -Name x
& (Get-Command foo)
& $cmd status
. (gcm git) status
& .\tool.ps1 -Recurse
& 'C:\tools\x.exe' -Recurse
EOF

echo "P1 review2 R7 compound assignment to a resolved variable makes it unresolved"
PSE=(TEMP=/tmp/pbfix3tempA TMP=/tmp/pbfix3tempB TMPDIR=/tmp/pbfix3tempC)
blk rm-outside <<'EOF'
$env:TEMP += '\..\..\Users'; Remove-Item -Recurse $env:TEMP
$env:TEMP -= 'x'; Remove-Item -Recurse $env:TEMP
$env:TEMP *= 2; Remove-Item -Recurse $env:TEMP
$env:TEMP /= 2; Remove-Item -Recurse $env:TEMP
$env:TEMP %= 2; Remove-Item -Recurse $env:TEMP
$env:TEMP ??= 'C:\Users'; Remove-Item -Recurse $env:TEMP
$Env:Temp+='\..\..\Users'; Remove-Item -Recurse -Force "$env:TEMP"
$env:TMP += '\..\..\Users'; Remove-Item -Recurse "$env:TMP\x"
$env:TMPDIR += '\..\..\Users'; Remove-Item -Recurse "$env:TMPDIR\x"
EOF
pas <<'EOF'
$env:FOO += '\..'; Remove-Item -Recurse -Force $env:TEMP\pbx
$x += 1; Remove-Item -Recurse -Force $env:TEMP\pbx
$x ??= 1; Remove-Item -Recurse -Force "$env:TEMP\pbx"
EOF
PSE=()
blk rm-outside /pbguard-home/proj <<'EOF'
$HOME += '\..\..'; Remove-Item -Recurse -Force $HOME\proj\build
$env:USERPROFILE += '\..\..'; Remove-Item -Recurse -Force $env:USERPROFILE\proj\build
EOF
PSE=(CLAUDE_PROJECT_DIR='C:\work\app')
blk rm-outside 'C:\other' <<'EOF'
$env:CLAUDE_PROJECT_DIR += '\..'; Remove-Item -Recurse -Force "$env:CLAUDE_PROJECT_DIR\build"
EOF
PSE=()

echo "P1 review2 addendum A: New-Item -Path Env: -Name X names the variable X"
PSE=(TEMP=/tmp/pbfix3tempA TMP=/tmp/pbfix3tempB TMPDIR=/tmp/pbfix3tempC)
blk rm-outside <<'EOF'
New-Item -Path Env: -Name TEMP -Value C:\Users -Force; Remove-Item -Recurse -Force $env:TEMP
New-Item -Path Env: -Name TEMP -Value C:\Users -Force; Remove-Item -Recurse -Force $env:TEMP\me
new-item -path ENV: -name temp -value C:\Users -force; Remove-Item -Recurse $env:TEMP\me
ni -Path env: -Name TMP -Value C:\Users -Force; Remove-Item -Recurse $env:TMP\me
New-Item -Name TMPDIR -Path Env: -Value C:\Users; Remove-Item -Recurse $env:TMPDIR\me
EOF
pas <<'EOF'
New-Item -Path Env: -Name FOO -Value C:\Users -Force; Remove-Item -Recurse -Force $env:TEMP\pbx
ni -Path env: -Name BAR -Value x; Remove-Item -Recurse -Force $env:TEMP\pbx
New-Item -Path .\dist -Name TEMP -ItemType Directory; Remove-Item -Recurse -Force $env:TEMP\pbx
EOF
PSE=()

echo "P1 review2 addendum B: a # comment after | keeps the pipeline across the newline"
psh "\"DROP TABLE t\" |  # c${NLC}sqlite3 app.db"; expect_block "B \"DROP TABLE t\" |  # c<newline>sqlite3 app.db" sql
psh "\"DROP TABLE t\" | # run it${NLC}${NLC}psql"; expect_block "B comment, blank line, then psql" sql
psh "'DROP TABLE t' |# c${CR}${NLC}sqlite3 app.db"; expect_block "B comment then CRLF" sql
psh "git status |  # c${NLC}Out-Null"; expect_pass "B control: git status | # c<newline>Out-Null"
psh "\"DROP TABLE t\" |  # c${NLC}Out-File notes.txt"; expect_pass "B control: comment, then Out-File (no SQL client)"
psh "\"DROP TABLE t\"  # c${NLC}sqlite3 app.db"; expect_pass "B control: no pipe, comment only, next line is a separate command"

# ---- review fix round 3 (tester fix4): lead-ins of an assignment, call operator on a string/group, more Unicode spaces ----
echo "P1 review3 F1 an assignment with a property, index, scope or typed target does not hide its right-hand command"
blk rm-outside <<'EOF'
$x.a = Remove-Item -Recurse -Force C:\Users\me
$x[0] = Remove-Item -Recurse -Force C:\Users\me
$script:r = Remove-Item -Recurse -Force C:\Users\me
$x.a.b = Remove-Item -Recurse -Force C:\Users\me
$h['k'] = Remove-Item -Recurse -Force C:\Users\me
$r -= Remove-Item -Recurse C:\Users\me
[string] $r = Remove-Item -Recurse -Force C:\Users\me
[int[]] $r = Remove-Item -Recurse -Force C:\Users\me
$env:R = Remove-Item -Recurse -Force C:\Users\me
$r=Remove-Item -Recurse -Force C:\Users\me
EOF
blk git-push-force <<'EOF'
$global:r = git push -f origin main
$env:R = git push -f
$r = . git push -f origin main
$r = & git push -f
$h['k'] = git push --force
$x.a.b = git push --force origin main
$x.a = git push -f
$x[0] = git push -f
$r=git push -f
[string] $r = git push -f
EOF
pas <<'EOF'
$x.a = 'C:\Users\me'
$h['k'] = 1
$script:r = git status
$r = . .\build.ps1
$x[0] = 'git push -f'
$x.a = Remove-Item -Recurse -Force .\dist
EOF

echo "P1 review3 F2 a call operator on a group with a switch attached by a colon, or on an expandable string, is an unknown command"
blk rm-outside <<'EOF'
& ($c) -Rec:$true C:\Users\me
& ($c) -Recurse:$true C:\Users\me
& "Remove-$x" -Recurse C:\Users\me
EOF
blk git-push-force <<'EOF'
& "$g" push -f
EOF
# [UNVERIFIED] whether PowerShell treats .$c as a dot-source call of the variable's value; the row pins fail closed (BLOCK any kind)
psh '.$c -Recurse C:\Users\me'; expect_block_any "F2 .\$c -Recurse C:\\Users\\me (fail closed) [kind open, UNVERIFIED]"
pas <<'EOF'
& "Remove-$x" -Name a
EOF

echo "P1 review3 F3 NEL U+0085, U+1680, U+2028 and U+2029 separate words like a space"
WNL=$'\xc2\x85' WOG=$'\xe1\x9a\x80' WLS=$'\xe2\x80\xa8' WPS=$'\xe2\x80\xa9'
set -- NEL-U+0085:"$WNL" OGHAM-U+1680:"$WOG" LINE-SEP-U+2028:"$WLS" PARA-SEP-U+2029:"$WPS"
for ws in "$@"; do
  wn="${ws%%:*}" wc="${ws#*:}"
  psh "Remove-Item${wc}-Recurse${wc}C:\\Users\\me"; expect_block "F3 [$wn] Remove-Item<ws>-Recurse<ws>C:\\Users\\me" rm-outside
  psh "git${wc}push -f"; expect_block "F3 [$wn] git<ws>push -f" git-push-force
  psh "git push${wc}--force origin main"; expect_block "F3 [$wn] git push<ws>--force origin main" git-push-force
  psh "Write-Host \"a${wc}b\"; git status"; expect_pass "F3 [$wn] control: the character inside quotes"
  psh "Write-Host \"git${wc}push -f\""; expect_pass "F3 [$wn] control: git<ws>push -f only inside a quoted string"
  psh "Remove-Item -Recurse -Force \".\\dist${wc}x\""; expect_pass "F3 [$wn] control: quoted inside delete target"
done

t_summary
