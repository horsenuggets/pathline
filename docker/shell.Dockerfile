FROM ubuntu:24.04
RUN apt-get update -qq && apt-get install -y -qq git bash zsh > /dev/null 2>&1
RUN git config --global user.email "test@test.com" && \
    git config --global user.name "Test" && \
    git config --global init.defaultBranch main
WORKDIR /pathline
