FROM alpine:3.20.2 AS builder

RUN apk update && \
    apk add --no-cache gcompat libstdc++

WORKDIR /app

COPY ./devel . 

RUN cd hugo-install && \
    tar -xzf hugo_extended_0.133.0_linux-amd64.tar.gz && \
    chmod +x hugo && \
    mv hugo /bin/ 

RUN rm -rf public && \
    hugo

FROM nginx:1.27.1-alpine

COPY --from=builder /app/public /usr/share/nginx/html


EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]
