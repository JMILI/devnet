#!/usr/bin/env bash
set +e
echo '=== ip route ==='
ip route show default
echo '=== resolv.conf ==='
head -5 /etc/resolv.conf
echo '=== detected host ==='
# shellcheck source=/dev/null
source /home/ubuntu2404/code_jm/devnet/lib/proxy.sh
echo "devnet_windows_host=$(devnet_windows_host)"
echo '=== doctor ==='
/home/ubuntu2404/code_jm/devnet/bin/net doctor
echo "DOCTOR_EXIT=$?"
echo '=== git-clone ==='
rm -rf /tmp/ProjectAccess-clone-test2
timeout 45 /home/ubuntu2404/code_jm/devnet/bin/net git-clone https://github.com/JMILI/ProjectAccess.git /tmp/ProjectAccess-clone-test2
echo "CLONE_EXIT=$?"
ls -la /tmp/ProjectAccess-clone-test2 2>&1 | head -15
