# 03. 환경 구성 가이드 (Environment Setup)

> **Phase 1 & 2** | Vagrant + VirtualBox VM 환경 구성

---

## 1. 사전 요구사항

| 항목 | 최소 사양 |
|------|----------|
| CPU | 16코어 (VM에 14코어 할당) |
| RAM | 32GB (VM에 20GB 할당) |
| 디스크 | 여유 공간 50GB 이상 |
| OS | Windows 10/11 또는 macOS 12+ |
| BIOS | VT-x / AMD-V 가상화 활성화 필수 |

---

## 2. STEP 1 — 호스트에 Vagrant & VirtualBox 설치

### Windows (PowerShell 관리자 권한)

```powershell
# Chocolatey로 한 번에 설치
choco install virtualbox vagrant -y

# 버전 확인
vagrant --version    # 2.4.0+
vboxmanage --version # 7.0+
```

> **BIOS 주의사항**: Intel Virtualization Technology → **Enabled** 확인

### macOS

```bash
brew install --cask virtualbox vagrant

vagrant --version
vboxmanage --version
```

### Linux (호스트가 Linux인 경우)

```bash
wget -q https://www.virtualbox.org/download/oracle_vbox_2016.asc \
    -O- | sudo apt-key add -
sudo apt install virtualbox vagrant -y
```

---

## 3. STEP 2 — 프로젝트 디렉토리 생성 (호스트에서)

```bash
mkdir -p ~/ai-system
cd ~/ai-system

# 하위 디렉토리 (VM과 공유됨)
mkdir -p rag_server gateway config models data logs
```

---

## 4. STEP 3 — Vagrantfile 작성

```ruby
# ~/ai-system/Vagrantfile

Vagrant.configure("2") do |config|

  # ── 베이스 박스 ──────────────────────────────────────────
  config.vm.box     = "ubuntu/jammy64"   # Ubuntu 22.04 LTS
  config.vm.box_version = ">= 20240101"
  config.vm.hostname = "ai-system"

  # ── VirtualBox 리소스 설정 ────────────────────────────────
  config.vm.provider "virtualbox" do |vb|
    vb.name   = "ai-system-vm"
    vb.memory = 20480          # 20 GB RAM
    vb.cpus   = 14             # 물리 코어 87% 할당
    vb.gui    = false

    # CPU 성능 최적화
    vb.customize ["modifyvm", :id, "--nested-hw-virt", "on"]
    vb.customize ["modifyvm", :id, "--paravirtprovider", "kvm"]
    vb.customize ["modifyvm", :id, "--ioapic", "on"]

    # 디스크 컨트롤러 성능 향상
    vb.customize ["storagectl", :id,
                  "--name", "SCSI",
                  "--hostiocache", "on"] rescue nil
  end

  # ── 네트워크: 포트 포워딩 ─────────────────────────────────
  config.vm.network "forwarded_port", guest: 8090,  host: 8090,  host_ip: "127.0.0.1"
  config.vm.network "forwarded_port", guest: 8080,  host: 8080,  host_ip: "127.0.0.1"
  config.vm.network "forwarded_port", guest: 11434, host: 11434, host_ip: "127.0.0.1"
  config.vm.network "forwarded_port", guest: 19530, host: 19530, host_ip: "127.0.0.1"
  config.vm.network "forwarded_port", guest: 5432,  host: 5432,  host_ip: "127.0.0.1"
  config.vm.network "forwarded_port", guest: 9090,  host: 9090,  host_ip: "127.0.0.1"
  config.vm.network "forwarded_port", guest: 3000,  host: 3000,  host_ip: "127.0.0.1"

  # ── 프라이빗 네트워크 (VM 고정 IP) ───────────────────────
  config.vm.network "private_network", ip: "192.168.56.10"

  # ── 공유 폴더 ─────────────────────────────────────────────
  config.vm.synced_folder ".", "/ai-system",
    type: "virtualbox",
    owner: "vagrant",
    group: "vagrant",
    mount_options: ["dmode=775,fmode=664"]

  config.vm.synced_folder "./models", "/ai-system/models",
    type: "virtualbox",
    owner: "vagrant",
    group: "vagrant"

  # ── 프로비저닝 ─────────────────────────────────────────────
  config.vm.provision "shell", inline: <<-SHELL
    set -e
    echo "=== [1/6] 시스템 업데이트 ==="
    apt-get update -q && apt-get upgrade -y -q

    echo "=== [2/6] 필수 패키지 설치 ==="
    apt-get install -y -q \
      build-essential cmake git curl wget unzip \
      python3 python3-pip python3-venv \
      htop net-tools

    echo "=== [3/6] Docker 설치 ==="
    curl -fsSL https://get.docker.com | sh
    usermod -aG docker vagrant

    echo "=== [4/6] Docker Compose v2 확인 ==="
    docker compose version

    echo "=== [5/6] Ollama 설치 ==="
    curl -fsSL https://ollama.com/install.sh | sh
    mkdir -p /etc/systemd/system/ollama.service.d
    cat > /etc/systemd/system/ollama.service.d/override.conf << 'EOF'
[Service]
Environment="OLLAMA_HOST=0.0.0.0:11434"
Environment="OLLAMA_NUM_PARALLEL=2"
EOF
    systemctl daemon-reload
    systemctl enable ollama
    systemctl start ollama

    echo "=== [6/6] Python 가상환경 생성 ==="
    cd /ai-system
    python3 -m venv .venv
    source .venv/bin/activate
    pip install --upgrade pip -q
    pip install -q \
      langchain langchain-community \
      pymilvus redis psycopg2-binary \
      fastapi uvicorn httpx \
      sentence-transformers \
      presidio-analyzer presidio-anonymizer \
      unstructured[pdf]

    echo "=== ✅ 프로비저닝 완료 ==="
  SHELL

end
```

---

## 5. STEP 4 — VM 시작 및 접속

```bash
# 호스트에서 실행 — 최초 실행 시 프로비저닝 자동 수행 (~10분)
cd ~/ai-system
vagrant up

# VM 상태 확인
vagrant status

# VM 접속
vagrant ssh

# VM 내부에서 확인
free -h        # 약 20GB 표시
nproc          # 14 표시
docker info    # Docker 정상 동작 확인
ollama list    # Ollama 설치 확인
```

---

## 6. STEP 5 — 디렉토리 구조 확인 (VM 내부)

```bash
# VM 내부에서
ls -la /ai-system/
# 호스트 ~/ai-system/ 의 파일들이 그대로 보여야 함

cd /ai-system
source .venv/bin/activate
```

---

## 7. 흔한 문제 해결

| 증상 | 원인 | 해결 |
|------|------|------|
| `vagrant up` 실패 (VT-x 오류) | BIOS 가상화 비활성화 | BIOS에서 VT-x/AMD-V 활성화 |
| 공유 폴더 마운트 안 됨 | Guest Additions 버전 불일치 | `vagrant plugin install vagrant-vbguest` 후 `vagrant reload` |
| Ollama 응답 없음 | 컨테이너 미기동 or 모델 미등록 | `docker compose logs ollama` 확인 |
| RAM 부족으로 컨테이너 재시작 | VM 메모리 초과 | Vagrantfile `vb.memory` 확인, Q3_K_M 양자화로 교체 |
| 포트 포워딩 접근 안 됨 | 방화벽 또는 포트 충돌 | `vagrant reload`, 호스트 방화벽 규칙 확인 |
