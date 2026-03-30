# OCI k3s Apply Guide

## Summary

이 문서는 현재 리포의 Kubernetes/Argo CD 설정을 실제 OCI 인스턴스와 Home node에 적용하는 절차를 정리한다.

대상 노드:

- Home node: Argo CD 관리 클러스터
- OCI `instance-control`: k3s server
- OCI `instance-worker-1`: k3s agent
- OCI `instance-worker-2`: k3s agent

## 1. OCI Security Rules

OCI security list 또는 NSG에서 최소한 아래 포트를 허용한다.

- Internet -> `instance-control`
  - `80/tcp`
  - `443/tcp`
  - `6443/tcp`
- Operator IP -> all nodes
  - `22/tcp`
- OCI private subnet internal
  - all node-to-node traffic for k3s overlay and agent/server communication

`6443/tcp`는 Home node의 Argo CD가 OCI 클러스터에 접근하기 위해 필요하다.

권장:

- `6443/tcp`는 전체 인터넷에 열지 말고 Home node의 공인 IP로만 제한한다.
- Home node에서 OCI kubeconfig가 가리키는 API 서버 주소는 실제로 Home node와 Argo CD pod가 모두 도달 가능한 주소여야 한다.

## 2. Install k3s on OCI

중요:

- `instance-control`에서는 `server` 설치만 실행한다.
- `instance-worker-1`, `instance-worker-2`에서는 `agent` join만 실행한다.
- `--node-ip` 값은 "지금 접속해 있는 머신"에 실제로 붙어 있는 private IP와 반드시 같아야 한다.
- `K3S_URL`을 주면 설치 스크립트는 agent로 동작한다. 따라서 `instance-control`에서 `K3S_URL=...` 형태의 join 명령을 실행하면 안 된다.

실행 전 빠른 확인:

```bash
hostname
ip -4 addr show | grep "10.0.0."
```

예상 결과:

- `instance-control`에서는 `10.0.0.195`
- `instance-worker-1`에서는 `10.0.0.149`
- `instance-worker-2`에서는 `10.0.0.81`

### 2.1 Control Plane on `instance-control`

`instance-control`에서 실행:

```bash
curl -sfL https://get.k3s.io | \
  INSTALL_K3S_EXEC="server \
    --write-kubeconfig-mode 644 \
    --node-ip 10.0.0.195 \
    --advertise-address 10.0.0.195 \
    --tls-san <OCI_CONTROL_PUBLIC_IP>" \
  sh -
```

토큰 확인:

```bash
sudo cat /var/lib/rancher/k3s/server/node-token
```

### 2.2 Join `instance-worker-1`

`instance-worker-1`에서 실행:

먼저 control plane 연결 확인:

```bash
curl -k https://10.0.0.195:6443/cacerts
```

여기서 CA 인증서가 내려오지 않으면 join 전에 아래를 먼저 확인한다.

- `instance-control`에서 `sudo systemctl status k3s --no-pager -l`
- OCI security list / NSG 에서 worker -> control plane `6443/tcp` 허용 여부
- OS firewall 에서 `6443/tcp` 허용 여부

정상 응답이 오면 join:

```bash
curl -sfL https://get.k3s.io | \
  K3S_URL=https://10.0.0.195:6443 \
  K3S_TOKEN=<NODE_TOKEN> \
  INSTALL_K3S_EXEC="agent --node-ip 10.0.0.149" \
  sh -
```

### 2.3 Join `instance-worker-2`

`instance-worker-2`에서 실행:

먼저 control plane 연결 확인:

```bash
curl -k https://10.0.0.195:6443/cacerts
```

정상 응답이 오면 join:

```bash
curl -sfL https://get.k3s.io | \
  K3S_URL=https://10.0.0.195:6443 \
  K3S_TOKEN=<NODE_TOKEN> \
  INSTALL_K3S_EXEC="agent --node-ip 10.0.0.81" \
  sh -
```

### 2.4 Verify OCI Cluster

`instance-control`에서 실행:

```bash
sudo kubectl get nodes -o wide
```

정상 결과는 노드 3대가 모두 `Ready` 상태여야 한다.

## 2.5 Troubleshooting Wrong-Node Join

증상 예시:

- `instance-control`에서 worker join 명령을 실행했다.
- `systemctl status k3s-agent`가 실패한다.
- `--node-ip 10.0.0.149` 같은 worker IP를 control plane 노드에서 사용했다.

이 경우 원인은 대체로 다음 둘 중 하나다.

- control plane 노드에 agent를 설치하려고 했다.
- 현재 노드에 없는 IP를 `--node-ip`로 넘겼다.

복구 절차는 아래와 같다.

### `instance-control`에서 agent를 잘못 실행한 경우

```bash
sudo /usr/local/bin/k3s-agent-uninstall.sh
sudo rm -f /etc/systemd/system/k3s-agent.service /etc/systemd/system/k3s-agent.service.env
sudo systemctl daemon-reload
```

그다음 control plane 명령만 다시 실행:

