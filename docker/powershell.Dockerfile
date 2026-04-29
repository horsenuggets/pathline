FROM --platform=linux/amd64 mcr.microsoft.com/powershell:7.4-mariner-2.0
RUN tdnf install -y git > /dev/null 2>&1
RUN git config --global user.email "test@test.com" && \
    git config --global user.name "Test" && \
    git config --global init.defaultBranch main
WORKDIR /pathline
