FROM alpine:latest

RUN wget https://github.com/gohugoio/hugo/releases/download/v0.148.1/hugo_0.148.1_linux-amd64.tar.gz && \
    tar -xzvf hugo_0.148.1_linux-amd64.tar.gz; rm -rf hugo_0.148.1_linux-amd64.tar.gz

WORKDIR /app
COPY . .

CMD ["/hugo", "serve", "--bind=0.0.0.0", "-b=https://sabersh.ir", "-p=443"]