```bash
curl -sfL https://get.k3s.io | \
  INSTALL_K3S_EXEC="server \
    --write-kubeconfig-mode 644 \
    --node-ip 10.0.0.195 \
    --advertise-address 10.0.0.195 \
    --tls-san <OCI_CONTROL_PUBLIC_IP>" \
  sh -
```

확인:

```bash
sudo systemctl status k3s --no-pager
sudo kubectl get nodes -o wide
sudo cat /var/lib/rancher/k3s/server/node-token
```

### worker에서 join이 꼬인 경우

```bash
sudo /usr/local/bin/k3s-agent-uninstall.sh
sudo rm -f /etc/systemd/system/k3s-agent.service /etc/systemd/system/k3s-agent.service.env
sudo rm -rf /etc/rancher/node /etc/rancher/k3s /var/lib/rancher/k3s
sudo systemctl daemon-reload
```

그다음 해당 worker의 올바른 private IP로 다시 join:

```bash
curl -sfL https://get.k3s.io | \
  K3S_URL=https://10.0.0.195:6443 \
  K3S_TOKEN=<NODE_TOKEN> \
  INSTALL_K3S_EXEC="agent --node-ip <THIS_WORKER_PRIVATE_IP>" \
  sh -
```

만약 이전에 같은 hostname으로 join 시도가 있었다면, control plane에서 기존 node 정보를 먼저 지우는 편이 안전하다.

```bash
sudo /usr/local/bin/k3s kubectl delete node instance-worker-1 || true
sudo /usr/local/bin/k3s kubectl delete node instance-worker-2 || true
```

## 2.6 Worker Join Failure Checklist

worker 로그에 아래 같은 메시지가 보이면:

```text
Failed to validate connection to cluster at https://10.0.0.195:6443
failed to get CA certs
Get "https://127.0.0.1:6444/cacerts": read tcp 127.0.0.1:*->127.0.0.1:6444: read: connection reset by peer
```

대개 원인은 아래 셋 중 하나다.

- `instance-control`의 `k3s.service`가 실제로 떠 있지 않다.
- worker에서 `10.0.0.195:6443`에 접근할 수 없다.
- worker에 남아 있는 이전 join 상태가 새 시도와 충돌한다.

확인 순서:

1. `instance-control`

```bash
sudo systemctl status k3s --no-pager -l
sudo ss -lntp | grep 6443
sudo /usr/local/bin/k3s kubectl get nodes -o wide
```

2. worker

```bash
curl -k https://10.0.0.195:6443/cacerts
sudo journalctl -u k3s-agent -n 100 --no-pager -l
```

3. Oracle Linux firewall 사용 중이면 `instance-control`에서:

```bash
sudo firewall-cmd --permanent --add-port=6443/tcp
sudo firewall-cmd --permanent --zone=trusted --add-source=10.42.0.0/16
sudo firewall-cmd --permanent --zone=trusted --add-source=10.43.0.0/16
sudo firewall-cmd --reload
```

필요하면 worker 재join 전에 OS firewall도 꺼둘 수 있다.

```bash
sudo systemctl disable firewalld --now
```

## 3. Prepare Kubeconfig for Home node

Home node에서 OCI kubeconfig를 가져온다.

```bash
mkdir -p ~/.kube
ssh opc@<OCI_CONTROL_PUBLIC_IP> "sudo cat /etc/rancher/k3s/k3s.yaml" > ~/.kube/oci-prod.yaml
sed -i "s/127.0.0.1/<OCI_CONTROL_PUBLIC_IP>/" ~/.kube/oci-prod.yaml
```

중요:

- 여기서 `<OCI_CONTROL_PUBLIC_IP>`는 Home node에서 실제로 접근 가능한 IP여야 한다.
- `argocd cluster add`는 이 kubeconfig의 server 주소로 직접 접속해 `kube-system`에 `argocd-manager` service account를 만든다.
- 따라서 Home node에서 아래 테스트가 먼저 성공해야 한다.

```bash
curl -k https://<OCI_CONTROL_PUBLIC_IP>:6443/cacerts
```

이 테스트가 실패하면 `argocd cluster add`도 실패한다.

컨텍스트 이름을 정리한다.

```bash
KUBECONFIG=~/.kube/oci-prod.yaml kubectl config rename-context default oci-prod
KUBECONFIG=~/.kube/oci-prod.yaml kubectl get nodes
```

## 4. Install Management Cluster on Home node

Home node에서 관리용 k3s를 설치한다.

```bash
curl -sfL https://get.k3s.io | \
  INSTALL_K3S_EXEC="server --write-kubeconfig-mode 644" \
  sh -
```

기본 kubeconfig 확인:

```bash
sudo kubectl get nodes
```

Home node에서 사용할 `kubectl` 기본 컨텍스트는 management cluster로 두는 편이 안전하다.

## 5. Install Argo CD on Home node

리포 루트에서 실행:

```bash
sudo kubectl apply --server-side --force-conflicts -k bootstrap/home-mgmt/argocd-install
sudo kubectl -n argocd get pods
```

