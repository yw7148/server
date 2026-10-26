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

## 7. Prepare OCI Vault Access for External Secrets

`portfolio server`가 받아야 할 런타임 secret은 OCI Vault에 저장한다.

권장 secret 이름:

- `portfolio-server-db-url`
- `portfolio-server-db-user`
- `portfolio-server-db-pw`
- `portfolio-server-jwt-secret`

OCI IAM 준비:

1. k3s 노드가 속한 dynamic group을 만든다.
2. Vault/Secret이 있는 compartment에 아래 예시 정책을 추가한다.

```text
Allow dynamic-group <K3S_NODE_DYNAMIC_GROUP> to read vaults in compartment <COMPARTMENT_NAME>
Allow dynamic-group <K3S_NODE_DYNAMIC_GROUP> to read secret-family in compartment <COMPARTMENT_NAME>
```

주의:

- 이 리포의 `ClusterSecretStore`는 `InstancePrincipal`을 기준으로 설계되어 있다.
- `OCI_REGION`은 비밀이 아니지만 `OCI_VAULT_OCID`는 환경 메타데이터이므로 공개 repo에 고정하지 않는다.
- 실제 `ClusterSecretStore`는 `clusters/oci-prod/secret-stores/clustersecretstore-oci-vault.yaml.tmpl`을 환경변수로 렌더링해 적용한다.
- OCI IAM policy가 반영되기까지 수 분 걸릴 수 있다.
- `ClusterSecretStore` CRD는 External Secrets Operator가 설치하므로 이 단계에서는 아직 template을 적용하지 않는다.

## 8. Apply GitOps Root Application

리포 루트에서 실행:

```bash
sudo kubectl apply -k bootstrap/home-mgmt/root-app
sudo kubectl -n argocd get applications
```

몇 분 뒤 아래 세 앱이 보여야 한다.

- `oci-base`
- `oci-external-secrets-operator`
- `portfolio-prod`

동기화 강제 실행:

```bash
argocd app sync server-root
argocd app sync oci-base
argocd app sync oci-external-secrets-operator
```

External Secrets Operator와 CRD가 준비될 때까지 기다린다.

```bash
KUBECONFIG=~/.kube/oci-prod.yaml kubectl wait \
  --for=condition=Established \
  crd/clustersecretstores.external-secrets.io \
  --timeout=120s

KUBECONFIG=~/.kube/oci-prod.yaml kubectl -n external-secrets rollout status \
  deployment/external-secrets \
  --timeout=180s
```

## 9. Apply OCI ClusterSecretStore

리포 루트에서 환경별 값을 준비하고 OCI k3s kubeconfig를 명시해 적용한다.

```bash
cp .env.example .env
# .env에 실제 OCI_REGION과 OCI_VAULT_OCID를 채운다.
OCI_KUBECONFIG="$HOME/.kube/oci-prod.yaml" ./scripts/apply-oci-secret-store.sh
```

`ClusterSecretStore`가 OCI Vault에 접근할 수 있는지 확인한 뒤 portfolio를 다시 동기화한다.

```bash
KUBECONFIG=~/.kube/oci-prod.yaml kubectl wait \
  --for=condition=Ready \
  clustersecretstore/oci-vault \
  --timeout=120s

argocd app sync portfolio-prod
```

자동 sync가 먼저 시작됐다면 `ClusterSecretStore` 생성 전까지 `portfolio-prod`가 일시적으로 오류 상태일 수 있다. Store가 `Ready=True`가 된 뒤 다시 sync하면 복구된다.

## 10. Verify OCI Runtime Resources

OCI cluster 기준으로 확인:

