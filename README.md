# server
Everything About my AWS Server Setting

## network 만들기
docker network create youngwon

## 배포
### Nginx
docker run -d -p 80:80 -p 8080:8080 -v /home/ec2-user/server/nginx.conf:/etc/nginx/nginx.conf --network youngwon --name nginx nginx:latest

### Jenkins
docker run -d -p 50000:50000 --network youngwon -v /home/ec2-user/jenkins:/var/jenkins_home --name jenkins jenkins/jenkins:lts

### Or Use Docker compose


## Urls
### Jenkins
http://3.37.247.4:8080