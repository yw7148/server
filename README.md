# server
Everything About my GitOps & Oracle Cloud Server Setting
```mermaid
flowchart LR
    DEV[Developer / Operator]
    GH[GitHub Repository<br/>server]
    GHA[GitHub Actions<br/>Build + Push]
    USER[Public User]
    CF[Cloudflare<br/>portfolio-api.youngwon.me]

    subgraph HOME[Home node]
        HOMEK3S[k3s management cluster]
        ARGO[Argo CD]
        HOMEK3S --> ARGO
    end

    subgraph OCI[OCI k3s runtime cluster]
        CONTROL[instance-control<br/>k3s server]
        WORKER1[instance-worker-1<br/>k3s agent]
        WORKER2[instance-worker-2<br/>k3s agent]
        TRAEFIK[Traefik Ingress]
        CERT[cert-manager]
        ESO[External Secrets Operator]
        VAULT[OCI Vault]
        APP[portfolio workload]

        CONTROL --> WORKER1
        CONTROL --> WORKER2
        TRAEFIK --> APP
        CERT --> TRAEFIK
        ESO --> APP
        VAULT --> ESO
    end

    DEV --> GH
    GH --> GHA
    GH --> ARGO
    ARGO --> CONTROL
    ARGO --> WORKER1
    ARGO --> WORKER2
    USER --> CF
    CF --> TRAEFIK
```

Home node의 Argo CD 관리 클러스터와 OCI k3s 런타임 클러스터로 전환한 상태를 관리한다.

- 설계 문서: `docs/k3s-argocd-migration-design.md`
- OCI 적용 가이드: `docs/oci-k3s-apply-guide.md`
- Argo CD bootstrap: `bootstrap/home-mgmt/`
- Argo CD application/app-of-apps: `argocd/`
- OCI 공통 플랫폼: `clusters/oci-prod/`
- 서비스별 앱 배포 선언: `apps/`

## Apply To OCI

상세 절차는 `docs/oci-k3s-apply-guide.md`를 보면 된다.

핵심 순서는 다음과 같다.

1. OCI `instance-control`, `instance-worker-1`, `instance-worker-2`에 k3s cluster를 구성한다.
2. Home node에 management k3s와 Argo CD를 설치한다.
3. Home node의 Argo CD에 OCI cluster를 `oci-prod`로 등록한다.
4. root app을 적용해 `cert-manager`와 `external-secrets`를 GitOps로 배포한다.
5. External Secrets Operator가 준비된 뒤 `ClusterSecretStore`를 환경변수 기반 템플릿으로 별도 적용한다.
6. `portfolio` 애플리케이션을 동기화하고 runtime secret 주입을 확인한다.
7. Cloudflare에서 `portfolio-api.youngwon.me`를 OCI ingress public IP로 연결한다.

주의:

- `instance-control`에서는 `server` 설치만 실행한다.
- `instance-worker-1`, `instance-worker-2`에서만 `K3S_URL=...` join 명령을 실행한다.
- `--node-ip`는 현재 로그인한 노드의 private IP와 정확히 일치해야 한다.

빠른 시작 명령:

```bash
kubectl apply --server-side --force-conflicts -k bootstrap/home-mgmt/argocd-install
argocd cluster add <kube-context> --name oci-prod
kubectl apply -k bootstrap/home-mgmt/root-app
```

## Portfolio Deployment

`portfolio`는 Docker Hub 이미지 `yw7148/portfolio`로 배포한다.

- base manifests: `apps/portfolio/base/`
- production overlay: `apps/portfolio/overlays/prod/`
- prod ingress host/path: `portfolio-api.youngwon.me/api`
- frontend host: `portfolio.youngwon.me` (Vercel 유지)
- 기본 태그 승격 workflow: `.github/workflows/promote-portfolio-image.yml`
- 런타임 secret source: OCI Vault -> External Secrets Operator -> Kubernetes Secret `portfolio-server-env`
- `ClusterSecretStore` 값은 공개 repo에 고정하지 않고 `scripts/apply-oci-secret-store.sh`에서 환경변수로 렌더링한다.

## Multi-Service Structure

현재 구조는 `portfolio` 한 개만 들어가 있지만, 여러 서비스를 추가할 수 있게 나눠져 있다.

- 서비스별 매니페스트: `apps/<service>/base/`
- 환경별 오버레이: `apps/<service>/overlays/prod/`
- Argo CD 앱 선언: `argocd/applications/<service>-prod.yaml`
- 서비스별 namespace: `clusters/oci-prod/namespaces/<service>.yaml`

예시는 `apps/README.md`에 정리해두었다.

민감한 값 주의:

- 실제 `K3S_TOKEN`, Argo CD 비밀번호, kubeconfig, 운영용 공인 IP는 문서에 하드코딩하지 않는다.
- 애플리케이션 secret 값은 Git에 넣지 않고 OCI Vault에 저장한 뒤 `ClusterSecretStore` / `ExternalSecret`으로 참조한다.
- `OCI_REGION`은 비밀은 아니지만, `OCI_VAULT_OCID`를 포함한 환경별 식별자는 공개 repo에 고정하지 않고 로컬 환경변수로 렌더링한다.
- 설치 예시는 항상 `<NODE_TOKEN>`, `<OCI_CONTROL_PUBLIC_IP>`, `<ARGOCD_ADMIN_PASSWORD>` 같은 placeholder를 사용한다.
