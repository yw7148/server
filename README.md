# server
Everything About my Oracle Cloud Server Setting

## WAS Server (144.24.80.106)


## Web Server (158.180.70.211)
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

## Local Server
 > Moved from Oracle Cloud server because of server performance issue.

### Jenkins
 > To use host docker engine in jenkins container, build Jenkins/Dockerfile with {HOST_DOCKER_GROUP_ID}
```
docker build --build-arg DOCKER_GROUP_ID={HOST_DOCKER_GROUP_ID} -t youngwon/jenkins:lts Jenkins/.
```
```
docker run -d \
    -p 50000:50000 -p 8080:8080 \
    -v {PATH_TO_JENKINS_HOME}:/var/jenkins_home \
    -v /var/run/docker.sock:/var/run/docker.sock \
    --name jenkins \
    --env-file {ENV_FILE_PATH}\
    youngwon/jenkins:lts
```
- My Server ( vscode dev container ):
```
docker build --build-arg DOCKER_GROUP_ID=1001 -t youngwon/jenkins:lts Jenkins/.
```
```
docker create volume jenkins_home
```
```
docker run -d \
    -p 50000:50000 -p 8080:8080 \
    -v jenkins_home:/var/jenkins_home \
    -v /var/run/docker.sock:/var/run/docker.sock \
    --name jenkins \
    --env-file /workspaces/java/secrets/serverSecrets \
    youngwon/jenkins:lts
```