FROM ubuntu:24.04
RUN apt-get update && apt-get install -y git bash zsh
RUN git config --global user.email "test@test.com" && \
    git config --global user.name "Test" && \
    git config --global init.defaultBranch main
WORKDIR /pathline
