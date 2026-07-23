#!/usr/bin/env sh
# SPDX-License-Identifier: 0BSD

set -eu

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
INSTALLER="$ROOT/deployments/native/linux/install.sh"

if [ "$(uname -s)" != Linux ]; then
  printf '%s\n' 'Linux installer contract test skipped outside Linux.'
  exit 0
fi

TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/sonarweaver-linux-test.XXXXXX")
cleanup() { rm -rf "$TEST_ROOT"; }
trap cleanup EXIT HUP INT TERM
mkdir "$TEST_ROOT/bin"

cat >"$TEST_ROOT/bin/java" <<'EOF'
#!/usr/bin/env sh
printf '%s\n' 'openjdk version "21.0.0"' >&2
EOF
cat >"$TEST_ROOT/bin/systemctl" <<'EOF'
#!/usr/bin/env sh
exit 0
EOF
cat >"$TEST_ROOT/bin/unzip" <<'EOF'
#!/usr/bin/env sh
exit 0
EOF
chmod +x "$TEST_ROOT/bin/java" "$TEST_ROOT/bin/systemctl" "$TEST_ROOT/bin/unzip"

if PATH="$TEST_ROOT/bin:$PATH" "$INSTALLER" --dry-run >/dev/null 2>&1; then
  printf '%s\n' 'Native production unexpectedly accepted missing JDBC inputs.' >&2
  exit 1
fi

if PATH="$TEST_ROOT/bin:$PATH" "$INSTALLER" --evaluation --jdbc-url 'jdbc:postgresql://db.example/sonarqube' --dry-run >/dev/null 2>&1; then
  printf '%s\n' 'Evaluation mode unexpectedly accepted JDBC inputs.' >&2
  exit 1
fi

PATH="$TEST_ROOT/bin:$PATH" "$INSTALLER" --evaluation --dry-run >/dev/null

service_template="$ROOT/deployments/native/linux/sonarqube.service.in"
grep -qx 'ProtectSystem=strict' "$service_template"
grep -qx 'ReadWritePaths=@DATA_DIR@ @LOGS_DIR@ @TEMP_DIR@' "$service_template"
grep -qx 'CapabilityBoundingSet=' "$service_template"
grep -qx 'RestrictAddressFamilies=AF_UNIX AF_INET AF_INET6' "$service_template"
grep -qx '  --upgrade-approved            Acknowledge the approved production upgrade plan' "$INSTALLER"
grep -qx '  --backup-verified             Acknowledge the isolated restore verification' "$INSTALLER"
grep -q 'A managed production installation already exists' "$INSTALLER"
printf '%s\n' 'Linux installer contract tests passed.'
