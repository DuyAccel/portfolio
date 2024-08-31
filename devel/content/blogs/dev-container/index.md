---
title: 'Custom devcontainer'
date: 2024-08-31T08:43:34Z
draft: false
author: Duy Nguyen
tags:
image: /blogs/dev-container/container.png
description: Make your dev environment more interesting.
toc:
---

# Not only neovim, you can bring all your config into your most isolated dev environment!

If you're a Linux user who has put some effort to `rice` within your operating system, you probably don’t want to interact with a boring terminal screen while working, right? In this article, I’ll show you how to create a development environment inside a Docker container that preserves your config files, particularly for *Neovim*. The best part is you can reuse them anywhere, as long as the system has Docker Engine installed.

The idea came from a comment on [Reddit](https://www.reddit.com/r/neovim/comments/169sls2/comment/jz3wj2j/?utm_source=share&utm_medium=web3x&utm_name=web3xcss&utm_term=1&utm_content=share_button).

## Issues

### Why use a devcontainer?

Isolating and ensuring a clean development environment is a fundamental requirement for every developer when starting a project. There are many different methods to support this, such as:
- Using `virtual environments` for programming languages like Python, Node.js, etc.
- Using `conda environments` provided by Anaconda.
- Using `virtual machines`.

Each method has its own pros and cons: `virtual environments` and `conda environments` can't install packages outside the scope of the package manager. `Virtual machines` allow more freedom in package installation but are more storage-intensive. These issues can be addressed by using `containers` as a development environment.

A `container`, specifically referring to Docker containers in this article, is a tool that allows for the virtualization of operating systems running on the computer’s hardware through a container engine. Since `containers` do not virtualize hardware like RAM and hard drives, they save significantly more space and memory compared to `virtual machines`. For instance, the Docker image for the Alpine Linux operating system is only 5MB.

### Why is configuration necessary?

You've put effort into configuring your code editor to your liking with all the plugins you need, but when you start working with a container, your Neovim inside the container is bare. It’s hard to accept, right? You could reinstall, but what if you need to work on multiple projects? As a developer, you should find ways to automate repetitive tasks.

![neovim-empty-vs-config](/blogs/dev-container/img-0.png)


### Why not use VSCode’s devcontainer?

For those using VSCode, you might be familiar with the dev container extension developed by Microsoft. However, I am a hardcore Neovim user, and using VSCode does not sit well with me. If you're like me, let’s get started.

## 1. Preparation

Ensure that you have Docker installed and know how to use it at a basic level. Identify the config files that need to be included in the container.

### 1.1. Storing System Configurations

GNU Stow is an essential tool for managing system configurations. If you're not familiar with it, here’s a brief explanation. Suppose your HOME directory is structured as follows:
```
~/
├──dotfiles/
|   ├── .zshrc
|   └── .config/
|       └── nvim/
|           └── init.lua
└── example.txt
```
Now, if you use the `stow .` command in the `~/dotfiles/` directory:
```
cd ~/dotfiles
stow .
```
The directories inside `dotfiles` will be mapped to `~/` as follows:
```
~/
├──dotfiles/
|   ├── .zshrc
|   └── .config/
|       └── nvim/
|           └── init.lua
├── .zshrc -> ~/dotfiles/.zshrc
├── .config/
|   └── nvim/
|       └── init.lua -> ~/dotfiles/.config/nvim/init.lua
└── example.txt
```
So, make sure the config files you want to use are consolidated into a folder like `dotfiles`.
### 1.2. Backing Up Configuration Files to Github

Github is a great tool for this purpose. However, make sure you don’t accidentally upload any sensitive information online.
```
cd ~/dotfiles
git init
git add .
git commit -m 'init dotfiles'

# Add your remote repository
git remote add origin https://github.com/your-github/repository.git
git push origin main
```

## 2. Configuring the Dev Container

### 2.1. Building the Dockerfile

You can use an image corresponding to the distro you are familiar with to ease your setup. Since `I use Arch, btw`, I previously used an image for this distro as a devcontainer, but its size was quite large. Therefore, in this article, we will use `Alpine`, a very lightweight Docker image that is well-known among Docker users. Below is my **Dockerfile**. You can modify the packages to install, the username, and replace the path when cloning the Github repository.

```
FROM alpine:3.20.2

RUN apk update && \
    apk add --no-cache git stow npm eza neovim fzf ripgrep \
            zsh zsh-autosuggestions zsh-syntax-highlighting \
            curl build-base && \ 
    curl -s https://ohmyposh.dev/install.sh | sh -s -- -d /usr/local/bin

RUN adduser -G wheel -s /bin/zsh -u 1000 -D duy

USER duy

RUN git clone https://github.com/DuyAccel/dotfiles.git ~/dotfiles && \
    cd ~/dotfiles && \
    stow .

```
Let’s break down what’s written here:

First, I declare the base image as *Alpine:3.20.2*, which is the latest version at the time of writing this article.
```
FROM alpine:3.20.2
```
Next, I update the Alpine package manager (`apk`) to ensure the packages are downloaded at their latest versions.
```
RUN apk update && \
```
We use the `--no-cache` flag to ensure `apk` does not cache the packages (helping to reduce the image size). The packages I install can be divided into three groups:
- Essential for Neovim:
  - `neovim`, our favorite text editor.
  - `git` and `stow` are used to fetch and apply the dotfiles stored on GitHub.
  - `npm` is the package manager used to install some Neovim plugins.
  - `eza`, `fzf`, and `ripgrep` are command-line tools necessary for Neovim plugins.
- Required for the terminal shell:
  - `zsh`, `zsh-autosuggestions`, and `zsh-syntax-highlighting` are the Z shell and plugins for my favorite Unix shell.
- Additional supporting tools:
  - `curl` is used to install oh-my-posh, a tool to enhance the terminal experience.
  - `build-base` is a basic development toolset to support running and building certain files during development.
```
    apk add --no-cache git stow npm eza neovim fzf ripgrep \
            zsh zsh-autosuggestions zsh-syntax-highlighting \
            curl build-base && \ 
```
The following command installs **oh-my-posh**.
```
    curl -s https://ohmyposh.dev/install.sh | sh -s -- -d /usr/local/bin
```
I also create a new user for use instead of `root`. Using a user with the same UID as the user on the host machine helps avoid permission conflicts when binding mounts between the container and the host.
```
RUN adduser -G wheel -s /bin/zsh -u 1000 -D duy

USER duy
```
After switching to the `duy` user, I clone the repository containing my config files and apply those configurations to the `duy` user using the `stow` command.
```
RUN git clone https://github.com/DuyAccel/dotfiles.git ~/dotfiles && \
    cd ~/dotfiles && \
    stow .
```
### 2.2. Build Image + Run Container

Navigate to the folder containing your Dockerfile and build + run the image. Here’s an example of how I did it:
```
docker build -t duyaccel/devcontainer .

docker run -it --name devcontainer duyaccel/devcontainer zsh
```
You will see that your file paths and shell look similar to the image below.
![container first look](/blogs/dev-container/container-shell.png)

Use the `nvim` command to open Neovim and start the configuration process.
```
nvim
```
Wait until LazyVim plugins have been fully installed, then run the command `:MasonInstallAll` to install plugins managed by Mason. Some plugins like *ruff* and *pydebug* might not be installable because Python is not yet installed in this container, but it should not cause any issues.
![init neovim](/blogs/dev-container/neovim.png)
![mason neovim](/blogs/dev-container/neovim-mason.png)

You can install additional packages with root permissions to suit your project needs.
![devcontainer vs host](/blogs/dev-container/devcontainer-and-host.png)

## 3. Storage

You can push the image you just created to Docker Hub and pull it down when needed without having to build the entire image from the Dockerfile again.
```
docker push duyaccel/devcontainer
```
You can visit Docker Hub, find, and download my image with the tag name: `duyaccel/devcontainer`. The image size is only about 135 MB.
```
docker pull duyaccel/devcontainer:latest
```

## Summary

To keep programming from becoming dry and monotonous, it’s beneficial to infuse a bit of your own touch into it to make your work environment more comfortable and enjoyable.
