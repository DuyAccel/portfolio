FROM alpine:3.20.2

RUN apk update && \
    apk add --no-cache --repository=https://dl-cdn.alpinelinux.org/alpine/edge/community hugo

RUN apk add --no-cache npm git

WORKDIR /app

COPY . .

RUN adduser -D -u 1000 duy &&\
    chown -R duy /app

USER duy
