# ~/ai-system/Vagrantfile
# Vagrant + VirtualBox VM 환경 AI 시스템
# 호스트: CPU 16코어 / RAM 32GB / GPU 없음
# VM: Ubuntu 22.04 / RAM 20GB / CPU 14코어
#
# ※ Ollama는 Docker Compose 컨테이너로 실행 (VM 시스템 설치 제거)
#   이유: VirtualBox에서 host.docker.internal 미작동
#         → Ollama를 Docker 네트워크 안에 두어야 http://ollama:11434 통신 가능

Vagrant.configure("2") do |config|

  # ── 베이스 박스 ──────────────────────────────────────────────
  config.vm.box         = "ubuntu/jammy64"   # Ubuntu 22.04 LTS
  config.vm.box_version = ">= 20240101"
  config.vm.hostname    = "ai-system"
  config.disksize.size = "80GB"

  # ── VirtualBox 리소스 설정 ──────────────────────────────────
  config.vm.provider "virtualbox" do |vb|
    vb.name   = "ai-system-vm"
    vb.memory = 20480          # 20 GB RAM
    vb.cpus   = 14             # 물리 코어 87% 할당
    vb.gui    = true
	 

    # CPU 성능 최적화
    vb.customize ["modifyvm", :id, "--nested-hw-virt", "on"]
    vb.customize ["modifyvm", :id, "--paravirtprovider", "kvm"]
    vb.customize ["modifyvm", :id, "--ioapic", "on"]

    # 디스크 컨트롤러 성능 향상
    vb.customize ["storagectl", :id,
                  "--name", "SCSI",
                  "--hostiocache", "on"] rescue nil
  end

  # ── 네트워크: 포트 포워딩 ──────────────────────────────────
  config.vm.network "forwarded_port", guest: 8090,  host: 8090,  host_ip: "0.0.0.0"  # Gateway
  config.vm.network "forwarded_port", guest: 8080,  host: 8080,  host_ip: "0.0.0.0"  # RAG Server
  config.vm.network "forwarded_port", guest: 11434, host: 11434, host_ip: "0.0.0.0"  # Ollama (Docker)
  config.vm.network "forwarded_port", guest: 19530, host: 19530, host_ip: "0.0.0.0"  # Milvus
  config.vm.network "forwarded_port", guest: 5432,  host: 5432,  host_ip: "0.0.0.0"  # PostgreSQL
  config.vm.network "forwarded_port", guest: 9090,  host: 9090,  host_ip: "0.0.0.0"  # Prometheus
  config.vm.network "forwarded_port", guest: 3000,  host: 3000,  host_ip: "0.0.0.0"  # Grafana
  config.vm.network "forwarded_port", guest: 8081,  host: 8081,  host_ip: "0.0.0.0"  # Airflow WebUI
  config.vm.network "forwarded_port", guest: 3001,  host: 3001,  host_ip: "0.0.0.0"  # Flutter WEB Frontend

  # ── 프라이빗 네트워크 (VM 고정 IP) ────────────────────────
  config.vm.network "private_network", ip: "192.168.56.10"

  # ── 공유 폴더 ────────────────────────────────────────────────
  # ⚠️  VirtualBox 공유 폴더는 symlink 미지원 → venv는 /opt/venv 에 생성
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

    echo "=== [1/5] 시스템 업데이트 ==="
    apt-get update -q && apt-get upgrade -y -q

    echo "=== [2/5] 필수 패키지 설치 ==="
    apt-get install -y -q \
      build-essential cmake git curl wget unzip \
      python3 python3-pip python3-venv \
      htop net-tools

    echo "=== [3/5] Docker 설치 ==="
    curl -fsSL https://get.docker.com | sh
    usermod -aG docker vagrant
    docker compose version

    echo "=== [4/5] Python 가상환경 생성 ==="
    # ⚠️  /ai-system(공유 폴더)에 venv 생성 시 Errno 71 symlink 오류 발생
    #     → VM 로컬 경로 /opt/venv 에 생성
    python3 -m venv /opt/venv
    /opt/venv/bin/pip install --upgrade pip -q
    /opt/venv/bin/pip install -q \
      langchain langchain-community \
      pymilvus redis psycopg2-binary \
      fastapi uvicorn httpx \
      sentence-transformers \
      presidio-analyzer presidio-anonymizer \
      "unstructured[pdf]"

    # 로그인 시 자동 활성화
    grep -qxF 'source /opt/venv/bin/activate' /home/vagrant/.bashrc \
      || echo 'source /opt/venv/bin/activate' >> /home/vagrant/.bashrc

    echo "=== [5/5] 완료 안내 ==="
    echo ""
    echo "✅ 프로비저닝 완료"
    echo ""
    echo "다음 단계:"
    echo "  vagrant ssh"
    echo "  cd /ai-system"
    echo "  docker compose up -d   ← Ollama 포함 전체 스택 시작"
    echo ""
    echo "※ Ollama는 Docker Compose 컨테이너로 실행됩니다 (VM 시스템 설치 없음)"
  SHELL

end