```bash
KUBECONFIG=~/.kube/oci-prod.yaml kubectl get ns
KUBECONFIG=~/.kube/oci-prod.yaml kubectl get pods -A
KUBECONFIG=~/.kube/oci-prod.yaml kubectl get ingress -A
KUBECONFIG=~/.kube/oci-prod.yaml kubectl -n external-secrets get deploy,pods
KUBECONFIG=~/.kube/oci-prod.yaml kubectl get clustersecretstore
KUBECONFIG=~/.kube/oci-prod.yaml kubectl -n portfolio get externalsecret,secret
KUBECONFIG=~/.kube/oci-prod.yaml kubectl -n portfolio get deploy,svc,pods
```

중점 확인 항목:

- `cert-manager` pod 정상 기동
- `external-secrets` controller 정상 기동
- `oci-vault` `ClusterSecretStore`가 `Ready=True`
- `portfolio-server-env` `ExternalSecret`가 `Ready=True`
- `portfolio-server-env` Kubernetes Secret 생성
- `portfolio` deployment replica 2개 정상 기동
- `portfolio` ingress에 `portfolio-api.youngwon.me`와 `/api` rule 반영
- `portfolio` deployment에 `SPRING_PROFILES_ACTIVE=prod` 반영

문제가 있으면 아래 확인이 빠르다.

```bash
KUBECONFIG=~/.kube/oci-prod.yaml kubectl -n portfolio describe externalsecret portfolio-server-env
KUBECONFIG=~/.kube/oci-prod.yaml kubectl -n external-secrets logs deployment/external-secrets
```

## 11. DNS Cutover

`portfolio.youngwon.me`는 Vercel을 계속 사용한다. Cloudflare에는 백엔드 전용
`portfolio-api.youngwon.me` record만 추가한다.

Cloudflare API로 적용할 때 필요한 최소 권한:

- API Token template: `Edit zone DNS`
- Resource: `youngwon.me` zone으로 제한
- 로컬 환경변수: `CLOUDFLARE_API_TOKEN`, `CLOUDFLARE_ZONE_ID`, `OCI_CONTROL_PUBLIC_IP`

실제 token과 zone ID, public IP는 Git에 저장하지 않는다. Cloudflare Dashboard에서
직접 생성하거나 아래 API 호출로 DNS-only `A` record를 생성한다.

```bash
curl --request POST \
  "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/dns_records" \
  --header "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" \
  --header "Content-Type: application/json" \
  --data "{\"type\":\"A\",\"name\":\"portfolio-api.youngwon.me\",\"content\":\"${OCI_CONTROL_PUBLIC_IP}\",\"ttl\":1,\"proxied\":false}"
```

먼저 HTTP origin route를 확인한다.

```bash
curl --header "Host: portfolio-api.youngwon.me" \
  http://<OCI_CONTROL_PUBLIC_IP>/api/v1/projects
```

cert-manager가 origin 인증서를 발급한 다음 `Certificate`가 `Ready=True`인지 확인한다.

```bash
KUBECONFIG=~/.kube/oci-prod.yaml kubectl -n portfolio get certificate
```

그 후 Cloudflare record를 Proxied로 전환하고 SSL/TLS mode를 `Full (strict)`로 설정한다.
이 순서를 지키면 origin 인증서 발급 전 Cloudflare의 strict 검증이 ACME HTTP-01을
막는 상황을 피할 수 있다.

변경 후 확인:

```bash
curl -I http://portfolio-api.youngwon.me/api/v1/projects
curl -i https://portfolio-api.youngwon.me/api/v1/projects
```

처음에는 cert-manager 인증서 발급까지 수 분이 걸릴 수 있다.

## 12. Promote a New Portfolio Image

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

## 13. Add More Services

현재 구조는 `portfolio` 하나만 배포하지만, 여러 서비스가 추가될 수 있게 이미 분리돼 있다.

새 서비스를 추가할 때 필요한 최소 경로는 아래다.

```text
apps/<service>/base/
apps/<service>/overlays/prod/
argocd/applications/<service>-prod.yaml
clusters/oci-prod/namespaces/<service>.yaml
```

같은 패턴으로 서비스별 namespace, deployment, service, ingress, overlay를 독립적으로 늘릴 수 있다.
