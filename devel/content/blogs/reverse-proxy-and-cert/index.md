---
title: "Reverse proxy with SSL/TLS configuration"
date: 2024-09-12T06:17:09Z
draft: false
author: Nguyen Chau Hieu Duy
tags: ['Nginx', 'Reverse proxy', 'SSL/TLS']
image: /blogs/reverse-proxy-and-cert/nginx-reverse-proxy.png
description:
toc:
---
In my previous [blog](https://website.duy.io.vn/blogs/website-with-cd/), I introduced basic steps to create a continuous deployment for portfolio website on EC2 instance. This time, I will focus on configurating a VPS to improve security and scalability on my my webservices. 

In this project, Nginx will serve as a gateway to multiple services, providing a unified access point while keeping individual ports hidden from direct exposure to the public internet. This setup not only improves security but also simplifies the management of different services by routing traffic efficiently.

## Requirements
- Your domain name.

You need a valid domain name to config reverse proxy and obtain SSL certificate. In term of scalability, we can use sub-domains to access different services.

- A linux VPS with docker enginee installed. 

I'm using AWS EC2 instance for VPS as it provide 12 months free tier with almost 24/24 up time VPS (EC2). There are many other choices like Oracle, Azure, Google Cloud, etc,... with free trial VPS service. 

## System architecture
![](/blogs/reverse-proxy-and-cert/arch.png)

### Explanation
`portfolio` and `jenkins` container will run on their isolated private networks. `Nginx (reverse-proxy)` is a bridge which has ability to connect and redirect request to them base on domain name. There are many advantages of this approach. Firstly, we do not need to expose service ports to public (more secure). Secondly, we can point many sub-domains to only one ip address to access multiple services on a same host. We also able to config SSL/TLS to encrypt transfer data and so on... 
Take a look at our folder tree:
```
my-server/
├── docker-compose.yml          # docker compose config
├── jenkins/                    # jenkins service data
├── nginx/                       
│   ├── conf.d/                  
│   │   ├── jenkins.conf        # nginx configuration for jenkins service
│   │   └── portfolio.conf      # nginx configuration for portfolio service 
│   ├── dockerfile              # dockerfile for reverse-proxy config
│   └── init_ssl.sh             # script to execute certificate config
├── schedule.txt                # cronjob schedule to renew certificates
└── ssl.log                     # log file of renew certificates job
```

### Docker compose

In other to  deploy this system, we will organize those containers with docker compose file. 
```
services:
  portfolio:
    image: duyaccel/personal-web:latest
    container_name: 'portfolio'
    restart: unless-stopped
    networks:
      - portfolio-net

  jenkins:
    image: jenkins/jenkins:2.462.2-jdk17
    container_name: 'jenkins'
    volumes:
      - ./jenkins:/var/jenkins_home
    restart: unless-stopped
    networks:
      - jenkins-net

  reverse-proxy:
    build:
      context: ./nginx
    container_name: 'reverse-proxy'
    volumes:
      - ./nginx/conf.d:/etc/nginx/conf.d
    ports:
      - '80:80'
      - '443:443'
    restart: unless-stopped
    networks:
      - portfolio-net
      - jenkins-net
    depends_on:
      - portfolio
      - jenkins

networks:
  portfolio-net:
    name: portfolio-network
    driver: bridge
  
  jenkins-net:
    name: jenkins-network
    driver: bridge
```

## Reverse proxy configuration

### Config services

There are some differences between Nginx package in most linux system and Nginx docker image. Docker image version will not have `/site-available` and `/site-enable` folders. We need to put configuration files inside `/etc/nginx/conf.d` folders. This is a example of `portfolio.conf` (similar to `jenkins.conf`) which will listen on port 80 (http) ipv4 address. In this case, if user try to access *duy.io.vn* or *website.duy.io.vn*, those request will reach **portfolio service**.

```
server {
  listen 80;
  server_name duy.io.vn website.duy.io.vn; 

  location / {
    proxy_pass                          http://portfolio:80;
    proxy_redirect                      off;
    proxy_set_header  Host              $http_host;
    proxy_set_header  X-Real-IP         $remote_addr;
    proxy_set_header  X-Forwarded-For   $proxy_add_x_forwarded_for;
    proxy_set_header  X-Forwarded-Proto $scheme;
    proxy_read_timeout                  900;
  }
}
```
If you follow my `docker-compose.yml` configuration file, Nginx will able to reach portfolio services at `http://portfolio:80` which we are routing to. 

Reverse proxy dockerfile is not complicated at all. We only need Nginx load the config files and script to install SSL/TLS certificate. This is how it looks like.
```
FROM nginx:1.27.1-alpine3.20

COPY ./conf.d /etc/nginx/conf.d

COPY init_ssl.sh .
```
You wonder where is `https` huh? I'll show you soon.
### Obtain certificates

![](/blogs/reverse-proxy-and-cert/le-logo.png)

**Let's encrypt** is a nonprofit Certificate Authority providing TLS certificates. They provide *Certbot ACME client* to automate certificate issuance and installation with no downtime. In case of web service using Nginx, Certbot provide *nginx plugin* which make the configuration steps more easier.

What's inside those SSL scripts and why I do not execute it in building image process? Certbot (Let's encrypt) will verify our connection between user request and website through domain names. Therefore, I want to make sure that all services is running and connected before the verification process start. We will execute `init_SSL.sh` script inside reverse-proxy manually with **docker exec** command. This is content of that file:
```
#!/bin/sh

apk add certbot-nginx

certbot \
        --nginx -m nguyenchauhieuduy@outlook.com \
        --agree-tos \
        --no-eff-email \
        -d duy.io.vn \
        -d website.duy.io.vn \
        -d cicd.duy.io.vn
```

## Deployment
### Step 1: Initialize services
Let's push our configuration files to the host. There are many command lines to do this on Linux and `rsync` is one of them. You should install and execute `rsync` command similar to this one:
```
rsync -av -e "ssh -i $your-ssh-key-location" ./server/ username@hostname:/home/username/my-server
```
Then, SSH into your Host and execute docker compose file to init those services
```
ssh -i $your-ssh-key-location username@hostname
cd my-server
docker compose up -d --build
```
### Step 2: Get certificates and schedule to renew them

Execute `init_SSL.ssh` inside nginx image via docker command:
```
docker exec reverse-proxy /init_SSL.sh
```
Every thing should run smoothly and you can access your website from browsers without security warning. Let's encrypt certificates will expire after 90 days. They suggest us to run `renew` command every 12 hour to check and renew it with certbot client. I will use `cron` to schedule this process and print log output to *SSL.log* file.
```
# content of schedule.txt
0 0,12 * * * /usr/bin/docker exec reverse-proxy certbot renew >> /home/ubuntu/server/ssl.log

# run this command to start cronjob write inside schedule.txt
crontab schedule.txt
```

### Shortcut (Enhanced)
A better way is write all those stuff inside a script file and execute them after push configuration file to host server. We will not need to copy setup script Nginx container.
```
#!/bin/sh
cd my-server &&

docker compose up -d --build &&

docker exec rerverse-proxy sh -c '
  apk add certbot-nginx
  certbot \
          --nginx -m nguyenchauhieuduy@outlook.com \
          --agree-tos \
          --no-eff-email \
          -d duy.io.vn \
          -d website.duy.io.vn \
          -d cicd.duy.io.vn
'
echo '
0 0,12 * * * docker exec reverse-proxy certbot renew >> /home/ubuntu/my-server/ssl.log
' > renew_ssl

crontab renew_ssl
```
You can find my this configuration at [my github repository]() 