중요:

- Argo CD의 `ApplicationSet` CRD는 크기가 커서 일반 `kubectl apply`로는 `metadata.annotations: Too long` 오류가 날 수 있다.
- 이 경우 설치 명령은 반드시 `--server-side --force-conflicts` 옵션을 사용한다.

초기 admin 비밀번호 확인:

```bash
sudo kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d && echo
```

필요 시 로컬 포트포워딩:

```bash
sudo kubectl -n argocd port-forward svc/argocd-server 8080:443
```

## 6. Register OCI Cluster to Argo CD

Home node에 Argo CD CLI가 없다면 설치:

```bash
VERSION=v3.3.6
curl -sSL -o /tmp/argocd-linux-amd64 \
  https://github.com/argoproj/argo-cd/releases/download/${VERSION}/argocd-linux-amd64
sudo install -m 0755 /tmp/argocd-linux-amd64 /usr/local/bin/argocd
```

Argo CD 로그인:

```bash
argocd login localhost:8080 --username admin --password <ARGOCD_ADMIN_PASSWORD> --insecure
```

OCI 클러스터 등록:

```bash
KUBECONFIG=~/.kube/oci-prod.yaml argocd cluster add oci-prod --name oci-prod --yes
```

만약 아래처럼 timeout이 나면:

```text
failed to create service account "argocd-manager" in namespace "kube-system"
dial tcp <OCI_CONTROL_PUBLIC_IP>:6443: i/o timeout
```

아래를 순서대로 확인한다.

1. Home node에서 API 서버 도달성 확인

```bash
curl -k https://<OCI_CONTROL_PUBLIC_IP>:6443/cacerts
```

2. `instance-control`에서 API 서버 리스닝 확인

```bash
sudo systemctl status k3s --no-pager -l
sudo ss -lntp | grep 6443
```

3. OCI security list / NSG에서 `6443/tcp`가 Home node 공인 IP에 대해 허용돼 있는지 확인

4. `instance-control`의 OS firewall에서 `6443/tcp` 허용 여부 확인

```bash
sudo systemctl status firewalld --no-pager
sudo firewall-cmd --list-ports
```

등록 확인:

```bash
argocd cluster list
```

## 7. Apply GitOps Root Application

리포 루트에서 실행:

```bash
sudo kubectl apply -k bootstrap/home-mgmt/root-app
sudo kubectl -n argocd get applications
```

몇 분 뒤 아래 두 앱이 보여야 한다.

- `oci-base`
- `portfolio-prod`

동기화 강제 실행:

```bash
argocd app sync server-root
argocd app sync oci-base
argocd app sync portfolio-prod
```

## 8. Verify OCI Runtime Resources

OCI cluster 기준으로 확인:

```bash
KUBECONFIG=~/.kube/oci-prod.yaml kubectl get ns
KUBECONFIG=~/.kube/oci-prod.yaml kubectl get pods -A
KUBECONFIG=~/.kube/oci-prod.yaml kubectl get ingress -A
KUBECONFIG=~/.kube/oci-prod.yaml kubectl -n portfolio get deploy,svc,pods
```

중점 확인 항목:

- `cert-manager` pod 정상 기동
- `portfolio` deployment replica 2개 정상 기동
- `portfolio` ingress에 `youngwon.me`와 `/portfolio` rule 반영

## 9. DNS Cutover

현재 `youngwon.me` DNS를 기존 Nginx가 아닌 OCI ingress 진입 public IP로 변경한다.

기본안:

- `A` record `youngwon.me` -> `<OCI_CONTROL_PUBLIC_IP>`

변경 후 확인:

```bash
curl -I http://youngwon.me/portfolio
curl -I https://youngwon.me/portfolio
```

처음에는 cert-manager 인증서 발급까지 수 분이 걸릴 수 있다.

## 10. Promote a New Portfolio Image

기본 배포 이미지는 `apps/portfolio/overlays/prod/kustomization.yaml`에서 관리한다.

새 이미지 태그 반영 방법:

```bash
gh workflow run promote-portfolio-image.yml -f image_tag=<NEW_TAG>
```

또는 직접 파일 수정:

```bash
sed -i 's/^    newTag: .*/    newTag: <NEW_TAG>/' apps/portfolio/overlays/prod/kustomization.yaml
git commit -am "chore(portfolio): promote image"
git push
```

push 후 Argo CD가 자동 동기화한다.

## 11. Add More Services

현재 구조는 `portfolio` 하나만 배포하지만, 여러 서비스가 추가될 수 있게 이미 분리돼 있다.

새 서비스를 추가할 때 필요한 최소 경로는 아래다.

```text
apps/<service>/base/
apps/<service>/overlays/prod/
argocd/applications/<service>-prod.yaml
clusters/oci-prod/namespaces/<service>.yaml
```

같은 패턴으로 서비스별 namespace, deployment, service, ingress, overlay를 독립적으로 늘릴 수 있다.
