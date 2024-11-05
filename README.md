# server
Everything About my Oracle Cloud Server Setting
![server-arch](https://github.com/yw7148/server/assets/71220342/a857d7df-631f-4a1e-9723-24d352748b1a)
## WAS Server (150.230.252.102)


## DevOps server (158.180.85.209)
### Network
```
docker network create youngwon
```

### Nginx
```
docker run -d \
    -p 80:80 -p 443:443\
    -v {PATH_TO_NGINX_CONF}:/etc/nginx/nginx.conf \
    --network youngwon \
    --name nginx \
    nginx:latest
```
 - My Server:
```
docker run -d \
    -p 80:80 -p 443:443\
    -v /home/opc/server/Nginx/nginx.conf:/etc/nginx/nginx.conf \
    --network youngwon \
    --name nginx \
    nginx:latest
```
or with docker-compose:
```
docker compose -f Nginx/docker-compose.yml up -d
```
## Local Server
 > Moved from Oracle Cloud server because of server performance issue.

### Jenkins
 > To use host docker engine in jenkins container, build Jenkins/Dockerfile with {HOST_DOCKER_GROUP_ID}
```
docker build --build-arg DOCKER_GROUP_ID={HOST_DOCKER_GROUP_ID} -t yw7148/jenkins:latest Jenkins/.
```
```
docker run -d \
    -p 50000:50000 -p 8080:8080 \
    -v {PATH_TO_JENKINS_HOME}:/var/jenkins_home \
    -v /var/run/docker.sock:/var/run/docker.sock \
    --name jenkins \
    --env-file {SECRETS_ENV_PATH}\
    yw7148/jenkins:latest
```
- My Server (WSL):
```
docker build --build-arg DOCKER_GROUP_ID=1001 -t yw7148/jenkins:latest Jenkins/.
```
```
docker run -d \
    -p 50000:50000 -p 8080:8080 \
    -v /home/youngwon/jenkins_home:/var/jenkins_home \
    -v /var/run/docker.sock:/var/run/docker.sock \
    --name jenkins \
    --env-file /home/youngwon/secrets/serverSecrets \
    --restart unless-stopped \
    yw7148/jenkins:latest
```
or with docker-compose
```
docker compose -f Jenkins/docker-compose.yml up -d --build
```
#### To support multi-platform image (linux/amd64, linux/arm64, ...)
```
docker buildx create --name multiplatform --bootstrap --use
```
#### To deploy with docker hub ( [Youngwon's DockerHub](https://hub.docker.com/repositories/yw7148) )
 - login to docker hub
> If you get "Error saving credentials: error storing credentials" error, open ~/.docker/config.json file and set "credsStore": "".
```
docker login
```
 - create docker context to deploy more easiliy
```
docker context create jenkins_was --docker host='ssh://jenkins@150.230.250.174'
docker context create jenkins_devops --docker host='ssh://jenkins@152.67.206.246'
```
 - now deploy to server with
```
docker --context {jenkins_was|jenkins_devops} run {yw7148/image}
```