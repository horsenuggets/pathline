FROM ubuntu:24.04
RUN apt-get -o Acquire::http::No-Cache=true update && \
    apt-get -o Acquire::http::No-Cache=true install -y git bash zsh
RUN git config --global user.email "test@test.com" && \
    git config --global user.name "Test" && \
    git config --global init.defaultBranch main
WORKDIR /pathline
