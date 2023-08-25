# server
Everything About my Oracle Cloud Server Setting

## WAS Server (144.24.80.106)
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

## DevOps Server (158.180.70.211)
### Jenkins
 > To use host docker engine in jenkins container, build Jenkins/Dockerfile with {HOST_DOCKER_GROUP_ID}
```
docker build --build-arg DOCKER_GROUP_ID={HOST_DOCKER_GROUP_ID} -t youngwon/jenkins:lts Jenkins/Dockerfile
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
- My Server:
```
docker build --build-arg DOCKER_GROUP_ID=982 -t youngwon/jenkins:lts Jenkins/Dockerfile
```
```
docker run -d \
    -p 50000:50000 -p 8080:8080 \
    -v /home/opc/jenkins_home:/var/jenkins_home \
    -v /var/run/docker.sock:/var/run/docker.sock \
    --name jenkins \
    --env-file /home/opc/secrets/serverSecrets \
    youngwon/jenkins:lts
```
- Jenkins server url: http://158.180.70.211:8080