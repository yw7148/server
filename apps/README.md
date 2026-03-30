# Apps Layout

현재 구조는 서비스별로 독립적인 Kubernetes 매니페스트를 추가할 수 있게 잡아두었다.

패턴:

```text
apps/<service>/base/
apps/<service>/overlays/prod/
argocd/applications/<service>-prod.yaml
clusters/oci-prod/namespaces/<service>.yaml
```

새 서비스를 추가할 때는 아래 순서를 따른다.

1. `clusters/oci-prod/namespaces/` 아래에 namespace를 추가한다.
2. `apps/<service>/base/`에 Deployment, Service, Ingress를 추가한다.
3. `apps/<service>/overlays/prod/`에서 이미지 태그와 prod 설정을 덮어쓴다.
4. `argocd/applications/` 아래에 새 Application을 추가한다.
5. `argocd/kustomization.yaml`에 새 Application을 등록한다.
